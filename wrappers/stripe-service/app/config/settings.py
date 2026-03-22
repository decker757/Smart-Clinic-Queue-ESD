from pydantic import BaseSettings

class Settings(BaseSettings):
    STRIPE_API_KEY: str

    FRONTEND_BASE_URL: str = "http://localhost:3000"
    STRIPE_SUCCESS_URL: str | None = None
    STRIPE_CANCEL_URL: str | None = None

    RABBITMQ_URL: str = "amqp://guest:guest@rabbitmq:5672/"

    class Config:
        env_file = ".env"


settings = Settings()