from functools import lru_cache

from dotenv import load_dotenv
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


load_dotenv()


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    service_name: str = Field(default="eta-service", alias="SERVICE_NAME")
    service_version: str = Field(default="1.0.0", alias="SERVICE_VERSION")
    host: str = Field(default="0.0.0.0", alias="HOST")
    port: int = Field(default=8081, alias="PORT")

    google_maps_api_key: str = Field(alias="GOOGLE_MAPS_API_KEY")
    google_distance_matrix_url: str = Field(
        default="https://maps.googleapis.com/maps/api/distancematrix/json",
        alias="GOOGLE_DISTANCE_MATRIX_URL",
    )

    clinic_lat: float = Field(alias="CLINIC_LAT")
    clinic_lng: float = Field(alias="CLINIC_LNG")
    travel_mode: str = Field(default="driving", alias="TRAVEL_MODE")
    request_timeout_seconds: float = Field(default=8.0, alias="REQUEST_TIMEOUT_SECONDS")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
