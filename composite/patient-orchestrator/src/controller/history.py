import grpc
from fastapi import HTTPException
from src.models.history import AddHistoryRequest
from src.services import history as history_service, rabbitmq


async def list_history(patient_id: str):
    try:
        return await history_service.list_history(patient_id)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Patient not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def add_history(patient_id: str, body: AddHistoryRequest):
    try:
        entry = await history_service.add_history(
            patient_id=patient_id,
            diagnosis=body.diagnosis,
            diagnosed_at=body.diagnosed_at or "",
            notes=body.notes or "",
        )
        await rabbitmq.publish_event("patient.history_added", {
            "patient_id": patient_id,
            "diagnosis": body.diagnosis,
        })
        return entry
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Patient not found")
        raise HTTPException(status_code=500, detail="Internal server error")
