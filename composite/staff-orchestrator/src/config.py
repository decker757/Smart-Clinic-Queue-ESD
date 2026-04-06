import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    DOCTOR_SERVICE_GRPC: str = os.getenv("DOCTOR_SERVICE_GRPC")
    QUEUE_SERVICE_GRPC: str = os.getenv("QUEUE_SERVICE_GRPC")
    PATIENT_SERVICE_GRPC: str = os.getenv("PATIENT_SERVICE_GRPC", "patient-service:50053")
    JWKS_URL: str = os.getenv("JWKS_URL", "http://auth-service:3000/api/auth/jwks")
    APPOINTMENT_SERVICE_URL: str = os.getenv("APPOINTMENT_SERVICE_URL")
    QUEUE_SERVICE_URL: str = os.getenv("QUEUE_SERVICE_URL", "")
    PAYMENT_SERVICE_URL: str = os.getenv("PAYMENT_SERVICE_URL", "http://payment-service:3008")
    PATIENT_SERVICE_URL: str = os.getenv("PATIENT_SERVICE_URL", "http://patient-service:3005")
    RABBITMQ_URL: str = os.getenv("RABBITMQ_URL")
    PORT: int = int(os.getenv("PORT", "8004"))

settings = Settings()
