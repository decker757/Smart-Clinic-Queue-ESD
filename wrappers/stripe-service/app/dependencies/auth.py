from dataclasses import dataclass
from fastapi import Header, HTTPException
from app.services.auth_service import verify_token


@dataclass
class AuthContext:
    token: str    # raw JWT — forwarded to atomic services if needed
    user_id: str  # JWT sub claim — used for ownership checks


async def require_auth(authorization: str = Header(...)) -> AuthContext:
    """Validate the Bearer JWT and return the caller's identity."""
    token = authorization.removeprefix("Bearer ")
    payload = await verify_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return AuthContext(token=token, user_id=payload["sub"])