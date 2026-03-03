from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class LiveLocation(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class CheckInRequest(BaseModel):
    appointment_id: str = Field(min_length=1, max_length=128)
    live_location: LiveLocation | None = None


class CheckInResponse(BaseModel):
    appointment_id: str
    queue_status: Literal["CHECKED_IN"]
    eta_minutes: int | None = None
    notification_sent: bool
    idempotent_replay: bool = False
    checked_in_at: datetime


class ErrorResponse(BaseModel):
    detail: str
