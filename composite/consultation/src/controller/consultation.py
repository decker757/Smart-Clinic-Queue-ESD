"""Consultation orchestration logic.

Implements the Scenario 3 flow from the architecture diagram:
  1. Doctor submits consultation completion from Staff Dashboard
  2. → gRPC POST MC + prescribed medication to patient-service
  3. → gRPC POST consultation notes to doctor-service (future)
  4. → HTTP PATCH mark appointment as complete via appointment-service
  5. → gRPC POST payment request to payment-service (future)
  6. → Publish "consultation.completed" event to RabbitMQ
       (consumed by notification-service, queue-coordinator, activity-log)
"""

import grpc
from fastapi import HTTPException

from src.models.consultation import CompleteConsultationRequest, ConsultationResponse
from src.services import (
    appointment as appointment_svc,
    patient as patient_svc,
    queue as queue_svc,
    rabbitmq,
)


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
            print(f"[WARN] Failed to add history: {e.details()}")

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

    # ── Step 5: Remove from queue ────────────────────────────
    try:
        await queue_svc.complete_appointment(body.appointment_id)
    except grpc.RpcError as e:
        # Non-critical — queue may already be cleared
        print(f"[WARN] Queue removal failed: {e.details()}")

    # ── Step 6: Request payment (TODO — needs payment-service) ──
    payment_link = None
    # When payment-service is built:
    # payment_link = await payment_svc.create_payment_request(...)

    # ── Step 7: Publish consultation.completed event ─────────
    await rabbitmq.publish_event(
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

    return ConsultationResponse(
        appointment_id=body.appointment_id,
        patient_id=body.patient_id,
        doctor_id=body.doctor_id,
        status="completed",
        payment_link=payment_link,
        message="Consultation completed successfully",
    )
