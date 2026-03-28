#!/bin/sh
# Create ECS Fargate services for all task definitions.
# Run from repo root: sh infra/scripts/create-ecs-services.sh

set -e

REGION=ap-southeast-1
CLUSTER=smart-clinic-queue
SUBNETS="subnet-06d141f46d4e8dc9b,subnet-031cb3f73eb316701,subnet-06a24f8b499abd877"
SG=sg-0153ba415474d0cea

# Service discovery IDs
SD_AUTH=srv-xqltioa3tkrtx25z
SD_APPOINTMENT=srv-yzlvlbnfgp2lfiip
SD_QUEUE=srv-z2fgpnoeka2cza7u
SD_PATIENT=srv-zprvsptjcivqcq6e
SD_DOCTOR=srv-nu5p7hyit5qjiaws
SD_ACTIVITY=srv-4xz2kbsa6kwl4cuu
SD_PAYMENT=srv-4mv676dgbpavd5ox
SD_ETA=srv-wayfcpj75exzbksi
SD_NOTIFICATION=srv-jqq64ivtxrpz2oju
SD_STRIPE=srv-e2ywwayyurfcu2vn
SD_COMPOSITE_APPT=srv-dl2457yiahsppnno
SD_COMPOSITE_PATIENT=srv-ugbghbkxpmnvsjtd
SD_COMPOSITE_CONSULTATION=srv-dguynfd57la7n3bi
SD_COMPOSITE_STAFF=srv-yvfp2zzbmvo3jk7k
SD_CHECKIN=srv-fwyi2kaqdieb2phq
SD_FRONTEND=srv-3coswgulkod32bb5

NAMESPACE_ID=ns-cetcm7jpnixwoatx

create_service() {
    NAME=$1
    SD_ID=$2
    echo "Creating ECS service: $NAME..."
    aws ecs create-service \
        --cluster "$CLUSTER" \
        --service-name "$NAME" \
        --task-definition "$NAME" \
        --desired-count 1 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=ENABLED}" \
        --service-registries "registryArn=arn:aws:servicediscovery:$REGION:617341601600:service/$SD_ID" \
        --region "$REGION" \
        --query "service.serviceArn" \
        --output text
}

create_service auth-service                   $SD_AUTH
create_service appointment-service            $SD_APPOINTMENT
create_service queue-coordinator-service      $SD_QUEUE
create_service patient-service                $SD_PATIENT
create_service doctor-service                 $SD_DOCTOR
create_service activity-log-service           $SD_ACTIVITY
create_service payment-service                $SD_PAYMENT
create_service eta-service                    $SD_ETA
create_service notification-service           $SD_NOTIFICATION
create_service stripe-service                 $SD_STRIPE
create_service composite-appointment          $SD_COMPOSITE_APPT
create_service composite-patient-orchestrator $SD_COMPOSITE_PATIENT
create_service composite-consultation         $SD_COMPOSITE_CONSULTATION
create_service composite-staff-orchestrator   $SD_COMPOSITE_STAFF
create_service checkin-orchestrator           $SD_CHECKIN
create_service frontend                       $SD_FRONTEND

echo ""
echo "All ECS services created."
echo "Monitor status: aws ecs list-services --cluster $CLUSTER --region $REGION"
