import grpc.aio
from src.proto import patient_pb2, patient_pb2_grpc
from src.config import settings


def _channel():
    return grpc.aio.insecure_channel(settings.PATIENT_SERVICE_GRPC)


async def get_memos(patient_id: str):
    try:
        async with _channel() as channel:
            stub = patient_pb2_grpc.PatientServiceStub(channel)
            response = await stub.GetMemos(
                patient_pb2.GetMemosRequest(patient_id=patient_id),
                timeout=10,
            )
            return response.memos
    except grpc.RpcError as e:
        raise e


async def create_text_memo(patient_id: str, title: str, content: str):
    try:
        async with _channel() as channel:
            stub = patient_pb2_grpc.PatientServiceStub(channel)
            response = await stub.CreateTextMemo(
                patient_pb2.CreateTextMemoRequest(
                    patient_id=patient_id,
                    title=title,
                    content=content,
                ),
                timeout=10,
            )
            return response
    except grpc.RpcError as e:
        raise e


async def create_file_memo(patient_id: str, title: str, file_data: bytes, original_name: str, mimetype: str):
    try:
        async with _channel() as channel:
            stub = patient_pb2_grpc.PatientServiceStub(channel)
            response = await stub.CreateFileMemo(
                patient_pb2.CreateFileMemoRequest(
                    patient_id=patient_id,
                    title=title,
                    file_data=file_data,
                    original_name=original_name,
                    mimetype=mimetype,
                ),
                timeout=10,
            )
            return response
    except grpc.RpcError as e:
        raise e


async def create_doctor_record(patient_id: str, title: str, content: str, record_type: str, issued_by: str):
    try:
        async with _channel() as channel:
            stub = patient_pb2_grpc.PatientServiceStub(channel)
            response = await stub.CreateDoctorRecord(
                patient_pb2.CreateDoctorRecordRequest(
                    patient_id=patient_id,
                    title=title,
                    content=content,
                    record_type=record_type,
                    issued_by=issued_by,
                ),
                timeout=10,
            )
            return response
    except grpc.RpcError as e:
        raise e
