from app.clients.base_client import BaseServiceClient
from app.core.config import Settings


class QueueClient(BaseServiceClient):
    def __init__(self, settings: Settings) -> None:
        super().__init__(
            base_url=settings.queue_service_url,
            settings=settings,
            service_name="queue-service",
        )

    async def update_status(self, appointment_id: str, status: str) -> dict:
        payload = {
            "appointment_id": appointment_id,
            "status": status,
        }
        return await self._request_with_retry(method="POST", path="/queue/status", payload=payload)
