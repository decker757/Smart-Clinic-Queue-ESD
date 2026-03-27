import json
import logging
from datetime import datetime, timezone
from fastapi import APIRouter, Header, HTTPException, Request
import stripe
from app.config.settings import settings
from app.messaging.publisher import publish_event

logger = logging.getLogger(__name__)

stripe.api_key = settings.STRIPE_API_KEY

router = APIRouter()


@router.post("/webhook")
async def stripe_webhook(request: Request, stripe_signature: str = Header(None, alias="stripe-signature")):
    if not stripe_signature:
        raise HTTPException(status_code=400, detail="Missing Stripe-Signature header")

    payload = await request.body()

    try:
        stripe.Webhook.construct_event(
            payload=payload,
            sig_header=stripe_signature,
            secret=settings.STRIPE_WEBHOOK_SIGNING_SECRET,
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid payload")
    except stripe.error.SignatureVerificationError:
        raise HTTPException(status_code=400, detail="Invalid signature")

    # Use the raw payload as a plain dict — the Stripe SDK's StripeObject
    # doesn't support .get() so we parse JSON ourselves after signature is verified.
    event_dict = json.loads(payload)
    await _handle_event(event_dict)
    return {"status": "ok"}


async def _handle_event(event: dict) -> None:
    event_type = event["type"]
    obj = event["data"]["object"]
    # PaymentIntent metadata may not be propagated from the session — use .get() defensively
    metadata = obj.get("metadata", {})
    now = datetime.now(timezone.utc).isoformat()

    if event_type == "checkout.session.completed":
        logger.info("Payment completed: consultation=%s patient=%s", metadata.get("consultation_id"), metadata.get("patient_id"))
        await publish_event("payment.completed", {
            "consultation_id": metadata.get("consultation_id"),
            "patient_id": metadata.get("patient_id"),
            "payment_intent_id": obj.get("payment_intent"),
            "timestamp": now,
        })

    elif event_type == "payment_intent.payment_failed":
        logger.warning("Payment failed: consultation=%s patient=%s", metadata.get("consultation_id"), metadata.get("patient_id"))
        await publish_event("payment.failed", {
            "consultation_id": metadata.get("consultation_id"),
            "patient_id": metadata.get("patient_id"),
            "payment_intent_id": obj.get("id"),
            "timestamp": now,
        })

    else:
        logger.debug("Unhandled Stripe event type: %s", event_type)
