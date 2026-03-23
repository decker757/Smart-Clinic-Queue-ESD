#!/bin/sh
# End-to-end test for the check-in orchestrator composite service.
# Run from the repo root: sh infra/tests/test-checkin.sh
#
# Requires (all via docker compose):
#   auth-service         → localhost:3000
#   composite-appointment → localhost:8080  (books the appointment)
#   queue-coordinator    → localhost:3002   (verifies queue state)
#   checkin-orchestrator → localhost:8085   (under test)
#   rabbitmq             → internal         (event bus)
#   eta-service          → optional         (falls back to 15 min)
#
# Start stack:  cd infra && docker compose up -d auth-service rabbitmq \
#                 composite-appointment queue-coordinator-service \
#                 checkin-orchestrator eta-service
#
# To test the 5-min TTL without waiting, temporarily set LATE_TTL_MS=10000
# in the checkin-orchestrator environment and rebuild:
#   docker compose up -d --build checkin-orchestrator

set -e

KONG="http://localhost:8000"
BASE_AUTH="$KONG/api/auth"
BASE_COMPOSITE="$KONG"
BASE_CHECKIN="$KONG/api"
BASE_QUEUE="$KONG"
EMAIL="checkin-$(date +%s)@test.com"
PASSWORD="password123"

CLINIC_LAT="1.3000"
CLINIC_LNG="103.8000"
PATIENT_LAT_ONTIME="1.2900"   # ~1 km from clinic  → on time
PATIENT_LAT_LATE="1.0000"     # ~33 km from clinic → late

echo ""
echo "=== 1. Sign up ==="
curl -sf -X POST "$BASE_AUTH/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"name\":\"Test Patient\"}" | jq .

