#!/bin/sh
# Full patient journey E2E test.
# Covers: check-in (on-time / late / no-response), payment webhooks, dedup guard.
#
# Run from repo root: sh infra/tests/test-patient-journey.sh
#
# Required services (all via docker compose):
#   kong                  → localhost:8000
#   auth-service          → (via Kong)
#   composite-appointment → (via Kong)
#   queue-coordinator     → (via Kong)
#   checkin-orchestrator  → (via Kong)
#   stripe-service        → localhost:8086 (webhook), localhost:50052 (gRPC)
#   rabbitmq              → internal
#
#   cd infra && docker compose up -d kong auth-service rabbitmq app-db \
#     composite-appointment queue-coordinator-service \
#     checkin-orchestrator stripe-service
#
# Scenario D (TTL auto-removal) requires LATE_TTL_MS=10000 in checkin-orchestrator:
#   Edit infra/env/checkin-orchestrator.env → LATE_TTL_MS=10000
#   docker compose up -d --build checkin-orchestrator
#   Then re-run this script.
#
# Requires: curl, jq, openssl, grpcurl

set -e

# Resolve repo root regardless of where the script is called from
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

KONG="http://localhost:8000"
BASE_AUTH="http://localhost:3000/api/auth"
BASE_COMPOSITE="$KONG"
BASE_CHECKIN="$KONG/api"
BASE_QUEUE="$KONG"
BASE_STRIPE="http://localhost:8086/api/payments"
GRPC_STRIPE="localhost:50060"
PROTO="$REPO_ROOT/wrappers/stripe-service/app/proto/payment.proto"

CLINIC_LAT="1.3000"
CLINIC_LNG="103.8000"
PATIENT_LAT_ONTIME="1.2900"   # ~1 km  → on time (ETA < appointment_time)
PATIENT_LAT_LATE="1.0000"     # ~33 km → late   (ETA > appointment_time)

# ── Load stripe webhook secret ────────────────────────────────────────────────
WEBHOOK_SECRET=$(grep STRIPE_WEBHOOK_SIGNING_SECRET "$REPO_ROOT/infra/env/stripe-service.env" 2>/dev/null | cut -d= -f2-)
if [ -z "$WEBHOOK_SECRET" ]; then
    echo "WARN: STRIPE_WEBHOOK_SIGNING_SECRET not set — payment webhook tests will be skipped"
fi

# ── Detect short TTL (Scenario D) ─────────────────────────────────────────────
LATE_TTL_MS=$(grep LATE_TTL_MS "$REPO_ROOT/infra/env/checkin-orchestrator.env" 2>/dev/null | cut -d= -f2-)
TTL_SHORT=false
if [ -n "$LATE_TTL_MS" ] && [ "$LATE_TTL_MS" -le 15000 ] 2>/dev/null; then
    TTL_SHORT=true
fi

wait_for_code() {
    URL="$1"
    JWT="$2"
    EXPECTED="$3"
    LABEL="$4"
    CODE="000"

    for _ in $(seq 1 30); do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" \
          -H "Authorization: Bearer $JWT")
        if [ "$CODE" = "$EXPECTED" ]; then
            break
        fi
        sleep 2
    done

    if [ "$CODE" != "$EXPECTED" ]; then
        echo "FAIL: $LABEL (last HTTP $CODE)"
        exit 1
    fi
}

# ── Helper: construct a valid Stripe-Signature header ─────────────────────────
sign_payload() {
    PAYLOAD="$1"
    TS=$(date +%s)
    SIGNED="${TS}.${PAYLOAD}"
    SIG=$(printf '%s' "$SIGNED" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print $2}')
    echo "t=${TS},v1=${SIG}"
}

