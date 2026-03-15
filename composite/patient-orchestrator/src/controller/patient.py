import grpc
from fastapi import HTTPException
from src.models.patient import CreatePatientRequest, UpdatePatientRequest
from src.services import patient as patient_service, rabbitmq


async def get_patient(patient_id: str):
    try:
        return await patient_service.get_patient(patient_id)
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Patient not found")
        raise HTTPException(status_code=500, detail="Internal server error")


async def create_patient(user_id: str, body: CreatePatientRequest):
    try:
        patient = await patient_service.create_patient(
            patient_id=user_id,
            phone=body.phone or "",
            dob=body.dob or "",
            nric=body.nric or "",
            gender=body.gender or "",
            allergies=body.allergies or [],
        )
        await rabbitmq.publish_event("patient.profile_created", {
            "patient_id": user_id,
        })
        return patient
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.ALREADY_EXISTS:
            raise HTTPException(status_code=409, detail="Patient already exists")
        raise HTTPException(status_code=500, detail="Internal server error")


async def update_patient(patient_id: str, body: UpdatePatientRequest):
    try:
        patient = await patient_service.update_patient(
            patient_id=patient_id,
            phone=body.phone,
            dob=body.dob,
            nric=body.nric,
            gender=body.gender,
            allergies=body.allergies,
        )
        await rabbitmq.publish_event("patient.profile_updated", {
            "patient_id": patient_id,
        })
        return patient
    except grpc.RpcError as e:
        if e.code() == grpc.StatusCode.NOT_FOUND:
            raise HTTPException(status_code=404, detail="Patient not found")
        raise HTTPException(status_code=500, detail="Internal server error")
