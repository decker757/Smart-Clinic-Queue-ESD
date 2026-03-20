"""Minimal payment-service stub for local development/testing.
Returns a fake Stripe-style checkout URL for every CreatePaymentRequest.
Replace with the real payment service when implemented.
"""
import asyncio
import uuid
import grpc
from grpc import aio

# ── Inline proto definitions (avoids needing protoc in this stub) ─────────────
from grpc import unary_unary_rpc_method_handler as rpc_handler
from google.protobuf import descriptor_pool, descriptor_pb2, symbol_database
from google.protobuf.descriptor import FileDescriptor

PROTO_SOURCE = """
syntax = "proto3";
package payment;
service PaymentService {
  rpc CreatePaymentRequest (PaymentRequest) returns (PaymentResponse);
}
message PaymentRequest { string appointment_id = 1; string patient_id = 2; }
message PaymentResponse { string payment_id = 1; string payment_link = 2; }
"""

# Use grpc reflection / dynamic proto loading via raw proto compile
import subprocess, sys, tempfile, os, importlib

def generate_stubs():
    proto_dir = tempfile.mkdtemp()
    proto_path = os.path.join(proto_dir, "payment.proto")
    with open(proto_path, "w") as f:
        f.write(PROTO_SOURCE)
    subprocess.run(
        [sys.executable, "-m", "grpc_tools.protoc",
         f"-I{proto_dir}",
         f"--python_out={proto_dir}",
         f"--grpc_python_out={proto_dir}",
         proto_path],
        check=True,
    )
    sys.path.insert(0, proto_dir)
    pb2 = importlib.import_module("payment_pb2")
    pb2_grpc = importlib.import_module("payment_pb2_grpc")
    return pb2, pb2_grpc

pb2, pb2_grpc = generate_stubs()


class PaymentServiceServicer(pb2_grpc.PaymentServiceServicer):
    async def CreatePaymentRequest(self, request, context):
        payment_id = str(uuid.uuid4())
        payment_link = f"https://checkout.stripe.com/pay/stub_{payment_id[:8]}"
        print(f"[Stub] Payment for appointment={request.appointment_id} → {payment_link}")
        return pb2.PaymentResponse(payment_id=payment_id, payment_link=payment_link)


async def serve():
    port = os.getenv("GRPC_PORT", "50056")
    server = aio.server()
    pb2_grpc.add_PaymentServiceServicer_to_server(PaymentServiceServicer(), server)
    server.add_insecure_port(f"[::]:{port}")
    await server.start()
    print(f"[Stub] Payment service listening on port {port}")
    await server.wait_for_termination()


if __name__ == "__main__":
    asyncio.run(serve())
