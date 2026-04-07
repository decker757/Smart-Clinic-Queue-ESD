from datetime import date
from typing import Optional

from pydantic import BaseModel


# ─── Incoming from Staff Dashboard (frontend) ────────────────
class CompleteConsultationRequest(BaseModel):
    """Sent by doctor when they finish a consultation."""

    appointment_id: str
    patient_id: str
    doctor_id: str

    # MC (medical certificate) — optional
    mc_days: Optional[int] = None
    mc_start_date: Optional[date] = None
    mc_reason: Optional[str] = None

    # Prescription — optional
    prescribed_medication: Optional[str] = None

    # Consultation notes
    diagnosis: Optional[str] = None
    consultation_notes: Optional[str] = None


# ─── Response to frontend ────────────────────────────────────
class ConsultationResponse(BaseModel):
    appointment_id: str
    patient_id: str
    doctor_id: str
    status: str  # "completed"
    message: str
    payment_link: Optional[str] = None
