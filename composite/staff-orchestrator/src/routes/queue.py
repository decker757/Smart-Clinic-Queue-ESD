from fastapi import APIRouter, Depends
from src.models.queue import AddToQueueRequest, CallNextRequest
from src.controller import queue as queue_controller
from src.dependencies import require_staff, AuthContext

router = APIRouter(prefix="/api/composite/staff/queue", tags=["queue"])


@router.get("/{appointment_id}/position")
async def get_queue_position(appointment_id: str, auth: AuthContext = Depends(require_staff)):
    return await queue_controller.get_queue_position(appointment_id)


@router.post("/{appointment_id}/checkin")
async def check_in(appointment_id: str, auth: AuthContext = Depends(require_staff)):
    return await queue_controller.check_in(appointment_id, caller_id=auth.user_id)


@router.post("")
async def add_to_queue(body: AddToQueueRequest, auth: AuthContext = Depends(require_staff)):
    return await queue_controller.add_to_queue(body)


@router.delete("/{appointment_id}")
async def remove_from_queue(appointment_id: str, auth: AuthContext = Depends(require_staff)):
    return await queue_controller.remove_from_queue(appointment_id, token=auth.token)


@router.patch("/{appointment_id}/no-show")
async def mark_no_show(appointment_id: str, auth: AuthContext = Depends(require_staff)):
    return await queue_controller.mark_no_show(appointment_id)


@router.patch("/{appointment_id}/complete")
async def complete_appointment(appointment_id: str, auth: AuthContext = Depends(require_staff)):
    return await queue_controller.complete_appointment(appointment_id)


@router.post("/call-next")
async def call_next(body: CallNextRequest, auth: AuthContext = Depends(require_staff)):
    return await queue_controller.call_next(body)
