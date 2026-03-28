import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    PATIENT_SERVICE_GRPC: str = os.getenv("PATIENT_SERVICE_GRPC")
    JWKS_URL: str = os.getenv("JWKS_URL", "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json")
    RABBITMQ_URL: str = os.getenv("RABBITMQ_URL")
    PORT: int = int(os.getenv("PORT"))

settings = Settings()