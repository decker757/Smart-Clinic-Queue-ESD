"""Consultation orchestration logic.

Implements the Scenario 3 flow from the architecture diagram:
  1. Doctor submits consultation completion from Staff Dashboard
  0. → ClaimConsultation on doctor-service (idempotency gate / outbox)
       Returns cached result immediately if already completed.
  1. → gRPC POST MC + prescribed medication to patient-service (idempotent)
  2. → gRPC POST consultation notes to doctor-service (idempotent)
  3. → HTTP PATCH mark appointment as complete via appointment-service
  4. → gRPC to Stripe Wrapper to create payment session
       (Stripe Wrapper publishes payment.pending independently)
  5. → Publish "consultation.completed" event to RabbitMQ
       (consumed by notification-service, queue-coordinator, activity-log)
       Queue removal happens async via RabbitMQ, NOT direct gRPC.
  6. → FinalizeConsultation on doctor-service (stores notes + marks completed)

On any failure at steps 4–6, FinalizeConsultation is called with
completion_status="failed" so the next retry re-enters cleanly without
duplicating the already-committed patient-service writes (which are idempotent).
"""

import grpc
import logging
from fastapi import HTTPException

from src.models.consultation import CompleteConsultationRequest, ConsultationResponse
from src.services import (
    appointment as appointment_svc,
    doctor as doctor_svc,
    patient as patient_svc,
    payment as payment_svc,
    rabbitmq,
)

logger = logging.getLogger(__name__)


