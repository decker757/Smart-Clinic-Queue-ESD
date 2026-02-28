import jwt
from jwt import PyJWKClient
from src.config import settings

_jwks_client: PyJWKClient | None = None


def _get_jwks_client() -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        _jwks_client = PyJWKClient(f"{settings.AUTH_SERVICE_URL}/api/auth/jwks")
    return _jwks_client


async def verify_token(token: str) -> dict | None:
    """Verify JWT token locally using the auth-service public key from JWKS.

    Returns the decoded payload (includes 'sub' as user id) or None if invalid.
    """
    try:
        client = _get_jwks_client()
        signing_key = client.get_signing_key_from_jwt(token)
        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=["EdDSA"],
            audience="smart-clinic-services",
            issuer="smart-clinic",
        )
        return payload
    except jwt.PyJWTError:
        return None
    except Exception:
        return None
