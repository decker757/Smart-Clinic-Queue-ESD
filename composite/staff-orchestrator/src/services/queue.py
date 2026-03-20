import grpc.aio
from src.proto import queue_pb2, queue_pb2_grpc
from src.config import settings

channel = grpc.aio.insecure_channel(settings.QUEUE_SERVICE_GRPC)
stub = queue_pb2_grpc.QueueServiceStub(channel)


async def get_queue_position(appointment_id: str):
    try:
        response = await stub.GetQueuePosition(queue_pb2.AppointmentRequest(
            appointment_id=appointment_id,
        ))
        return response
    except grpc.RpcError as e:
        raise e


async def check_in(appointment_id: str, caller_id: str):
    try:
        response = await stub.CheckIn(queue_pb2.CallerRequest(
            appointment_id=appointment_id,
            caller_id=caller_id,
        ))
        return response
    except grpc.RpcError as e:
        raise e


async def add_to_queue(appointment_id: str, patient_id: str, doctor_id: str, session: str, start_time: str):
    try:
        response = await stub.AddToQueue(queue_pb2.AddToQueueRequest(
            appointment_id=appointment_id,
            patient_id=patient_id,
            doctor_id=doctor_id,
            session=session,
            start_time=start_time,
        ))
        return response
    except grpc.RpcError as e:
        raise e


async def remove_from_queue(appointment_id: str):
    try:
        response = await stub.RemoveFromQueue(queue_pb2.AppointmentRequest(
            appointment_id=appointment_id,
        ))
        return response
    except grpc.RpcError as e:
        raise e


async def mark_no_show(appointment_id: str):
    try:
        response = await stub.MarkNoShow(queue_pb2.AppointmentRequest(
            appointment_id=appointment_id,
        ))
        return response
    except grpc.RpcError as e:
        raise e


async def complete_appointment(appointment_id: str):
    try:
        response = await stub.CompleteAppointment(queue_pb2.AppointmentRequest(
            appointment_id=appointment_id,
        ))
        return response
    except grpc.RpcError as e:
        raise e


async def call_next(session: str, doctor_id: str):
    try:
        response = await stub.CallNext(queue_pb2.CallNextRequest(
            session=session,
            doctor_id=doctor_id,
        ))
        return response
    except grpc.RpcError as e:
        raise e
