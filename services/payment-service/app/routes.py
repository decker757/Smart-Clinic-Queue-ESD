from fastapi import APIRouter, HTTPException
from app.db import get_pool

router = APIRouter(prefix="/api/payments")


@router.get("/consultation/{consultation_id}")
async def get_payment_history(consultation_id: str):
    """Return all payment attempts for a consultation, newest first."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, consultation_id, patient_id, payment_intent_id, status, created_at
            FROM payments.payments
            WHERE consultation_id = $1
            ORDER BY created_at DESC
            """,
            consultation_id,
        )
    if not rows:
        raise HTTPException(status_code=404, detail="No payment records found")
    return [dict(r) for r in rows]


@router.get("/patient/{patient_id}")
async def get_patient_payment_history(patient_id: str):
    """Return all payment attempts for a patient, newest first."""
    pool = await get_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT id, consultation_id, patient_id, payment_intent_id, status, created_at
            FROM payments.payments
            WHERE patient_id = $1
            ORDER BY created_at DESC
            """,
            patient_id,
        )
    if not rows:
        raise HTTPException(status_code=404, detail="No payment records found")
    return [dict(r) for r in rows]
