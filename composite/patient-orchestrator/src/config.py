import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    PATIENT_SERVICE_GRPC: str = os.getenv("PATIENT_SERVICE_GRPC")
    AUTH_SERVICE_URL: str = os.getenv("AUTH_SERVICE_URL")
    RABBITMQ_URL: str = os.getenv("RABBITMQ_URL")
    PORT: int = int(os.getenv("PORT"))

settings = Settings()