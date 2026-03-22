from fastapi import APIRouter, Request, Header, HTTPException
import stripe
import os
from dotenv import load_dotenv

load_dotenv()

stripe.api_key = os.getenv("STRIPE_API_KEY")
WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SIGNING_SECRET")

router = APIRouter()

@router.post("/webhook")
async def stripe_webhook(request: Request, stripe_signature: str = Header(None)):
    if stripe_signature is None:
        raise HTTPException(status_code=400, detail="Missing Stripe-Signature header")
    
    payload = await request.body()

    try:
        event = stripe.Webhook.construct_event(
            payload=payload,
            sig_header=stripe_signature,
            secret=WEBHOOK_SECRET,
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid payload")
    except stripe.error.SignatureVerificationError:
        raise HTTPException(status_code=400, detail="Invalid signature")

    # Handle the event type
    if event["type"] == "checkout.session.completed":
        session = event["data"]["object"]
        # TODO: update your DB / notify orchestrator
        print(f"✅ Payment completed for consultation {session['metadata']['consultation_id']}")
    elif event["type"] == "payment_intent.payment_failed":
        session = event["data"]["object"]
        print(f"❌ Payment failed for consultation {session['metadata']['consultation_id']}")
    else:
        print(f"⚠ Unhandled event type {event['type']}")

    return {"status": "success"}