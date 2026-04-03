import asyncio
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from app.api import payments
from app.grpc.server import serve as grpc_serve

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Start gRPC server as a background task sharing the event loop with uvicorn
    grpc_task = asyncio.create_task(grpc_serve())
    logger.info("gRPC payment server starting")
    yield
    grpc_task.cancel()
    try:
        await grpc_task
    except asyncio.CancelledError:
        pass
    logger.info("gRPC payment server stopped")


app = FastAPI(title="Stripe Payment Service", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.exception_handler(HTTPException)
async def unified_error_envelope(request: Request, exc: HTTPException):
    return JSONResponse(status_code=exc.status_code, content={"error": exc.detail})


@app.get("/health")
async def health():
    return {"status": "ok", "service": "stripe-service"}


app.include_router(payments.router, prefix="/api/payments")
