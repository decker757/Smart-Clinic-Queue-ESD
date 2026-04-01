from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.routes import router

app = FastAPI(
    title="Check-in Orchestrator",
    version="1.0.0",
    docs_url="/api/check-in/docs",
    openapi_url="/api/check-in/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health():
    return {"status": "ok", "service": "checkin-orchestrator"}


app.include_router(router, prefix="/api")