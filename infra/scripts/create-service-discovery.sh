#!/bin/sh
# Create Cloud Map service discovery entries for all backend services.
# Run from repo root: sh infra/scripts/create-service-discovery.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env.aws"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE not found."
    echo "Copy env-aws.example to .env.aws and fill in your deployment config."
    exit 1
fi

# shellcheck disable=SC1090
. "$ENV_FILE"

for var in AWS_REGION CLOUD_MAP_NAMESPACE_ID; do
    eval val=\$$var
    if [ -z "$val" ]; then
        echo "ERROR: $var is not set in .env.aws"
        exit 1
    fi
done

REGION=$AWS_REGION
NAMESPACE_ID=$CLOUD_MAP_NAMESPACE_ID

create_sd() {
    NAME=$1
    echo "Creating service discovery for $NAME..."
    aws servicediscovery create-service \
        --name "$NAME" \
        --namespace-id "$NAMESPACE_ID" \
        --dns-config "NamespaceId=$NAMESPACE_ID,DnsRecords=[{Type=A,TTL=10}]" \
        --health-check-custom-config "FailureThreshold=1" \
        --region "$REGION" \
        --query "Service.Id" \
        --output text
}

create_sd auth-service
create_sd appointment-service
create_sd queue-coordinator-service
create_sd patient-service
create_sd doctor-service
create_sd activity-log-service
create_sd payment-service
create_sd eta-service
create_sd notification-service
create_sd stripe-service
create_sd composite-appointment
create_sd composite-patient-orchestrator
create_sd composite-consultation
create_sd composite-staff-orchestrator
create_sd checkin-orchestrator

echo ""
echo "All service discovery entries created."
echo "Frontend is deployed via S3/CloudFront and does not need Cloud Map."
