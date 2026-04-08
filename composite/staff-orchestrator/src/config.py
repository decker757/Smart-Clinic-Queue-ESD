import os
from dotenv import load_dotenv

load_dotenv()

_REQUIRED = [
    "DOCTOR_SERVICE_GRPC",
    "QUEUE_SERVICE_GRPC",
    "PATIENT_SERVICE_GRPC",
    "JWKS_URL",
    "APPOINTMENT_SERVICE_URL",
    "QUEUE_SERVICE_URL",
    "PAYMENT_SERVICE_URL",
    "PATIENT_SERVICE_URL",
    "RABBITMQ_URL",
    "PORT",
]
_missing = [name for name in _REQUIRED if not os.getenv(name)]
if _missing:
    raise RuntimeError(f"Missing required env vars: {', '.join(_missing)}")


class Settings:
    DOCTOR_SERVICE_GRPC: str = os.getenv("DOCTOR_SERVICE_GRPC", "")
    QUEUE_SERVICE_GRPC: str = os.getenv("QUEUE_SERVICE_GRPC", "")
    PATIENT_SERVICE_GRPC: str = os.getenv("PATIENT_SERVICE_GRPC", "")
    JWKS_URL: str = os.getenv("JWKS_URL", "")
    APPOINTMENT_SERVICE_URL: str = os.getenv("APPOINTMENT_SERVICE_URL", "")
    QUEUE_SERVICE_URL: str = os.getenv("QUEUE_SERVICE_URL", "")
    PAYMENT_SERVICE_URL: str = os.getenv("PAYMENT_SERVICE_URL", "")
    PATIENT_SERVICE_URL: str = os.getenv("PATIENT_SERVICE_URL", "")
    RABBITMQ_URL: str = os.getenv("RABBITMQ_URL", "")
    PORT: int = int(os.getenv("PORT", "8004"))

settings = Settings()
