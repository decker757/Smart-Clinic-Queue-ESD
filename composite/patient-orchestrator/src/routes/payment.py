import httpx
from fastapi import APIRouter, Depends, HTTPException
from src.dependencies import require_auth, AuthContext
from src.config import settings

router = APIRouter(prefix="/api/composite/patients", tags=["payments"])


@router.get("/{patient_id}/payments")
async def get_patient_payments(patient_id: str, auth: AuthContext = Depends(require_auth)):
    if auth.user_id != patient_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    async with httpx.AsyncClient() as client:
        res = await client.get(
            f"{settings.PAYMENT_SERVICE_URL}/api/payments/patient/{patient_id}",
            headers={"Authorization": f"Bearer {auth.token}"},
            timeout=10,
        )
    if res.status_code in (404, 401):
        return []
    if not res.is_success:
        raise HTTPException(status_code=502, detail="Payment service unavailable")
    return res.json()


@router.post("/{patient_id}/payments/{consultation_id}/refresh")
async def refresh_payment_link(patient_id: str, consultation_id: str, auth: AuthContext = Depends(require_auth)):
    if auth.user_id != patient_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    async with httpx.AsyncClient() as client:
        res = await client.post(
            f"{settings.PAYMENT_SERVICE_URL}/api/payments/consultation/{consultation_id}/refresh",
            headers={"Authorization": f"Bearer {auth.token}"},
            timeout=15,
        )
    if res.status_code == 404:
        raise HTTPException(status_code=404, detail="Payment not found")
    if res.status_code == 400:
        raise HTTPException(status_code=400, detail=res.json().get("detail", "Bad request"))
    if not res.is_success:
        raise HTTPException(status_code=502, detail="Payment service unavailable")
    return res.json()
