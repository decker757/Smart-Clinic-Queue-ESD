"""gRPC client for stripe-service (Stripe wrapper).

Security: This is an internal-only gRPC call between the consultation
orchestrator and the stripe wrapper. Both services run inside the same
Docker network (local) or ECS VPC (AWS) with no external exposure.
The originating HTTP request was already authenticated at the API gateway
layer, so we do not re-attach a bearer token on the gRPC channel.
"""

import grpc.aio

from src.proto import payment_pb2, payment_pb2_grpc
from src.config import settings

channel = grpc.aio.insecure_channel(settings.PAYMENT_SERVICE_GRPC)
stub = payment_pb2_grpc.PaymentServiceStub(channel)


async def create_payment_request(appointment_id: str, patient_id: str) -> str:
    """Send payment request to stripe-service → Stripe. Returns checkout URL."""
    response = await stub.CreatePaymentRequest(
        payment_pb2.PaymentRequest(
            appointment_id=appointment_id,
            patient_id=patient_id,
        ),
        timeout=15,
    )
    return response.payment_link
