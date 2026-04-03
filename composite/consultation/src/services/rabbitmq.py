import asyncio
import json
import logging

import aio_pika
from aio_pika.abc import AbstractRobustConnection

from src.config import settings

logger = logging.getLogger(__name__)

_connection: AbstractRobustConnection | None = None

PUBLISH_MAX_RETRIES = 3
PUBLISH_RETRY_DELAY = 0.5  # seconds, doubles each attempt


async def connect():
    global _connection
    _connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
    logger.info("RabbitMQ connection established")


async def disconnect():
    global _connection
    if _connection and not _connection.is_closed:
        await _connection.close()
    _connection = None


async def publish_event(routing_key: str, payload: dict) -> bool:
    """Publish event to clinic.events topic exchange with retry.

    Returns True on success, False if all retries exhausted.
    Retries up to 3 times with exponential backoff. Reconnects if
    the persistent connection has dropped.
    """
    global _connection
    last_error: Exception | None = None

    for attempt in range(PUBLISH_MAX_RETRIES):
        try:
            # Reconnect if connection was lost
            if _connection is None or _connection.is_closed:
                _connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
                logger.info("RabbitMQ reconnected")

            channel = await _connection.channel()
            exchange = await channel.declare_exchange(
                "clinic.events",
                aio_pika.ExchangeType.TOPIC,
                durable=True,
            )
            await exchange.publish(
                aio_pika.Message(
                    body=json.dumps(payload).encode(),
                    content_type="application/json",
                ),
                routing_key=routing_key,
            )
            return True
        except Exception as e:
            last_error = e
            delay = PUBLISH_RETRY_DELAY * (2 ** attempt)
            logger.warning(
                "Publish %s attempt %d/%d failed: %s. Retrying in %.1fs...",
                routing_key, attempt + 1, PUBLISH_MAX_RETRIES, e, delay,
            )
            # Force reconnect on next attempt
            _connection = None
            await asyncio.sleep(delay)

    logger.error("Publish %s failed after %d retries: %s", routing_key, PUBLISH_MAX_RETRIES, last_error)
    return False
