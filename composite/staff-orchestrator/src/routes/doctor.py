from fastapi import APIRouter, Depends
from src.models.doctor import UpdateSlotStatusRequest, AddConsultationNotesRequest
from src.controller import doctor as doctor_controller
from src.dependencies import require_staff, AuthContext

router = APIRouter(prefix="/api/composite/staff/doctors", tags=["doctors"])


@router.get("")
async def list_doctors(auth: AuthContext = Depends(require_staff)):
    return await doctor_controller.list_doctors()


@router.get("/{doctor_id}")
async def get_doctor(doctor_id: str, auth: AuthContext = Depends(require_staff)):
    return await doctor_controller.get_doctor(doctor_id)


@router.get("/{doctor_id}/slots")
async def get_doctor_slots(doctor_id: str, auth: AuthContext = Depends(require_staff)):
    return await doctor_controller.get_doctor_slots(doctor_id)


@router.patch("/slots/{slot_id}")
async def update_slot_status(
    slot_id: str,
    body: UpdateSlotStatusRequest,
    auth: AuthContext = Depends(require_staff),
):
    return await doctor_controller.update_slot_status(slot_id, body)


@router.post("/{appointment_id}/notes")
async def add_consultation_notes(
    appointment_id: str,
    body: AddConsultationNotesRequest,
    auth: AuthContext = Depends(require_staff),
):
    return await doctor_controller.add_consultation_notes(appointment_id, auth.user_id, body)
