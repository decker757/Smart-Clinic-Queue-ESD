#!/bin/sh
# Register ECS task definitions for all backend ECS services.
# Run from repo root: sh infra/scripts/register-task-definitions.sh
#
# Deployment config is loaded from infra/scripts/.env.aws (gitignored).
# Copy env-aws.example → .env.aws and fill in your real values.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env.aws"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE not found."
    echo "Copy env-aws.example to .env.aws and fill in your secrets."
    exit 1
fi

# shellcheck disable=SC1090
. "$ENV_FILE"

# Validate required deployment config is set
for var in AWS_ACCOUNT_ID AWS_REGION DB_URL MQ_URL REDIS_URL BETTER_AUTH_SECRET \
           BETTER_AUTH_URL FRONTEND_BASE_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
           S3_BUCKET GOOGLE_MAPS_API_KEY TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN \
           STRIPE_API_KEY STRIPE_WEBHOOK_SIGNING_SECRET COGNITO_JWKS_URL; do
    eval val=\$$var
    if [ -z "$val" ]; then
        echo "ERROR: $var is not set in .env.aws"
        exit 1
    fi
done

ACCOUNT=$AWS_ACCOUNT_ID
REGION=$AWS_REGION
REGISTRY=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com
EXEC_ROLE=${ECS_TASK_EXECUTION_ROLE_ARN:-arn:aws:iam::${ACCOUNT}:role/ecsTaskExecutionRole}
LOG_GROUP=${CLOUDWATCH_LOG_GROUP:-/ecs/smart-clinic}
NS=${CLOUD_MAP_NAMESPACE:-smart-clinic.local}
STRIPE_SUCCESS_URL_VALUE=${STRIPE_SUCCESS_URL:-}
STRIPE_CANCEL_URL_VALUE=${STRIPE_CANCEL_URL:-}

if [ -z "$STRIPE_SUCCESS_URL_VALUE" ]; then
    STRIPE_SUCCESS_URL_VALUE="$FRONTEND_BASE_URL/success?session_id={CHECKOUT_SESSION_ID}"
fi

if [ -z "$STRIPE_CANCEL_URL_VALUE" ]; then
    STRIPE_CANCEL_URL_VALUE="$FRONTEND_BASE_URL/cancel"
fi

echo "Creating CloudWatch log group ${LOG_GROUP}..."
aws logs create-log-group --log-group-name "$LOG_GROUP" --region "$REGION" 2>/dev/null || true

TMP=$(mktemp -d)

register() {
    NAME=$1
    FILE=$TMP/$NAME.json
    cat > "$FILE"
    echo "Registering $NAME..."
    aws ecs register-task-definition --region "$REGION" --cli-input-json "file://$FILE"
}

log() {
    cat <<EOF
{"logDriver":"awslogs","options":{"awslogs-group":"$LOG_GROUP","awslogs-region":"$REGION","awslogs-stream-prefix":"$1"}}
EOF
}

# ─── auth-service ─────────────────────────────────────────────────────────────
register auth-service <<EOF
{
  "family": "auth-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "auth-service",
    "image": "$REGISTRY/auth-service",
    "portMappings": [{"containerPort": 3000}],
    "environment": [
      {"name": "DATABASE_URL", "value": "$DB_URL"},
      {"name": "BETTER_AUTH_SECRET", "value": "$BETTER_AUTH_SECRET"},
      {"name": "BETTER_AUTH_URL", "value": "$BETTER_AUTH_URL"},
      {"name": "CORS_ORIGIN", "value": "$FRONTEND_BASE_URL"},
      {"name": "NODE_TLS_REJECT_UNAUTHORIZED", "value": "0"}
    ],
    "logConfiguration": $(log auth-service)
  }]
}
EOF

