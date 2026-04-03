import asyncio
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from app.routes import router
from app.consumer import start_consumer
from app.db import close_pool

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    consumer_task = asyncio.create_task(start_consumer())
    yield
    consumer_task.cancel()
    try:
        await consumer_task
    except asyncio.CancelledError:
        pass
    await close_pool()


app = FastAPI(
    title="Payment Service",
    description="Records and queries payment history for consultations. "
    "Consumes payment.completed / payment.failed events from the Stripe wrapper via RabbitMQ.",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/api/payments/docs",
    openapi_url="/api/payments/openapi.json",
)
app.include_router(router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "payment-service"}
