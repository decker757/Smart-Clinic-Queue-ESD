from pydantic import BaseModel
from typing import Optional

class AddHistoryRequest(BaseModel):
    diagnosis: str
    diagnosed_at: Optional[str] = None
    notes: Optional[str] = None

class HistoryResponse(BaseModel):
    id: str
    patient_id: str
    diagnosis: str
    diagnosed_at: Optional[str] = None
    notes: Optional[str] = None
    created_at: str

