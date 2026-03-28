#!/bin/sh
# Build and push all service images to ECR.
# Run from repo root: sh infra/scripts/push-to-ecr.sh

set -e

ACCOUNT=617341601600
REGION=ap-southeast-1
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
build_and_push frontend                      frontend/vue-app/Dockerfile.dev

echo ""
echo "All images pushed to ECR successfully."
