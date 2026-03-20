from pydantic import BaseModel


class QueuePositionResponse(BaseModel):
    queue_number: int
    estimated_time: str
    status: str


class QueueEntryResponse(BaseModel):
    appointment_id: str
    patient_id: str
    doctor_id: str
    session: str
    queue_number: int
    status: str
    estimated_time: str


class AddToQueueRequest(BaseModel):
    appointment_id: str
    patient_id: str
    doctor_id: str
    session: str
    start_time: str


class CallNextRequest(BaseModel):
    session: str
    doctor_id: str
