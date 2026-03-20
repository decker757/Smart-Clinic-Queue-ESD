from pydantic import BaseModel


class DoctorResponse(BaseModel):
    id: str
    name: str
    specialisation: str
    contact: str
    created_at: str


class SlotResponse(BaseModel):
    id: str
    doctor_id: str
    start_time: str
    end_time: str
    status: str


class UpdateSlotStatusRequest(BaseModel):
    status: str


class AddConsultationNotesRequest(BaseModel):
    patient_id: str
    notes: str
    diagnosis: str


class ConsultationNotesResponse(BaseModel):
    id: str
    appointment_id: str
    doctor_id: str
    patient_id: str
    created_at: str
