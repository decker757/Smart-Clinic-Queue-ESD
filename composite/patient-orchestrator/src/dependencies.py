from dataclasses import dataclass
from fastapi import Header, HTTPException
from src.services import auth


@dataclass
class AuthContext:
    token: str      # raw JWT
    user_id: str    # JWT sub claim


async def require_auth(authorization: str = Header(...)) -> AuthContext:
    token = authorization.removeprefix("Bearer ")
    payload = await auth.verify_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return AuthContext(token=token, user_id=payload["sub"])
