import json
import logging
import aio_pika
from app.config import settings
from app.db import get_pool

logger = logging.getLogger(__name__)

EXCHANGE = "clinic.events"


async def _record_payment(status: str, payload: dict):
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute(
            """
            INSERT INTO payments.payments
                (consultation_id, patient_id, payment_intent_id, status, payment_link)
            VALUES ($1, $2, $3, $4, $5)
            """,
            payload.get("consultation_id"),
            payload.get("patient_id"),
            payload.get("payment_intent_id"),
            status,
            payload.get("payment_link"),
        )
    logger.info("Recorded payment %s for consultation %s", status, payload.get("consultation_id"))


async def start_consumer():
    connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
    channel = await connection.channel()
    exchange = await channel.declare_exchange(EXCHANGE, aio_pika.ExchangeType.TOPIC, durable=True)
    queue = await channel.declare_queue("payment-service.events", durable=True)
    await queue.bind(exchange, routing_key="payment.pending")
    await queue.bind(exchange, routing_key="payment.completed")
    await queue.bind(exchange, routing_key="payment.failed")

    async with queue.iterator() as messages:
        async for message in messages:
            async with message.process():
                try:
                    payload = json.loads(message.body)
                    routing_key = message.routing_key
                    if routing_key == "payment.pending":
                        await _record_payment("pending", payload)
                    elif routing_key == "payment.completed":
                        await _record_payment("paid", payload)
                    elif routing_key == "payment.failed":
                        await _record_payment("failed", payload)
                except Exception:
                    logger.exception("Failed to process payment event")
