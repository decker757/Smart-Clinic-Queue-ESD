from fastapi import APIRouter, Depends, status

from app.core.config import Settings, get_settings
from app.core.dependencies import get_checkin_service
from app.models.checkin_models import CheckInRequest, CheckInResponse
from app.services.checkin_service import CheckInService

router = APIRouter()


@router.get("/health", tags=["health"])
async def health(settings: Settings = Depends(get_settings)) -> dict:
    return {
        "status": "ok",
        "service": settings.service_name,
        "version": settings.service_version,
    }


@router.post(
    "/check-in",
    response_model=CheckInResponse,
    status_code=status.HTTP_200_OK,
    tags=["check-in"],
)
async def check_in(
    payload: CheckInRequest,
    service: CheckInService = Depends(get_checkin_service),
) -> CheckInResponse:
    return await service.process_check_in(payload)
