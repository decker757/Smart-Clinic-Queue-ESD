"""gRPC client for patient-service (atomic)."""

import grpc.aio

from src.proto import patient_pb2, patient_pb2_grpc
from src.config import settings

channel = grpc.aio.insecure_channel(settings.PATIENT_SERVICE_GRPC)
stub = patient_pb2_grpc.PatientServiceStub(channel)


async def create_doctor_record(
    patient_id: str,
    title: str,
    content: str,
    record_type: str,  # "mc" or "prescription"
    issued_by: str,
):
    """Create an MC or prescription record on the patient's profile."""
    response = await stub.CreateDoctorRecord(
        patient_pb2.CreateDoctorRecordRequest(
            patient_id=patient_id,
            title=title,
            content=content,
            record_type=record_type,
            issued_by=issued_by,
        ),
        timeout=10,
    )
    return response


async def add_history(
    patient_id: str,
    diagnosis: str,
    notes: str = "",
    diagnosed_at: str = "",
):
    """Add a history entry to the patient's medical record."""
    response = await stub.AddHistory(
        patient_pb2.AddHistoryRequest(
            patient_id=patient_id,
            diagnosis=diagnosis,
            notes=notes,
            diagnosed_at=diagnosed_at,
        ),
        timeout=10,
    )
    return response
