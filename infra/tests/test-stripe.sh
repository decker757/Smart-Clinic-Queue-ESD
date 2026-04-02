#!/bin/sh
# End-to-end test for the stripe-service wrapper.
# Run from the repo root: sh infra/tests/test-stripe.sh
#
# Requires (all via docker compose):
#   stripe-service → localhost:8086  (HTTP webhook)
#                  → localhost:50052 (gRPC)
#   rabbitmq       → localhost:15672 (management API for event verification)
#
# Start stack:
#   cd infra && docker compose up -d stripe-service rabbitmq
#
# Requires: curl, jq, openssl, grpcurl

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BASE="http://localhost:8086/api/payments"
GRPC="localhost:50060"
PROTO="$REPO_ROOT/wrappers/stripe-service/app/proto/payment.proto"

# Load webhook secret from env file so we can sign test payloads
WEBHOOK_SECRET=$(grep STRIPE_WEBHOOK_SIGNING_SECRET "$REPO_ROOT/infra/env/stripe-service.env" 2>/dev/null | cut -d= -f2-)
if [ -z "$WEBHOOK_SECRET" ]; then
  echo "SKIP: STRIPE_WEBHOOK_SIGNING_SECRET not found in infra/env/stripe-service.env"
  exit 0
fi

# ── Helper: construct a valid Stripe-Signature header ────────────────────────
# Stripe signs: "<timestamp>.<raw_body>" with HMAC-SHA256
sign_payload() {
    PAYLOAD="$1"
    TS=$(date +%s)
    SIGNED="${TS}.${PAYLOAD}"
    SIG=$(printf '%s' "$SIGNED" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print $2}')
    echo "t=${TS},v1=${SIG}"
}

CONSULTATION_ID="c-$(date +%s)"
PATIENT_ID="p-test-001"
PAYMENT_INTENT_ID="pi_test_$(date +%s)"

echo ""
echo "=== 1. Health check (HTTP server up) ==="
curl -sf "$BASE/../.." 2>/dev/null | jq '.detail // "ok"' 2>/dev/null || \
  curl -sf -o /dev/null -w "%{http_code}" "http://localhost:8086/" | grep -qE "^(200|404|422)$" && echo "HTTP server is up" || \
  { echo "FAIL: stripe-service not reachable on :8086"; exit 1; }

echo ""
echo "=== 2. Webhook: missing Stripe-Signature header (expect 400) ==="
curl -s -X POST "$BASE/webhook" \
  -H "Content-Type: application/json" \
  -d '{"type":"checkout.session.completed"}' | jq .
# Expected: {"detail": "Missing Stripe-Signature header"}

echo ""
echo "=== 3. Webhook: invalid signature (expect 400) ==="
curl -s -X POST "$BASE/webhook" \
  -H "Content-Type: application/json" \
  -H "stripe-signature: t=0,v1=invalidsignature" \
  -d '{"type":"checkout.session.completed"}' | jq .
# Expected: {"detail": "Invalid signature"}

echo ""
echo "=== 4. Webhook: checkout.session.completed (expect 200, publishes payment.completed) ==="
COMPLETED_PAYLOAD=$(cat <<EOF
{
  "id": "evt_test_001",
  "object": "event",
  "type": "checkout.session.completed",
  "data": {
    "object": {
      "id": "cs_test_001",
      "payment_intent": "$PAYMENT_INTENT_ID",
      "metadata": {
        "consultation_id": "$CONSULTATION_ID",
        "patient_id": "$PATIENT_ID"
      }
    }
  }
}
EOF
)
SIG=$(sign_payload "$COMPLETED_PAYLOAD")
curl -sf -X POST "$BASE/webhook" \
  -H "Content-Type: application/json" \
  -H "stripe-signature: $SIG" \
  -d "$COMPLETED_PAYLOAD" | jq .
# Expected: {"status": "ok"}
# → publishes payment.completed to clinic.events

echo ""
echo "=== 5. Webhook: payment_intent.payment_failed (expect 200, publishes payment.failed) ==="
FAILED_PAYLOAD=$(cat <<EOF
{
  "id": "evt_test_002",
  "object": "event",
  "type": "payment_intent.payment_failed",
  "data": {
    "object": {
      "id": "$PAYMENT_INTENT_ID",
      "metadata": {
        "consultation_id": "$CONSULTATION_ID",
        "patient_id": "$PATIENT_ID"
      }
    }
  }
}
EOF
)
SIG=$(sign_payload "$FAILED_PAYLOAD")
curl -sf -X POST "$BASE/webhook" \
  -H "Content-Type: application/json" \
  -H "stripe-signature: $SIG" \
  -d "$FAILED_PAYLOAD" | jq .
# Expected: {"status": "ok"}
# → publishes payment.failed to clinic.events

echo ""
echo "=== 6. Webhook: unhandled event type (expect 200, no-op) ==="
UNHANDLED_PAYLOAD='{"id":"evt_test_003","object":"event","type":"customer.created","data":{"object":{}}}'
SIG=$(sign_payload "$UNHANDLED_PAYLOAD")
curl -sf -X POST "$BASE/webhook" \
  -H "Content-Type: application/json" \
  -H "stripe-signature: $SIG" \
  -d "$UNHANDLED_PAYLOAD" | jq .
# Expected: {"status": "ok"} — silently ignored

echo ""
echo "=== 7. gRPC: CreatePayment (requires valid STRIPE_API_KEY) ==="
grpcurl -plaintext \
  -proto "$PROTO" \
  -d "{
    \"patient_id\": \"$PATIENT_ID\",
    \"amount\": 2500,
    \"currency\": \"sgd\",
    \"consultation_id\": \"$CONSULTATION_ID\"
  }" \
  "$GRPC" payment.PaymentService/CreatePayment | jq .
# Expected: {"paymentUrl": "https://checkout.stripe.com/...", "status": "pending"}
# Note: requires a valid test STRIPE_API_KEY — will return gRPC INTERNAL error if key is invalid

echo ""
echo "=== 8. gRPC: server reflection (service list) ==="
grpcurl -plaintext "$GRPC" list | grep -q "payment.PaymentService" && \
  echo "payment.PaymentService is registered ✓" || \
  echo "WARN: reflection not returning PaymentService"

echo ""
echo "=== 9. Verify RabbitMQ received payment.completed event ==="
# Uses RabbitMQ management API (guest:guest) — requires rabbitmq with management plugin
MSG_COUNT=$(curl -sf -u guest:guest \
  "http://localhost:15672/api/exchanges/%2F/clinic.events/bindings/source" 2>/dev/null | jq 'length' 2>/dev/null || echo "unavailable")
echo "clinic.events bindings: $MSG_COUNT (management API check)"
# For deeper verification check docker logs:
echo "--- stripe-service logs (last 10 lines) ---"
docker logs stripe-service --tail 10 2>/dev/null || echo "(run via docker compose to see logs)"

echo ""
echo "==================================================================="
echo "  To test the duplicate queue.removed deduplication:"
echo "  1. Send queue.removed twice for the same appointment_id"
echo "  2. Check notification-service logs — second should be dropped"
echo "  docker logs infra-notification-service-1 --tail 20"
echo "==================================================================="
echo ""
echo "=== All tests done ==="
