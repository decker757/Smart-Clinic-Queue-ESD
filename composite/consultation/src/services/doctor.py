"""gRPC client for doctor-service (atomic)."""

import grpc.aio

from src.proto import doctor_pb2, doctor_pb2_grpc
from src.config import settings

channel = grpc.aio.insecure_channel(settings.DOCTOR_SERVICE_GRPC)
stub = doctor_pb2_grpc.DoctorServiceStub(channel)


async def get_doctor(doctor_id: str):
    """Retrieve doctor details by ID."""
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
