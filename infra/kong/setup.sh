#!/bin/sh

KONG_ADMIN="http://kong:8001"

echo "Waiting for Kong to be ready..."
until curl -sf "$KONG_ADMIN/status" > /dev/null 2>&1; do
  echo "Kong not ready yet, retrying in 5s..."
  sleep 5
done
echo "Kong is ready."

set -e

# ─── Auth Service ────────────────────────────────────────────
echo "Configuring auth-service..."

curl -sf -o /dev/null -X PUT "$KONG_ADMIN/services/auth-service" \
  --data "url=http://auth-service:3000"

curl -sf -o /dev/null -X PUT "$KONG_ADMIN/routes/auth-route" \
  --data "service.name=auth-service" \
  --data "paths[]=/api/auth" \
  --data "paths[]=/api/auth/" \
  --data "strip_path=false" \
  --data "regex_priority=0"

# ─── Appointment Service ─────────────────────────────────────
# echo "Configuring appointment-service..."
# curl -sf -o /dev/null -X PUT "$KONG_ADMIN/services/appointment-service" \
#   --data "url=http://appointment-service:3001"
# curl -sf -o /dev/null -X PUT "$KONG_ADMIN/routes/appointment-route" \
#   --data "service.name=appointment-service" \
#   --data "paths[]=/api/appointments" \
#   --data "strip_path=false"

# ─── Queue Coordinator Service ───────────────────────────────
# echo "Configuring queue-coordinator-service..."
# curl -sf -o /dev/null -X PUT "$KONG_ADMIN/services/queue-coordinator-service" \
#   --data "url=http://queue-coordinator-service:3002"
# curl -sf -o /dev/null -X PUT "$KONG_ADMIN/routes/queue-route" \
#   --data "service.name=queue-coordinator-service" \
#   --data "paths[]=/api/queue" \
#   --data "strip_path=false"

# ─── ETA Service ─────────────────────────────────────────────
# echo "Configuring eta-service..."
# curl -sf -o /dev/null -X PUT "$KONG_ADMIN/services/eta-service" \
#   --data "url=http://eta-service:3003"
# curl -sf -o /dev/null -X PUT "$KONG_ADMIN/routes/eta-route" \
#   --data "service.name=eta-service" \
#   --data "paths[]=/api/eta" \
#   --data "strip_path=false"

# ─── Notification Service ────────────────────────────────────
# echo "Configuring notification-service..."
# curl -sf -o /dev/null -X PUT "$KONG_ADMIN/services/notification-service" \
#   --data "url=http://notification-service:3004"
# curl -sf -o /dev/null -X PUT "$KONG_ADMIN/routes/notification-route" \
#   --data "service.name=notification-service" \
#   --data "paths[]=/api/notifications" \
#   --data "strip_path=false"

# ─── Activity Log Service ────────────────────────────────────
# echo "Configuring activity-log-service..."
# curl -sf -o /dev/null -X PUT "$KONG_ADMIN/services/activity-log-service" \
#   --data "url=http://activity-log-service:3005"
# curl -sf -o /dev/null -X PUT "$KONG_ADMIN/routes/activity-log-route" \
#   --data "service.name=activity-log-service" \
#   --data "paths[]=/api/activity" \
#   --data "strip_path=false"

# ─── JWT Plugin ─────────────────────────────────────────────
echo "Configuring JWT plugin..."

# Create a Kong consumer representing BetterAuth
curl -sf -o /dev/null -X PUT "$KONG_ADMIN/consumers/better-auth"

# Add JWT credential matching BetterAuth's issuer and secret
curl -sf -o /dev/null -X POST "$KONG_ADMIN/consumers/better-auth/jwt" \
  --data "algorithm=HS256" \
  --data "key=smart-clinic" \
  --data "secret=${BETTER_AUTH_SECRET}"

# Enable JWT plugin on all protected routes (not auth)
for ROUTE in appointment-route queue-route eta-route notification-route activity-log-route; do
  curl -sf -o /dev/null -X POST "$KONG_ADMIN/routes/$ROUTE/plugins" \
    --data "name=jwt" 2>/dev/null || true
done

echo "Kong configuration complete."
