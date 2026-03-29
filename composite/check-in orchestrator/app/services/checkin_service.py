from datetime import datetime, timedelta, timezone
from app.clients.eta_client import get_travel_time
from app.messaging.publisher import publish_event, publish_late_with_ttl


async def process_check_in(body):
    eta_minutes = await get_travel_time(
        body.patient_location,
        body.clinic_location
    )

    now = datetime.now(timezone.utc)
    arrival_time = now + timedelta(minutes=eta_minutes)

    if body.appointment_time is None or arrival_time <= body.appointment_time:
        # Patient is on time
        await publish_event("queue.checked_in", {
            "patient_id": body.patient_id,
            "appointment_id": body.appointment_id,
            "eta_minutes": eta_minutes,
            "timestamp": now.isoformat()
        })
        return {"status": "checked_in", "eta_minutes": eta_minutes}

    # Patient is late — publish to notification exchange AND schedule auto-removal via TTL
    payload = {
        "patient_id": body.patient_id,
        "appointment_id": body.appointment_id,
        "eta_minutes": eta_minutes,
        "timestamp": now.isoformat()
    }
    await publish_event("queue.late_detected", payload)
    await publish_late_with_ttl(payload)
    return {"status": "late", "eta_minutes": eta_minutes}


async def handle_confirmation(body):
    if body.is_coming:
        await publish_event("queue.deprioritized", {
            "patient_id": body.patient_id,
            "appointment_id": body.appointment_id,
            "timestamp": datetime.now(timezone.utc).isoformat()
        })
        return {"status": "queue_deprioritized"}

    await publish_event("queue.removed", {
        "patient_id": body.patient_id,
        "appointment_id": body.appointment_id,
        "timestamp": datetime.now(timezone.utc).isoformat()
    })
    return {"status": "queue_removed"}
