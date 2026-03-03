from pydantic import BaseModel, Field


class EtaRequest(BaseModel):
    patient_lat: float = Field(ge=-90, le=90)
    patient_lng: float = Field(ge=-180, le=180)


class EtaResponse(BaseModel):
    distance_km: float
    duration_minutes: int


class ErrorResponse(BaseModel):
    detail: str
