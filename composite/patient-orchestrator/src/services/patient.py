import grpc.aio
from src.proto import patient_pb2, patient_pb2_grpc
from src.config import settings


def _channel():
    return grpc.aio.insecure_channel(settings.PATIENT_SERVICE_GRPC)


async def get_patient(patient_id: str):
    try:
        async with _channel() as channel:
            stub = patient_pb2_grpc.PatientServiceStub(channel)
            response = await stub.GetPatient(
                patient_pb2.GetPatientRequest(id=patient_id),
                timeout=10,
            )
            return response
    except grpc.RpcError as e:
        raise e


async def create_patient(patient_id: str, phone: str, dob: str, nric: str, gender: str, allergies: list[str]):
    try:
        async with _channel() as channel:
            stub = patient_pb2_grpc.PatientServiceStub(channel)
            response = await stub.CreatePatient(
                patient_pb2.CreatePatientRequest(
                    id=patient_id,
                    phone=phone,
                    dob=dob,
                    nric=nric,
                    gender=gender,
                    allergies=allergies,
                ),
                timeout=10,
            )
            return response
    except grpc.RpcError as e:
        raise e


async def update_patient(patient_id: str, phone: str = None, dob: str = None, nric: str = None, gender: str = None, allergies: list[str] = None):
    try:
        async with _channel() as channel:
            stub = patient_pb2_grpc.PatientServiceStub(channel)
            response = await stub.UpdatePatient(
                patient_pb2.UpdatePatientRequest(
                    id=patient_id,
                    phone=phone or "",
                    dob=dob or "",
                    nric=nric or "",
                    gender=gender or "",
                    allergies=allergies or [],
                ),
                timeout=10,
            )
            return response
    except grpc.RpcError as e:
        raise e
