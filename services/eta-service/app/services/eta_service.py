from math import ceil

import httpx
from fastapi import HTTPException, status

from app.core.config import Settings
from app.models.eta_models import EtaRequest, EtaResponse


class EtaService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    async def calculate_eta(self, payload: EtaRequest) -> EtaResponse:
        params = {
            "origins": f"{payload.patient_lat},{payload.patient_lng}",
            "destinations": f"{self.settings.clinic_lat},{self.settings.clinic_lng}",
            "mode": self.settings.travel_mode,
            "units": "metric",
            "key": self.settings.google_maps_api_key,
        }

        try:
            async with httpx.AsyncClient(timeout=self.settings.request_timeout_seconds) as client:
                response = await client.get(self.settings.google_distance_matrix_url, params=params)
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Failed to reach Google Distance Matrix API: {exc}",
            ) from exc

        if response.status_code >= 400:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Google Distance Matrix API error: HTTP {response.status_code}",
            )

        data = response.json()
        api_status = data.get("status")
        if api_status != "OK":
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Google Distance Matrix API returned status: {api_status}",
            )

        rows = data.get("rows") or []
        if not rows or not rows[0].get("elements"):
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Malformed Distance Matrix response: missing rows/elements",
            )

        element = rows[0]["elements"][0]
        element_status = element.get("status")
        if element_status != "OK":
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Route not available: {element_status}",
            )

        distance_meters = element.get("distance", {}).get("value")
        duration_seconds = element.get("duration", {}).get("value")

        if distance_meters is None or duration_seconds is None:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Malformed Distance Matrix response: missing distance/duration",
            )

        distance_km = round(distance_meters / 1000, 2)
        duration_minutes = int(ceil(duration_seconds / 60))

        return EtaResponse(distance_km=distance_km, duration_minutes=duration_minutes)
