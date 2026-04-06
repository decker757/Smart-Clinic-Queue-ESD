import grpc.aio
from src.proto import queue_pb2, queue_pb2_grpc
from src.config import settings


def _channel():
    return grpc.aio.insecure_channel(settings.QUEUE_SERVICE_GRPC)


async def get_queue_position(appointment_id: str):
    async with _channel() as channel:
        stub = queue_pb2_grpc.QueueServiceStub(channel)
        return await stub.GetQueuePosition(
            queue_pb2.AppointmentRequest(
                appointment_id=appointment_id,
            ),
            timeout=10,
        )


async def check_in(appointment_id: str):
    # No caller_id — staff check-in bypasses patient ownership check in queue-coordinator
    async with _channel() as channel:
        stub = queue_pb2_grpc.QueueServiceStub(channel)
        return await stub.CheckIn(
            queue_pb2.CallerRequest(
                appointment_id=appointment_id,
            ),
            timeout=10,
        )


async def add_to_queue(appointment_id: str, patient_id: str, doctor_id: str, session: str, start_time: str):
    async with _channel() as channel:
        stub = queue_pb2_grpc.QueueServiceStub(channel)
        return await stub.AddToQueue(
            queue_pb2.AddToQueueRequest(
                appointment_id=appointment_id,
                patient_id=patient_id,
                doctor_id=doctor_id,
                session=session,
                start_time=start_time,
            ),
            timeout=10,
        )


async def remove_from_queue(appointment_id: str):
    async with _channel() as channel:
        stub = queue_pb2_grpc.QueueServiceStub(channel)
        return await stub.RemoveFromQueue(
            queue_pb2.AppointmentRequest(
                appointment_id=appointment_id,
            ),
            timeout=10,
        )


async def mark_no_show(appointment_id: str):
    async with _channel() as channel:
        stub = queue_pb2_grpc.QueueServiceStub(channel)
        return await stub.MarkNoShow(
            queue_pb2.AppointmentRequest(
                appointment_id=appointment_id,
            ),
            timeout=10,
        )


async def complete_appointment(appointment_id: str):
    async with _channel() as channel:
        stub = queue_pb2_grpc.QueueServiceStub(channel)
        return await stub.CompleteAppointment(
            queue_pb2.AppointmentRequest(
                appointment_id=appointment_id,
            ),
            timeout=10,
        )


async def call_next(session: str, doctor_id: str):
    async with _channel() as channel:
        stub = queue_pb2_grpc.QueueServiceStub(channel)
        return await stub.CallNext(
            queue_pb2.CallNextRequest(
                session=session,
                doctor_id=doctor_id,
            ),
            timeout=10,
        )
