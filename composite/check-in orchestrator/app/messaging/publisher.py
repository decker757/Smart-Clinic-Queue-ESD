import json
import aio_pika
from app.config.settings import settings

async def publish_event(routing_key: str, payload: dict):
    """Publish an event to the clinic topic exchange.

    routing_key examples: "appointment.booked", "appointment.cancelled"
    Each downstream service binds its own queue to this exchange,
    so all subscribers receive every matching event independently.
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
        # log but don't fail the request if RabbitMQ is unavailable
        print(f"[RabbitMQ] Failed to publish {routing_key}: {e}")