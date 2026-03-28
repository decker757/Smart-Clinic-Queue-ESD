from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from src.routes import patient, history, memo, payment

app = FastAPI(title="Patient Orchestrator", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(patient.router)
app.include_router(history.router)
app.include_router(memo.router)
app.include_router(payment.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "patient-orchestrator"}
