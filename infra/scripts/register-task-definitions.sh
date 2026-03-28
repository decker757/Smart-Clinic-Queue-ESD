#!/bin/sh
# Register ECS task definitions for all services.
# Run from repo root: sh infra/scripts/register-task-definitions.sh

set -e

ACCOUNT=617341601600
REGION=ap-southeast-1
REGISTRY=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com
EXEC_ROLE=arn:aws:iam::${ACCOUNT}:role/ecsTaskExecutionRole
LOG_GROUP=/ecs/smart-clinic
NS=smart-clinic.local

DB_URL="postgresql://postgres:ILoveRaphaelKwek@database-1.cxmuigc66kv3.ap-southeast-1.rds.amazonaws.com:5432/postgres?sslmode=require"
MQ_URL="amqps://ILoveRaphaelKwek:ILoveRaphaelKwek@b-54162137-647b-4099-9afa-433eac8e27f6.mq.ap-southeast-1.on.aws:5671"
REDIS_URL="rediss://smart-clinic-redis-fbrr4j.serverless.apse1.cache.amazonaws.com:6379"

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
      {"name": "BETTER_AUTH_SECRET", "value": "4cbW0So2oqMJMEISOp0sabki7eFcAfDk"},
      {"name": "BETTER_AUTH_URL", "value": "http://auth-service.$NS:3000"},
      {"name": "CORS_ORIGIN", "value": "*"},
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
      {"name": "JWKS_URL", "value": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json"}
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
      {"name": "AWS_REGION", "value": "ap-southeast-1"},
      {"name": "AWS_ACCESS_KEY_ID", "value": "AKIAY7PDNI5AF6LKL7G5"},
      {"name": "AWS_SECRET_ACCESS_KEY", "value": "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"},
      {"name": "S3_BUCKET", "value": "esd-smart-clinic-queue-prod-ap-southeast-1"},
      {"name": "NODE_TLS_REJECT_UNAUTHORIZED", "value": "0"},
      {"name": "JWKS_URL", "value": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json"}
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
      {"name": "JWKS_URL", "value": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json"}
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
      {"name": "GOOGLE_MAPS_API_KEY", "value": "AIzaSyAo59AdfI4gKLNya0i19k4i_O9qQ3wfOQg"},
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
      {"name": "TWILIO_ACCOUNT_SID", "value": "AC89ea4bd58c578bfba71ea526c84bddbf"},
      {"name": "TWILIO_AUTH_TOKEN", "value": "d37cd5c36a4192fd6e0a8a5bff3815f6"},
      {"name": "TWILIO_PHONE_NUMBER", "value": "+18056000492"},
      {"name": "JWKS_URL", "value": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json"},
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
      {"name": "STRIPE_API_KEY", "value": "sk_test_51TDe9SB5GxrqfIetUJPN5mtBAz5lcDGJ0vLgPzRtyHhBOtxrr4oasIWImu667pvPkAKw5GwPGOxGy8EY3qjLQb7L004IM2PqUu"},
      {"name": "STRIPE_WEBHOOK_SIGNING_SECRET", "value": "whsec_ppfgdog90JAFwMUWxOIsdD4p1HId4IvE"},
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "FRONTEND_BASE_URL", "value": "http://smart-clinic-alb-2054248031.ap-southeast-1.elb.amazonaws.com"},
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
      {"name": "JWKS_URL", "value": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json"},
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
      {"name": "JWKS_URL", "value": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json"},
      {"name": "PATIENT_SERVICE_GRPC", "value": "patient-service.$NS:50053"},
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
      {"name": "JWKS_URL", "value": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json"},
      {"name": "APPOINTMENT_SERVICE_URL", "value": "http://appointment-service.$NS:3001"},
      {"name": "PATIENT_SERVICE_GRPC", "value": "patient-service.$NS:50053"},
      {"name": "DOCTOR_SERVICE_GRPC", "value": "doctor-service.$NS:50055"},
      {"name": "QUEUE_SERVICE_GRPC", "value": "queue-coordinator-service.$NS:50052"},
      {"name": "PAYMENT_SERVICE_GRPC", "value": "stripe-service.$NS:50051"},
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
      {"name": "JWKS_URL", "value": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json"},
      {"name": "APPOINTMENT_SERVICE_URL", "value": "http://appointment-service.$NS:3001"},
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
      {"name": "JWKS_URL", "value": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json"},
      {"name": "RABBITMQ_URL", "value": "$MQ_URL"},
      {"name": "ETA_SERVICE_HOST", "value": "eta-service.$NS"},
      {"name": "ETA_SERVICE_PORT", "value": "50054"},
      {"name": "LATE_TTL_MS", "value": "300000"}
    ],
    "logConfiguration": $(log checkin-orchestrator)
  }]
}
EOF

# ─── frontend ─────────────────────────────────────────────────────────────────
register frontend <<EOF
{
  "family": "frontend",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC_ROLE",
  "containerDefinitions": [{
    "name": "frontend",
    "image": "$REGISTRY/frontend",
    "portMappings": [{"containerPort": 5173}],
    "environment": [
      {"name": "VITE_API_BASE_URL", "value": "http://TO_BE_FILLED_API_GATEWAY_URL"}
    ],
    "logConfiguration": $(log frontend)
  }]
}
EOF

rm -rf "$TMP"
echo ""
echo "All task definitions registered."
echo "Next: set up Cloud Map namespace '$NS' and create ECS services."
