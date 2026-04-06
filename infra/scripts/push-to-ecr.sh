#!/bin/sh
# Build and push all backend service images to ECR.
# Run from repo root: sh infra/scripts/push-to-ecr.sh

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

for var in AWS_ACCOUNT_ID AWS_REGION; do
    eval val=\$$var
    if [ -z "$val" ]; then
        echo "ERROR: $var is not set in .env.aws"
        exit 1
    fi
done

ACCOUNT=$AWS_ACCOUNT_ID
REGION=$AWS_REGION
REGISTRY=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com

echo "Authenticating with ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY

build_and_push() {
    NAME=$1
    DOCKERFILE=$2
    echo ""
    echo ">>> Building $NAME..."
    docker build --platform linux/amd64 -t $REGISTRY/$NAME -f "$DOCKERFILE" .
    echo ">>> Pushing $NAME..."
    docker push $REGISTRY/$NAME
}

build_and_push auth-service                  services/auth-service/Dockerfile
build_and_push appointment-service           services/appointment-service/Dockerfile
build_and_push queue-coordinator-service     services/queue-coordinator-service/Dockerfile
build_and_push patient-service               services/patient-service/Dockerfile
build_and_push doctor-service                services/doctor-service/Dockerfile
build_and_push activity-log-service          services/activity-log-service/Dockerfile
build_and_push payment-service               services/payment-service/Dockerfile
build_and_push eta-service                   wrappers/eta-service/Dockerfile
build_and_push notification-service          wrappers/notification-service/Dockerfile
echo ""
echo ">>> Building stripe-service..."
docker build --platform linux/amd64 -t $REGISTRY/stripe-service wrappers/stripe-service
docker push $REGISTRY/stripe-service
build_and_push composite-appointment         composite/appointment/Dockerfile
build_and_push composite-patient-orchestrator composite/patient-orchestrator/Dockerfile
build_and_push composite-consultation        composite/consultation/Dockerfile
build_and_push composite-staff-orchestrator  composite/staff-orchestrator/Dockerfile
echo ""
echo ">>> Building checkin-orchestrator..."
docker build --platform linux/amd64 -t $REGISTRY/checkin-orchestrator "composite/check-in orchestrator"
docker push $REGISTRY/checkin-orchestrator

echo ""
echo "All backend images pushed to ECR successfully."
echo "Frontend is deployed separately via S3/CloudFront, not ECR/ECS."
