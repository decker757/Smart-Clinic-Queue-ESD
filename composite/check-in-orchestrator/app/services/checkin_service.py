import asyncio
import logging
from datetime import datetime, timezone

from app.clients.appointment_client import AppointmentClient
from app.clients.eta_client import EtaClient
from app.clients.notification_client import NotificationClient
from app.clients.queue_client import QueueClient
from app.core.exceptions import ValidationError
from app.models.checkin_models import CheckInRequest, CheckInResponse

LOGGER = logging.getLogger(__name__)


class CheckInService:
    def __init__(
        self,
        appointment_client: AppointmentClient,
        queue_client: QueueClient,
        eta_client: EtaClient,
        notification_client: NotificationClient,
    ) -> None:
        self.appointment_client = appointment_client
        self.queue_client = queue_client
        self.eta_client = eta_client
        self.notification_client = notification_client
        self._idempotency_store: dict[str, CheckInResponse] = {}
        self._lock_store: dict[str, asyncio.Lock] = {}
        self._lock_store_guard = asyncio.Lock()

    async def _get_lock(self, key: str) -> asyncio.Lock:
        async with self._lock_store_guard:
            if key not in self._lock_store:
                self._lock_store[key] = asyncio.Lock()
            return self._lock_store[key]

    async def process_check_in(self, request: CheckInRequest) -> CheckInResponse:
        appointment_id = request.appointment_id

        existing = self._idempotency_store.get(appointment_id)
        if existing is not None:
            return existing.model_copy(update={"idempotent_replay": True})

        lock = await self._get_lock(appointment_id)
        async with lock:
            existing = self._idempotency_store.get(appointment_id)
            if existing is not None:
                return existing.model_copy(update={"idempotent_replay": True})

            appointment = await self.appointment_client.get_appointment(appointment_id)
            if not appointment:
                raise ValidationError(message=f"Appointment {appointment_id} is invalid")

            eta_minutes: int | None = None
            if request.live_location is not None:
                eta_data = await self.eta_client.estimate_eta(
                    appointment_id=appointment_id,
                    lat=request.live_location.lat,
                    lng=request.live_location.lng,
                )
                eta_minutes = eta_data.get("eta_minutes")

            await self.queue_client.update_status(appointment_id=appointment_id, status="CHECKED_IN")
            await self.notification_client.send_checkin_confirmation(
                appointment_id=appointment_id,
                eta_minutes=eta_minutes,
            )

            response = CheckInResponse(
                appointment_id=appointment_id,
                queue_status="CHECKED_IN",
                eta_minutes=eta_minutes,
                notification_sent=True,
                idempotent_replay=False,
                checked_in_at=datetime.now(timezone.utc),
            )
            self._idempotency_store[appointment_id] = response

            LOGGER.info("checkin_completed", extra={"appointment_id": appointment_id})
            return response
