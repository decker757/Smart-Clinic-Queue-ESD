import os
from dotenv import load_dotenv

load_dotenv()


class Settings:
    # ── Atomic service URLs ──────────────────────────────────
    APPOINTMENT_SERVICE_URL: str = os.getenv(
        "APPOINTMENT_SERVICE_URL", "http://appointment-service:3001"
    )
    PATIENT_SERVICE_GRPC: str = os.getenv(
        "PATIENT_SERVICE_GRPC", "patient-service:50053"
    )
    DOCTOR_SERVICE_GRPC: str = os.getenv(
        "DOCTOR_SERVICE_GRPC", "doctor-service:50055"
    )
    QUEUE_SERVICE_GRPC: str = os.getenv(
        "QUEUE_SERVICE_GRPC", "queue-coordinator-service:50052"
    )

    # ── Auth ─────────────────────────────────────────────────
    JWKS_URL: str = os.getenv(
        "JWKS_URL", "http://auth-service:3000/api/auth/jwks"
    )

    # ── Messaging ────────────────────────────────────────────
    RABBITMQ_URL: str = os.getenv(
        "RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672"
    )

    PORT: int = int(os.getenv("PORT", 8002))


settings = Settings()
