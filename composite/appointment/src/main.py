import json
import aio_pika
from fastapi import FastAPI, HTTPException, Header
from src.config import settings
from src.models.appointment import (
    CreateAppointmentRequest,
    AppointmentServiceRequest,
    AppointmentBookedEvent,
    AppointmentResponse,
)
from src.services import auth, appointment as appointment_service

app = FastAPI(title="Appointment Composite Service", version="1.0.0")


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


@app.post("/composite/appointments", response_model=AppointmentResponse, status_code=201)
async def create_appointment(
    body: CreateAppointmentRequest,
    authorization: str = Header(...),
):
    token = authorization.removeprefix("Bearer ")

    # 1. Verify user
    user = await auth.verify_token(token)
    if not user:
        raise HTTPException(status_code=401, detail="Unauthorized")

    # 2. Create appointment via atomic service
    appt = await appointment_service.create_appointment(
        AppointmentServiceRequest(
            patient_id=body.patient_id,
            doctor_id=body.doctor_id,
            start_time=body.start_time,
            notes=body.notes,
        ),
        token,
    )

    # 3. Publish event to RabbitMQ for queue-coordinator + notification-service
    await publish_event("appointment.booked", AppointmentBookedEvent(
        appointment_id=appt.id,
        patient_id=appt.patient_id,
        doctor_id=appt.doctor_id,
        start_time=appt.start_time,
    ).model_dump(mode="json"))

    return appt


@app.get("/composite/appointments/{appointment_id}", response_model=AppointmentResponse)
async def get_appointment(
    appointment_id: str,
    authorization: str = Header(...),
):
    token = authorization.removeprefix("Bearer ")

    user = await auth.verify_token(token)
    if not user:
        raise HTTPException(status_code=401, detail="Unauthorized")

    return await appointment_service.get_appointment(appointment_id, token)


@app.delete("/composite/appointments/{appointment_id}", response_model=AppointmentResponse)
async def cancel_appointment(
    appointment_id: str,
    authorization: str = Header(...),
):
    token = authorization.removeprefix("Bearer ")

    user = await auth.verify_token(token)
    if not user:
        raise HTTPException(status_code=401, detail="Unauthorized")

    # cancel via atomic service
    appt = await appointment_service.cancel_appointment(appointment_id, token)

    # notify queue-coordinator that appointment was cancelled
    await publish_event("appointment.cancelled", {
        "appointment_id": appointment_id,
        "patient_id": appt.patient_id,
    })

    return appt
