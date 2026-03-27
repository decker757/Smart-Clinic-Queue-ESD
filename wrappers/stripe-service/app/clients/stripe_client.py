import stripe
from app.config.settings import settings

stripe.api_key = settings.STRIPE_API_KEY

def get_success_url():
    return settings.STRIPE_SUCCESS_URL or f"{settings.FRONTEND_BASE_URL}/success"

def get_cancel_url():
    return settings.STRIPE_CANCEL_URL or f"{settings.FRONTEND_BASE_URL}/cancel"


async def create_checkout_session(amount, currency, metadata):
    session = stripe.checkout.Session.create(
        payment_method_types=["card"],
        line_items=[{
            "price_data": {
                "currency": currency,
                "product_data": {
                    "name": "Consultation Payment",
                },
                "unit_amount": amount,
            },
            "quantity": 1,
        }],
        mode="payment",
        success_url=get_success_url(),
        cancel_url=get_cancel_url(),
        metadata=metadata,
    )
    return session