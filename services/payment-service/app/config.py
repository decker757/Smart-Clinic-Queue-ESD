from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str
    RABBITMQ_URL: str
    PORT: int = 3008
    STRIPE_SERVICE_URL: str
    APPOINTMENT_SERVICE_URL: str
    JWKS_URL: str

    class Config:
        env_file = ".env"


settings = Settings()
