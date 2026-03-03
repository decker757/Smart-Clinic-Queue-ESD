import logging
from http import HTTPStatus

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.api.routes import router
from app.core.config import get_settings
from app.core.exceptions import AppException
from app.core.logging import configure_logging
from app.models.checkin_models import ErrorResponse

configure_logging(get_settings().log_level)
LOGGER = logging.getLogger(__name__)

app = FastAPI(title="Check-In Orchestrator", version=get_settings().service_version)
app.include_router(router)


@app.exception_handler(AppException)
async def app_exception_handler(_: Request, exc: AppException) -> JSONResponse:
    LOGGER.error("application_error", extra={"error": exc.message})
    return JSONResponse(
        status_code=exc.status_code,
        content=ErrorResponse(detail=exc.message).model_dump(),
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
    LOGGER.warning("request_validation_error", extra={"error": str(exc)})
    return JSONResponse(
        status_code=HTTPStatus.UNPROCESSABLE_ENTITY,
        content=ErrorResponse(detail="Invalid request payload").model_dump(),
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(_: Request, exc: Exception) -> JSONResponse:
    LOGGER.exception("unhandled_error", extra={"error": str(exc)})
    return JSONResponse(
        status_code=HTTPStatus.INTERNAL_SERVER_ERROR,
        content=ErrorResponse(detail="Internal server error").model_dump(),
    )
