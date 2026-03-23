import json
import aio_pika
from src.config import settings

_connection: aio_pika.RobustConnection | None = None


async def connect():
    global _connection
    _connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)


async def disconnect():
    global _connection
    if _connection:
        await _connection.close()
        _connection = None


async def publish_event(routing_key: str, payload: dict):
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
        print(f"[RabbitMQ] Failed to publish {routing_key}: {e}")
