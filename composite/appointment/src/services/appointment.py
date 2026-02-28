import httpx
from src.config import settings
from src.models.appointment import AppointmentServiceRequest, AppointmentResponse


async def create_appointment(data: AppointmentServiceRequest, token: str) -> AppointmentResponse:
    """Call atomic appointment-service to create an appointment."""
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{settings.APPOINTMENT_SERVICE_URL}/appointments",
            json=data.model_dump(mode="json"),
            headers={"Authorization": f"Bearer {token}"},
            timeout=10.0,
        )
        response.raise_for_status()
        return AppointmentResponse(**response.json())


async def get_appointment(appointment_id: str, token: str) -> AppointmentResponse:
    """Fetch a single appointment from atomic appointment-service."""
    async with httpx.AsyncClient() as client:
        response = await client.get(
            f"{settings.APPOINTMENT_SERVICE_URL}/appointments/{appointment_id}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10.0,
        )
        response.raise_for_status()
        return AppointmentResponse(**response.json())


async def cancel_appointment(appointment_id: str, token: str) -> AppointmentResponse:
    """Cancel an appointment via atomic appointment-service."""
    async with httpx.AsyncClient() as client:
        response = await client.delete(
            f"{settings.APPOINTMENT_SERVICE_URL}/appointments/{appointment_id}",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10.0,
        )
        response.raise_for_status()
        return AppointmentResponse(**response.json())
