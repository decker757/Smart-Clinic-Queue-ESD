from app.clients.base_client import BaseServiceClient
from app.core.config import Settings


class NotificationClient(BaseServiceClient):
    def __init__(self, settings: Settings) -> None:
        super().__init__(
            base_url=settings.notification_service_url,
            settings=settings,
            service_name="notification-service",
        )

    async def send_checkin_confirmation(self, appointment_id: str, eta_minutes: int | None) -> dict:
        payload = {
            "appointment_id": appointment_id,
            "template": "check_in_confirmation",
            "data": {
                "eta_minutes": eta_minutes,
            },
        }
        return await self._request_with_retry(method="POST", path="/notifications", payload=payload)