echo ""
echo "=== 2. Sign in ==="
SIGNIN=$(curl -sf -X POST "$BASE_AUTH/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
echo "$SIGNIN" | jq .
SESSION_TOKEN=$(echo "$SIGNIN" | jq -r '.token')
USER_ID=$(echo "$SIGNIN" | jq -r '.user.id')

echo ""
echo "=== 3. Get JWT ==="
JWT=$(curl -sf "$BASE_AUTH/token" \
  -H "Authorization: Bearer $SESSION_TOKEN" | jq -r '.token')
echo "JWT acquired."

echo ""
echo "=== 4. Book a morning appointment (creates queue entry) ==="
BOOKING=$(curl -sf -X POST "$BASE_COMPOSITE/api/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"E2E check-in test\"}")
echo "$BOOKING" | jq .
APPT_ID=$(echo "$BOOKING" | jq -r '.id')
echo "Appointment ID: $APPT_ID"

echo ""
echo "--- Waiting 2s for queue-coordinator to process appointment.booked event ---"
sleep 2

echo ""
echo "=== 5. Verify queue entry exists (status=waiting) ==="
curl -sf "$BASE_QUEUE/api/queue/position/$APPT_ID" \
  -H "Authorization: Bearer $JWT" | jq .
# Expected: status = "waiting"

echo ""
echo "=== 6. On-time check-in (patient nearby) ==="
CHECKIN=$(curl -sf -X POST "$BASE_CHECKIN/check-in" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{
    \"patient_id\": \"$USER_ID\",
    \"appointment_id\": \"$APPT_ID\",
    \"appointment_time\": \"2026-12-01T10:00:00Z\",
    \"patient_location\": {\"lat\": $PATIENT_LAT_ONTIME, \"lng\": $CLINIC_LNG},
    \"clinic_location\": {\"lat\": $CLINIC_LAT, \"lng\": $CLINIC_LNG}
  }")
echo "$CHECKIN" | jq .
# Expected: {"status": "checked_in", "eta_minutes": 15}
# → publishes queue.checked_in → queue-coordinator sets status=checked_in

echo ""
echo "--- Waiting 2s for queue-coordinator to process queue.checked_in event ---"
sleep 2

echo ""
echo "=== 7. Verify queue status is now checked_in ==="
curl -sf "$BASE_QUEUE/api/queue/position/$APPT_ID" \
  -H "Authorization: Bearer $JWT" | jq .
# Expected: status = "checked_in"

echo ""
echo "=== 8. Book a second appointment for late-arrival tests ==="
BOOKING2=$(curl -sf -X POST "$BASE_COMPOSITE/api/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"afternoon\",\"notes\":\"Late test\"}")
echo "$BOOKING2" | jq .
APPT_ID2=$(echo "$BOOKING2" | jq -r '.id')
echo "Appointment ID: $APPT_ID2"
sleep 2

echo ""
echo "=== 9. Late check-in (patient far away) ==="
LATE=$(curl -sf -X POST "$BASE_CHECKIN/check-in" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{
    \"patient_id\": \"$USER_ID\",
    \"appointment_id\": \"$APPT_ID2\",
    \"appointment_time\": \"2026-01-01T08:00:00Z\",
    \"patient_location\": {\"lat\": $PATIENT_LAT_LATE, \"lng\": $CLINIC_LNG},
    \"clinic_location\": {\"lat\": $CLINIC_LAT, \"lng\": $CLINIC_LNG}
  }")
echo "$LATE" | jq .
# Expected: {"status": "late", "eta_minutes": 15}
# → publishes queue.late_detected → notification service sends "Are you still coming?" SMS
# → late-detection-ttl queue starts 5-min countdown; if no /confirm, fires queue.removed

echo ""
echo "=== 10. Patient confirms: still coming (deprioritise) ==="
curl -sf -X POST "$BASE_CHECKIN/check-in/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\": \"$USER_ID\", \"appointment_id\": \"$APPT_ID2\", \"is_coming\": true}" | jq .
# Expected: {"status": "queue_deprioritized"}
sleep 2

echo ""
echo "=== 11. Verify queue entry moved to back (new queue_number, status=waiting) ==="
curl -sf "$BASE_QUEUE/api/queue/position/$APPT_ID2" \
  -H "Authorization: Bearer $JWT" | jq .

echo ""
echo "=== 12. Book a third appointment for cancel-via-confirm test ==="
BOOKING3=$(curl -sf -X POST "$BASE_COMPOSITE/api/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Cancel test\"}")
APPT_ID3=$(echo "$BOOKING3" | jq -r '.id')
echo "Appointment ID: $APPT_ID3"
sleep 2

echo ""
echo "=== 13. Late check-in for third appointment ==="
curl -sf -X POST "$BASE_CHECKIN/check-in" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{
    \"patient_id\": \"$USER_ID\",
    \"appointment_id\": \"$APPT_ID3\",
    \"appointment_time\": \"2026-01-01T08:00:00Z\",
    \"patient_location\": {\"lat\": $PATIENT_LAT_LATE, \"lng\": $CLINIC_LNG},
    \"clinic_location\": {\"lat\": $CLINIC_LAT, \"lng\": $CLINIC_LNG}
  }" | jq .

echo ""
echo "=== 14. Patient confirms: NOT coming (remove from queue) ==="
curl -sf -X POST "$BASE_CHECKIN/check-in/confirm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\": \"$USER_ID\", \"appointment_id\": \"$APPT_ID3\", \"is_coming\": false}" | jq .
# Expected: {"status": "queue_removed"}
sleep 2

echo ""
echo "=== 15. Verify third appointment removed (expect error — not in queue) ==="
curl -s "$BASE_QUEUE/api/queue/position/$APPT_ID3" \
  -H "Authorization: Bearer $JWT" | jq .
# Expected: error "Appointment not in queue" (queue-coordinator returns 500/404 for cancelled entries)

echo ""
echo "=== 16. Auth checks ==="
echo "-- No auth header (expect 401) --"
curl -s -X POST "$BASE_CHECKIN/check-in" \
  -H "Content-Type: application/json" \
  -d "{\"patient_id\":\"x\",\"appointment_id\":\"x\",\"appointment_time\":\"2026-12-01T10:00:00Z\",\"patient_location\":{\"lat\":1.3,\"lng\":103.8},\"clinic_location\":{\"lat\":1.3,\"lng\":103.8}}" | jq .

echo "-- Bad token (expect 401) --"
curl -s -X POST "$BASE_CHECKIN/check-in" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer badtoken" \
  -d "{\"patient_id\":\"x\",\"appointment_id\":\"x\",\"appointment_time\":\"2026-12-01T10:00:00Z\",\"patient_location\":{\"lat\":1.3,\"lng\":103.8},\"clinic_location\":{\"lat\":1.3,\"lng\":103.8}}" | jq .

echo ""
echo "=== 17. Missing field (expect 422) ==="
curl -s -X POST "$BASE_CHECKIN/check-in" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\": \"$USER_ID\"}" | jq .

echo ""
echo "==================================================================="
echo "  To test the 5-min TTL auto-removal without waiting:"
echo "  1. Set LATE_TTL_MS=10000 in checkin-orchestrator env"
echo "  2. docker compose up -d --build checkin-orchestrator"
echo "  3. Run a late check-in (step 9 above) without calling /confirm"
echo "  4. Wait 10s, then check queue position — should be cancelled"
echo "==================================================================="
echo ""
echo "=== All tests done ==="
