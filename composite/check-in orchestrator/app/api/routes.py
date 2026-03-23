from fastapi import APIRouter, Depends
from app.schemas.checkin import CheckInRequest, CheckInResponse, ConfirmRequest
from app.dependencies.auth import require_auth, AuthContext
from app.services.checkin_service import process_check_in, handle_confirmation

router = APIRouter()

@router.post("/check-in", response_model=CheckInResponse)
async def check_in(body: CheckInRequest, auth_ctx: AuthContext = Depends(require_auth)):
    return await process_check_in(body)

@router.post("/check-in/confirm")
async def confirm_check_in(body: ConfirmRequest, auth_ctx: AuthContext = Depends(require_auth)):
    return await handle_confirmation(body)