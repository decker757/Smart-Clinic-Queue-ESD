"""gRPC client for stripe-service (wrapper).

Scenario 3, Step 11: The Consultation Orchestrator calls the Stripe
Wrapper via gRPC to create a Stripe Checkout session. The Stripe Wrapper
independently publishes a payment.pending event to RabbitMQ (Step 15).
"""

import grpc.aio

from src.config import settings
from src.proto import payment_pb2, payment_pb2_grpc


def _channel():
    return grpc.aio.insecure_channel(settings.STRIPE_SERVICE_GRPC)


async def create_payment_request(
    appointment_id: str,
    patient_id: str,
) -> dict:
    """Create a Stripe checkout session via the Stripe Wrapper gRPC service.

    Returns dict with 'payment_id' and 'payment_link'.
    The Stripe Wrapper publishes a payment.pending event independently.
    """
    async with _channel() as channel:
        stub = payment_pb2_grpc.PaymentServiceStub(channel)
        response = await stub.CreatePaymentRequest(
            payment_pb2.PaymentRequest(
                appointment_id=appointment_id,
                patient_id=patient_id,
            ),
            timeout=10,
        )
    return {
        "payment_id": response.payment_id,
        "payment_link": response.payment_link,
    }
