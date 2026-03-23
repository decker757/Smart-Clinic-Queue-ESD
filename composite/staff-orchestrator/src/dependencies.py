from dataclasses import dataclass
from fastapi import Depends, Header, HTTPException
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


async def require_staff(ctx: AuthContext = Depends(require_auth)) -> AuthContext:
    if ctx.role not in ("staff", "doctor", "admin"):
        raise HTTPException(status_code=403, detail="Staff access required")
    return ctx
