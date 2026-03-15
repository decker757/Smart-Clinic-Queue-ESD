import grpc
from fastapi import HTTPException, UploadFile
from src.models.memo import CreateTextMemoRequest, CreateDoctorRecordRequest
from src.services import memo as memo_service, rabbitmq


async def get_memos(patient_id: str):
    try:
        return await memo_service.get_memos(patient_id)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Patient not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def create_text_memo(patient_id: str, body: CreateTextMemoRequest):
    try:
        memo = await memo_service.create_text_memo(
            patient_id=patient_id,
            title=body.title,
            content=body.content,
        )
        await rabbitmq.publish_event("patient.memo_created", {
            "patient_id": patient_id,
            "title": body.title,
        })
        return memo
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Patient not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def create_file_memo(patient_id: str, title: str, file: UploadFile):
    try:
        file_data = await file.read()
        memo = await memo_service.create_file_memo(
            patient_id=patient_id,
            title=title,
            file_data=file_data,
            original_name=file.filename,
            mimetype=file.content_type,
        )
        await rabbitmq.publish_event("patient.memo_created", {
            "patient_id": patient_id,
            "title": title,
        })
        return memo
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Patient not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def create_doctor_record(patient_id: str, body: CreateDoctorRecordRequest):
    try:
        memo = await memo_service.create_doctor_record(
            patient_id=patient_id,
            title=body.title,
            content=body.content,
            record_type=body.record_type,
            issued_by=body.issued_by,
        )
        await rabbitmq.publish_event("patient.memo_created", {
            "patient_id": patient_id,
            "title": body.title,
            "record_type": body.record_type,
        })
        return memo
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Patient not found")
        raise HTTPException(status_code=500, detail="Internal server error")
