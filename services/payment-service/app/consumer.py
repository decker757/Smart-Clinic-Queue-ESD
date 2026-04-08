import asyncio
import json
import logging
import aio_pika
from app.config import settings
from app.db import get_pool

logger = logging.getLogger(__name__)

EXCHANGE = "clinic.events"

# Dead-letter exchange: failed messages go here for inspection/replay
DLX = "clinic.events.dlx"
DLQ = "payment-service.events.dlq"


def _validate_payload(status: str, payload: dict):
    required = ["consultation_id", "patient_id", "payment_intent_id"]
    if status == "pending":
        required.append("payment_link")

    missing = [field for field in required if not payload.get(field)]
    if missing:
        raise ValueError(f"Missing required payment fields: {', '.join(missing)}")


async def _record_payment(status: str, payload: dict):
    _validate_payload(status, payload)
    pool = await get_pool()
    async with pool.acquire() as conn:
        await conn.execute(
            """
            INSERT INTO payments.payments
                (consultation_id, patient_id, payment_intent_id, amount_cents, currency, status, payment_link)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (consultation_id, payment_intent_id) WHERE payment_intent_id IS NOT NULL
            DO UPDATE SET
                status       = EXCLUDED.status,
                payment_link = EXCLUDED.payment_link
            """,
            payload.get("consultation_id"),
            payload.get("patient_id"),
            payload.get("payment_intent_id"),
            payload.get("amount_cents"),
            payload.get("currency", "sgd"),
            status,
            payload.get("payment_link"),
        )
    logger.info("Recorded payment %s for consultation %s", status, payload.get("consultation_id"))


async def _consume_once():
    """Connect, declare topology, and consume until the connection drops."""
    connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
    channel = await connection.channel()
    exchange = await channel.declare_exchange(EXCHANGE, aio_pika.ExchangeType.TOPIC, durable=True)

    # Declare DLX and DLQ
    dlx = await channel.declare_exchange(DLX, aio_pika.ExchangeType.TOPIC, durable=True)
    dlq = await channel.declare_queue(DLQ, durable=True)
    await dlq.bind(dlx, routing_key="#")

    queue = await channel.declare_queue(
        "payment-service.events",
        durable=True,
        arguments={"x-dead-letter-exchange": DLX},
    )
    await queue.bind(exchange, routing_key="payment.pending")
    await queue.bind(exchange, routing_key="payment.completed")
    await queue.bind(exchange, routing_key="payment.failed")

    logger.info("[Consumer] Connected and consuming from payment-service.events")
    async with queue.iterator() as messages:
        async for message in messages:
            try:
                payload = json.loads(message.body)
                routing_key = message.routing_key
                if routing_key == "payment.pending":
                    await _record_payment("pending", payload)
                elif routing_key == "payment.completed":
                    await _record_payment("paid", payload)
                elif routing_key == "payment.failed":
                    await _record_payment("failed", payload)
                await message.ack()
            except Exception:
                logger.exception("Failed to process payment event — sending to DLQ")
                await message.nack(requeue=False)


async def start_consumer():
    """Retry loop — restarts the consumer if setup or the connection ever fails."""
    while True:
        try:
            await _consume_once()
        except asyncio.CancelledError:
            logger.info("[Consumer] Shutting down")
            raise
        except Exception as e:
            logger.error("[Consumer] Crashed (%s), restarting in 5s…", e)
            await asyncio.sleep(5)
