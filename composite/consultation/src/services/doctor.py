"""gRPC client for doctor-service (atomic)."""

import grpc.aio

from src.proto import doctor_pb2, doctor_pb2_grpc
from src.config import settings


def _channel():
    return grpc.aio.insecure_channel(settings.DOCTOR_SERVICE_GRPC)


async def get_doctor(doctor_id: str):
    """Retrieve doctor details by ID."""
    async with _channel() as channel:
        stub = doctor_pb2_grpc.DoctorServiceStub(channel)
        response = await stub.GetDoctor(
            doctor_pb2.GetDoctorRequest(doctor_id=doctor_id),
            timeout=10,
        )
        return response


async def add_consultation_notes(
    appointment_id: str,
    doctor_id: str,
    patient_id: str,
    notes: str = "",
    diagnosis: str = "",
):
    """Store consultation notes on the doctor-service."""
    async with _channel() as channel:
        stub = doctor_pb2_grpc.DoctorServiceStub(channel)
        response = await stub.AddConsultationNotes(
            doctor_pb2.AddConsultationNotesRequest(
                appointment_id=appointment_id,
                doctor_id=doctor_id,
                patient_id=patient_id,
                notes=notes,
                diagnosis=diagnosis,
            ),
            timeout=10,
        )
        return response


async def claim_consultation(appointment_id: str, doctor_id: str, patient_id: str):
    """Atomically claim a consultation slot as the idempotency gate.

    Returns a ClaimConsultationResponse with:
      claimed     — True if this call now owns the flow
      status      — "processing" | "completed" | "in_progress"
      payment_link — populated when status == "completed" (idempotent replay)
    """
    async with _channel() as channel:
        stub = doctor_pb2_grpc.DoctorServiceStub(channel)
        response = await stub.ClaimConsultation(
            doctor_pb2.ClaimConsultationRequest(
                appointment_id=appointment_id,
                doctor_id=doctor_id,
                patient_id=patient_id,
            ),
            timeout=10,
        )
        return response


async def finalize_consultation(
    appointment_id: str,
    notes: str = "",
    diagnosis: str = "",
    payment_link: str = "",
    completion_status: str = "completed",
):
    """Store notes/diagnosis/payment_link and mark the outbox entry as completed or failed."""
    async with _channel() as channel:
        stub = doctor_pb2_grpc.DoctorServiceStub(channel)
        response = await stub.FinalizeConsultation(
            doctor_pb2.FinalizeConsultationRequest(
                appointment_id=appointment_id,
                notes=notes,
                diagnosis=diagnosis,
                payment_link=payment_link,
                completion_status=completion_status,
            ),
            timeout=10,
        )
        return response
