"""Billing controller — orchestrates across appointment-service, patient-service,
and payment-service to let staff finalise billing for completed consultations.

Appointment/payment checks use HTTP. Prescription review uses the internal
patient-service gRPC API so staff can read doctor-issued memos without relying
on the patient-only public HTTP endpoint.
"""

import asyncio
import logging
import grpc
import httpx
from fastapi import HTTPException

from src.config import settings
from src.services import patient as patient_svc

logger = logging.getLogger(__name__)


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


async def get_pending_billing(token: str):
    """Return completed appointments that don't yet have a payment record.

    Strategy: fetch all completed appointments from appointment-service,
    then check payment-service for each. Those without a payment record
    are pending billing.
    """
    async with httpx.AsyncClient(timeout=10) as client:
        # 1. Get all appointments
        appt_res = await client.get(
            f"{settings.APPOINTMENT_SERVICE_URL}/appointments",
            headers=_auth(token),
        )
        if not appt_res.is_success:
            raise HTTPException(status_code=appt_res.status_code, detail="Failed to fetch appointments")

        appointments = appt_res.json() or []
        completed = [a for a in appointments if a.get("status") == "completed"]

        if not completed:
            return []

        # 2. Check which have no payment record yet
        async def has_no_billing(appt: dict) -> bool:
            pay_res = await client.get(
                f"{settings.PAYMENT_SERVICE_URL}/api/payments/consultation/{appt['id']}",
                headers=_auth(token),
            )
            if pay_res.status_code == 404:
                return True
            if pay_res.is_success:
                return False
            raise HTTPException(
                status_code=pay_res.status_code,
                detail=f"Failed to fetch billing status for appointment {appt['id']}",
            )

        pending_mask = await asyncio.gather(*(has_no_billing(appt) for appt in completed))
        return [appt for appt, include in zip(completed, pending_mask) if include]


async def get_prescription(appointment_id: str, token: str):
    """Fetch prescription and MC memos for a specific appointment.

    Uses HTTP to hit the patient-service memos endpoint via the patient
    details fetched from appointment-service.
    """
    async with httpx.AsyncClient(timeout=10) as client:
        # 1. Get the appointment to find patient_id
        appt_res = await client.get(
            f"{settings.APPOINTMENT_SERVICE_URL}/appointments/{appointment_id}",
            headers=_auth(token),
        )
        if not appt_res.is_success:
            raise HTTPException(status_code=404, detail="Appointment not found")

        appt = appt_res.json()
        patient_id = appt.get("patient_id")
        if not patient_id:
            return []

    try:
        memos = await patient_svc.get_memos(patient_id)
    except grpc.RpcError as exc:
        logger.warning("Failed to fetch memos for patient %s: %s", patient_id, exc.details())
        return []

    # 2. Filter to prescription + mc for this appointment
    return [
        {
            "id": memo.id,
            "patient_id": memo.patient_id,
            "title": memo.title,
            "content": memo.content,
            "file_url": memo.file_url,
            "file_type": memo.file_type,
            "record_type": memo.record_type,
            "issued_by": memo.issued_by,
            "created_at": memo.created_at,
            "appointment_id": memo.appointment_id,
        }
        for memo in memos
        if memo.record_type in ("prescription", "mc")
        and memo.appointment_id == appointment_id
    ]


async def create_billing(
    consultation_id: str,
    amount_cents: int,
    currency: str,
    token: str,
):
    """Create a billing record + Stripe checkout via payment-service."""
    async with httpx.AsyncClient(timeout=15) as client:
        res = await client.post(
            f"{settings.PAYMENT_SERVICE_URL}/api/payments/billing",
            headers=_auth(token),
            json={
                "consultation_id": consultation_id,
                "amount_cents": amount_cents,
                "currency": currency,
            },
        )
    if not res.is_success:
        body = res.json() if "application/json" in res.headers.get("content-type", "") else {}
        detail = body.get("error") or body.get("detail") or "Failed to create billing"
        raise HTTPException(status_code=res.status_code, detail=detail)

    return res.json()
