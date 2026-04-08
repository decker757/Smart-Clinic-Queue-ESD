"""gRPC client for queue-coordinator-service (atomic)."""

import grpc.aio

from src.proto import queue_pb2, queue_pb2_grpc
from src.config import settings


def _channel():
    return grpc.aio.insecure_channel(settings.QUEUE_SERVICE_GRPC)


async def complete_appointment(appointment_id: str):
    """Mark an appointment as completed in the queue and remove from active queue."""
    async with _channel() as channel:
        stub = queue_pb2_grpc.QueueServiceStub(channel)
        response = await stub.CompleteAppointment(
            queue_pb2.AppointmentRequest(appointment_id=appointment_id),
            timeout=10,
        )
        return response


async def remove_from_queue(appointment_id: str):
    """Remove a patient from the active queue."""
    async with _channel() as channel:
        stub = queue_pb2_grpc.QueueServiceStub(channel)
        response = await stub.RemoveFromQueue(
            queue_pb2.AppointmentRequest(appointment_id=appointment_id),
            timeout=10,
        )
        return response
