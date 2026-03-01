#!/bin/sh
# End-to-end test for the appointment composite service.
# Run from the repo root: sh infra/tests/test-appointment.sh

set -e

BASE_AUTH="http://localhost:3000"
BASE_COMPOSITE="http://localhost:8080"
EMAIL="test-$(date +%s)@test.com"
PASSWORD="password123"

echo ""
echo "=== 1. Sign up ==="
curl -sf -X POST "$BASE_AUTH/api/auth/sign-up/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"name\":\"Test User\"}" | jq .

echo ""
echo "=== 2. Sign in ==="
SIGNIN=$(curl -sf -X POST "$BASE_AUTH/api/auth/sign-in/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
echo "$SIGNIN" | jq .
SESSION_TOKEN=$(echo "$SIGNIN" | jq -r '.token')
USER_ID=$(echo "$SIGNIN" | jq -r '.user.id')

echo ""
echo "=== 3. Get JWT ==="
JWT=$(curl -sf "$BASE_AUTH/api/auth/token" \
  -H "Authorization: Bearer $SESSION_TOKEN" | jq -r '.token')
echo "JWT acquired."

echo ""
echo "=== 4. Book generic morning slot ==="
MORNING=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"notes\":\"Headache\"}")
echo "$MORNING" | jq .
MORNING_ID=$(echo "$MORNING" | jq -r '.id')

echo ""
echo "=== 5. Book generic afternoon slot ==="
AFTERNOON=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"afternoon\",\"notes\":\"Follow-up\"}")
echo "$AFTERNOON" | jq .
AFTERNOON_ID=$(echo "$AFTERNOON" | jq -r '.id')

echo ""
echo "=== 6. Book specific doctor slot ==="
SPECIFIC=$(curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"doctor_id\":\"a0000000-0000-0000-0000-000000000001\",\"start_time\":\"2026-04-01T09:00:00Z\",\"notes\":\"Chest pain\"}")
echo "$SPECIFIC" | jq .
SPECIFIC_ID=$(echo "$SPECIFIC" | jq -r '.id')

echo ""
echo "=== 7. Fill doctor slot to capacity (book same slot 2 more times) ==="
curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"doctor_id\":\"a0000000-0000-0000-0000-000000000001\",\"start_time\":\"2026-04-01T09:00:00Z\",\"notes\":\"Booking 2\"}" | jq .id

curl -sf -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"doctor_id\":\"a0000000-0000-0000-0000-000000000001\",\"start_time\":\"2026-04-01T09:00:00Z\",\"notes\":\"Booking 3\"}" | jq .id

echo ""
echo "=== 8. Exceed capacity — expect 409 ==="
curl -s -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"doctor_id\":\"a0000000-0000-0000-0000-000000000001\",\"start_time\":\"2026-04-01T09:00:00Z\",\"notes\":\"Booking 4 - should fail\"}" | jq .

echo ""
echo "=== 9. Get morning appointment ==="
curl -sf "$BASE_COMPOSITE/composite/appointments/$MORNING_ID" \
  -H "Authorization: Bearer $JWT" | jq .

echo ""
echo "=== 7. Invalid: both session and start_time — expect 422 ==="
curl -s -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\",\"start_time\":\"2026-04-01T09:00:00Z\"}" | jq .

echo ""
echo "=== 8. Invalid: neither session nor start_time — expect 422 ==="
curl -s -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"notes\":\"nothing\"}" | jq .

echo ""
echo "=== 9. Invalid: start_time without doctor_id — expect 422 ==="
curl -s -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"start_time\":\"2026-04-01T09:00:00Z\"}" | jq .

echo ""
echo "=== 10. Invalid: non-15min interval — expect 400 ==="
curl -s -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT" \
  -d "{\"patient_id\":\"$USER_ID\",\"doctor_id\":\"a0000000-0000-0000-0000-000000000001\",\"start_time\":\"2026-04-01T09:07:00Z\"}" | jq .

echo ""
echo "=== 11. Invalid token — expect 401 ==="
curl -s -X POST "$BASE_COMPOSITE/composite/appointments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer badtoken" \
  -d "{\"patient_id\":\"$USER_ID\",\"session\":\"morning\"}" | jq .

echo ""
echo "=== 12. Cancel morning appointment ==="
curl -sf -X DELETE "$BASE_COMPOSITE/composite/appointments/$MORNING_ID" \
  -H "Authorization: Bearer $JWT" | jq .

echo ""
echo "=== 13. Cancel already-cancelled — expect 409 ==="
curl -s -X DELETE "$BASE_COMPOSITE/composite/appointments/$MORNING_ID" \
  -H "Authorization: Bearer $JWT" | jq .

echo ""
echo "=== 14. Get non-existent appointment — expect 404 ==="
curl -s "$BASE_COMPOSITE/composite/appointments/00000000-0000-0000-0000-000000000000" \
  -H "Authorization: Bearer $JWT" | jq .

echo ""
echo "=== All tests done ==="
