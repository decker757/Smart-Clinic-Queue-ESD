import grpc.aio
from src.proto import patient_pb2, patient_pb2_grpc
from src.config import settings

channel = grpc.aio.insecure_channel(settings.PATIENT_SERVICE_GRPC)
stub = patient_pb2_grpc.PatientServiceStub(channel)


async def get_memos(patient_id: str):
    try:
        response = await stub.GetMemos(patient_pb2.GetMemosRequest(patient_id=patient_id))
        return response.memos
    except grpc.RpcError as e:
        raise e


async def create_text_memo(patient_id: str, title: str, content: str):
    try:
        response = await stub.CreateTextMemo(patient_pb2.CreateTextMemoRequest(
            patient_id=patient_id,
            title=title,
            content=content,
        ))
        return response
    except grpc.RpcError as e:
        raise e


async def create_file_memo(patient_id: str, title: str, file_data: bytes, original_name: str, mimetype: str):
    try:
        response = await stub.CreateFileMemo(patient_pb2.CreateFileMemoRequest(
            patient_id=patient_id,
            title=title,
            file_data=file_data,
            original_name=original_name,
            mimetype=mimetype,
        ))
        return response
    except grpc.RpcError as e:
        raise e


async def create_doctor_record(patient_id: str, title: str, content: str, record_type: str, issued_by: str):
    try:
        response = await stub.CreateDoctorRecord(patient_pb2.CreateDoctorRecordRequest(
            patient_id=patient_id,
            title=title,
            content=content,
            record_type=record_type,
            issued_by=issued_by,
        ))
        return response
    except grpc.RpcError as e:
        raise e
