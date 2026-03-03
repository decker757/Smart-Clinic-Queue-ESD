from app.clients.base_client import BaseServiceClient
from app.core.config import Settings


class EtaClient(BaseServiceClient):
    def __init__(self, settings: Settings) -> None:
        super().__init__(
            base_url=settings.eta_service_url,
            settings=settings,
            service_name="eta-service",
        )

    async def estimate_eta(self, appointment_id: str, lat: float, lng: float) -> dict:
        payload = {
            "appointment_id": appointment_id,
            "lat": lat,
            "lng": lng,
        }
        return await self._request_with_retry(method="POST", path="/eta/estimate", payload=payload)
