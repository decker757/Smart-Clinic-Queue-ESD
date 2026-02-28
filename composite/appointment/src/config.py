import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    APPOINTMENT_SERVICE_URL: str = os.getenv("APPOINTMENT_SERVICE_URL", "http://appointment-service:3001")
    AUTH_SERVICE_URL: str = os.getenv("AUTH_SERVICE_URL", "http://auth-service:3000")
    RABBITMQ_URL: str = os.getenv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672")
    PORT: int = int(os.getenv("PORT", 8000))

settings = Settings()
