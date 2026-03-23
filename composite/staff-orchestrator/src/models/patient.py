from pydantic import BaseModel
from typing import List, Optional


class PatientResponse(BaseModel):
    id: str
    phone: str
    dob: str
    nric: str
    gender: Optional[str] = None
    allergies: Optional[List[str]] = []
    created_at: str
    updated_at: str


class HistoryResponse(BaseModel):
    id: str
    patient_id: str
    diagnosis: str
    diagnosed_at: str
    notes: str
    created_at: str
