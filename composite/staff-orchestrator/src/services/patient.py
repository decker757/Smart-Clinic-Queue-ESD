import grpc.aio
from src.proto import patient_pb2, patient_pb2_grpc
from src.config import settings

channel = grpc.aio.insecure_channel(settings.PATIENT_SERVICE_GRPC)
stub = patient_pb2_grpc.PatientServiceStub(channel)


async def get_patient(patient_id: str):
    try:
        response = await stub.GetPatient(patient_pb2.GetPatientRequest(id=patient_id))
        return response
    except grpc.RpcError as e:
        raise e


async def get_history(patient_id: str):
    try:
        response = await stub.GetHistory(patient_pb2.GetHistoryRequest(patient_id=patient_id))
        return response.entries
    except grpc.RpcError as e:
        raise e
