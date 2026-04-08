import stripe
from app.config.settings import settings

stripe.api_key = settings.STRIPE_API_KEY


def create_checkout_session(
    amount: int,
    currency: str,
    consultation_id: str,
    patient_id: str,
    idempotency_key: str | None = None,
):
    metadata = {
        "consultation_id": consultation_id,
        "patient_id": patient_id,
    }
    kwargs: dict = dict(
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
        metadata=metadata,
        payment_intent_data={"metadata": metadata},
    )
    if idempotency_key:
        kwargs["idempotency_key"] = idempotency_key
    return stripe.checkout.Session.create(**kwargs)
