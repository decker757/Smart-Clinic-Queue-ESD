from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str
    RABBITMQ_URL: str = "amqp://guest:guest@rabbitmq:5672/"
    PORT: int = 3008
    STRIPE_SERVICE_URL: str = "http://stripe-service:3009"
    JWKS_URL: str = "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json"

    class Config:
        env_file = ".env"


settings = Settings()
