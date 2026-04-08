#!/bin/sh
# deploy-service.sh — build, push, and redeploy a single ECS service.
# Always updates the service to the latest task definition revision.
#
# Usage: sh infra/scripts/deploy-service.sh <service-name>
# Example: sh infra/scripts/deploy-service.sh composite-consultation
#
# Requires: aws CLI, docker, credentials set in environment.

set -e

SERVICE="$1"
if [ -z "$SERVICE" ]; then
  echo "Usage: $0 <service-name>"
  exit 1
fi

ECR="929702668297.dkr.ecr.ap-southeast-2.amazonaws.com"
CLUSTER="smart-clinic-queue"
REGION="ap-southeast-2"

pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; }
info() { printf "  \033[34m→\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; exit 1; }

# Map service name → Dockerfile path
dockerfile_for() {
  case "$1" in
    auth-service)                   echo "services/auth-service/Dockerfile" ;;
    appointment-service)            echo "services/appointment-service/Dockerfile" ;;
    queue-coordinator-service)      echo "services/queue-coordinator-service/Dockerfile" ;;
    patient-service)                echo "services/patient-service/Dockerfile" ;;
    doctor-service)                 echo "services/doctor-service/Dockerfile" ;;
    activity-log-service)           echo "services/activity-log-service/Dockerfile" ;;
    payment-service)                echo "services/payment-service/Dockerfile" ;;
    eta-service)                    echo "wrappers/eta-service/Dockerfile" ;;
    notification-service)           echo "wrappers/notification-service/Dockerfile" ;;
    stripe-service)                 echo "wrappers/stripe-service/Dockerfile" ;;
    composite-appointment)          echo "composite/appointment/Dockerfile" ;;
    composite-consultation)         echo "composite/consultation/Dockerfile" ;;
    composite-patient-orchestrator) echo "composite/patient-orchestrator/Dockerfile" ;;
    composite-staff-orchestrator)   echo "composite/staff-orchestrator/Dockerfile" ;;
    checkin-orchestrator)           echo "composite/check-in orchestrator/Dockerfile" ;;
    *) fail "Unknown service: $1" ;;
  esac
}

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DOCKERFILE=$(dockerfile_for "$SERVICE")
IMAGE="${ECR}/${SERVICE}:latest"

printf "\n\033[1m━━━ Deploying %s ━━━\033[0m\n" "$SERVICE"

# 1. Login to ECR
info "Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR" > /dev/null 2>&1
pass "ECR login"

# 2. Build
info "Building image (linux/amd64)..."
docker build --platform linux/amd64 -t "$IMAGE" -f "$DOCKERFILE" . > /dev/null 2>&1
pass "Image built"

# 3. Push
info "Pushing to ECR..."
docker push "$IMAGE" > /dev/null 2>&1
pass "Image pushed"

# 4. Get latest task definition revision
LATEST_REV=$(aws ecs describe-task-definition \
  --task-definition "$SERVICE" \
  --region "$REGION" \
  --query 'taskDefinition.revision' \
  --output text 2>/dev/null)
[ -z "$LATEST_REV" ] && fail "Could not find task definition for $SERVICE"
pass "Latest task definition: ${SERVICE}:${LATEST_REV}"

# 5. Update service to latest revision + force new deployment
info "Updating ECS service..."
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "${SERVICE}:${LATEST_REV}" \
  --force-new-deployment \
  --region "$REGION" \
  --query 'service.deployments[0].rolloutState' \
  --output text > /dev/null 2>&1
pass "Service update triggered (${SERVICE}:${LATEST_REV})"

printf "\n\033[32mDone.\033[0m Deployment in progress — check status with:\n"
printf "  aws ecs describe-services --cluster %s --services %s --region %s \\\n" "$CLUSTER" "$SERVICE" "$REGION"
printf "    --query 'services[0].[runningCount,desiredCount,deployments[0].rolloutState]'\n\n"
