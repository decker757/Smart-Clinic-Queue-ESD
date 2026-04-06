import json
import logging

import aio_pika

from app.config import settings

logger = logging.getLogger(__name__)

EXCHANGE = "clinic.events"


async def publish_event(routing_key: str, payload: dict) -> None:
    """Best-effort event publishing for downstream notifications/logging."""
    try:
        connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
        async with connection:
            channel = await connection.channel()
            exchange = await channel.declare_exchange(
                EXCHANGE,
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
    except Exception:
        logger.exception("Failed to publish %s event", routing_key)
