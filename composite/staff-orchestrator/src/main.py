from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.routes import doctor, queue, patient
from src.services import rabbitmq


@asynccontextmanager
async def lifespan(app: FastAPI):
    await rabbitmq.connect()
    yield
    await rabbitmq.disconnect()


app = FastAPI(
    title="Staff Management Orchestrator",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/api/composite/staff/docs",
    openapi_url="/api/composite/staff/openapi.json",
)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

app.include_router(doctor.router)
app.include_router(queue.router)
app.include_router(patient.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "staff-orchestrator"}
