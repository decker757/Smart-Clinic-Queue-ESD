"""HTTP client for payment-service (atomic)."""

import httpx
from fastapi import HTTPException

from src.config import settings

FIXED_CONSULTATION_FEE_CENTS = 5000
FIXED_CURRENCY = "sgd"


async def create_payment_request(appointment_id: str, token: str) -> dict:
    """Create the standard fixed-fee payment for a completed consultation."""
    async with httpx.AsyncClient(timeout=15) as client:
        res = await client.post(
            f"{settings.PAYMENT_SERVICE_URL}/api/payments/billing",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "consultation_id": appointment_id,
                "amount_cents": FIXED_CONSULTATION_FEE_CENTS,
                "currency": FIXED_CURRENCY,
            },
        )

    if not res.is_success:
        detail = "Failed to create payment request"
        if "application/json" in res.headers.get("content-type", ""):
            body = res.json()
            detail = body.get("detail") or body.get("error") or detail
        raise HTTPException(status_code=res.status_code, detail=detail)

    return res.json()
