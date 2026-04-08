import httpx
from datetime import datetime
from typing import Optional
from uuid import UUID
from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException
from app.auth import AuthContext, require_auth, require_staff
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


class CreateBillingRequest(BaseModel):
    """Staff sets the final billing amount for a completed consultation."""
    consultation_id: str
    amount_cents: int       # total charge in smallest currency unit (e.g. 2000 = $20.00)
    currency: str = "sgd"


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
               SET payment_link = $1, payment_intent_id = $2
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


@router.post(
    "/billing",
    response_model=PaymentRecord,
    summary="Staff creates a billing entry and generates a Stripe payment link",
    responses={
        400: {"description": "Payment already exists for this consultation"},
        403: {"description": "Staff access required"},
        502: {"description": "Stripe service unavailable"},
    },
)
async def create_billing(body: CreateBillingRequest, auth: AuthContext = Depends(require_staff)):
    """Called by staff-orchestrator after staff sets the final amount."""
    if body.amount_cents <= 0:
        raise HTTPException(status_code=400, detail="amount_cents must be greater than 0")

    currency = _normalize_currency(body.currency)
    pool = await get_pool()

    try:
        async with httpx.AsyncClient() as client:
            appt_res = await client.get(
                f"{settings.APPOINTMENT_SERVICE_URL}/appointments/{body.consultation_id}",
                headers={"Authorization": f"Bearer {auth.token}"},
                timeout=10,
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Appointment service unavailable") from exc

    if appt_res.status_code == 404:
        raise HTTPException(status_code=404, detail="Consultation not found")
    if not appt_res.is_success:
        raise HTTPException(status_code=502, detail="Appointment service unavailable")

    appointment = appt_res.json()
    if appointment.get("status") != "completed":
        raise HTTPException(status_code=400, detail="Billing can only be created for completed consultations")

    patient_id = appointment.get("patient_id")
    if not patient_id:
        raise HTTPException(status_code=400, detail="Consultation is missing a patient_id")

    # Serialize concurrent submissions for the same consultation using a
    # PostgreSQL advisory lock. The lock is held for the duration of the
    # transaction (check → Stripe call → insert) so two concurrent staff
    # clicks cannot both pass the duplicate check and generate two payment links.
    async with pool.acquire() as conn:
        async with conn.transaction():
            await conn.execute(
                "SELECT pg_advisory_xact_lock(hashtext($1))",
                body.consultation_id,
            )
            existing = await conn.fetchrow(
                "SELECT id FROM payments.payments WHERE consultation_id = $1 LIMIT 1",
                body.consultation_id,
            )
            if existing:
                raise HTTPException(status_code=400, detail="Billing already created for this consultation")

            # Create Stripe checkout session (inside the advisory lock so only
            # one request reaches Stripe per consultation).
            try:
                async with httpx.AsyncClient() as client:
                    res = await client.post(
                        f"{settings.STRIPE_SERVICE_URL}/api/payments/create-session",
                        json={
                            "appointment_id": body.consultation_id,
                            "patient_id": patient_id,
                            "amount_cents": body.amount_cents,
                            "currency": currency,
                        },
                        timeout=15,
                    )
            except httpx.HTTPError as exc:
                raise HTTPException(status_code=502, detail="Could not create payment session") from exc
            if not res.is_success:
                raise HTTPException(status_code=502, detail="Could not create payment session")

            data = res.json()
            payment_link = data["payment_link"]
            session_id = data["session_id"]

            row = await conn.fetchrow(
                """
                INSERT INTO payments.payments
                    (consultation_id, patient_id, payment_intent_id, amount_cents, currency, status, payment_link)
                VALUES ($1, $2, $3, $4, $5, 'pending', $6)
                RETURNING id, consultation_id, patient_id, payment_intent_id, amount_cents, currency, status, payment_link, created_at
                """,
                body.consultation_id,
                patient_id,
                session_id,
                body.amount_cents,
                currency,
                payment_link,
            )

    await publish_event(
        "payment.link_created",
        {
            "consultation_id": body.consultation_id,
            "patient_id": patient_id,
            "payment_link": payment_link,
            "amount_cents": body.amount_cents,
            "currency": currency,
        },
    )

    return _serialize_payment_record(row)
