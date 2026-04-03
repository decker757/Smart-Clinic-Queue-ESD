"""Consultation orchestration logic.

Implements the Scenario 3 flow from the architecture diagram:
  1. Doctor submits consultation completion from Staff Dashboard
  2. → gRPC POST MC + prescribed medication to patient-service
  3. → gRPC POST consultation notes to doctor-service (future)
  4. → HTTP PATCH mark appointment as complete via appointment-service
  5. → gRPC POST payment request to payment-service → Stripe → returns link
  6. → Publish "consultation.completed" event to RabbitMQ
       (consumed by notification-service, queue-coordinator, activity-log)
       Queue removal happens async via RabbitMQ, NOT direct gRPC.
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

    # ── Step 1: Create MC record on patient-service (if MC issued) ──
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
            raise HTTPException(
                status_code=500,
                detail=f"Failed to create MC record: {e.details()}",
            )

    # ── Step 2: Create prescription record (if medication prescribed) ──
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
            raise HTTPException(
                status_code=500,
                detail=f"Failed to create prescription: {e.details()}",
            )

    # ── Step 3: Add diagnosis to patient history ─────────────
    if body.diagnosis:
        try:
            await patient_svc.add_history(
                patient_id=body.patient_id,
                diagnosis=body.diagnosis,
                notes=body.consultation_notes or "",
            )
        except grpc.RpcError as e:
            # Non-critical — log but don't fail
            logger.warning("Failed to add history: %s", e.details())

    # ── Step 3: Store consultation notes on doctor-service ───
    try:
        await doctor_svc.add_consultation_notes(
            appointment_id=body.appointment_id,
            doctor_id=body.doctor_id,
            patient_id=body.patient_id,
            notes=body.consultation_notes or "",
            diagnosis=body.diagnosis or "",
        )
    except grpc.RpcError as e:
        # Non-critical — notes not saving should not block payment/completion
        logger.warning("Failed to store consultation notes: %s", e.details())

    # ── Step 4: Mark appointment as completed ────────────────
    try:
        await appointment_svc.mark_complete(body.appointment_id, token)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to mark appointment complete: {e}",
        )

    # ── Step 5: Request payment synchronously (payment-service → Stripe) ──
    payment_link = None
    try:
        payment_link = await payment_svc.create_payment_request(
            appointment_id=body.appointment_id,
            patient_id=body.patient_id,
        )
    except grpc.RpcError as e:
        logger.warning("Failed to create payment request: %s", e.details())

    # ── Step 6: Publish consultation.completed event ─────────
    # Queue removal, notification, and activity logging happen
    # asynchronously via RabbitMQ consumers on each service.
    event_published = await rabbitmq.publish_event(
        "consultation.completed",
        {
            "appointment_id": body.appointment_id,
            "patient_id": body.patient_id,
            "doctor_id": body.doctor_id,
            "payment_link": payment_link,
            "mc_issued": bool(body.mc_days),
            "prescribed_medication": body.prescribed_medication,
            "diagnosis": body.diagnosis,
        },
    )

    message = "Consultation completed successfully"
    if not event_published:
        message += " (warning: queue/notification update may be delayed — event bus temporarily unavailable)"

    return ConsultationResponse(
        appointment_id=body.appointment_id,
        patient_id=body.patient_id,
        doctor_id=body.doctor_id,
        status="completed",
        payment_link=payment_link,
        message=message,
    )
