"""
Async Redis client for the appointment composite service.

Used for distributed idempotency caching so the service can scale
horizontally behind a load balancer without duplicate bookings.

STRICT MODE: if Redis is unreachable when an idempotency key is provided,
the request is rejected (503) rather than silently losing duplicate protection.
Duplicate appointments are worse than a brief "try again later".
"""

import json
import logging
from typing import Optional

import redis.asyncio as aioredis
from fastapi import HTTPException

from src.config import settings

logger = logging.getLogger(__name__)

_redis: Optional[aioredis.Redis] = None

IDEMPOTENCY_TTL = 86400  # 24 hours — long enough to catch retries, short enough to self-clean


async def get_redis() -> aioredis.Redis:
    """Lazy-initialise and return the shared Redis connection."""
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
        )
        try:
            await _redis.ping()
            logger.info("[Redis] connected to %s", settings.REDIS_URL)
        except Exception as e:
            logger.warning("[Redis] startup ping failed: %s", e)
    return _redis


async def get_idempotency(key: str) -> Optional[dict]:
    """Return cached response for an idempotency key, or None.

    Raises 503 if Redis is unreachable — we cannot safely allow the
    request through without duplicate protection.
    """
    try:
        r = await get_redis()
        cached = await r.get(f"idempotency:appt:{key}")
        if cached:
            return json.loads(cached)
        return None
    except Exception as e:
        logger.error("[Redis] idempotency GET failed (key=%s): %s", key, e)
        raise HTTPException(
            status_code=503,
            detail="Idempotency store unavailable — please retry shortly",
        )


async def set_idempotency(key: str, response: dict) -> None:
    """Cache a response under an idempotency key with TTL.

    Raises 503 if Redis is unreachable — the booking succeeded but we
    cannot guarantee idempotency for future retries, so we alert the client.
    """
    try:
        r = await get_redis()
        await r.setex(
            f"idempotency:appt:{key}",
            IDEMPOTENCY_TTL,
            json.dumps(response),
        )
    except Exception as e:
        logger.error("[Redis] idempotency SET failed (key=%s): %s", key, e)
        raise HTTPException(
            status_code=503,
            detail="Booking succeeded but idempotency store is unavailable — avoid retrying this request",
        )
