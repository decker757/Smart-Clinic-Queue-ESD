import grpc.aio
from src.proto import doctor_pb2, doctor_pb2_grpc
from src.config import settings


def _channel():
    return grpc.aio.insecure_channel(settings.DOCTOR_SERVICE_GRPC)


async def list_doctors():
    async with _channel() as channel:
        stub = doctor_pb2_grpc.DoctorServiceStub(channel)
        response = await stub.ListDoctors(
            doctor_pb2.ListDoctorsRequest(),
            timeout=10,
        )
        return response.doctors


async def get_doctor(doctor_id: str):
    async with _channel() as channel:
        stub = doctor_pb2_grpc.DoctorServiceStub(channel)
        return await stub.GetDoctor(
            doctor_pb2.GetDoctorRequest(doctor_id=doctor_id),
            timeout=10,
        )


async def get_doctor_slots(doctor_id: str):
    async with _channel() as channel:
        stub = doctor_pb2_grpc.DoctorServiceStub(channel)
        response = await stub.GetDoctorSlots(
            doctor_pb2.GetDoctorSlotsRequest(doctor_id=doctor_id),
            timeout=10,
        )
        return response.slots


async def update_slot_status(slot_id: str, status: str):
    async with _channel() as channel:
        stub = doctor_pb2_grpc.DoctorServiceStub(channel)
        return await stub.UpdateSlotStatus(
            doctor_pb2.UpdateSlotStatusRequest(
                slot_id=slot_id,
                status=status,
            ),
            timeout=10,
        )


async def add_consultation_notes(appointment_id: str, doctor_id: str, patient_id: str, notes: str, diagnosis: str):
    async with _channel() as channel:
        stub = doctor_pb2_grpc.DoctorServiceStub(channel)
        return await stub.AddConsultationNotes(
            doctor_pb2.AddConsultationNotesRequest(
                appointment_id=appointment_id,
                doctor_id=doctor_id,
                patient_id=patient_id,
                notes=notes,
                diagnosis=diagnosis,
            ),
            timeout=10,
        )
