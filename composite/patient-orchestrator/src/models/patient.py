from pydantic import BaseModel
from typing import Optional, List

class CreatePatientRequest(BaseModel):
    phone: str
    dob: str
    nric: str
    gender: Optional[str] = None
    allergies: Optional[List[str]] = []

class UpdatePatientRequest(BaseModel):
    phone: Optional[str] = None
    dob: Optional[str] = None
    nric: Optional[str] = None
    gender: Optional[str] = None
    allergies: Optional[List[str]] = None

class PatientResponse(BaseModel):
    id:str
    phone: str
    dob: str
    nric: str
    gender: Optional[str] = None
    allergies: Optional[List[str]] = []
    created_at: str
    updated_at: str