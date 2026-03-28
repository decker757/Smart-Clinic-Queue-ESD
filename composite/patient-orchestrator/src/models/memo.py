from pydantic import BaseModel
from typing import Optional

#POST /memos - text note
class CreateTextMemoRequest(BaseModel): 
    title: str
    content: str

#POST /memos/upload
class CreateFileMemoRequest(BaseModel):
    title: str

#POST /memos/doctor
class CreateDoctorRecordRequest(BaseModel):
    title: str
    content: str
    record_type: str # "mc" or "prescription"
    file_type: Optional[str] = None
    issued_by: str

class MemoResponse(BaseModel):
    id: str
    patient_id: str
    title: str
    content: Optional[str] = None
    file_url: Optional[str] = None
    file_type: Optional[str] = None
    record_type: str
    issued_by: Optional[str] = None
    appointment_id: Optional[str] = None
    created_at: str
