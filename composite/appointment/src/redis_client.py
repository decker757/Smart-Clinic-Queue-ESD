"""
Async Redis client for the appointment composite service.

Used for distributed idempotency caching so the service can scale
horizontally behind a load balancer without duplicate bookings.

DUAL MODE:
- local `redis://` keeps strict fail-closed idempotency semantics
- AWS `rediss://` uses TLS and degrades gracefully if ElastiCache is unavailable
"""

import json
import logging
from typing import Optional
from urllib.parse import urlparse

import redis.asyncio as aioredis
from fastapi import HTTPException

from src.config import settings

logger = logging.getLogger(__name__)

_redis: Optional[aioredis.Redis] = None

IDEMPOTENCY_TTL = 86400  # 24 hours


def _is_aws_tls_redis() -> bool:
    return urlparse(settings.REDIS_URL).scheme == "rediss"


def _make_redis() -> aioredis.Redis:
    """
    Build a Redis client directly (not via from_url) so we have full
    control over SSL parameters regardless of URL scheme.
    """
    parsed = urlparse(settings.REDIS_URL)
    use_ssl = parsed.scheme in ("rediss",)

    kwargs = {
        "host": parsed.hostname,
        "port": parsed.port or 6379,
        "password": parsed.password or None,
        "ssl": use_ssl,
        "decode_responses": True,
        "socket_connect_timeout": 5,
        "socket_timeout": 5,
    }

    if use_ssl:
        # ElastiCache Serverless uses an AWS-internal CA not in the default
        # Python trust bundle — skip certificate verification. redis-py
        # expects these as keyword flags, not an SSLContext object.
        kwargs["ssl_cert_reqs"] = "none"
        kwargs["ssl_check_hostname"] = False

    return aioredis.Redis(**kwargs)


async def get_redis() -> Optional[aioredis.Redis]:
    """Lazy-initialise and return the shared Redis connection, or None on failure."""
    global _redis
    if _redis is None:
        try:
            _redis = _make_redis()
            await _redis.ping()
            logger.info("[Redis] connected to %s:%s", urlparse(settings.REDIS_URL).hostname, urlparse(settings.REDIS_URL).port)
        except Exception as e:
            logger.warning("[Redis] connection failed: %s — idempotency disabled", e)
            _redis = None
    return _redis


async def get_idempotency(key: str) -> Optional[dict]:
    """Return cached response for an idempotency key, or None.

    Local Docker keeps strict idempotency guarantees. AWS rediss degrades
    gracefully so demos keep moving if ElastiCache is briefly unavailable.
    """
    global _redis
    r = await get_redis()
    if r is None:
        if not _is_aws_tls_redis():
            raise HTTPException(
                status_code=503,
                detail="Idempotency store unavailable — please retry shortly",
            )
        logger.warning("[Redis] skipping idempotency check (Redis unavailable)")
        return None
    try:
        cached = await r.get(f"idempotency:appt:{key}")
        if cached:
            return json.loads(cached)
        return None
    except Exception as e:
        logger.error("[Redis] idempotency GET failed (key=%s): %s", key, e)
        _redis = None  # force reconnect next time
        if not _is_aws_tls_redis():
            raise HTTPException(
                status_code=503,
                detail="Idempotency store unavailable — please retry shortly",
            )
        return None


async def set_idempotency(key: str, response: dict) -> None:
    """Cache a response under an idempotency key with TTL.

    Local Docker fails closed. AWS rediss skips caching if the managed
    Redis layer is temporarily unreachable.
    """
    global _redis
    r = await get_redis()
    if r is None:
        if not _is_aws_tls_redis():
            raise HTTPException(
                status_code=503,
                detail="Booking succeeded but idempotency store is unavailable — avoid retrying this request",
            )
        logger.warning("[Redis] skipping idempotency store (Redis unavailable)")
        return
    try:
        await r.setex(
            f"idempotency:appt:{key}",
            IDEMPOTENCY_TTL,
            json.dumps(response),
        )
    except Exception as e:
        logger.error("[Redis] idempotency SET failed (key=%s): %s", key, e)
        _redis = None
        if not _is_aws_tls_redis():
            raise HTTPException(
                status_code=503,
                detail="Booking succeeded but idempotency store is unavailable — avoid retrying this request",
            )
