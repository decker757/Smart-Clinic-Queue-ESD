import grpc
from fastapi import HTTPException
from google.protobuf.json_format import MessageToDict
from src.models.doctor import UpdateSlotStatusRequest, AddConsultationNotesRequest
from src.services import doctor as doctor_service, rabbitmq


def _msg(proto):
    return MessageToDict(proto, preserving_proto_field_name=True)


async def list_doctors():
    try:
        doctors = await doctor_service.list_doctors()
        return [_msg(d) for d in doctors]
    except grpc.RpcError as e:
        raise HTTPException(status_code=500, detail="Internal server error")


async def get_doctor(doctor_id: str):
    try:
        return _msg(await doctor_service.get_doctor(doctor_id))
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Doctor not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def get_doctor_slots(doctor_id: str, date: str = ""):
    try:
        slots = await doctor_service.get_doctor_slots(doctor_id, date)
        return [_msg(s) for s in slots]
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
        return _msg(slot)
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
        return _msg(result)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Appointment not found")
        raise HTTPException(status_code=500, detail="Internal server error")