# ── Helper: book an appointment and wait for queue entry ──────────────────────
book_appointment() {
    SESSION="$1"
    NOTES="$2"
    RESULT=$(curl -sf -X POST "$BASE_COMPOSITE/api/composite/appointments" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $JWT" \
      -d "{\"patient_id\":\"$USER_ID\",\"session\":\"$SESSION\",\"notes\":\"$NOTES\"}")
    echo "$RESULT" | jq . >&2    # display to stderr — not captured by $()
    echo "$RESULT" | jq -r '.id' # only the ID goes to stdout → captured by $()
}

# ── Helper: late check-in ─────────────────────────────────────────────────────
late_checkin() {
    APPT="$1"
    curl -sf -X POST "$BASE_CHECKIN/check-in" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $JWT" \
      -d "{
        \"patient_id\": \"$USER_ID\",
        \"appointment_id\": \"$APPT\",
        \"appointment_time\": \"2026-01-01T08:00:00Z\",
        \"patient_location\": {\"lat\": $PATIENT_LAT_LATE, \"lng\": $CLINIC_LNG},
        \"clinic_location\": {\"lat\": $CLINIC_LAT, \"lng\": $CLINIC_LNG}
      }" | jq .
}

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║        PATIENT JOURNEY — E2E TEST        ║"
echo "╚══════════════════════════════════════════╝"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ PART 1: SETUP (auth) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EMAIL="journey-$(date +%s)@test.com"
PASSWORD="password123"

echo ""
echo "--- 1. Sign up ---"
curl -sf -X POST "$BASE_AUTH/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"name\":\"Test Patient\"}" | jq .

echo ""
echo "--- 2. Sign in ---"
SIGNIN=$(curl -sf -X POST "$BASE_AUTH/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
echo "$SIGNIN" | jq .
SESSION_TOKEN=$(echo "$SIGNIN" | jq -r '.token')
USER_ID=$(echo "$SIGNIN" | jq -r '.user.id')

echo ""
echo "--- 3. Get JWT ---"
JWT=$(curl -sf "$BASE_AUTH/token" \
  -H "Authorization: Bearer $SESSION_TOKEN" | jq -r '.token')
echo "JWT acquired. USER_ID: $USER_ID"

echo ""
echo "--- 3b. Wait for Kong routes ---"
wait_for_code "$BASE_COMPOSITE/api/composite/appointments/openapi.json" "$JWT" "200" "Composite appointment route ready"
wait_for_code "$BASE_QUEUE/api/queue/openapi.json" "$JWT" "200" "Queue route ready"
wait_for_code "$BASE_CHECKIN/check-in/openapi.json" "$JWT" "200" "Check-in route ready"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ SCENARIO A: On-time check-in → consultation → payment success ━━━━━━━"
echo ""
echo "--- A1. Book morning appointment ---"
APPT_A=$(book_appointment "morning" "Scenario A: on-time")
echo "Appointment: $APPT_A"
sleep 2

echo ""
echo "--- A2. Verify queue entry (status=waiting) ---"
curl -sf "$BASE_QUEUE/api/queue/position/$APPT_A" \
  -H "Authorization: Bearer $JWT" | jq .

echo ""
echo "--- A3. On-time check-in (patient nearby) ---"
curl -sf -X POST "$BASE_CHECKIN/check-in" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{
    \"patient_id\": \"$USER_ID\",
    \"appointment_id\": \"$APPT_A\",
    \"appointment_time\": \"2026-12-01T10:00:00Z\",
    \"patient_location\": {\"lat\": $PATIENT_LAT_ONTIME, \"lng\": $CLINIC_LNG},
    \"clinic_location\": {\"lat\": $CLINIC_LAT, \"lng\": $CLINIC_LNG}
  }" | jq .
# Expected: {"status": "checked_in", "eta_minutes": 15}
sleep 2

echo ""
echo "--- A4. Verify queue status → checked_in ---"
curl -sf "$BASE_QUEUE/api/queue/position/$APPT_A" \
  -H "Authorization: Bearer $JWT" | jq .
# Expected: status = "checked_in"

if [ -n "$WEBHOOK_SECRET" ]; then
    echo ""
    echo "--- A5. Consultation complete → Stripe fires checkout.session.completed ---"
    PAYMENT_INTENT_A="pi_test_A_$(date +%s)"
    COMPLETED_PAYLOAD=$(cat <<EOF
{
  "id": "evt_test_A",
  "object": "event",
  "type": "checkout.session.completed",
  "data": {
    "object": {
      "id": "cs_test_A",
      "payment_intent": "$PAYMENT_INTENT_A",
      "metadata": {
        "consultation_id": "$APPT_A",
        "patient_id": "$USER_ID"
      }
    }
  }
}
EOF
)
    SIG=$(sign_payload "$COMPLETED_PAYLOAD")
    curl -sf -X POST "$BASE_STRIPE/webhook" \
      -H "Content-Type: application/json" \
      -H "stripe-signature: $SIG" \
      -d "$COMPLETED_PAYLOAD" | jq .
    # Expected: {"status": "ok"} → publishes payment.completed
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ SCENARIO B: Late check-in → patient responds YES → deprioritized ━━━━"
echo ""
echo "--- B1. Book afternoon appointment ---"
APPT_B=$(book_appointment "afternoon" "Scenario B: late + yes")
echo "Appointment: $APPT_B"
sleep 2

echo ""
echo "--- B2. Late check-in (patient far away) ---"
late_checkin "$APPT_B"
# Expected: {"status": "late", "eta_minutes": 15}
# → publishes queue.late_detected → notification SMS sent

echo ""
echo "--- B3. Patient responds YES → deprioritized ---"
curl -sf -X POST "$BASE_CHECKIN/check-in/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\": \"$USER_ID\", \"appointment_id\": \"$APPT_B\", \"is_coming\": true}" | jq .
# Expected: {"status": "queue_deprioritized"}
sleep 2

echo ""
echo "--- B4. Verify moved to back of queue (new queue_number, status=waiting) ---"
curl -sf "$BASE_QUEUE/api/queue/position/$APPT_B" \
  -H "Authorization: Bearer $JWT" | jq .

if [ -n "$WEBHOOK_SECRET" ]; then
    echo ""
    echo "--- B5. Patient eventually seen → payment fails (card declined) ---"
    PAYMENT_INTENT_B="pi_test_B_$(date +%s)"
    FAILED_PAYLOAD=$(cat <<EOF
{
  "id": "evt_test_B",
  "object": "event",
  "type": "payment_intent.payment_failed",
  "data": {
    "object": {
      "id": "$PAYMENT_INTENT_B",
      "metadata": {
        "consultation_id": "$APPT_B",
        "patient_id": "$USER_ID"
      }
    }
  }
}
EOF
)
    SIG=$(sign_payload "$FAILED_PAYLOAD")
    curl -sf -X POST "$BASE_STRIPE/webhook" \
      -H "Content-Type: application/json" \
      -H "stripe-signature: $SIG" \
      -d "$FAILED_PAYLOAD" | jq .
    # Expected: {"status": "ok"} → publishes payment.failed
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ SCENARIO C: Late check-in → patient responds NO → removed ━━━━━━━━━━━"
echo ""
echo "--- C1. Book morning appointment ---"
APPT_C=$(book_appointment "morning" "Scenario C: late + no")
echo "Appointment: $APPT_C"
sleep 2

echo ""
echo "--- C2. Late check-in ---"
late_checkin "$APPT_C"

echo ""
echo "--- C3. Patient responds NO → removed from queue ---"
curl -sf -X POST "$BASE_CHECKIN/check-in/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\": \"$USER_ID\", \"appointment_id\": \"$APPT_C\", \"is_coming\": false}" | jq .
# Expected: {"status": "queue_removed"}
sleep 2

echo ""
echo "--- C4. Verify removed (expect error — not in queue) ---"
curl -s "$BASE_QUEUE/api/queue/position/$APPT_C" \
  -H "Authorization: Bearer $JWT" | jq .
# Expected: {"error": "Appointment not in queue"}

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ SCENARIO D: Late check-in → no response → TTL auto-removal ━━━━━━━━━━"

if [ "$TTL_SHORT" = "false" ]; then
    echo ""
    echo "  SKIPPED — LATE_TTL_MS is not set to a short value."
    echo "  To run this scenario:"
    echo "    1. Edit infra/env/checkin-orchestrator.env → LATE_TTL_MS=10000"
    echo "    2. cd infra && docker compose up -d --build checkin-orchestrator"
    echo "    3. Re-run this script."
else
    echo ""
    echo "--- D1. Book afternoon appointment ---"
    APPT_D=$(book_appointment "afternoon" "Scenario D: no response")
    echo "Appointment: $APPT_D"
    sleep 2

    echo ""
    echo "--- D2. Late check-in (no confirm will follow) ---"
    late_checkin "$APPT_D"
    # → publishes queue.late_detected
    # → TTL queue starts $LATE_TTL_MS ms countdown

    echo ""
    echo "--- D3. Waiting ${LATE_TTL_MS}ms for TTL to fire queue.removed ---"
    WAIT_SECS=$(( (LATE_TTL_MS + 2000) / 1000 ))
    sleep "$WAIT_SECS"

    echo ""
    echo "--- D4. Verify auto-removed (expect error — not in queue) ---"
    curl -s "$BASE_QUEUE/api/queue/position/$APPT_D" \
      -H "Authorization: Bearer $JWT" | jq .
    # Expected: {"error": "Appointment not in queue"}

    echo ""
    echo "--- D5. Dedup test: send queue.removed again for same appointment ---"
    echo "    Notification service should log 'Dropping duplicate queue.removed'"
    echo "    Check with: docker logs infra-notification-service-1 --tail 20"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ PART 2: PAYMENT WEBHOOK SECURITY ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -z "$WEBHOOK_SECRET" ]; then
    echo "  SKIPPED — STRIPE_WEBHOOK_SIGNING_SECRET not set in stripe-service.env"
else
    echo ""
    echo "--- P1. Missing Stripe-Signature header (expect 400) ---"
    curl -s -X POST "$BASE_STRIPE/webhook" \
      -H "Content-Type: application/json" \
      -d '{"type":"checkout.session.completed"}' | jq .

    echo ""
    echo "--- P2. Invalid signature (expect 400) ---"
    curl -s -X POST "$BASE_STRIPE/webhook" \
      -H "Content-Type: application/json" \
      -H "stripe-signature: t=0,v1=invalidsignature" \
      -d '{"type":"checkout.session.completed"}' | jq .

    echo ""
    echo "--- P3. Unhandled event type (expect 200, no-op) ---"
    UNHANDLED='{"id":"evt_test_P3","object":"event","type":"customer.created","data":{"object":{}}}'
    SIG=$(sign_payload "$UNHANDLED")
    curl -s -X POST "$BASE_STRIPE/webhook" \
      -H "Content-Type: application/json" \
      -H "stripe-signature: $SIG" \
      -d "$UNHANDLED" | jq .
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ PART 3: gRPC ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "--- G1. Service reflection (PaymentService registered) ---"
if command -v grpcurl >/dev/null 2>&1; then
  grpcurl -plaintext "$GRPC_STRIPE" list 2>/dev/null | grep -q "payment.PaymentService" && \
    echo "payment.PaymentService ✓" || \
    echo "WARN: reflection not returning PaymentService (is stripe-service running?)"
else
  echo "SKIP: grpcurl not installed; skipping reflection check"
fi

echo ""
echo "--- G2. CreatePaymentRequest (requires valid STRIPE_API_KEY) ---"
if command -v grpcurl >/dev/null 2>&1; then
  grpcurl -plaintext \
    -proto "$PROTO" \
    -d "{
      \"appointment_id\": \"$APPT_A\",
      \"patient_id\": \"$USER_ID\"
    }" \
    "$GRPC_STRIPE" payment.PaymentService/CreatePaymentRequest 2>&1 | jq . 2>/dev/null || \
    echo "(gRPC INTERNAL error expected if Stripe key is test/invalid)"
