#!/bin/sh
# Create ECS Fargate services for all backend task definitions.
# Run from repo root: sh infra/scripts/create-ecs-services.sh

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

for var in AWS_ACCOUNT_ID AWS_REGION ECS_CLUSTER_NAME ECS_SUBNETS ECS_SECURITY_GROUP \
           CLOUD_MAP_NAMESPACE_ID TG_AUTH_NAME TG_QUEUE_NAME TG_COMPOSITE_APPOINTMENT_NAME \
           TG_CHECKIN_NAME TG_COMPOSITE_CONSULTATION_NAME TG_COMPOSITE_STAFF_NAME \
           TG_COMPOSITE_PATIENT_NAME TG_PAYMENT_NAME TG_STRIPE_WEBHOOK_NAME \
           TG_APPOINTMENT_NAME; do
    eval val=\$$var
    if [ -z "$val" ]; then
        echo "ERROR: $var is not set in .env.aws"
        exit 1
    fi
done

ACCOUNT=$AWS_ACCOUNT_ID
REGION=$AWS_REGION
CLUSTER=$ECS_CLUSTER_NAME
SUBNETS=$ECS_SUBNETS
SG=$ECS_SECURITY_GROUP
NAMESPACE_ID=$CLOUD_MAP_NAMESPACE_ID
DESIRED_COUNT=${ECS_DESIRED_COUNT:-1}
ASSIGN_PUBLIC_IP=${ECS_ASSIGN_PUBLIC_IP:-ENABLED}
NETWORK_CONFIG="awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=$ASSIGN_PUBLIC_IP}"

resolve_sd_id() {
    NAME=$1
    aws servicediscovery list-services \
        --region "$REGION" \
        --filters "Name=NAMESPACE_ID,Values=$NAMESPACE_ID,Condition=EQ" \
        --query "Services[?Name=='$NAME'].Id | [0]" \
        --output text
}

resolve_tg_arn() {
    NAME=$1
    aws elbv2 describe-target-groups \
        --region "$REGION" \
        --names "$NAME" \
        --query "TargetGroups[0].TargetGroupArn" \
        --output text
}

create_service() {
    NAME=$1
    PORT=$2
    TG_NAME=${3:-}
    SD_ID=$(resolve_sd_id "$NAME")
    if [ -z "$SD_ID" ] || [ "$SD_ID" = "None" ]; then
        echo "ERROR: Cloud Map service for $NAME not found in namespace $NAMESPACE_ID"
        exit 1
    fi
    echo "Creating ECS service: $NAME..."
    SERVICE_REGISTRY="registryArn=arn:aws:servicediscovery:$REGION:$ACCOUNT:service/$SD_ID"

    if [ -n "$TG_NAME" ]; then
        TG_ARN=$(resolve_tg_arn "$TG_NAME")
        if [ -z "$TG_ARN" ] || [ "$TG_ARN" = "None" ]; then
            echo "ERROR: Target group $TG_NAME not found"
            exit 1
        fi
        aws ecs create-service \
            --cluster "$CLUSTER" \
            --service-name "$NAME" \
            --task-definition "$NAME" \
            --desired-count "$DESIRED_COUNT" \
            --launch-type FARGATE \
            --network-configuration "$NETWORK_CONFIG" \
            --service-registries "$SERVICE_REGISTRY" \
            --load-balancers "targetGroupArn=$TG_ARN,containerName=$NAME,containerPort=$PORT" \
            --health-check-grace-period-seconds 60 \
            --region "$REGION" \
            --query "service.serviceArn" \
            --output text
    else
        aws ecs create-service \
            --cluster "$CLUSTER" \
            --service-name "$NAME" \
            --task-definition "$NAME" \
            --desired-count "$DESIRED_COUNT" \
            --launch-type FARGATE \
            --network-configuration "$NETWORK_CONFIG" \
            --service-registries "$SERVICE_REGISTRY" \
            --region "$REGION" \
            --query "service.serviceArn" \
            --output text
    fi
}

create_service auth-service                   3000 "$TG_AUTH_NAME"
create_service appointment-service            3001 "$TG_APPOINTMENT_NAME"
create_service queue-coordinator-service      3002 "$TG_QUEUE_NAME"
create_service patient-service                3007
create_service doctor-service                 3006
create_service activity-log-service           3005
create_service payment-service                3008 "$TG_PAYMENT_NAME"
create_service eta-service                    50054
create_service notification-service           3004
create_service stripe-service                 8001 "$TG_STRIPE_WEBHOOK_NAME"
create_service composite-appointment          8000 "$TG_COMPOSITE_APPOINTMENT_NAME"
create_service composite-patient-orchestrator 8001 "$TG_COMPOSITE_PATIENT_NAME"
create_service composite-consultation         8002 "$TG_COMPOSITE_CONSULTATION_NAME"
create_service composite-staff-orchestrator   8004 "$TG_COMPOSITE_STAFF_NAME"
create_service checkin-orchestrator           8000 "$TG_CHECKIN_NAME"

echo ""
echo "All backend ECS services created."
echo "Monitor status: aws ecs list-services --cluster $CLUSTER --region $REGION"
