import stripe
from app.config.settings import settings

stripe.api_key = settings.STRIPE_API_KEY


def create_checkout_session(amount: int, currency: str, consultation_id: str, patient_id: str):
    return stripe.checkout.Session.create(
        payment_method_types=["card"],
        line_items=[{
            "price_data": {
                "currency": currency,
                "product_data": {"name": f"Consultation {consultation_id}"},
                "unit_amount": amount,
            },
            "quantity": 1,
        }],
        mode="payment",
        success_url=settings.STRIPE_SUCCESS_URL or f"{settings.FRONTEND_BASE_URL}/success?session_id={{CHECKOUT_SESSION_ID}}",
        cancel_url=settings.STRIPE_CANCEL_URL or f"{settings.FRONTEND_BASE_URL}/cancel",
        metadata={
            "consultation_id": consultation_id,
            "patient_id": patient_id,
        },
    )


async def handle_create_payment(payload: dict) -> dict:
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
