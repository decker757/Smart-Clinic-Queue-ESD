import asyncio
import json
import aio_pika
from dataclasses import dataclass
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from typing import List, Optional
from src.config import settings
from src.models.appointment import (
    CreateAppointmentRequest,
    AppointmentServiceRequest,
    AppointmentBookedEvent,
    AppointmentResponse,
)
from src.services import auth, appointment as appointment_service

app = FastAPI(
    title="Appointment Composite Service",
    version="1.0.0",
    docs_url="/api/composite/appointments/docs",
    openapi_url="/api/composite/appointments/openapi.json",
)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# In-memory idempotency cache: key → serialised AppointmentResponse dict
# Prevents duplicate appointment creation when clients retry on network failures.
_idempotency_cache: dict[str, dict] = {}


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

@app.get("/health")
async def health():
    return {"status": "ok", "service": "composite-appointment"}


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
    x_idempotency_key: Optional[str] = Header(None),
):
    if body.patient_id != auth_ctx.user_id:
        raise HTTPException(status_code=403, detail="Forbidden")

    # Return cached response for duplicate requests (client retry after network failure)
    if x_idempotency_key and x_idempotency_key in _idempotency_cache:
        return _idempotency_cache[x_idempotency_key]

    appt = await appointment_service.create_appointment(
        AppointmentServiceRequest(**body.model_dump(exclude={"slot_id"})),
        auth_ctx.token,
    )

    event_payload = AppointmentBookedEvent(
        appointment_id=appt.id,
        patient_id=appt.patient_id,
        doctor_id=appt.doctor_id,
        start_time=appt.start_time,
        session=appt.session,
    ).model_dump(mode="json")

    if body.slot_id:
        try:
            # mark_slot_booked and publish_event are independent — run concurrently
            await asyncio.gather(
                appointment_service.mark_slot_booked(body.slot_id, auth_ctx.token),
                publish_event("appointment.booked", event_payload),
            )
        except HTTPException as e:
            if e.status_code == 409:
                # Slot was taken by a concurrent booking — cancel the just-created appointment
                try:
                    await appointment_service.cancel_appointment(appt.id, auth_ctx.token)
                except Exception:
                    pass
                raise HTTPException(status_code=409, detail="This time slot was just booked by someone else. Please choose another.")
            raise
    else:
        await publish_event("appointment.booked", event_payload)

    if x_idempotency_key:
        _idempotency_cache[x_idempotency_key] = appt.model_dump(mode="json")

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

    # Release the doctor's time slot if this was a specific-doctor booking
    if existing.doctor_id and existing.start_time:
        try:
            await appointment_service.release_slot(
                existing.doctor_id,
                existing.start_time.isoformat() if hasattr(existing.start_time, "isoformat") else str(existing.start_time),
                auth_ctx.token,
            )
        except Exception as e:
            # Non-critical: log but don't block the cancellation
            import logging
            logging.warning(f"Could not release slot for cancelled appointment {appointment_id}: {e}")

    await publish_event("appointment.cancelled", {
        "appointment_id": appointment_id,
        "patient_id": appt.patient_id,
        "doctor_id": appt.doctor_id,
        "start_time": appt.start_time.isoformat() if appt.start_time else None,
    })

    return appt
