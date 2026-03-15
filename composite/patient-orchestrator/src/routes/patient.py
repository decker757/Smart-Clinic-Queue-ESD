from fastapi import APIRouter, Depends, HTTPException
from src.models.patient import CreatePatientRequest, UpdatePatientRequest, PatientResponse
from src.controller import patient as patient_controller
from src.dependencies import require_auth, AuthContext

router = APIRouter(prefix="/api/composite/patients", tags=["patients"])


@router.get("/{patient_id}", response_model=PatientResponse)
async def get_patient(patient_id: str, auth: AuthContext = Depends(require_auth)):
    if auth.user_id != patient_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return await patient_controller.get_patient(patient_id)


@router.post("", response_model=PatientResponse, status_code=201)
async def create_patient(body: CreatePatientRequest, auth: AuthContext = Depends(require_auth)):
    return await patient_controller.create_patient(auth.user_id, body)


@router.put("/{patient_id}", response_model=PatientResponse)
async def update_patient(patient_id: str, body: UpdatePatientRequest, auth: AuthContext = Depends(require_auth)):
    if auth.user_id != patient_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return await patient_controller.update_patient(patient_id, body)
