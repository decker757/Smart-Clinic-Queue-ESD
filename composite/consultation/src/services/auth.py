import jwt
from jwt import PyJWKClient

from src.config import settings

_jwks_client: PyJWKClient | None = None
JWT_AUDIENCE = "smart-clinic-services"
JWT_ISSUER = "smart-clinic"


def _get_jwks_client() -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        _jwks_client = PyJWKClient(settings.JWKS_URL)
    return _jwks_client


def _decode_kwargs() -> dict:
    # AWS uses Cognito JWKS URLs; local Docker uses BetterAuth's JWKS endpoint.
    if settings.JWKS_URL.endswith("/.well-known/jwks.json"):
        return {
            "issuer": settings.JWKS_URL.removesuffix("/.well-known/jwks.json"),
            "options": {"verify_aud": False},
        }
    return {
        "issuer": JWT_ISSUER,
        "audience": JWT_AUDIENCE,
    }


async def verify_token(token: str) -> dict | None:
    """Verify JWT in either local BetterAuth or AWS Cognito mode.
    Returns decoded payload (includes 'sub' as user id) or None.
    """
    try:
        client = _get_jwks_client()
        signing_key = client.get_signing_key_from_jwt(token)
        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            **_decode_kwargs(),
        )
        return payload
    except jwt.PyJWTError:
        return None
    except Exception:
        return None
