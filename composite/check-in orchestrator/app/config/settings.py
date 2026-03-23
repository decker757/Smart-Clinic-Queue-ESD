from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    RABBITMQ_URL: str = "amqp://guest:guest@rabbitmq:5672/"
    ETA_SERVICE_HOST: str = "eta-service"
    ETA_SERVICE_PORT: int = 50051
    AUTH_SERVICE_URL: str = "http://auth-service:3000"
    LATE_TTL_MS: int = 5 * 60 * 1000  # override for testing: set to e.g. 10000

    class Config:
        env_file = ".env"


settings = Settings()