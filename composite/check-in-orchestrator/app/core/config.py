from functools import lru_cache

from dotenv import load_dotenv
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


load_dotenv()


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    service_name: str = Field(default="check-in-orchestrator", alias="SERVICE_NAME")
    service_version: str = Field(default="1.0.0", alias="SERVICE_VERSION")
    environment: str = Field(default="development", alias="ENVIRONMENT")
    host: str = Field(default="0.0.0.0", alias="HOST")
    port: int = Field(default=8080, alias="PORT")
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")

    appointment_service_url: str = Field(alias="APPOINTMENT_SERVICE_URL")
    queue_service_url: str = Field(alias="QUEUE_SERVICE_URL")
    eta_service_url: str = Field(alias="ETA_SERVICE_URL")
    notification_service_url: str = Field(alias="NOTIFICATION_SERVICE_URL")

    http_timeout_seconds: float = Field(default=5.0, alias="HTTP_TIMEOUT_SECONDS")
    http_max_retries: int = Field(default=3, alias="HTTP_MAX_RETRIES")
    http_retry_backoff_seconds: float = Field(default=0.25, alias="HTTP_RETRY_BACKOFF_SECONDS")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
