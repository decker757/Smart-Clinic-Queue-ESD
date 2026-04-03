from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
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


@app.exception_handler(HTTPException)
async def unified_error_envelope(request: Request, exc: HTTPException):
    return JSONResponse(status_code=exc.status_code, content={"error": exc.detail})


@app.get("/health")
async def health():
    return {"status": "ok", "service": "checkin-orchestrator"}


app.include_router(router, prefix="/api")