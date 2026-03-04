import httpx
from fastapi import HTTPException
from typing import Literal, NoReturn
from src.config import settings
from src.models.appointment import AppointmentServiceRequest, AppointmentResponse


def _forward_error(e: httpx.HTTPStatusError) -> NoReturn:
    """Re-raise an atomic service error as a FastAPI HTTPException."""
    try:
        detail = e.response.json().get("error", e.response.text)
    except Exception:
        detail = e.response.text
    raise HTTPException(status_code=e.response.status_code, detail=detail)


async def _call(method: Literal["get", "post", "put", "patch", "delete"], path: str, token: str, **kwargs) -> httpx.Response:
    """Single entry-point for all calls to the atomic appointment-service."""
    async with httpx.AsyncClient(
        base_url=settings.APPOINTMENT_SERVICE_URL,
        headers={"Authorization": f"Bearer {token}"},
        timeout=10.0,
    ) as client:
        response = await getattr(client, method)(path, **kwargs)
        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            _forward_error(e)
        return response


async def list_appointments(patient_id: str, token: str) -> list[AppointmentResponse]:
    """List all appointments for a patient from atomic appointment-service."""
    response = await _call("get", "/appointments", token, params={"patient_id": patient_id})
    return [AppointmentResponse(**a) for a in response.json() or []]


async def create_appointment(data: AppointmentServiceRequest, token: str) -> AppointmentResponse:
    """Call atomic appointment-service to create an appointment."""
    response = await _call("post", "/appointments", token, json=data.model_dump(mode="json"))
    return AppointmentResponse(**response.json())


async def get_appointment(appointment_id: str, token: str) -> AppointmentResponse:
    """Fetch a single appointment from atomic appointment-service."""
    response = await _call("get", f"/appointments/{appointment_id}", token)
    return AppointmentResponse(**response.json())


async def cancel_appointment(appointment_id: str, token: str) -> AppointmentResponse:
    """Cancel an appointment via atomic appointment-service."""
    response = await _call("delete", f"/appointments/{appointment_id}", token)
    return AppointmentResponse(**response.json())
