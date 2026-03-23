import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    DOCTOR_SERVICE_GRPC: str = os.getenv("DOCTOR_SERVICE_GRPC")
    QUEUE_SERVICE_GRPC: str = os.getenv("QUEUE_SERVICE_GRPC")
    PATIENT_SERVICE_GRPC: str = os.getenv("PATIENT_SERVICE_GRPC")
    AUTH_SERVICE_URL: str = os.getenv("AUTH_SERVICE_URL")
    APPOINTMENT_SERVICE_URL: str = os.getenv("APPOINTMENT_SERVICE_URL")
    RABBITMQ_URL: str = os.getenv("RABBITMQ_URL")
    PORT: int = int(os.getenv("PORT", "8004"))

settings = Settings()
