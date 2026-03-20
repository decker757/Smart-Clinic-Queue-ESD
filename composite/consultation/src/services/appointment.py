"""HTTP client for appointment-service (atomic)."""

from typing import Literal, NoReturn

import httpx
from fastapi import HTTPException

from src.config import settings


def _forward_error(e: httpx.HTTPStatusError) -> NoReturn:
    """Re-raise an atomic service error as FastAPI HTTPException."""
    try:
        detail = e.response.json().get("error", e.response.text)
    except Exception:
        detail = e.response.text
    raise HTTPException(status_code=e.response.status_code, detail=detail)


async def _call(
    method: Literal["get", "post", "put", "patch", "delete"],
    path: str,
    token: str,
    **kwargs,
) -> httpx.Response:
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


async def mark_complete(appointment_id: str, token: str) -> dict:
    """PATCH appointment status to 'completed'."""
    response = await _call(
        "patch",
        f"/appointments/{appointment_id}/status",
        token,
        json={"status": "completed"},
    )
    return response.json()