# ─── appointment-service ──────────────────────────────────────────────────────
register appointment-service <<EOF
{
  "family": "appointment-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "appointment-service",
    "image": "$REGISTRY/appointment-service",
    "portMappings": [{"containerPort": 3001}],
    "environment": [
      {"name": "DATABASE_URL", "value": "$DB_URL"},
      {"name": "PORT", "value": "3001"},
      {"name": "JWKS_URL", "value": "$COGNITO_JWKS_URL"}
    ],
    "logConfiguration": $(log appointment-service)
  }]
}
EOF

# ─── queue-coordinator-service ────────────────────────────────────────────────
register queue-coordinator-service <<EOF
{
  "family": "queue-coordinator-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "queue-coordinator-service",
    "image": "$REGISTRY/queue-coordinator-service",
    "portMappings": [{"containerPort": 3002}, {"containerPort": 50052}],
    "environment": [
      {"name": "DATABASE_URL", "value": "$DB_URL"},
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "REDIS_URL", "value": "$REDIS_URL"},
      {"name": "PORT", "value": "3002"},
      {"name": "NODE_TLS_REJECT_UNAUTHORIZED", "value": "0"}
    ],
    "logConfiguration": $(log queue-coordinator-service)
  }]
}
EOF

# ─── patient-service ──────────────────────────────────────────────────────────
register patient-service <<EOF
{
  "family": "patient-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "patient-service",
    "image": "$REGISTRY/patient-service",
    "portMappings": [{"containerPort": 3007}, {"containerPort": 50053}],
    "environment": [
      {"name": "DATABASE_URL", "value": "$DB_URL"},
      {"name": "PORT", "value": "3007"},
      {"name": "GRPC_PORT", "value": "50053"},
      {"name": "AWS_REGION", "value": "$REGION"},
      {"name": "AWS_ACCESS_KEY_ID", "value": "$AWS_ACCESS_KEY_ID"},
      {"name": "AWS_SECRET_ACCESS_KEY", "value": "$AWS_SECRET_ACCESS_KEY"},
      {"name": "S3_BUCKET", "value": "$S3_BUCKET"},
      {"name": "NODE_TLS_REJECT_UNAUTHORIZED", "value": "0"},
      {"name": "JWKS_URL", "value": "$COGNITO_JWKS_URL"}
    ],
    "logConfiguration": $(log patient-service)
  }]
}
EOF

# ─── doctor-service ───────────────────────────────────────────────────────────
register doctor-service <<EOF
{
  "family": "doctor-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "doctor-service",
    "image": "$REGISTRY/doctor-service",
    "portMappings": [{"containerPort": 3006}, {"containerPort": 50055}],
    "environment": [
      {"name": "DATABASE_URL", "value": "$DB_URL"},
      {"name": "PORT", "value": "3006"},
      {"name": "GRPC_PORT", "value": "50055"},
      {"name": "NODE_TLS_REJECT_UNAUTHORIZED", "value": "0"},
      {"name": "JWKS_URL", "value": "$COGNITO_JWKS_URL"}
    ],
    "logConfiguration": $(log doctor-service)
  }]
}
EOF

# ─── activity-log-service ─────────────────────────────────────────────────────
register activity-log-service <<EOF
{
  "family": "activity-log-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "activity-log-service",
    "image": "$REGISTRY/activity-log-service",
    "portMappings": [{"containerPort": 3005}],
    "environment": [
      {"name": "DATABASE_URL", "value": "$DB_URL"},
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "PORT", "value": "3005"},
      {"name": "NODE_TLS_REJECT_UNAUTHORIZED", "value": "0"}
    ],
    "logConfiguration": $(log activity-log-service)
  }]
}
EOF

