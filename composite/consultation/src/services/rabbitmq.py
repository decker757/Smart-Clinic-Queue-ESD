import json

import aio_pika

from src.config import settings


async def publish_event(routing_key: str, payload: dict):
    """Publish event to clinic.events topic exchange.

    routing_key examples:
        "consultation.completed"
    """
    try:
        connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
        async with connection:
            channel = await connection.channel()
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
        print(f"[RabbitMQ] Failed to publish {routing_key}: {e}")
