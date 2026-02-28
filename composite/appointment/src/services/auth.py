import httpx
from src.config import settings


async def verify_token(token: str) -> dict | None:
    """Verify JWT token against auth-service. Returns session data or None if invalid."""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{settings.AUTH_SERVICE_URL}/api/auth/get-session",
                headers={"Authorization": f"Bearer {token}"},
                timeout=5.0,
            )
            if response.status_code != 200:
                return None
            data = response.json()
            return data if data else None
    except httpx.RequestError:
        return None
