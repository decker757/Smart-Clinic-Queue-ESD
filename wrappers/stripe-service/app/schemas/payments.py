from pydantic import BaseModel
from typing import Optional

class CreatePaymentRequest(BaseModel):
    amount: int
    currency: str
    metadata: Optional[dict]

class PaymentResponse(BaseModel):
    status: str
    payment_intent_id: str
    client_secret: str

class ConfirmPaymentRequest(BaseModel):
    payment_intent_id: str

class RefundRequest(BaseModel):
    payment_intent_id: str
    amount: Optional[int]