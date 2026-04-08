from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    STRIPE_API_KEY: str
    STRIPE_WEBHOOK_SIGNING_SECRET: str = ""

    FRONTEND_BASE_URL: str = "http://localhost:5173"
    STRIPE_SUCCESS_URL: str = ""
    STRIPE_CANCEL_URL: str = ""

    RABBITMQ_URL: str = "amqp://guest:guest@rabbitmq:5672/"
    AUTH_SERVICE_URL: str = "http://auth-service:3000"

    # Consultation fee charged via Stripe (smallest currency unit, e.g. cents)
    CONSULTATION_FEE_CENTS: int = 5000  # SGD $50.00 default
    CURRENCY: str = "sgd"

    class Config:
        env_file = ".env"


settings = Settings()
