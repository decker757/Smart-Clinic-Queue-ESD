from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from src.routes import consultation
from src.services import rabbitmq


@asynccontextmanager
async def lifespan(app: FastAPI):
    await rabbitmq.connect()
    yield
    await rabbitmq.disconnect()


app = FastAPI(
    title="Consultation Orchestrator",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/api/composite/consultations/docs",
    openapi_url="/api/composite/consultations/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.exception_handler(HTTPException)
async def unified_error_envelope(request: Request, exc: HTTPException):
    return JSONResponse(status_code=exc.status_code, content={"error": exc.detail})

app.include_router(consultation.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "consultation-orchestrator"}
