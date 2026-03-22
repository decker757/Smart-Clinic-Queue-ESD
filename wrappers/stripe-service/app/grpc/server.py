import asyncio
import grpc
from grpc_reflection.v1alpha import reflection
from app.grpc import payment_pb2, payment_pb2_grpc
from app.services.stripe_service import handle_create_payment


class PaymentServiceServicer(payment_pb2_grpc.PaymentServiceServicer):
    async def CreatePayment(self, request, context):
        try:
            # Convert gRPC request to dict for Stripe service
            payload = {
                "patient_id": request.patient_id,
                "amount": request.amount,
                "currency": request.currency,
                "consultation_id": request.consultation_id,
            }

            # Call Stripe service (async-safe)
            result = await handle_create_payment(payload)

            return payment_pb2.CreatePaymentResponse(
                payment_url=result["payment_url"],
                payment_intent_id=result["payment_intent_id"],
                status=result["status"]
            )

        except Exception as e:
            context.set_details(str(e))
            context.set_code(grpc.StatusCode.INTERNAL)
            return payment_pb2.CreatePaymentResponse()


async def serve():
    # Create async gRPC server
    server = grpc.aio.server()
    payment_pb2_grpc.add_PaymentServiceServicer_to_server(PaymentServiceServicer(), server)

    # Enable reflection for grpcurl
    SERVICE_NAMES = (
        payment_pb2.DESCRIPTOR.services_by_name['PaymentService'].full_name,
        reflection.SERVICE_NAME,
    )
    reflection.enable_server_reflection(SERVICE_NAMES, server)

    server.add_insecure_port("[::]:50051")
    print("💳 Payment gRPC server running on port 50051")
    await server.start()
    await server.wait_for_termination()


if __name__ == "__main__":
    asyncio.run(serve())