import asyncio
import logging
from collections.abc import Callable
from http import HTTPStatus
from typing import Any

import httpx

from app.core.config import Settings
from app.core.exceptions import ExternalServiceError

LOGGER = logging.getLogger(__name__)


class BaseServiceClient:
    def __init__(self, base_url: str, settings: Settings, service_name: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.settings = settings
        self.service_name = service_name

    async def _request_with_retry(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        params: dict[str, Any] | None = None,
        validate_response: Callable[[httpx.Response], Any] | None = None,
    ) -> Any:
        timeout = self.settings.http_timeout_seconds
        retries = self.settings.http_max_retries
        backoff = self.settings.http_retry_backoff_seconds

        for attempt in range(1, retries + 1):
            try:
                async with httpx.AsyncClient(base_url=self.base_url, timeout=timeout) as client:
                    response = await client.request(method=method, url=path, json=payload, params=params)

                if response.status_code >= HTTPStatus.INTERNAL_SERVER_ERROR:
                    raise ExternalServiceError(
                        message=(
                            f"{self.service_name} returned {response.status_code}"
                            f" for {method} {path}"
                        )
                    )

                if response.status_code >= HTTPStatus.BAD_REQUEST:
                    raise ExternalServiceError(
                        message=(
                            f"{self.service_name} request failed with {response.status_code}:"
                            f" {response.text}"
                        ),
                        status_code=response.status_code,
                    )

                if validate_response is None:
                    return response.json() if response.content else None
                return validate_response(response)

            except (httpx.TimeoutException, httpx.NetworkError, ExternalServiceError) as exc:
                is_last_attempt = attempt == retries
                should_retry = isinstance(exc, (httpx.TimeoutException, httpx.NetworkError))
                if isinstance(exc, ExternalServiceError) and exc.status_code >= HTTPStatus.INTERNAL_SERVER_ERROR:
                    should_retry = True

                LOGGER.warning(
                    "outbound_call_failed",
                    extra={
                        "service": self.service_name,
                        "error": str(exc),
                    },
                )

                if is_last_attempt or not should_retry:
                    if isinstance(exc, ExternalServiceError):
                        raise exc
                    raise ExternalServiceError(
                        message=f"Unable to reach {self.service_name}: {exc}"
                    ) from exc

                sleep_for = backoff * (2 ** (attempt - 1))
                await asyncio.sleep(sleep_for)
