from pydantic import BaseSettings


class Settings(BaseSettings):
    RABBITMQ_URL: str = "amqp://guest:guest@rabbitmq:5672/"
    ETA_SERVICE_HOST: str = "eta-service"
    ETA_SERVICE_PORT: int = 50051

    class Config:
        env_file = ".env"


settings = Settings()