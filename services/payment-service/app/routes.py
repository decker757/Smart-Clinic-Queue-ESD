import httpx
from datetime import datetime
from typing import Optional
from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException
from app.auth import require_auth
from app.db import get_pool
from app.config import settings


class PaymentRecord(BaseModel):
    id: str
    consultation_id: str
    patient_id: str
    payment_intent_id: Optional[str] = None
    status: str  # pending | paid | failed
    payment_link: Optional[str] = None
    created_at: datetime


class RefreshLinkResponse(BaseModel):
    payment_link: str


router = APIRouter(prefix="/api/payments", tags=["Payments"])


@router.get(
    "/consultation/{consultation_id}",
    response_model=list[PaymentRecord],
    summary="Get payment history for a consultation",
    responses={404: {"description": "No payment records found"}},
)
async def get_payment_history(consultation_id: str, caller_id: str = Depends(require_auth)):
    """Return all payment attempts for a consultation, newest first."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, consultation_id, patient_id, payment_intent_id, status, payment_link, created_at
            FROM payments.payments
            WHERE consultation_id = $1
            ORDER BY created_at DESC
            """,
            consultation_id,
        )
    if not rows:
        raise HTTPException(status_code=404, detail="No payment records found")
    return [dict(r) for r in rows]


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
async def refresh_payment_link(consultation_id: str, caller_id: str = Depends(require_auth)):
    """Create a new Stripe checkout session and update the stored payment_link."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT patient_id, status FROM payments.payments WHERE consultation_id = $1 ORDER BY created_at DESC LIMIT 1",
            consultation_id,
        )
    if not row:
        raise HTTPException(status_code=404, detail="No payment record found")
    if row["status"] == "paid":
        raise HTTPException(status_code=400, detail="Payment already completed")

    async with httpx.AsyncClient() as client:
        res = await client.post(
            f"{settings.STRIPE_SERVICE_URL}/api/payments/create-session",
            json={"appointment_id": consultation_id, "patient_id": row["patient_id"]},
            timeout=15,
        )
    if not res.is_success:
        raise HTTPException(status_code=502, detail="Could not create payment session")

    data = res.json()
    new_link = data["payment_link"]
    new_session_id = data["session_id"]

    async with pool.acquire() as conn:
        await conn.execute(
            """UPDATE payments.payments
               SET payment_link = $1, payment_intent_id = $2
               WHERE consultation_id = $3""",
            new_link, new_session_id, consultation_id,
        )

    return {"payment_link": new_link}

@router.get(
    "/patient/{patient_id}",
    response_model=list[PaymentRecord],
    summary="Get payment history for a patient",
    responses={404: {"description": "No payment records found"}},
)
async def get_patient_payment_history(patient_id: str, caller_id: str = Depends(require_auth)):
    """Return all payment attempts for a patient, newest first."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, consultation_id, patient_id, payment_intent_id, status, payment_link, created_at
            FROM payments.payments
            WHERE patient_id = $1
            ORDER BY created_at DESC
            """,
            patient_id,
        )
    if not rows:
        raise HTTPException(status_code=404, detail="No payment records found")
    return [dict(r) for r in rows]
