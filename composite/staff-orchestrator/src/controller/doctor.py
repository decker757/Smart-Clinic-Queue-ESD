import grpc
from fastapi import HTTPException
from src.models.doctor import UpdateSlotStatusRequest, AddConsultationNotesRequest
from src.services import doctor as doctor_service, rabbitmq


async def list_doctors():
    try:
        return await doctor_service.list_doctors()
    except grpc.RpcError as e:
        raise HTTPException(status_code=500, detail="Internal server error")


async def get_doctor(doctor_id: str):
    try:
        return await doctor_service.get_doctor(doctor_id)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Doctor not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def get_doctor_slots(doctor_id: str):
    try:
        return await doctor_service.get_doctor_slots(doctor_id)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Doctor not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def update_slot_status(slot_id: str, body: UpdateSlotStatusRequest):
    try:
        slot = await doctor_service.update_slot_status(slot_id, body.status)
        await rabbitmq.publish_event("staff.slot_updated", {
            "slot_id": slot_id,
            "status": body.status,
        })
        return slot
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Slot not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def add_consultation_notes(appointment_id: str, staff_id: str, body: AddConsultationNotesRequest):
    try:
        result = await doctor_service.add_consultation_notes(
            appointment_id=appointment_id,
            doctor_id=staff_id,
            patient_id=body.patient_id,
            notes=body.notes,
            diagnosis=body.diagnosis,
        )
        await rabbitmq.publish_event("staff.consultation_notes_added", {
            "appointment_id": appointment_id,
            "doctor_id": staff_id,
            "patient_id": body.patient_id,
        })
        return result
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Appointment not found")
        raise HTTPException(status_code=500, detail="Internal server error")
