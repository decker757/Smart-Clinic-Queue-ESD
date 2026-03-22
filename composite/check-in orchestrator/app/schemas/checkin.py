from pydantic import BaseModel
from datetime import datetime
from typing import Optional

class Location(BaseModel):
    lat: float
    lng: float

class CheckInRequest(BaseModel):
    patient_id: str
    appointment_time: datetime
    patient_location: Location   # now a dict-like object
    clinic_location: Location



class CheckInResponse(BaseModel):
    status: str
    eta_minutes: Optional[int] = None


class ConfirmRequest(BaseModel):
    patient_id: str
    is_coming: bool