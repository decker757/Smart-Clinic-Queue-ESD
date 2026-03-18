from fastapi import APIRouter, Depends

from src.models.consultation import CompleteConsultationRequest, ConsultationResponse
from src.controller import consultation as consultation_controller
from src.dependencies import require_auth, AuthContext

router = APIRouter(
    prefix="/api/composite/consultations",
    tags=["consultations"],
)


@router.post("/complete", response_model=ConsultationResponse)
async def complete_consultation(
    body: CompleteConsultationRequest,
    auth: AuthContext = Depends(require_auth),
):
    """Called by doctor from Staff Dashboard when consultation is done.

    Orchestrates: patient records → appointment update → queue removal
                  → payment request → event publishing
    """
    return await consultation_controller.complete_consultation(
        body=body,
        token=auth.token,
    )