async def complete_consultation(
    body: CompleteConsultationRequest,
    token: str,
) -> ConsultationResponse:
    """Orchestrate the full consultation completion flow."""

    # ── Step 0: Claim the consultation (idempotency gate) ────────────
    # Atomically inserts a row in doctors.consultations with status='processing'.
    # Returns immediately with the cached payment_link if already completed.
    try:
        claim = await doctor_svc.claim_consultation(
            appointment_id=body.appointment_id,
            doctor_id=body.doctor_id,
            patient_id=body.patient_id,
        )
    except grpc.RpcError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Consultation service unavailable — please retry: {e.details()}",
        )

    if not claim.claimed:
        if claim.status == "completed":
            # Idempotent replay — return the stored result.
            return ConsultationResponse(
                appointment_id=body.appointment_id,
                patient_id=body.patient_id,
                doctor_id=body.doctor_id,
                status="completed",
                message="Consultation completed successfully",
                payment_link=claim.payment_link or None,
            )
        # Another request is currently processing this consultation.
        raise HTTPException(
            status_code=409,
            detail="Consultation is already being processed. Please retry shortly.",
        )

    # Helper: mark the outbox entry as failed so the next retry can re-enter.
    async def _mark_failed() -> None:
        try:
            await doctor_svc.finalize_consultation(
                appointment_id=body.appointment_id,
                notes=body.consultation_notes or "",
                diagnosis=body.diagnosis or "",
                payment_link="",
                completion_status="failed",
            )
        except Exception as fe:
            logger.error("[Consultation] Failed to mark outbox as failed: %s", fe)

    # ── Step 1: Create MC record on patient-service (if MC issued) ──────
    # Idempotent: ON CONFLICT (appointment_id, record_type) DO UPDATE in patient-service.
    if body.mc_days and body.mc_start_date:
        try:
            mc_content = (
                f"MC for {body.mc_days} day(s) starting {body.mc_start_date}. "
                f"Reason: {body.mc_reason or 'N/A'}"
            )
            await patient_svc.create_doctor_record(
                patient_id=body.patient_id,
                title=f"Medical Certificate - {body.mc_start_date}",
                content=mc_content,
                record_type="mc",
                issued_by=body.doctor_id,
                appointment_id=body.appointment_id,
            )
        except grpc.RpcError as e:
            await _mark_failed()
            raise HTTPException(
                status_code=500,
                detail=f"Failed to create MC record: {e.details()}",
            )

    # ── Step 2: Create prescription record (if medication prescribed) ──
    # Idempotent: ON CONFLICT (appointment_id, record_type) DO UPDATE in patient-service.
    if body.prescribed_medication:
        try:
            await patient_svc.create_doctor_record(
                patient_id=body.patient_id,
                title="Prescription",
                content=body.prescribed_medication,
                record_type="prescription",
                issued_by=body.doctor_id,
                appointment_id=body.appointment_id,
            )
        except grpc.RpcError as e:
            await _mark_failed()
            raise HTTPException(
                status_code=500,
                detail=f"Failed to create prescription: {e.details()}",
            )

    # ── Step 3: Add diagnosis to patient history ─────────────────────
    # Idempotent: ON CONFLICT (appointment_id) DO UPDATE in patient-service.
    if body.diagnosis:
        try:
            await patient_svc.add_history(
                patient_id=body.patient_id,
                diagnosis=body.diagnosis,
                notes=body.consultation_notes or "",
                appointment_id=body.appointment_id,
            )
        except grpc.RpcError as e:
            # Non-critical — log but don't fail the consultation.
            logger.warning("Failed to add history: %s", e.details())

    # ── Step 4: Mark appointment as completed ────────────────────────
    try:
        await appointment_svc.mark_complete(body.appointment_id, token)
    except HTTPException:
        await _mark_failed()
        raise
    except Exception as e:
        await _mark_failed()
        raise HTTPException(
            status_code=500,
            detail=f"Failed to mark appointment complete: {e}",
        )

    # ── Step 5: Create Stripe payment session via gRPC ───────────────
    # Fail hard — if no payment row is created, the refresh endpoint has nothing
    # to recover later, making the consultation unbillable.
    payment_link = None
    try:
        payment = await payment_svc.create_payment_request(
            appointment_id=body.appointment_id,
            patient_id=body.patient_id,
        )
        payment_link = payment.get("payment_link")
    except grpc.RpcError as e:
        await _mark_failed()
        raise HTTPException(
            status_code=503,
            detail=f"Payment session could not be created — please retry: {e.details()}",
        )
    except Exception as e:
        await _mark_failed()
        raise HTTPException(
            status_code=503,
            detail=f"Payment session could not be created — please retry: {e}",
        )

    # ── Step 6: Publish consultation.completed event ─────────────────
    # Queue removal, notifications, and audit all depend on this event.
    # Fail hard so the doctor retries rather than leaving the patient stuck
    # in the active queue with no downstream updates.
    event_published = await rabbitmq.publish_event(
        "consultation.completed",
        {
            "appointment_id": body.appointment_id,
            "patient_id": body.patient_id,
            "doctor_id": body.doctor_id,
            "mc_issued": bool(body.mc_days),
            "prescribed_medication": body.prescribed_medication,
            "diagnosis": body.diagnosis,
            "payment_link": payment_link,
        },
    )
    if not event_published:
        await _mark_failed()
        raise HTTPException(
            status_code=503,
            detail="Queue update could not be dispatched — please retry to ensure the patient is removed from the queue.",
        )

    # ── Step 7: Finalize outbox — store notes and mark completed ─────
    try:
        await doctor_svc.finalize_consultation(
            appointment_id=body.appointment_id,
            notes=body.consultation_notes or "",
            diagnosis=body.diagnosis or "",
            payment_link=payment_link or "",
            completion_status="completed",
        )
    except grpc.RpcError as e:
        # Finalization failed after all real side effects (appointment marked
        # complete, Stripe session created, event published) have already committed.
        # Retry once before giving up.
        logger.warning(
            "[Consultation] FinalizeConsultation failed for %s: %s — retrying once",
            body.appointment_id, e.details(),
        )
        try:
            await doctor_svc.finalize_consultation(
                appointment_id=body.appointment_id,
                notes=body.consultation_notes or "",
                diagnosis=body.diagnosis or "",
                payment_link=payment_link or "",
                completion_status="completed",
            )
        except grpc.RpcError as e2:
            # Both attempts failed. Reset to 'failed' so the next retry can
            # re-enter via claim_consultation instead of 409-ing forever.
            # Individual steps (mark_complete, Stripe session) are idempotent
            # so re-entry is safe. If _mark_failed also fails (doctor-service
            # still down), the row stays 'processing' and ops must intervene.
            logger.error(
                "[Consultation] FinalizeConsultation retry also failed for %s: %s"
                " — attempting reset to failed for retry recovery",
                body.appointment_id, e2.details(),
            )
            await _mark_failed()
            raise HTTPException(
                status_code=503,
                detail="Consultation finalization failed — please retry shortly.",
            )

    return ConsultationResponse(
        appointment_id=body.appointment_id,
        patient_id=body.patient_id,
        doctor_id=body.doctor_id,
        status="completed",
        message="Consultation completed successfully",
        payment_link=payment_link,
    )
