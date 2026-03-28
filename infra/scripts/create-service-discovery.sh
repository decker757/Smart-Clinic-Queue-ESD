#!/bin/sh
# Create Cloud Map service discovery entries for all services.
# Run from repo root: sh infra/scripts/create-service-discovery.sh

set -e

REGION=ap-southeast-1
NAMESPACE_ID=ns-cetcm7jpnixwoatx

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
create_sd frontend

echo ""
echo "All service discovery entries created."
echo "Note the service IDs above — you'll need them when creating ECS services."
