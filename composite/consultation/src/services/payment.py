"""gRPC client for stripe-service (Stripe wrapper)."""

import grpc.aio

from src.proto import payment_pb2, payment_pb2_grpc
from src.config import settings

channel = grpc.aio.insecure_channel(settings.PAYMENT_SERVICE_GRPC)
stub = payment_pb2_grpc.PaymentServiceStub(channel)


async def create_payment_request(appointment_id: str, patient_id: str) -> str:
    """Send payment request to payment-service → Stripe. Returns checkout URL."""
    response = await stub.CreatePaymentRequest(
        payment_pb2.PaymentRequest(
            appointment_id=appointment_id,
            patient_id=patient_id,
        ),
        timeout=15,
    )
    return response.payment_link
