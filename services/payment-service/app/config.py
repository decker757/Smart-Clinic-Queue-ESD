from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str
    RABBITMQ_URL: str = "amqp://guest:guest@rabbitmq:5672/"
    PORT: int = 3008
    STRIPE_SERVICE_URL: str = "http://stripe-service:3009"

    class Config:
        env_file = ".env"


settings = Settings()
