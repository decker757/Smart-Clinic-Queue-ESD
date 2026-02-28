from pydantic import BaseModel
from datetime import datetime


# ─── Incoming from frontend ──────────────────────────────────

class CreateAppointmentRequest(BaseModel):
    patient_id: str
    doctor_id: str | None = None        # optional doctor preference
    start_time: datetime                 # preferred timeslot
    notes: str | None = None            # symptoms / reason for visit


# ─── Sent to atomic appointment-service ──────────────────────

class AppointmentServiceRequest(BaseModel):
    patient_id: str
    doctor_id: str | None = None
    start_time: datetime
    notes: str | None = None


# ─── Sent to notification-service (via RabbitMQ) ─────────────

class AppointmentBookedEvent(BaseModel):
    appointment_id: str
    patient_id: str
    doctor_id: str | None = None
    start_time: datetime


# ─── Returned to frontend ────────────────────────────────────

class AppointmentResponse(BaseModel):
    id: str
    patient_id: str
    doctor_id: str | None = None
    start_time: datetime
    estimated_time: datetime | None = None  # set later by ETA service
    queue_position: int | None = None       # set later by queue coordinator
    notes: str | None = None
    status: str
    created_at: datetime
    updated_at: datetime
