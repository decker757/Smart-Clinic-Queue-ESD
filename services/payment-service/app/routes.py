import httpx
from datetime import datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException
from app.auth import AuthContext, require_auth
from app.db import get_pool
from app.config import settings
from app.publisher import publish_event


class PaymentRecord(BaseModel):
    id: str
    consultation_id: str
    patient_id: str
    payment_intent_id: Optional[str] = None
    amount_cents: Optional[int] = None
    currency: Optional[str] = "sgd"
    status: str  # pending | paid | failed
    payment_link: Optional[str] = None
    created_at: datetime



class RefreshLinkResponse(BaseModel):
    payment_link: str


router = APIRouter(prefix="/api/payments", tags=["Payments"])


def _normalize_currency(currency: Optional[str]) -> str:
    value = (currency or "sgd").strip().lower()
    if len(value) != 3 or not value.isalpha():
        raise HTTPException(status_code=400, detail="currency must be a 3-letter ISO code")
    return value


def _is_staff(auth: AuthContext) -> bool:
    return auth.role in {"staff", "doctor", "admin"}


def _serialize_payment_record(row) -> dict:
    record = dict(row)
    for key, value in record.items():
        if isinstance(value, UUID):
            record[key] = str(value)
    return record


@router.get(
    "/consultation/{consultation_id}",
    response_model=list[PaymentRecord],
    summary="Get payment history for a consultation",
    responses={404: {"description": "No payment records found"}},
)
async def get_payment_history(consultation_id: str, auth: AuthContext = Depends(require_auth)):
    """Return all payment attempts for a consultation, newest first."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, consultation_id, patient_id, payment_intent_id, amount_cents, currency, status, payment_link, created_at
            FROM payments.payments
            WHERE consultation_id = $1
            ORDER BY created_at DESC
            """,
            consultation_id,
        )
    if not rows:
        raise HTTPException(status_code=404, detail="No payment records found")
    if not _is_staff(auth) and rows[0]["patient_id"] != auth.user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return [_serialize_payment_record(r) for r in rows]


@router.post(
    "/consultation/{consultation_id}/refresh",
    response_model=RefreshLinkResponse,
    summary="Refresh an expired payment link",
    responses={
        400: {"description": "Payment already completed"},
        404: {"description": "No payment record found"},
        502: {"description": "Stripe service unavailable"},
    },
)
async def refresh_payment_link(consultation_id: str, auth: AuthContext = Depends(require_auth)):
    """Create a new Stripe checkout session and update the stored payment_link."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            SELECT id, patient_id, status, amount_cents, currency
            FROM payments.payments
            WHERE consultation_id = $1
            ORDER BY created_at DESC
            LIMIT 1
            """,
            consultation_id,
        )
    if not row:
        raise HTTPException(status_code=404, detail="No payment record found")
    if not _is_staff(auth) and row["patient_id"] != auth.user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    if row["status"] == "paid":
        raise HTTPException(status_code=400, detail="Payment already completed")

    stripe_payload = {
        "appointment_id": consultation_id,
        "patient_id": row["patient_id"],
    }
    if row["amount_cents"] is not None:
        stripe_payload["amount_cents"] = row["amount_cents"]
    if row["currency"]:
        stripe_payload["currency"] = row["currency"]

    try:
        async with httpx.AsyncClient() as client:
            res = await client.post(
                f"{settings.STRIPE_SERVICE_URL}/api/payments/create-session",
                json=stripe_payload,
                timeout=15,
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Could not create payment session") from exc
    if not res.is_success:
        raise HTTPException(status_code=502, detail="Could not create payment session")

    data = res.json()
    new_link = data["payment_link"]
    new_session_id = data["session_id"]

    async with pool.acquire() as conn:
        await conn.execute(
            """UPDATE payments.payments
               SET payment_link = $1, payment_intent_id = $2, status = 'pending'
               WHERE id = $3""",
            new_link, new_session_id, row["id"],
        )

    return {"payment_link": new_link}

@router.get(
    "/patient/{patient_id}",
    response_model=list[PaymentRecord],
    summary="Get payment history for a patient",
    responses={404: {"description": "No payment records found"}},
)
async def get_patient_payment_history(patient_id: str, auth: AuthContext = Depends(require_auth)):
    """Return all payment attempts for a patient, newest first."""
    if not _is_staff(auth) and auth.user_id != patient_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, consultation_id, patient_id, payment_intent_id, amount_cents, currency, status, payment_link, created_at
            FROM payments.payments
            WHERE patient_id = $1
            ORDER BY created_at DESC
            """,
            patient_id,
        )
    if not rows:
        raise HTTPException(status_code=404, detail="No payment records found")
    return [_serialize_payment_record(r) for r in rows]

