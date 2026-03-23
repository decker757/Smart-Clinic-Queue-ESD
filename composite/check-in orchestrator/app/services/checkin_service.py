from datetime import datetime, timedelta, timezone
from app.clients.eta_client import get_travel_time
from app.messaging.publisher import publish_event


async def process_check_in(body, auth_ctx):
    eta_minutes = await get_travel_time(
        body.patient_location,
        body.clinic_location
    )
    
    now = datetime.now(timezone.utc)
    arrival_time = now + timedelta(minutes=eta_minutes)

    if arrival_time <= body.appointment_time:
        # Patient is on time
        await publish_event("checked_in", {
            "patient_id": body.patient_id,
            "eta_minutes": eta_minutes,
            "timestamp": now.isoformat()
        })
        return {"status": "checked_in", "eta_minutes": eta_minutes}
    
    # Patient is late
    await publish_event("late.detected", {
        "patient_id": body.patient_id,
        "eta_minutes": eta_minutes,
        "timestamp": now.isoformat()
    })
    return {"status": "late", "eta_minutes": eta_minutes}


async def handle_confirmation(body):
    # Body is ConfirmRequest
    if body.is_coming:
        await publish_event("queue.deprioritized", {
            "patient_id": body.patient_id,
            "timestamp": datetime.now(timezone.utc).isoformat()
        })
        return {"status": "queue_deprioritized"}
    
    # Patient is not coming
    else:
        await publish_event("queue.removed", {
            "patient_id": body.patient_id,
            "timestamp": datetime.now(timezone.utc).isoformat()
        })
        return {"status": "queue_removed"}