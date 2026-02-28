#!/bin/sh
# End-to-end test for the appointment composite service.
# Run from the repo root: sh infra/test-appointment.sh

set -e

BASE_AUTH="http://localhost:3000"
BASE_COMPOSITE="http://localhost:8080"
BASE_ATOMIC="http://localhost:3001"
EMAIL="test-$(date +%s)@test.com"
PASSWORD="password123"

echo ""
echo "=== 1. Sign up ==="
curl -sf -X POST "$BASE_AUTH/api/auth/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"name\":\"Test User\"}" | jq .

echo ""
echo "=== 2. Sign in (get session token) ==="
SIGNIN=$(curl -sf -X POST "$BASE_AUTH/api/auth/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
echo "$SIGNIN" | jq .
SESSION_TOKEN=$(echo "$SIGNIN" | jq -r '.token')
USER_ID=$(echo "$SIGNIN" | jq -r '.user.id')
echo "Session token: $SESSION_TOKEN"
echo "User ID: $USER_ID"

echo ""
echo "=== 3. Exchange for JWT ==="
JWT_RESP=$(curl -sf "$BASE_AUTH/api/auth/token" \
  -H "Authorization: Bearer $SESSION_TOKEN")
echo "$JWT_RESP" | jq .
JWT=$(echo "$JWT_RESP" | jq -r '.token')
echo "JWT: $JWT"

echo ""
echo "=== 4. Book appointment (composite) ==="
APPT=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"start_time\":\"2026-04-01T09:00:00Z\",\"notes\":\"Headache\"}")
echo "$APPT" | jq .
APPT_ID=$(echo "$APPT" | jq -r '.id')
echo "Appointment ID: $APPT_ID"

echo ""
echo "=== 5. Get appointment ==="
curl -sf "$BASE_COMPOSITE/composite/appointments/$APPT_ID" \
  -H "Authorization: Bearer $JWT" | jq .

echo ""
echo "=== 6. Invalid timeslot — expect 400 ==="
curl -s -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"start_time\":\"2026-04-01T09:07:00Z\"}" | jq .

echo ""
echo "=== 7. Invalid token — expect 401 ==="
curl -s -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer badtoken" \
  -d "{\"patient_id\":\"$USER_ID\",\"start_time\":\"2026-04-01T09:30:00Z\"}" | jq .

echo ""
echo "=== 8. Cancel appointment ==="
curl -sf -X DELETE "$BASE_COMPOSITE/composite/appointments/$APPT_ID" \
  -H "Authorization: Bearer $JWT" | jq .

echo ""
echo "=== 9. Cancel already-cancelled — expect 409 ==="
curl -s -X DELETE "$BASE_COMPOSITE/composite/appointments/$APPT_ID" \
  -H "Authorization: Bearer $JWT" | jq .

echo ""
echo "=== 10. Get non-existent appointment — expect 404 ==="
curl -s "$BASE_COMPOSITE/composite/appointments/00000000-0000-0000-0000-000000000000" \
  -H "Authorization: Bearer $JWT" | jq .

echo ""
echo "=== All tests done ==="
