import os
from dotenv import load_dotenv

load_dotenv()

_REQUIRED = [
    "PATIENT_SERVICE_GRPC",
    "JWKS_URL",
    "RABBITMQ_URL",
    "PAYMENT_SERVICE_URL",
    "PORT",
]
_missing = [v for v in _REQUIRED if not os.getenv(v)]
if _missing:
    raise RuntimeError(f"Missing required env vars: {', '.join(_missing)}")


class Settings:
    PATIENT_SERVICE_GRPC: str = os.getenv("PATIENT_SERVICE_GRPC", "")
    JWKS_URL: str = os.getenv("JWKS_URL", "")
    RABBITMQ_URL: str = os.getenv("RABBITMQ_URL", "")
    PORT: int = int(os.getenv("PORT", "8001"))
    PAYMENT_SERVICE_URL: str = os.getenv("PAYMENT_SERVICE_URL", "")

settings = Settings()
