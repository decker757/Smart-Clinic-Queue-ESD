#!/bin/sh
# Enable CPU-based auto-scaling on ECS Fargate services.
# Run from repo root: sh infra/scripts/enable-auto-scaling.sh
#
# Each listed service gets:
#   - A scalable target (min 1, max 4 tasks)
#   - A target-tracking policy that keeps average CPU at ~70%
#
# ECS + ALB handles the rest: new tasks register with the target group
# automatically, and the ALB distributes traffic across all healthy tasks.
#
# Prerequisites:
#   - ECS services must already be created (run create-ecs-services.sh first)
#   - .env.aws must be populated

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

for var in AWS_REGION ECS_CLUSTER_NAME; do
    eval val=\$$var
    if [ -z "$val" ]; then
        echo "ERROR: $var is not set in .env.aws"
        exit 1
    fi
done

REGION=$AWS_REGION
CLUSTER=$ECS_CLUSTER_NAME
MIN_TASKS=${AUTOSCALING_MIN_TASKS:-1}
MAX_TASKS=${AUTOSCALING_MAX_TASKS:-4}
CPU_TARGET=${AUTOSCALING_CPU_TARGET:-70}

# Services to auto-scale — stateless composites that sit behind the ALB.
# Atomic services (DB-bound) and singletons (stripe webhook) are excluded.
SCALABLE_SERVICES="
  composite-appointment
  composite-patient-orchestrator
  composite-consultation
  composite-staff-orchestrator
  checkin-orchestrator
"

register_scaling() {
    SVC=$1
    RESOURCE_ID="service/$CLUSTER/$SVC"

    echo "  Registering scalable target: $SVC (min=$MIN_TASKS, max=$MAX_TASKS)..."
    aws application-autoscaling register-scalable-target \
        --service-namespace ecs \
        --resource-id "$RESOURCE_ID" \
        --scalable-dimension ecs:service:DesiredCount \
        --min-capacity "$MIN_TASKS" \
        --max-capacity "$MAX_TASKS" \
        --region "$REGION"

    echo "  Attaching CPU target-tracking policy: $SVC (target=${CPU_TARGET}%)..."
    aws application-autoscaling put-scaling-policy \
        --service-namespace ecs \
        --resource-id "$RESOURCE_ID" \
        --scalable-dimension ecs:service:DesiredCount \
        --policy-name "${SVC}-cpu-scaling" \
        --policy-type TargetTrackingScaling \
        --target-tracking-scaling-policy-configuration \
            "TargetValue=${CPU_TARGET},PredefinedMetricSpecification={PredefinedMetricType=ECSServiceAverageCPUUtilization},ScaleInCooldown=300,ScaleOutCooldown=60" \
        --region "$REGION"
}

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Enabling Auto-Scaling on ECS Fargate Services          ║"
echo "║  Cluster: $CLUSTER"
echo "║  Min: $MIN_TASKS  Max: $MAX_TASKS  CPU Target: ${CPU_TARGET}%"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

for svc in $SCALABLE_SERVICES; do
    register_scaling "$svc"
    echo ""
done

echo "Auto-scaling enabled for all composite services."
echo ""
echo "Useful commands:"
echo "  # View scaling activities"
echo "  aws application-autoscaling describe-scaling-activities --service-namespace ecs --region $REGION"
echo ""
echo "  # View current scaling policies"
echo "  aws application-autoscaling describe-scaling-policies --service-namespace ecs --region $REGION"
echo ""
echo "  # Override: manually scale a service"
echo "  aws ecs update-service --cluster $CLUSTER --service <name> --desired-count 3 --region $REGION"
