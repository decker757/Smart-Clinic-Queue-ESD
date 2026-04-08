import grpc.aio
from src.proto import patient_pb2, patient_pb2_grpc
from src.config import settings


def _channel():
    return grpc.aio.insecure_channel(settings.PATIENT_SERVICE_GRPC)


async def get_patient(patient_id: str):
    async with _channel() as channel:
        stub = patient_pb2_grpc.PatientServiceStub(channel)
        return await stub.GetPatient(
            patient_pb2.GetPatientRequest(id=patient_id),
            timeout=10,
        )


async def get_history(patient_id: str):
    async with _channel() as channel:
        stub = patient_pb2_grpc.PatientServiceStub(channel)
        response = await stub.GetHistory(
            patient_pb2.GetHistoryRequest(patient_id=patient_id),
            timeout=10,
        )
        return response.entries


async def get_memos(patient_id: str):
    async with _channel() as channel:
        stub = patient_pb2_grpc.PatientServiceStub(channel)
        response = await stub.GetMemos(
            patient_pb2.GetMemosRequest(patient_id=patient_id),
            timeout=10,
        )
        return response.memos
