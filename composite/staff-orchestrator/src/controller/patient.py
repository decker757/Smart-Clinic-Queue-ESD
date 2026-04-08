import grpc
from fastapi import HTTPException
from google.protobuf.json_format import MessageToDict
from src.services import patient as patient_service, rabbitmq


def _msg(proto):
    return MessageToDict(proto, preserving_proto_field_name=True)


async def get_patient(patient_id: str, staff_id: str):
    try:
        patient = await patient_service.get_patient(patient_id)
        await rabbitmq.publish_event("staff.patient_profile_viewed", {
            "patient_id": patient_id,
            "viewed_by": staff_id,
        })
        return _msg(patient)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Patient not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def get_patient_history(patient_id: str):
    try:
        entries = await patient_service.get_history(patient_id)
        return [_msg(e) for e in entries]
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Patient not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def get_patient_memos(patient_id: str):
    try:
        memos = await patient_service.get_memos(patient_id)
        return [_msg(m) for m in memos]
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Patient not found")
        raise HTTPException(status_code=500, detail="Internal server error")
