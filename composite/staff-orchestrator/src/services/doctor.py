import grpc.aio
from src.proto import doctor_pb2, doctor_pb2_grpc
from src.config import settings

channel = grpc.aio.insecure_channel(settings.DOCTOR_SERVICE_GRPC)
stub = doctor_pb2_grpc.DoctorServiceStub(channel)


async def list_doctors():
    response = await stub.ListDoctors(doctor_pb2.ListDoctorsRequest())
    return response.doctors


async def get_doctor(doctor_id: str):
    return await stub.GetDoctor(doctor_pb2.GetDoctorRequest(doctor_id=doctor_id))


async def get_doctor_slots(doctor_id: str):
    response = await stub.GetDoctorSlots(doctor_pb2.GetDoctorSlotsRequest(doctor_id=doctor_id))
    return response.slots


async def update_slot_status(slot_id: str, status: str):
    return await stub.UpdateSlotStatus(doctor_pb2.UpdateSlotStatusRequest(
        slot_id=slot_id,
        status=status,
    ))


async def add_consultation_notes(appointment_id: str, doctor_id: str, patient_id: str, notes: str, diagnosis: str):
    return await stub.AddConsultationNotes(doctor_pb2.AddConsultationNotesRequest(
        appointment_id=appointment_id,
        doctor_id=doctor_id,
        patient_id=patient_id,
        notes=notes,
        diagnosis=diagnosis,
    ))
