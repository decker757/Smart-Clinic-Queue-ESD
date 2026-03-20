from fastapi import APIRouter, Depends
from src.models.patient import PatientResponse
from src.controller import patient as patient_controller
from src.dependencies import require_staff, AuthContext

router = APIRouter(prefix="/api/composite/staff/patients", tags=["patients"])


@router.get("/{patient_id}", response_model=PatientResponse)
async def get_patient(patient_id: str, auth: AuthContext = Depends(require_staff)):
    return await patient_controller.get_patient(patient_id, staff_id=auth.user_id)


@router.get("/{patient_id}/history")
async def get_patient_history(patient_id: str, auth: AuthContext = Depends(require_staff)):
    return await patient_controller.get_patient_history(patient_id)
