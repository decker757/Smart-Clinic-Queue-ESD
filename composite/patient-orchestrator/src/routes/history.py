from fastapi import APIRouter, Depends, HTTPException
from src.models.history import AddHistoryRequest, HistoryResponse
from src.controller import history as history_controller
from src.dependencies import require_auth, AuthContext

router = APIRouter(prefix="/api/composite/patients", tags=["history"])


@router.get("/{patient_id}/history", response_model=list[HistoryResponse])
async def list_history(patient_id: str, auth: AuthContext = Depends(require_auth)):
    if auth.user_id != patient_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return await history_controller.list_history(patient_id)


@router.post("/{patient_id}/history", response_model=HistoryResponse, status_code=201)
async def add_history(patient_id: str, body: AddHistoryRequest, auth: AuthContext = Depends(require_auth)):
    if auth.user_id != patient_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return await history_controller.add_history(patient_id, body)