# ─── payment-service ──────────────────────────────────────────────────────────
register payment-service <<EOF
{
  "family": "payment-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "payment-service",
    "image": "$REGISTRY/payment-service",
    "portMappings": [{"containerPort": 3008}],
    "environment": [
      {"name": "DATABASE_URL", "value": "$DB_URL"},
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "JWKS_URL", "value": "$COGNITO_JWKS_URL"},
      {"name": "STRIPE_SERVICE_URL", "value": "http://stripe-service.$NS:8001"},
      {"name": "APPOINTMENT_SERVICE_URL", "value": "http://appointment-service.$NS:3001"},
      {"name": "PORT", "value": "3008"}
    ],
    "logConfiguration": $(log payment-service)
  }]
}
EOF

# ─── eta-service ──────────────────────────────────────────────────────────────
register eta-service <<EOF
{
  "family": "eta-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "eta-service",
    "image": "$REGISTRY/eta-service",
    "portMappings": [{"containerPort": 50054}],
    "environment": [
      {"name": "GOOGLE_MAPS_API_KEY", "value": "$GOOGLE_MAPS_API_KEY"},
      {"name": "CLINIC_LAT", "value": "1.4172"},
      {"name": "CLINIC_LNG", "value": "103.8330"},
      {"name": "GRPC_PORT", "value": "50054"}
    ],
    "logConfiguration": $(log eta-service)
  }]
}
EOF

# ─── notification-service ─────────────────────────────────────────────────────
register notification-service <<EOF
{
  "family": "notification-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "notification-service",
    "image": "$REGISTRY/notification-service",
    "portMappings": [{"containerPort": 3004}],
    "environment": [
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "TWILIO_ACCOUNT_SID", "value": "$TWILIO_ACCOUNT_SID"},
      {"name": "TWILIO_AUTH_TOKEN", "value": "$TWILIO_AUTH_TOKEN"},
      {"name": "TWILIO_PHONE_NUMBER", "value": "${TWILIO_PHONE_NUMBER:-+18056000492}"},
      {"name": "JWKS_URL", "value": "$COGNITO_JWKS_URL"},
      {"name": "PATIENT_SERVICE_GRPC_URL", "value": "patient-service.$NS:50053"},
      {"name": "PORT", "value": "3004"}
    ],
    "logConfiguration": $(log notification-service)
  }]
}
EOF

# ─── stripe-service ───────────────────────────────────────────────────────────
register stripe-service <<EOF
{
  "family": "stripe-service",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "stripe-service",
    "image": "$REGISTRY/stripe-service",
    "portMappings": [{"containerPort": 8001}, {"containerPort": 50051}],
    "environment": [
      {"name": "STRIPE_API_KEY", "value": "$STRIPE_API_KEY"},
      {"name": "STRIPE_WEBHOOK_SIGNING_SECRET", "value": "$STRIPE_WEBHOOK_SIGNING_SECRET"},
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "AUTH_SERVICE_URL", "value": "http://auth-service.$NS:3000"},
      {"name": "FRONTEND_BASE_URL", "value": "$FRONTEND_BASE_URL"},
      {"name": "STRIPE_SUCCESS_URL", "value": "$STRIPE_SUCCESS_URL_VALUE"},
      {"name": "STRIPE_CANCEL_URL", "value": "$STRIPE_CANCEL_URL_VALUE"},
      {"name": "CONSULTATION_FEE_CENTS", "value": "5000"},
      {"name": "CURRENCY", "value": "sgd"}
    ],
    "logConfiguration": $(log stripe-service)
  }]
}
EOF

# ─── composite-appointment ────────────────────────────────────────────────────
register composite-appointment <<EOF
{
  "family": "composite-appointment",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "composite-appointment",
    "image": "$REGISTRY/composite-appointment",
    "portMappings": [{"containerPort": 8000}],
    "environment": [
      {"name": "JWKS_URL", "value": "$COGNITO_JWKS_URL"},
      {"name": "APPOINTMENT_SERVICE_URL", "value": "http://appointment-service.$NS:3001"},
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "PORT", "value": "8000"}
    ],
    "logConfiguration": $(log composite-appointment)
  }]
}
EOF

