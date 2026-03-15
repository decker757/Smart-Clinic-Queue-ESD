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


async def create_patient(patient_id: str, phone: str, dob: str, nric: str, gender: str, allergies: list[str]):
    try:
        response = await stub.CreatePatient(patient_pb2.CreatePatientRequest(
            id=patient_id,
            phone=phone,
            dob=dob,
            nric=nric,
            gender=gender,
            allergies=allergies,
        ))
        return response
    except grpc.RpcError as e:
        raise e


async def update_patient(patient_id: str, phone: str = None, dob: str = None, nric: str = None, gender: str = None, allergies: list[str] = None):
    try:
        response = await stub.UpdatePatient(patient_pb2.UpdatePatientRequest(
            id=patient_id,
            phone=phone or "",
            dob=dob or "",
            nric=nric or "",
            gender=gender or "",
            allergies=allergies or [],
        ))
        return response
    except grpc.RpcError as e:
        raise e
