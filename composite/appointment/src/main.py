import json
import aio_pika
from dataclasses import dataclass
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from typing import List
from src.config import settings
from src.models.appointment import (
    CreateAppointmentRequest,
    AppointmentServiceRequest,
    AppointmentBookedEvent,
    AppointmentResponse,
)
from src.services import auth, appointment as appointment_service

app = FastAPI(title="Appointment Composite Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Auth dependency ──────────────────────────────────────────────────────────

@dataclass
class AuthContext:
    token: str    # raw JWT — forwarded to atomic services
    user_id: str  # JWT sub claim — used for ownership checks


async def require_auth(authorization: str = Header(...)) -> AuthContext:
    """Validate the Bearer JWT and return the caller's identity + raw token."""
    token = authorization.removeprefix("Bearer ")
    payload = await auth.verify_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Unauthorized")
    return AuthContext(token=token, user_id=payload["sub"])


# ─── RabbitMQ helper ──────────────────────────────────────────────────────────

async def publish_event(routing_key: str, payload: dict):
    """Publish an event to the clinic topic exchange.

    routing_key examples: "appointment.booked", "appointment.cancelled"
    Each downstream service binds its own queue to this exchange,
    so all subscribers receive every matching event independently.
    """
    try:
        connection = await aio_pika.connect_robust(settings.RABBITMQ_URL)
        async with connection:
            channel = await connection.channel()
            exchange = await channel.declare_exchange(
                "clinic.events",
                aio_pika.ExchangeType.TOPIC,
                durable=True,
            )
            await exchange.publish(
                aio_pika.Message(
                    body=json.dumps(payload).encode(),
                    content_type="application/json",
                ),
                routing_key=routing_key,
            )
    except Exception as e:
        # log but don't fail the request if RabbitMQ is unavailable
        print(f"[RabbitMQ] Failed to publish {routing_key}: {e}")


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.get("/api/composite/appointments", response_model=List[AppointmentResponse])
async def list_appointments(
    patient_id: str = Query(..., description="Filter by patient ID"),
    auth_ctx: AuthContext = Depends(require_auth),
):
    if patient_id != auth_ctx.user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return await appointment_service.list_appointments(patient_id, auth_ctx.token)


@app.post("/api/composite/appointments", response_model=AppointmentResponse, status_code=201)
async def create_appointment(
    body: CreateAppointmentRequest,
    auth_ctx: AuthContext = Depends(require_auth),
):
    if body.patient_id != auth_ctx.user_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    appt = await appointment_service.create_appointment(
        AppointmentServiceRequest(**body.model_dump()),
        auth_ctx.token,
    )

    await publish_event("appointment.booked", AppointmentBookedEvent(
        appointment_id=appt.id,
        patient_id=appt.patient_id,
        doctor_id=appt.doctor_id,
        start_time=appt.start_time,
        session=appt.session,
    ).model_dump(mode="json"))

    return appt


@app.get("/api/composite/appointments/{appointment_id}", response_model=AppointmentResponse)
async def get_appointment(
    appointment_id: str,
    auth_ctx: AuthContext = Depends(require_auth),
):
    appt = await appointment_service.get_appointment(appointment_id, auth_ctx.token)
    if appt.patient_id != auth_ctx.user_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return appt


@app.delete("/api/composite/appointments/{appointment_id}", response_model=AppointmentResponse)
async def cancel_appointment(
    appointment_id: str,
    auth_ctx: AuthContext = Depends(require_auth),
):
    # Verify ownership before mutating — fetch first so we don't cancel blindly.
    existing = await appointment_service.get_appointment(appointment_id, auth_ctx.token)
    if existing.patient_id != auth_ctx.user_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    appt = await appointment_service.cancel_appointment(appointment_id, auth_ctx.token)

    await publish_event("appointment.cancelled", {
        "appointment_id": appointment_id,
        "patient_id": appt.patient_id,
    })

    return appt
