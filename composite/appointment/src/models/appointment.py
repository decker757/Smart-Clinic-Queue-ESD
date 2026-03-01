from pydantic import BaseModel, model_validator
from datetime import datetime
from typing import Literal


# ─── Incoming from frontend ──────────────────────────────────

class CreateAppointmentRequest(BaseModel):
    patient_id: str
    doctor_id: str | None = None
    start_time: datetime | None = None                       # required for specific doctor bookings
    session: Literal["morning", "afternoon"] | None = None  # required for generic bookings
    notes: str | None = None

    @model_validator(mode="after")
    def validate_booking_type(self):
        if self.session and self.start_time:
            raise ValueError("provide either session or start_time+doctor_id, not both")
        if not self.session and not self.start_time:
            raise ValueError("provide either session (morning/afternoon) or start_time+doctor_id")
        if self.start_time and not self.doctor_id:
            raise ValueError("doctor_id is required when start_time is provided")
        return self


# ─── Sent to atomic appointment-service ──────────────────────

class AppointmentServiceRequest(BaseModel):
    patient_id: str
    doctor_id: str | None = None
    start_time: datetime | None = None
    session: str | None = None
    notes: str | None = None


# ─── Sent to downstream services (via RabbitMQ) ──────────────

class AppointmentBookedEvent(BaseModel):
    appointment_id: str
    patient_id: str
    doctor_id: str | None = None
    start_time: datetime | None = None
    session: str | None = None


# ─── Returned to frontend ────────────────────────────────────

class AppointmentResponse(BaseModel):
    id: str
    patient_id: str
    doctor_id: str | None = None
    start_time: datetime | None = None
    session: str | None = None
    estimated_time: datetime | None = None  # set later by ETA service
    queue_position: int | None = None       # set later by queue coordinator
    notes: str | None = None
    status: str
    created_at: datetime
    updated_at: datetime
