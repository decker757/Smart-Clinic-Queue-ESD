from dataclasses import dataclass
from fastapi import Header, HTTPException



@dataclass
class AuthContext:
    token: str    # raw JWT — forwarded to atomic services
    user_id: str  # JWT sub claim — used for ownership checks


async def require_auth(authorization: str = Header(...)) -> AuthContext:
    """Validate the Bearer JWT and return the caller's identity + raw token."""
    token = authorization.removeprefix("Bearer ")
    payload = await auth.verify_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return AuthContext(token=token, user_id=payload["sub"])