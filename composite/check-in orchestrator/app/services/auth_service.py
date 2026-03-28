import logging
import jwt
from jwt import PyJWKClient
from app.config.settings import settings

logger = logging.getLogger(__name__)

_jwks_client: PyJWKClient | None = None


def _get_jwks_client() -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        _jwks_client = PyJWKClient(settings.JWKS_URL)
    return _jwks_client


async def verify_token(token: str) -> dict | None:
    """Verify JWT token using Cognito JWKS.

    Returns the decoded payload (includes 'sub' as user id) or None if invalid.
    """
    try:
        client = _get_jwks_client()
        signing_key = client.get_signing_key_from_jwt(token)
        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=["RS256"],
            options={"verify_aud": False},
        )
        return payload
    except jwt.PyJWTError:
        return None
    except Exception as e:
        logger.warning("Unexpected error during token verification: %s", e)
        return None
