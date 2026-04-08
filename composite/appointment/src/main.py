import asyncio
import json
import logging
import aio_pika
from dataclasses import dataclass
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from typing import List, Optional
from src.config import settings
from src.models.appointment import (
    CreateAppointmentRequest,
    AppointmentServiceRequest,
    AppointmentBookedEvent,
    AppointmentResponse,
)
from src.services import auth, appointment as appointment_service
from src.redis_client import get_idempotency, set_idempotency, reserve_idempotency, clear_idempotency_reservation

logger = logging.getLogger(__name__)

app = FastAPI(
    title="Appointment Composite Service",
    version="1.0.0",
    docs_url="/api/composite/appointments/docs",
    openapi_url="/api/composite/appointments/openapi.json",
)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.exception_handler(HTTPException)
async def unified_error_envelope(request: Request, exc: HTTPException):
    """Standardize error responses: { "error": "..." } across all services."""
    return JSONResponse(status_code=exc.status_code, content={"error": exc.detail})


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

PUBLISH_MAX_RETRIES = 3
PUBLISH_RETRY_DELAY = 0.5  # seconds, doubles each attempt


async def publish_event(routing_key: str, payload: dict):
    """Publish an event to the clinic topic exchange with retry.

    Retries up to 3 times with exponential backoff. If all attempts fail,
    raises an HTTPException so the caller can decide how to handle it
    (e.g. warn the client instead of silently losing the event).
    """
    last_error: Exception | None = None
    for attempt in range(PUBLISH_MAX_RETRIES):
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
            return  # success
        except Exception as e:
            last_error = e
            delay = PUBLISH_RETRY_DELAY * (2 ** attempt)
            logger.warning(
                "[RabbitMQ] Publish %s attempt %d/%d failed: %s. Retrying in %.1fs...",
                routing_key, attempt + 1, PUBLISH_MAX_RETRIES, e, delay,
            )
            await asyncio.sleep(delay)

    logger.error("[RabbitMQ] Publish %s failed after %d attempts: %s", routing_key, PUBLISH_MAX_RETRIES, last_error)
    raise HTTPException(
        status_code=503,
        detail=f"Event bus unavailable — {routing_key} could not be published after {PUBLISH_MAX_RETRIES} retries",
    )


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

    # Return cached response for duplicate requests (client retry after network failure).
    # Atomically reserve the key before proceeding so concurrent retries don't both
    # create an appointment and then race to write the same cache entry.
    if x_idempotency_key:
        cached = await get_idempotency(x_idempotency_key)
        if cached:
            return cached
        reserved = await reserve_idempotency(x_idempotency_key)
        if not reserved:
            raise HTTPException(
                status_code=409,
                detail="A booking with this idempotency key is already in progress. Please retry after a moment.",
            )

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
        # Claim the slot first — only publish the event once we know the slot is ours.
        # Running both concurrently (asyncio.gather) risks publishing appointment.booked
        # for a slot that is then rejected with 409.
        try:
            await appointment_service.mark_slot_booked(body.slot_id, auth_ctx.token)
        except Exception as e:
            # Roll back the appointment for any slot-claim failure (409 conflict,
            # 5xx, timeout) so we never leave an orphaned appointment row.
            try:
                await appointment_service.cancel_appointment(appt.id, auth_ctx.token)
            except Exception:
                pass
            if x_idempotency_key:
                await clear_idempotency_reservation(x_idempotency_key)
            if isinstance(e, HTTPException) and e.status_code == 409:
                raise HTTPException(status_code=409, detail="This time slot was just booked by someone else. Please choose another.")
            raise

    try:
        await publish_event("appointment.booked", event_payload)
    except HTTPException as e:
        if e.status_code == 503:
            # Event bus is down — roll back so the patient doesn't end up with
            # a persisted appointment but no queue entry or downstream notifications.
            logger.error("Event publish failed for appointment %s — rolling back", appt.id)
            try:
                await appointment_service.cancel_appointment(appt.id, auth_ctx.token)
                if body.slot_id:
                    await appointment_service.release_slot(
                        appt.doctor_id,
                        appt.start_time.isoformat() if appt.start_time else "",
                        auth_ctx.token,
                    )
            except Exception:
                pass
            if x_idempotency_key:
                await clear_idempotency_reservation(x_idempotency_key)
            raise HTTPException(
                status_code=503,
                detail="Booking service is temporarily unavailable — please try again in a moment.",
            )
        raise

    response = appt.model_dump(mode="json")

    if x_idempotency_key:
        await set_idempotency(x_idempotency_key, response)

    return response


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

    # Release the doctor's time slot if this was a specific-doctor booking.
    # Retry a few times — if all attempts fail the slot stays marked booked
    # until manually corrected, but the cancellation itself is not rolled back.
    if existing.doctor_id and existing.start_time:
        start_str = existing.start_time.isoformat() if hasattr(existing.start_time, "isoformat") else str(existing.start_time)
        for attempt in range(3):
            try:
                await appointment_service.release_slot(existing.doctor_id, start_str, auth_ctx.token)
                break
            except Exception as e:
                if attempt == 2:
                    logger.error(
                        "Could not release slot for cancelled appointment %s after 3 attempts: %s — slot may need manual correction",
                        appointment_id, e,
                    )
                else:
                    await asyncio.sleep(0.5 * (2 ** attempt))

    try:
        await publish_event("appointment.cancelled", {
            "appointment_id": appointment_id,
            "patient_id": appt.patient_id,
            "doctor_id": appt.doctor_id,
            "start_time": appt.start_time.isoformat() if appt.start_time else None,
        })
    except HTTPException as e:
        if e.status_code == 503:
            logger.error("Event publish failed for cancellation %s — queue may not update", appointment_id)
        else:
            raise

    return appt
