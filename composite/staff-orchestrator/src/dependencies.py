from dataclasses import dataclass
from fastapi import Header, HTTPException
from src.services import auth


@dataclass
class AuthContext:
    token: str
    user_id: str
    role: str


async def require_auth(authorization: str = Header(...)) -> AuthContext:
    token = authorization.removeprefix("Bearer ")
    payload = await auth.verify_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return AuthContext(
        token=token,
        user_id=payload["sub"],
        role=payload.get("role", ""),
    )


async def require_staff(authorization: str = Header(...)) -> AuthContext:
    ctx = await require_auth(authorization)
    if ctx.role not in ("staff", "doctor", "admin"):
        raise HTTPException(status_code=403, detail="Staff access required")
    return ctx
