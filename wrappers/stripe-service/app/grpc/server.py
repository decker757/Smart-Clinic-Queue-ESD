import asyncio
import grpc
from grpc_reflection.v1alpha import reflection
from app.grpc import payment_pb2, payment_pb2_grpc
from app.config.settings import settings
from app.services.stripe_service import create_checkout_session
from app.messaging.publisher import publish_event


class PaymentServiceServicer(payment_pb2_grpc.PaymentServiceServicer):
    async def CreatePaymentRequest(self, request, context):
        """Create a Stripe checkout session and publish payment.pending event.

        Security: This gRPC endpoint is internal-only. Callers are already
        authenticated at the API gateway layer (Kong locally, AWS API Gateway
        in production). Only composite orchestrators running inside the
        Docker/ECS network can reach this port — it is never exposed externally.
        """
        try:
            session = create_checkout_session(
                amount=settings.CONSULTATION_FEE_CENTS,
                currency=settings.CURRENCY,
                consultation_id=request.appointment_id,
                patient_id=request.patient_id,
            )
            await publish_event("payment.pending", {
                "consultation_id": request.appointment_id,
                "patient_id": request.patient_id,
                "payment_intent_id": session.id,
                "payment_link": session.url,
            })
            return payment_pb2.PaymentResponse(
                payment_id=session.payment_intent or session.id,
                payment_link=session.url,
            )
        except Exception as e:
            context.set_details(str(e))
            context.set_code(grpc.StatusCode.INTERNAL)
            return payment_pb2.PaymentResponse()


async def serve():
    server = grpc.aio.server()
    payment_pb2_grpc.add_PaymentServiceServicer_to_server(PaymentServiceServicer(), server)

    SERVICE_NAMES = (
        payment_pb2.DESCRIPTOR.services_by_name['PaymentService'].full_name,
        reflection.SERVICE_NAME,
    )
    reflection.enable_server_reflection(SERVICE_NAMES, server)

    server.add_insecure_port("[::]:50051")
    await server.start()
    await server.wait_for_termination()


if __name__ == "__main__":
    asyncio.run(serve())
