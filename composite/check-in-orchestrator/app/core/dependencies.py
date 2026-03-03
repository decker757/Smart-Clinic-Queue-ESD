from functools import lru_cache

from app.clients.appointment_client import AppointmentClient
from app.clients.eta_client import EtaClient
from app.clients.notification_client import NotificationClient
from app.clients.queue_client import QueueClient
from app.core.config import get_settings
from app.services.checkin_service import CheckInService


@lru_cache(maxsize=1)
def get_checkin_service() -> CheckInService:
    settings = get_settings()
    return CheckInService(
        appointment_client=AppointmentClient(settings),
        queue_client=QueueClient(settings),
        eta_client=EtaClient(settings),
        notification_client=NotificationClient(settings),
    )
