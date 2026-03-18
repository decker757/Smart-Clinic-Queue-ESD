from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.routes import consultation

app = FastAPI(title="Consultation Orchestrator", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(consultation.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "consultation-orchestrator"}
