"""Billing routes — staff sets the final consultation amount before payment.

Flow:
  1. GET  /pending-billing  → list completed appointments without a payment record
  2. GET  /{appointment_id}/prescription → fetch prescription memo for that consult
  3. POST /create           → staff sets amount, creates Stripe checkout + payment record
"""

from pydantic import BaseModel
from fastapi import APIRouter, Depends
from src.controller import billing as billing_controller
from src.dependencies import require_staff, AuthContext

router = APIRouter(prefix="/api/composite/staff/billing", tags=["billing"])


class CreateBillingRequest(BaseModel):
    appointment_id: str
    amount_cents: int       # total charge (smallest currency unit, e.g. 2000 = $20.00)
    currency: str = "sgd"


@router.get("/pending")
async def pending_billing(auth: AuthContext = Depends(require_staff)):
    """Return completed appointments that have no payment record yet."""
    return await billing_controller.get_pending_billing(auth.token)


@router.get("/{appointment_id}/prescription")
async def get_prescription(appointment_id: str, auth: AuthContext = Depends(require_staff)):
    """Return the prescription memo for a given appointment."""
    return await billing_controller.get_prescription(appointment_id, auth.token)


@router.post("/create")
async def create_billing(body: CreateBillingRequest, auth: AuthContext = Depends(require_staff)):
    """Staff sets the billing amount and generates a Stripe payment link."""
    return await billing_controller.create_billing(
        consultation_id=body.appointment_id,
        amount_cents=body.amount_cents,
        currency=body.currency,
        token=auth.token,
    )
