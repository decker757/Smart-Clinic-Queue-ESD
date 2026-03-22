from fastapi import FastAPI
from app.api import payments

app = FastAPI(title="Stripe Payment Service")

# Include the payments router
app.include_router(payments.router, prefix="/payments")