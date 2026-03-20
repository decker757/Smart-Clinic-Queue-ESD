from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.routes import doctor, queue, patient

app = FastAPI(title="Staff Management Orchestrator", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(doctor.router)
app.include_router(queue.router)
app.include_router(patient.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "staff-orchestrator"}
