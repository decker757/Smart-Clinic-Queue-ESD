import grpc.aio
from src.proto import patient_pb2, patient_pb2_grpc
from src.config import settings

channel = grpc.aio.insecure_channel(settings.PATIENT_SERVICE_GRPC)
stub = patient_pb2_grpc.PatientServiceStub(channel)


async def get_patient(patient_id: str):
    return await stub.GetPatient(patient_pb2.GetPatientRequest(id=patient_id))


async def get_history(patient_id: str):
    response = await stub.GetHistory(patient_pb2.GetHistoryRequest(patient_id=patient_id))
    return response.entries


async def get_memos(patient_id: str):
    response = await stub.GetMemos(patient_pb2.GetMemosRequest(patient_id=patient_id))
    return response.memos
