from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from src.models.memo import CreateTextMemoRequest, CreateDoctorRecordRequest, MemoResponse
from src.controller import memo as memo_controller
from src.dependencies import require_auth, AuthContext

router = APIRouter(prefix="/api/composite/patients", tags=["memos"])


@router.get("/{patient_id}/memos", response_model=list[MemoResponse])
async def get_memos(patient_id: str, auth: AuthContext = Depends(require_auth)):
    if auth.user_id != patient_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return await memo_controller.get_memos(patient_id)


@router.post("/{patient_id}/memos", response_model=MemoResponse, status_code=201)
async def create_text_memo(patient_id: str, body: CreateTextMemoRequest, auth: AuthContext = Depends(require_auth)):
    if auth.user_id != patient_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return await memo_controller.create_text_memo(patient_id, body)


@router.post("/{patient_id}/memos/upload", response_model=MemoResponse, status_code=201)
async def create_file_memo(
    patient_id: str,
    title: str = Form(...),
    file: UploadFile = File(...),
    auth: AuthContext = Depends(require_auth),
):
    if auth.user_id != patient_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return await memo_controller.create_file_memo(patient_id, title, file)


@router.post("/{patient_id}/memos/doctor", response_model=MemoResponse, status_code=201)
async def create_doctor_record(patient_id: str, body: CreateDoctorRecordRequest, auth: AuthContext = Depends(require_auth)):
    return await memo_controller.create_doctor_record(patient_id, body)
