import json
import aio_pika
from app.config.settings import settings

EXCHANGE = "clinic.events"
LATE_TTL_QUEUE = "late-detection-ttl"
LATE_TTL_MS = settings.LATE_TTL_MS


async def publish_event(routing_key: str, payload: dict):
    """Publish an event to the clinic topic exchange."""
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
    except Exception as e:
        # log but don't fail the request if RabbitMQ is unavailable
        print(f"[RabbitMQ] Failed to publish {routing_key}: {e}")


async def publish_late_with_ttl(payload: dict):
    """Publish the late-detection payload to a TTL queue.

    If the patient does not respond within LATE_TTL_MS, the message is
    dead-lettered to clinic.events with routing key 'queue.removed',
    automatically removing them from the queue.
    """
    try:
        connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
        async with connection:
            channel = await connection.channel()

            # Ensure the main exchange exists (idempotent)
            await channel.declare_exchange(
                EXCHANGE,
                aio_pika.ExchangeType.TOPIC,
                durable=True,
            )

            # TTL queue: messages expire → dead-letter to clinic.events as queue.removed
            await channel.declare_queue(
                LATE_TTL_QUEUE,
                durable=True,
                arguments={
                    "x-message-ttl": LATE_TTL_MS,
                    "x-dead-letter-exchange": EXCHANGE,
                    "x-dead-letter-routing-key": "queue.removed",
                },
            )

            # Publish directly to the queue via the default exchange
            await channel.default_exchange.publish(
                aio_pika.Message(
                    body=json.dumps(payload).encode(),
                    content_type="application/json",
                ),
                routing_key=LATE_TTL_QUEUE,
            )
    except Exception as e:
        print(f"[RabbitMQ] Failed to publish late TTL message: {e}")
