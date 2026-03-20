import json
import logging

import aio_pika
from aio_pika.abc import AbstractRobustConnection

from src.config import settings

logger = logging.getLogger(__name__)

_connection: AbstractRobustConnection | None = None


async def connect():
    global _connection
    _connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
    logger.info("RabbitMQ connection established")


async def disconnect():
    global _connection
    if _connection and not _connection.is_closed:
        await _connection.close()
    _connection = None


async def publish_event(routing_key: str, payload: dict):
    """Publish event to clinic.events topic exchange."""
    if _connection is None or _connection.is_closed:
        logger.error("RabbitMQ not connected — cannot publish %s", routing_key)
        return
    try:
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
    except Exception as e:
        logger.error("Failed to publish %s: %s", routing_key, e)
