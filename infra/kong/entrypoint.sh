#!/bin/sh
set -e

# Convert multiline PEM to single-line escaped form so it fits in a
# YAML double-quoted string:  "-----BEGIN PUBLIC KEY-----\nMIIB...\n"
# YAML double-quoted strings interpret \n as actual newlines — Kong accepts this.
export BETTER_AUTH_RSA_PUBLIC_KEY_ESCAPED=$(printf '%s' "$BETTER_AUTH_RSA_PUBLIC_KEY" | awk '{printf "%s\\n", $0}')

# Substitute all env vars into the kong.yml template
envsubst '$AUTH_SERVICE_URL $COMPOSITE_APPOINTMENT_URL $COMPOSITE_CONSULTATION_URL $COMPOSITE_PATIENT_URL $QUEUE_COORDINATOR_URL $ACTIVITY_LOG_SERVICE_URL $PATIENT_SERVICE_URL $DOCTOR_SERVICE_URL $BETTER_AUTH_RSA_PUBLIC_KEY_ESCAPED' \
  < /etc/kong/kong.yml.template \
  > /etc/kong/kong.yml

exec /docker-entrypoint.sh kong docker-start
