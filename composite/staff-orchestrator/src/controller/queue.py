import grpc
from fastapi import HTTPException
from google.protobuf.json_format import MessageToDict
from src.models.queue import AddToQueueRequest, CallNextRequest
from src.services import queue as queue_service, rabbitmq


def _msg(proto):
    return MessageToDict(proto, preserving_proto_field_name=True)


async def get_queue_position(appointment_id: str):
    try:
        return _msg(await queue_service.get_queue_position(appointment_id))
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Appointment not found in queue")
        raise HTTPException(status_code=500, detail="Internal server error")


async def check_in(appointment_id: str, caller_id: str):
    try:
        result = await queue_service.check_in(appointment_id)
        await rabbitmq.publish_event("staff.patient_checked_in", {
            "appointment_id": appointment_id,
            "checked_in_by": caller_id,
        })
        return _msg(result)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Appointment not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def add_to_queue(body: AddToQueueRequest):
    try:
        result = await queue_service.add_to_queue(
            appointment_id=body.appointment_id,
            patient_id=body.patient_id,
            doctor_id=body.doctor_id,
            session=body.session,
            start_time=body.start_time,
        )
        await rabbitmq.publish_event("staff.patient_added_to_queue", {
            "appointment_id": body.appointment_id,
            "patient_id": body.patient_id,
            "doctor_id": body.doctor_id,
        })
        return _msg(result)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.ALREADY_EXISTS:
            raise HTTPException(status_code=409, detail="Patient already in queue")
        raise HTTPException(status_code=500, detail="Internal server error")


async def remove_from_queue(appointment_id: str):
    try:
        result = await queue_service.remove_from_queue(appointment_id)
        await rabbitmq.publish_event("staff.patient_removed_from_queue", {
            "appointment_id": appointment_id,
        })
        return _msg(result)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Appointment not found in queue")
        raise HTTPException(status_code=500, detail="Internal server error")


async def mark_no_show(appointment_id: str):
    try:
        result = await queue_service.mark_no_show(appointment_id)
        await rabbitmq.publish_event("staff.patient_no_show", {
            "appointment_id": appointment_id,
        })
        return _msg(result)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Appointment not found in queue")
        raise HTTPException(status_code=500, detail="Internal server error")


async def complete_appointment(appointment_id: str):
    try:
        result = await queue_service.complete_appointment(appointment_id)
        await rabbitmq.publish_event("staff.appointment_completed", {
            "appointment_id": appointment_id,
        })
        return _msg(result)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Appointment not found in queue")
        raise HTTPException(status_code=500, detail="Internal server error")


async def call_next(body: CallNextRequest):
    try:
        result = await queue_service.call_next(
            session=body.session,
            doctor_id=body.doctor_id,
        )
        await rabbitmq.publish_event("staff.next_patient_called", {
            "session": body.session,
            "doctor_id": body.doctor_id,
            "appointment_id": result.appointment_id,
            "patient_id": result.patient_id,
        })
        return _msg(result)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="No patients in queue")
        raise HTTPException(status_code=500, detail="Internal server error")
