import grpc.aio
from src.proto import patient_pb2, patient_pb2_grpc
from src.models.history import AddHistoryRequest, HistoryResponse
from src.config import settings


def _channel():
    return grpc.aio.insecure_channel(settings.PATIENT_SERVICE_GRPC)

async def list_history(patient_id: str) -> list[HistoryResponse]:
    try:
        async with _channel() as channel:
            stub = patient_pb2_grpc.PatientServiceStub(channel)
            response = await stub.GetHistory(
                patient_pb2.GetHistoryRequest(patient_id=patient_id),
                timeout=10,
            )
            return response.entries
    except grpc.RpcError as e:
        raise e

async def add_history(patient_id: str, diagnosis: str, diagnosed_at: str = "", notes: str = ""):
    try:
        async with _channel() as channel:
            stub = patient_pb2_grpc.PatientServiceStub(channel)
            response = await stub.AddHistory(
                patient_pb2.AddHistoryRequest(
                    patient_id=patient_id,
                    diagnosis=diagnosis,
                    diagnosed_at=diagnosed_at,
                    notes=notes,
                ),
                timeout=10,
            )
            return response
    except grpc.RpcError as e:
        raise e
