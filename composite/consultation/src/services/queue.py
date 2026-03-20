"""gRPC client for queue-coordinator-service (atomic)."""

import grpc.aio

from src.proto import queue_pb2, queue_pb2_grpc
from src.config import settings

channel = grpc.aio.insecure_channel(settings.QUEUE_SERVICE_GRPC)
stub = queue_pb2_grpc.QueueServiceStub(channel)


async def complete_appointment(appointment_id: str):
    """Mark an appointment as completed in the queue and remove from active queue."""
    response = await stub.CompleteAppointment(
        queue_pb2.AppointmentRequest(appointment_id=appointment_id),
        timeout=10,
    )
    return response


async def remove_from_queue(appointment_id: str):
    """Remove a patient from the active queue."""
    response = await stub.RemoveFromQueue(
        queue_pb2.AppointmentRequest(appointment_id=appointment_id),
        timeout=10,
    )
    return response
