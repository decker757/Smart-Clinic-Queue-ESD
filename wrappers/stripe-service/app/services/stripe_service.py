# app/services/stripe_service.py
import os
from dotenv import load_dotenv
import stripe

load_dotenv()
stripe.api_key = os.getenv("STRIPE_API_KEY")
FRONTEND_BASE_URL = os.getenv("FRONTEND_BASE_URL", "http://localhost:3000")


def create_checkout_session(amount, currency, consultation_id, patient_id):
    session = stripe.checkout.Session.create(
        payment_method_types=["card"],
        line_items=[{
            "price_data": {
                "currency": currency,
                "product_data": {"name": f"Consultation {consultation_id}"},
                "unit_amount": amount,  # in cents
            },
            "quantity": 1,
        }],
        mode="payment",
        success_url=f"{FRONTEND_BASE_URL}/success?session_id={{CHECKOUT_SESSION_ID}}",
        cancel_url=f"{FRONTEND_BASE_URL}/cancel",
        metadata={
            "consultation_id": consultation_id,
            "patient_id": patient_id,
        },
    )
    return session


async def handle_create_payment(payload):
    # Stripe SDK is synchronous, so do NOT use 'await' here
    session = create_checkout_session(
        amount=payload["amount"],
        currency=payload["currency"],
        consultation_id=payload["consultation_id"],
        patient_id=payload["patient_id"],
    )
    return {
        "payment_url": session.url,
        "payment_intent_id": session.payment_intent,
        "status": "pending",
    }