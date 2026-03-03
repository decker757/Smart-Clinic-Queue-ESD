from fastapi import APIRouter, Depends

from app.core.config import Settings, get_settings
from app.models.eta_models import EtaRequest, EtaResponse
from app.services.eta_service import EtaService

router = APIRouter()


@router.post("/eta", response_model=EtaResponse, tags=["eta"])
async def estimate_eta(
    payload: EtaRequest,
    settings: Settings = Depends(get_settings),
) -> EtaResponse:
    service = EtaService(settings)
    return await service.calculate_eta(payload)


@router.get("/health", tags=["health"])
async def health(settings: Settings = Depends(get_settings)) -> dict:
    return {
        "status": "ok",
        "service": settings.service_name,
        "version": settings.service_version,
    }