# ─── composite-patient-orchestrator ──────────────────────────────────────────
register composite-patient-orchestrator <<EOF
{
  "family": "composite-patient-orchestrator",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "composite-patient-orchestrator",
    "image": "$REGISTRY/composite-patient-orchestrator",
    "portMappings": [{"containerPort": 8001}],
    "environment": [
      {"name": "JWKS_URL", "value": "$COGNITO_JWKS_URL"},
      {"name": "PATIENT_SERVICE_GRPC", "value": "patient-service.$NS:50053"},
      {"name": "PAYMENT_SERVICE_URL", "value": "http://payment-service.$NS:3008"},
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "PORT", "value": "8001"}
    ],
    "logConfiguration": $(log composite-patient-orchestrator)
  }]
}
EOF

# ─── composite-consultation ───────────────────────────────────────────────────
register composite-consultation <<EOF
{
  "family": "composite-consultation",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "composite-consultation",
    "image": "$REGISTRY/composite-consultation",
    "portMappings": [{"containerPort": 8002}],
    "environment": [
      {"name": "JWKS_URL", "value": "$COGNITO_JWKS_URL"},
      {"name": "APPOINTMENT_SERVICE_URL", "value": "http://appointment-service.$NS:3001"},
      {"name": "PAYMENT_SERVICE_URL", "value": "http://payment-service.$NS:3008"},
      {"name": "PATIENT_SERVICE_GRPC", "value": "patient-service.$NS:50053"},
      {"name": "DOCTOR_SERVICE_GRPC", "value": "doctor-service.$NS:50055"},
      {"name": "QUEUE_SERVICE_GRPC", "value": "queue-coordinator-service.$NS:50052"},
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "PORT", "value": "8002"}
    ],
    "logConfiguration": $(log composite-consultation)
  }]
}
EOF

# ─── composite-staff-orchestrator ─────────────────────────────────────────────
register composite-staff-orchestrator <<EOF
{
  "family": "composite-staff-orchestrator",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "composite-staff-orchestrator",
    "image": "$REGISTRY/composite-staff-orchestrator",
    "portMappings": [{"containerPort": 8004}],
    "environment": [
      {"name": "JWKS_URL", "value": "$COGNITO_JWKS_URL"},
      {"name": "APPOINTMENT_SERVICE_URL", "value": "http://appointment-service.$NS:3001"},
      {"name": "PAYMENT_SERVICE_URL", "value": "http://payment-service.$NS:3008"},
      {"name": "PATIENT_SERVICE_URL", "value": "http://patient-service.$NS:3007"},
      {"name": "DOCTOR_SERVICE_GRPC", "value": "doctor-service.$NS:50055"},
      {"name": "PATIENT_SERVICE_GRPC", "value": "patient-service.$NS:50053"},
      {"name": "QUEUE_SERVICE_GRPC", "value": "queue-coordinator-service.$NS:50052"},
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "PORT", "value": "8004"}
    ],
    "logConfiguration": $(log composite-staff-orchestrator)
  }]
}
EOF

# ─── checkin-orchestrator ─────────────────────────────────────────────────────
register checkin-orchestrator <<EOF
{
  "family": "checkin-orchestrator",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "checkin-orchestrator",
    "image": "$REGISTRY/checkin-orchestrator",
    "portMappings": [{"containerPort": 8000}],
    "environment": [
      {"name": "JWKS_URL", "value": "$COGNITO_JWKS_URL"},
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "ETA_SERVICE_HOST", "value": "eta-service.$NS"},
      {"name": "ETA_SERVICE_PORT", "value": "50054"},
      {"name": "LATE_TTL_MS", "value": "300000"}
    ],
    "logConfiguration": $(log checkin-orchestrator)
  }]
}
EOF

rm -rf "$TMP"
echo ""
echo "All backend task definitions registered."
echo "Next: ensure Cloud Map namespace '$NS' and ALB target groups exist, then create ECS services."
