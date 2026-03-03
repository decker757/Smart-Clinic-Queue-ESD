from app.clients.base_client import BaseServiceClient
from app.core.config import Settings


class AppointmentClient(BaseServiceClient):
    def __init__(self, settings: Settings) -> None:
        super().__init__(
            base_url=settings.appointment_service_url,
            settings=settings,
            service_name="appointment-service",
        )

    async def get_appointment(self, appointment_id: str) -> dict:
        return await self._request_with_retry(method="GET", path=f"/appointments/{appointment_id}")
