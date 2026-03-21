from pydantic import BaseModel
from datetime import datetime
from typing import Optional


class CheckInRequest(BaseModel):
    patient_id: str
    appointment_time: datetime
    patient_location: str
    clinic_location: str



class CheckInResponse(BaseModel):
    status: str
    eta_minutes: Optional[int] = None


class ConfirmRequest(BaseModel):
    patient_id: str
    is_coming: bool