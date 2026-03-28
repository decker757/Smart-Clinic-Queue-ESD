import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    APPOINTMENT_SERVICE_URL: str = os.getenv("APPOINTMENT_SERVICE_URL", "http://appointment-service:3001")
    JWKS_URL: str = os.getenv("JWKS_URL", "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json")
    RABBITMQ_URL: str = os.getenv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672")
    PORT: int = int(os.getenv("PORT", 8000))

settings = Settings()