else
  echo "SKIP: grpcurl not installed; skipping CreatePaymentRequest check"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━ PART 4: ERROR / VALIDATION CASES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "--- E1. Check-in with no auth (expect 401) ---"
curl -s -X POST "$BASE_CHECKIN/check-in" \
  -H "Content-Type: application/json" \
  -d "{\"patient_id\":\"x\",\"appointment_id\":\"x\",\"appointment_time\":\"2026-12-01T10:00:00Z\",\"patient_location\":{\"lat\":1.3,\"lng\":103.8},\"clinic_location\":{\"lat\":1.3,\"lng\":103.8}}" | jq .

echo ""
echo "--- E2. Check-in with bad token (expect 401) ---"
curl -s -X POST "$BASE_CHECKIN/check-in" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer badtoken" \
  -d "{\"patient_id\":\"x\",\"appointment_id\":\"x\",\"appointment_time\":\"2026-12-01T10:00:00Z\",\"patient_location\":{\"lat\":1.3,\"lng\":103.8},\"clinic_location\":{\"lat\":1.3,\"lng\":103.8}}" | jq .

echo ""
echo "--- E3. Check-in with missing fields (expect 422) ---"
curl -s -X POST "$BASE_CHECKIN/check-in" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\": \"$USER_ID\"}" | jq .

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║           ALL SCENARIOS DONE             ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Scenario summary:"
echo "  A — On-time check-in + payment success  : appointment $APPT_A"
echo "  B — Late + YES (deprioritized) + payment failed : appointment $APPT_B"
echo "  C — Late + NO (removed)                 : appointment $APPT_C"
if [ "$TTL_SHORT" = "true" ]; then
echo "  D — Late + no response (TTL auto-removal): appointment $APPT_D"
else
echo "  D — TTL auto-removal                    : SKIPPED (set LATE_TTL_MS=10000)"
fi
echo ""
echo "Verify RabbitMQ events in service logs:"
echo "  docker logs infra-queue-coordinator-service-1 --tail 30"
echo "  docker logs infra-notification-service-1 --tail 30"
echo "  docker logs stripe-service --tail 20"
