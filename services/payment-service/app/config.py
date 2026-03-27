from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str
    RABBITMQ_URL: str = "amqp://guest:guest@rabbitmq:5672/"
    PORT: int = 3008

    class Config:
        env_file = ".env"


settings = Settings()
