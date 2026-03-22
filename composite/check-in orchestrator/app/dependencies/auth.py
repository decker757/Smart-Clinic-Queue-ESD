from dataclasses import dataclass
from fastapi import Header, HTTPException
from app.services.auth_service import verify_token

@dataclass
class AuthContext:
    token: str
    user_id: str

async def require_auth(authorization: str = Header(...)) -> AuthContext:
    token = authorization.removeprefix("Bearer ")
    payload = await verify_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return AuthContext(token=token, user_id=payload["sub"])