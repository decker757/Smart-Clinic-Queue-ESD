from dataclasses import dataclass

import jwt
from jwt import PyJWKClient
from fastapi import Depends, Header, HTTPException
from app.config import settings

_jwks_client: PyJWKClient | None = None


@dataclass
class AuthContext:
    user_id: str
    role: str
    token: str


def _get_jwks_client() -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        _jwks_client = PyJWKClient(settings.JWKS_URL)
    return _jwks_client


async def require_auth(authorization: str = Header(...)) -> AuthContext:
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Unauthorized")

    token = authorization.removeprefix("Bearer ").strip()
    try:
        client = _get_jwks_client()
        signing_key = client.get_signing_key_from_jwt(token)
        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            options={"verify_aud": False},
        )
        return AuthContext(
            user_id=payload["sub"],
            role=str(payload.get("custom:role", payload.get("role", ""))).lower(),
            token=token,
        )
    except Exception:
        raise HTTPException(status_code=401, detail="Unauthorized")


async def require_staff(ctx: AuthContext = Depends(require_auth)) -> AuthContext:
    if ctx.role not in {"staff", "doctor", "admin"}:
        raise HTTPException(status_code=403, detail="Staff access required")
    return ctx
