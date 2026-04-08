# Smart-Clinic-Queue-ESD

Smart Clinic Queue is a polyclinic queue management platform built on an event-driven microservices architecture. The system supports appointment booking, queue check-in and reprioritization, consultation completion, payment link generation, and real-time queue visibility for patients, staff, and doctors.

This repository contains the complete project implementation for both local Docker deployment and the production-oriented AWS environment used for the final demonstration.

## Contents

- [Project Overview](#project-overview)
- [Technology Stack](#technology-stack)
- [Public Endpoints](#public-endpoints)
- [Architecture Overview](#architecture-overview)
- [System Components](#system-components)
- [Authentication](#authentication)
- [Core Business Scenarios](#core-business-scenarios)
- [Requirements Coverage](#requirements-coverage)
- [Data Model](#data-model)
- [AWS Infrastructure Setup](#aws-infrastructure-setup)
- [Deployed Resource Reference](#deployed-resource-reference)
- [Service Operations](#service-operations)
- [Local Development](#local-development-docker-compose)
- [CI/CD](#cicd)
- [Architecture Principles](#architecture-principles)
- [Contributing](#contributing)

## Project Overview

Smart Clinic Queue addresses a common clinic operations challenge: coordinating appointments, patient arrivals, consultation progress, and billing across multiple roles without relying on a monolithic system.

The solution is organized around:

- atomic microservices for core business entities such as appointments, patients, doctors, queue entries, and payments
- composite services that orchestrate cross-service workflows for patient, staff, doctor, and check-in journeys
- asynchronous event propagation through RabbitMQ for queue updates, notifications, and audit trails
- external service integrations for ETA calculation, payments, SMS notifications, and production authentication
- a Vue-based web frontend for patients, staff, and doctors

## Technology Stack

| Layer | Technology |
|-------|-----------|
| CDN / HTTPS | AWS CloudFront |
| API Gateway | AWS API Gateway (HTTP API, Cognito JWT authorizer) |
| Load Balancer | AWS Application Load Balancer |
| Message Broker | Amazon MQ (RabbitMQ) |
| Database | AWS RDS (PostgreSQL) |
| Cache | AWS ElastiCache Redis (queue position cache) |
| Auth | AWS Cognito (RS256 JWT) |
| Notifications | Twilio (SMS via notification-service) |
| Payments | Stripe |
| Frontend | Vue 3 + Vite + Tailwind CSS |
| Infrastructure | AWS ECS Fargate (15 backend services) |

## Public Endpoints

| Endpoint | URL |
|----------|-----|
| Frontend | `https://d1ny1tpqtbblzr.cloudfront.net` |
| API Gateway | `https://raw9qjg8o0.execute-api.ap-southeast-2.amazonaws.com` |
| API Docs | Open `docs/index.html` locally via `npx serve docs/` |

## Architecture Overview

The production deployment uses CloudFront, API Gateway, an Application Load Balancer, ECS Fargate services, Amazon MQ, RDS PostgreSQL, and ElastiCache Redis. Internally, services communicate through a mix of synchronous HTTP/gRPC calls and asynchronous RabbitMQ events.

![Technical Overview](diagrams/TechnicalOverview.jpg)

> WebSocket connections use `wss://` to CloudFront. CloudFront forwards them as `ws://` to the ALB — this handles the mixed-content restriction when the frontend is served over HTTPS.

### API Gateway Routing

Method-specific routes are used (not `ANY`) so OPTIONS preflight requests bypass the JWT authorizer and are handled by API Gateway's built-in CORS support.

| Route | Auth | Forwards to |
|-------|------|-------------|
| `GET/POST /api/auth/{proxy+}` | None | auth-service |
| `POST /api/composite/appointments` | Cognito JWT | composite-appointment |
| `GET/DELETE /api/composite/appointments/{proxy+}` | Cognito JWT | composite-appointment |
| `POST /api/check-in` | Cognito JWT | checkin-orchestrator |
| `POST /api/check-in/{proxy+}` | Cognito JWT | checkin-orchestrator |
| `GET/POST /api/queue/{proxy+}` | Cognito JWT | queue-coordinator |
| `GET/POST /api/composite/consultations/{proxy+}` | Cognito JWT | composite-consultation |
| `GET/POST /api/composite/staff/{proxy+}` | Cognito JWT | composite-staff-orchestrator |
| `GET/POST/PUT /api/composite/patients/{proxy+}` | Cognito JWT | composite-patient-orchestrator |
| `GET/POST /api/payments/{proxy+}` | Cognito JWT | payment-service |
| `POST /api/payments/webhook` | None (Stripe signature) | stripe-service |

### ALB Path Routing

The ALB receives traffic from both API Gateway and CloudFront (WebSocket path only).

| Path Pattern | Service | Port |
|-------------|---------|------|
| `/api/auth*` | auth-service | 3000 |
| `/api/queue/ws*` | queue-coordinator-service | 3002 |
| `/api/queue/*` | queue-coordinator-service | 3002 |
| `/api/composite/appointments*` | composite-appointment | 8000 |
| `/api/check-in*` | checkin-orchestrator | 8000 |
| `/api/composite/consultations*` | composite-consultation | 8002 |
| `/api/composite/staff*` | composite-staff-orchestrator | 8004 |
| `/api/composite/patients*` | composite-patient-orchestrator | 8001 |
| `/api/payments/webhook` | stripe-service | 8001 |
| `/api/payments*` | payment-service | 3008 |
| `/api/appointments*` | appointment-service | 3001 |

### Internal Service Communication

Services communicate internally via Cloud Map DNS (`<service>.smart-clinic.local`).

```
RabbitMQ clinic.events (topic exchange)
  ├── appointment.booked        → queue-coordinator-service
  ├── appointment.cancelled     → queue-coordinator-service
  ├── queue.checked_in          → queue-coordinator-service
  ├── queue.late_detected       → notification-service
  ├── queue.deprioritized       → notification-service, queue-coordinator-service
  ├── queue.removed             → notification-service, queue-coordinator-service
  ├── consultation.completed    → notification-service, queue-coordinator-service, activity-log-service
  ├── payment.pending           → payment-service
  ├── payment.completed         → payment-service
  └── payment.failed            → payment-service
```

## System Components

### Atomic Services

| Service | Port | gRPC Port | Language | Description |
|---------|------|-----------|----------|-------------|
| `auth-service` | 3000 | — | Node.js + BetterAuth | Legacy auth (superseded by Cognito in production) |
| `appointment-service` | 3001 | — | Go + Gin | Appointment lifecycle |
| `queue-coordinator-service` | 3002 | 50052 | Node.js + Express | Queue management + WebSocket |
| `patient-service` | 3007 | 50053 | Node.js + Express | Patient profiles, memos, MC/prescriptions |
| `doctor-service` | 3006 | 50055 | Node.js + Express | Doctor profiles, slots, consultation notes |
| `activity-log-service` | 3005 | — | Node.js + Express | Audit log → OutSystems |
| `payment-service` | 3008 | — | Python + FastAPI | Payment history |

### Wrapper Services

| Service | Port | gRPC Port | Language | Description |
|---------|------|-----------|----------|-------------|
| `eta-service` | — | 50054 | Node.js + TypeScript | Google Maps travel time (gRPC only) |
| `notification-service` | 3004 | — | Node.js + TypeScript | SMS via Twilio |
| `stripe-service` | 8086 | 50060 | Python + FastAPI | Stripe checkout sessions + webhook |

### Composite Services

| Service | Port | Language | Description |
|---------|------|----------|-------------|
| `composite-appointment` | 8000 | Python + FastAPI | Patient books/cancels appointments |
| `composite-patient-orchestrator` | 8001 | Python + FastAPI | Patient profile, history, memos |
| `composite-consultation` | 8002 | Python + FastAPI | Doctor completes consultation, triggers payment |
| `composite-staff-orchestrator` | 8004 | Python + FastAPI | Staff views queue, calls next patient |
| `checkin-orchestrator` | 8085 | Python + FastAPI | Patient check-in, late detection via ETA |

### Frontend

| Service | Port | Language |
|---------|------|----------|
| `frontend` | 5173 | Vue 3 + Vite + Tailwind CSS v4 |

## Authentication

Production authentication is handled by AWS Cognito with RS256 JWTs. Local Docker development uses BetterAuth to provide a self-contained setup without requiring AWS resources.

### Production Auth (Cognito)

All services validate RS256 JWTs issued by AWS Cognito.

- **User Pool:** `ap-southeast-2_gxGEa7l58`
- **App Client:** `1pm7h3lr03k62ncrvkmtf2s5vl` (no secret — browser-safe)
- **JWKS URL:** `https://cognito-idp.ap-southeast-2.amazonaws.com/ap-southeast-2_gxGEa7l58/.well-known/jwks.json`
- **Role claim:** `custom:role` in the ID token (`patient` | `staff` | `doctor` | `admin`)
- **Pre-SignUp trigger:** `cognito-auto-confirm` Lambda — users are auto-confirmed (no email verification required)

### Cognito Sign-In Example

```bash
curl -X POST https://cognito-idp.ap-southeast-2.amazonaws.com/ \
  -H "Content-Type: application/x-amz-json-1.1" \
  -H "X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth" \
  -d '{
    "AuthFlow": "USER_PASSWORD_AUTH",
    "ClientId": "1pm7h3lr03k62ncrvkmtf2s5vl",
    "AuthParameters": { "USERNAME": "<email>", "PASSWORD": "<password>" }
  }'
# Use AuthenticationResult.IdToken as the Bearer token
```

### Production Demo Accounts

| Role | Username | Password |
|------|----------|----------|
| Patient | `test-patient` | `Test1234!` |
| Staff | `test-staff` | `Staff1234!` |

> Password policy: min 8 chars, uppercase + lowercase + number + symbol.

### Create Staff or Doctor Accounts (Admin)

```bash
aws cognito-idp admin-create-user \
  --user-pool-id ap-southeast-2_gxGEa7l58 \
  --username <username> \
  --user-attributes Name=email,Value=<email> Name=name,Value="<Full Name>" \
    Name="custom:role",Value=doctor Name=email_verified,Value=true \
  --message-action SUPPRESS \
  --temporary-password "Temp1234!"

aws cognito-idp admin-set-user-password \
  --user-pool-id ap-southeast-2_gxGEa7l58 \
  --username <username> \
  --password "<permanent-password>" \
  --permanent
```

### Local Docker Demo Accounts

When running locally with Docker Compose, seed test accounts by running:

```bash
sh infra/scripts/seed-users.sh
```

| Role | Email | Password |
|------|-------|----------|
| Doctor | `doctor@clinic.com` | `password123` |
| Staff | `staff@clinic.com` | `password123` |
| Patient | `patient@clinic.com` | `password123` |

The seed script also inserts the doctor into the `doctors.doctors` and `appointments.doctors` tables so booking and consultation flows work out of the box.

## Core Business Scenarios

### Scenario 1 — Patient Books Appointment

![Scenario 1](diagrams/Scenario1.jpg)

1. Patient signs in → receives Cognito ID token
2. Submits booking via frontend → API Gateway validates token → `composite-appointment`
3. `composite-appointment` calls `appointment-service` → creates appointment
4. Publishes `appointment.booked` → `queue-coordinator` adds patient to queue

### Scenario 2 — Patient Check-In

![Scenario 2](diagrams/Scenario2.jpg)

1. Patient checks in via frontend (with location)
2. `checkin-orchestrator` calls `eta-service` via gRPC for travel time
3. On time → `queue.checked_in` → queue-coordinator updates status
4. Late → `queue.late_detected` → notification sent; patient must confirm
5. Patient YES → `queue.deprioritized` → moved to back of queue
6. Patient NO / no response (TTL 5 min) → `queue.removed` → removed from queue

### Scenario 3 — Doctor Completes Consultation

![Scenario 3](diagrams/Scenario3.jpg)

1. Doctor submits notes, MC, prescription via doctor dashboard
2. `composite-consultation` (synchronously):
   - Calls `patient-service` via gRPC → stores MC + prescription
   - Calls `doctor-service` via gRPC → stores consultation notes
   - Calls `appointment-service` → marks appointment `completed`
   - Calls `stripe-service` via gRPC → creates a Stripe checkout session (payment link)
3. Publishes `consultation.completed` → `queue-coordinator` removes patient from queue
4. Patient receives or sees the payment link and can pay immediately

### Scenario 3b — Staff Designates Billing
This flow still exists in the codebase, but the default demo path uses the automatic fixed-fee payment flow in Scenario 3 instead.

### Scenario 4 — Real-Time Queue Updates

Patient WebSocket (tracks own position):
```
wss://d1ny1tpqtbblzr.cloudfront.net/api/queue/ws?appointment_id=<id>&token=<jwt>
```

Staff WebSocket (full queue snapshot + live updates):
```
wss://d1ny1tpqtbblzr.cloudfront.net/api/queue/ws/staff?token=<jwt>
```

Both use `token` as a query parameter because browsers cannot set custom headers on WebSocket connections.

## Requirements Coverage

The current implementation satisfies the project's core technical requirements:

| Requirement | Implementation |
|-------------|----------------|
| Minimum 3 interesting user scenarios | Booking, check-in with late handling, consultation completion with payment, plus real-time queue updates |
| Minimum 3 atomic microservices for distinct entities | Appointment, Patient, Doctor, Queue, Payment, Activity Log, Auth |
| At least 1 reused microservice | Appointment, Queue, Patient, Doctor, and Auth services are reused across multiple scenarios |
| At least 1 OutSystems atomic service | `activity-log-service` integrates with an OutSystems REST endpoint |
| At least 1 external service | Stripe, Twilio, Google Maps, and Cognito |
| HTTP communication between services | Composite services call atomic services over HTTP |
| Message-based communication | RabbitMQ `clinic.events` topic exchange |
| Web-based GUI | Vue frontend for patient, staff, and doctor workflows |
| JSON usage | REST APIs, frontend requests/responses, and event payloads |
| Docker-based local deployment | Full local stack provided via Docker Compose |

## Data Model

Run `infra/migrations/schema.sql` against a fresh PostgreSQL database. For local Docker, the `app-db` container automatically loads this schema on a fresh volume.

| Schema | Used by |
|--------|---------|
| `appointments` | appointment-service |
| `queue` | queue-coordinator-service |
| `activity_log` | activity-log-service |
| `patients` | patient-service |
| `doctors` | doctor-service |
| `payments` | payment-service |

> All services use explicit `schema.table` in SQL (e.g. `queue.queue_entries`) — required because RDS Proxy / PgBouncer transaction mode strips `search_path`.

## AWS Infrastructure Setup

This section documents how to recreate the AWS deployment from scratch.

### Setup Order

```
IAM → Cognito → RDS → Amazon MQ → ElastiCache → ECR → ECS (Cluster + Cloud Map + Services) → ALB → API Gateway → S3 → CloudFront
```

### 1. IAM

**Task Execution Role** (required for ECS to pull images and write logs):

1. Go to **IAM → Roles → Create role**
2. Trusted entity: **AWS service → Elastic Container Service Task**
3. Attach policy: `AmazonECSTaskExecutionRolePolicy`
4. Role name: `ecsTaskExecutionRole`

**Developer group** (optional, for team console access):

1. Go to **IAM → User groups → Create group**
2. Name: `clinic-queue-dev-team`
3. Attach: `AmazonECS_FullAccess`, `AmazonEC2ContainerRegistryFullAccess`, `AmazonAPIGatewayAdministrator`, `AmazonS3FullAccess`, `AmazonCognitoPowerUser`, `CloudWatchLogsFullAccess`, `AmazonVPCFullAccess`

### 2. Cognito

1. Go to **Cognito → User Pools → Create user pool**
   - Name: `clinic-users`
   - Sign-in: Email
   - App client type: **Public client** (no secret)
   - App client name: `clinic-web-client`

2. Add custom attribute: **Sign-up experience → Custom attributes**
   - Name: `role`, Type: String, Mutable: Yes

3. Add a Pre-SignUp Lambda trigger to auto-confirm users (avoids email verification flow):
   - Go to **Lambda → Create function**, runtime: Python 3.11, name: `cognito-auto-confirm`
   - Paste this code and click Deploy:
     ```python
     def lambda_handler(event, context):
         event['response']['autoConfirmUser'] = True
         event['response']['autoVerifyEmail'] = True
         return event
     ```
   - Attach under **Cognito → User Pool → User pool properties → Add Lambda trigger → Sign-up → Pre sign-up**

4. Note your **User Pool ID** and **App Client ID** — used in all service env vars.

The JWKS URL for all services:
```
https://cognito-idp.ap-southeast-2.amazonaws.com/<USER_POOL_ID>/.well-known/jwks.json
```

### 3. RDS PostgreSQL

1. Go to **RDS → Create database**
   - Engine: PostgreSQL 16
   - Instance: `db.t3.micro`
   - Public access: No (VPC only)
   - VPC security group: allow port 5432 from ECS security group

2. After creation, run the schema:
```bash
psql "postgresql://postgres:<PASSWORD>@<RDS_ENDPOINT>:5432/postgres?sslmode=require" \
  -f infra/migrations/schema.sql
```

### 4. Amazon MQ (RabbitMQ)

1. Go to **Amazon MQ → Create broker**
   - Engine: RabbitMQ
   - Deployment: Single-instance (dev) or Cluster (prod)
   - Public accessibility: No (VPC only)

2. The AMQPS URL becomes `RABBITMQ_URL` in services:
   ```
   amqps://<user>:<password>@<broker-id>.mq.<region>.on.aws:5671
   ```

### 5. ElastiCache Redis

1. Go to **ElastiCache → Redis OSS caches → Create**
   - Serverless mode or standard cluster
   - Same VPC as ECS

2. The TLS URL becomes `REDIS_URL`:
   ```
   rediss://<endpoint>:6379
   ```

### 6. ECR

Create one private repository per service (names match the service names in the Services table above).

```bash
# Authenticate
aws ecr get-login-password --region ap-southeast-2 \
  | docker login --username AWS --password-stdin \
    929702668297.dkr.ecr.ap-southeast-2.amazonaws.com

# Build and push all backend images (always --platform linux/amd64 — ECS is x86-64)
sh infra/scripts/push-to-ecr.sh
```

The frontend is deployed separately to S3 + CloudFront in Step 10.

> **Critical:** Always use `--platform linux/amd64`. If you build on Apple Silicon (`arm64`) without this flag, the container may silently fail on Fargate without producing useful logs.

### 7. ECS Cluster + Cloud Map

**CloudWatch log group:**
```bash
aws logs create-log-group --log-group-name /ecs/smart-clinic --region ap-southeast-2
```

**ECS Cluster:**
1. Go to **ECS → Clusters → Create cluster**
   - Name: `smart-clinic-queue`
   - Infrastructure: AWS Fargate (serverless)

**Cloud Map (internal DNS):**
1. Go to **Cloud Map → Namespaces → Create namespace**
   - Name: `smart-clinic.local`
   - Type: Private DNS namespace
   - VPC: default

2. Copy `infra/scripts/env-aws.example` to `infra/scripts/.env.aws` and fill in your account, network, Cloud Map, target group, URL, and secret values.

3. Create service discovery entries for all 15 backend services:
```bash
sh infra/scripts/create-service-discovery.sh
```

**Task Definitions:**

Register task definitions from the shared `.env.aws` contract:
```bash
sh infra/scripts/register-task-definitions.sh
```

Each task: Fargate, 0.25 vCPU, 512 MB, `ecsTaskExecutionRole`.

**ECS Services:**

Create ECS services from the shared `.env.aws` contract:
```bash
sh infra/scripts/create-ecs-services.sh
```

**VPC / Security Group:**

All tasks share one security group. Add a self-referencing inbound rule (all traffic, source = same SG) so services can reach each other via gRPC.

### 8. Application Load Balancer

1. Go to **EC2 → Load Balancers → Create ALB**
   - Scheme: Internet-facing
   - Listener: HTTP port 80 (CloudFront handles TLS)
   - All availability zone subnets

2. Create **target groups** (type: IP, protocol: HTTP) for each externally-exposed service with appropriate health check paths (e.g. `/health`, `/api/<service>/openapi.json`).

3. Add **listener rules** in priority order:

| Priority | Path | Target Group |
|----------|------|--------------|
| 1 | `/api/auth*` | auth-service |
| 2 | `/api/queue/ws*` | queue-coordinator |
| 3 | `/api/queue/*` | queue-coordinator |
| 4 | `/api/composite/appointments*` | composite-appointment |
| 5 | `/api/check-in*` | checkin-orchestrator |
| 6 | `/api/composite/consultations*` | composite-consultation |
| 7 | `/api/composite/staff*` | composite-staff-orchestrator |
| 8 | `/api/composite/patients*` | composite-patient-orchestrator |
| 9 | `/api/payments/webhook` | stripe-service |
| 10 | `/api/payments*` | payment-service |
| 11 | `/api/appointments*` | appointment-service |

4. Register ECS task IPs to their target groups (ECS handles this automatically when services are created with `--load-balancers`).

### 9. API Gateway (HTTP API)

1. Go to **API Gateway → Create API → HTTP API**
   - Name: `smart-clinic-api`

2. **JWT Authorizer:**
   - Type: JWT
   - Issuer: `https://cognito-idp.ap-southeast-2.amazonaws.com/<USER_POOL_ID>`
   - Audience: your App Client ID

3. **Routes:** Create method-specific routes (not `ANY`) pointing at the ALB URL as an HTTP proxy integration. Attach the JWT authorizer to all routes except `/api/auth/*` and the Stripe webhook. See the API Gateway Routes table above.

4. **CORS:**
   - Allow origins: `https://<cloudfront-domain>`
   - Allow methods: `GET, POST, PUT, DELETE, OPTIONS`
   - Allow headers: `Authorization, Content-Type`

### 10. S3 (Frontend)

1. Create bucket: `esd-smart-clinic-queue-prod-ap-southeast-2`
   - Region: `ap-southeast-2`
   - Block all public access: **On** (CloudFront uses OAC)

2. Build and deploy:
```bash
cd frontend/vue-app
npm run build -- --mode production
aws s3 sync dist s3://esd-smart-clinic-queue-prod-ap-southeast-2 --delete
aws cloudfront create-invalidation --distribution-id E30HDOAOLMHC2G --paths "/*"
```

### 11. CloudFront

1. Go to **CloudFront → Create distribution**

2. **Origins:**

| Origin ID | Domain | Protocol |
|-----------|--------|----------|
| S3Origin | `<bucket>.s3.<region>.amazonaws.com` | HTTPS (OAC) |
| ALBOrigin | ALB DNS name | HTTP only (port 80) |
| APIGWOrigin | API Gateway invoke URL | HTTPS |

   For S3: create an **Origin Access Control (OAC)** and apply the generated bucket policy to your S3 bucket.

3. **Cache Behaviors** (in priority order):

| Path Pattern | Origin | Cache | Notes |
|-------------|--------|-------|-------|
| `/api/queue/ws*` | ALBOrigin | Disabled | WebSocket — must not cache |
| `/api/*` | APIGWOrigin | Disabled | REST API |
| `/*` (default) | S3Origin | CachingOptimized | Vue SPA |

4. **Custom Error Responses** (for Vue Router HTML5 history mode):
   - HTTP 403 → `/index.html`, response code 200
   - HTTP 404 → `/index.html`, response code 200

---

## Deployed Resource Reference

| Resource | Identifier |
|----------|-----------|
| AWS Region | `ap-southeast-2` |
| AWS Account | `929702668297` |
| Cognito User Pool | `ap-southeast-2_gxGEa7l58` |
| ECR Registry | `929702668297.dkr.ecr.ap-southeast-2.amazonaws.com` |
| ECS Cluster | `smart-clinic-queue` |
| Cloud Map Namespace | `smart-clinic.local` |
| ALB | `smart-clinic-alb-103991392.ap-southeast-2.elb.amazonaws.com` |
| API Gateway | `https://raw9qjg8o0.execute-api.ap-southeast-2.amazonaws.com` |
| CloudFront | `https://d1ny1tpqtbblzr.cloudfront.net` (dist `E30HDOAOLMHC2G`) |
| S3 Bucket | `esd-smart-clinic-queue-prod-ap-southeast-2` |
| CloudWatch Logs | `/ecs/smart-clinic` |

---

## Service Operations

### Deploy a service update

```bash
# 1. Build and push all images (always --platform linux/amd64)
sh infra/scripts/push-to-ecr.sh

# 2. Register new task definitions
sh infra/scripts/register-task-definitions.sh

# 3. Force-redeploy a specific service
aws ecs update-service --cluster smart-clinic-queue --region ap-southeast-2 \
  --service <service-name> --task-definition <service-name> --force-new-deployment
```

### View logs

```bash
aws logs tail /ecs/smart-clinic --log-stream-name-prefix <service-name> --follow
```

### Horizontal scaling

The system is designed for horizontal scaling: composite orchestrators are stateless, Redis manages shared queue state, and the ALB distributes traffic across healthy tasks.

**Local (Docker Compose):** The four main composite services (`composite-appointment`, `composite-patient-orchestrator`, `composite-staff-orchestrator`, `composite-consultation`) run with `deploy.replicas: 2` by default. Kong's internal DNS round-robins across replicas automatically. To adjust:

```bash
docker compose -f infra/docker-compose.yml up -d --scale composite-appointment=3
```

**AWS (ECS Fargate):** After creating services, enable CPU-based auto-scaling:

```bash
sh infra/scripts/enable-auto-scaling.sh
```

This configures each composite service to scale between 1 and 4 tasks, targeting 70% average CPU utilization. The ALB automatically registers new tasks and distributes traffic. Scaling parameters are configurable in `.env.aws` (`AUTOSCALING_MIN_TASKS`, `AUTOSCALING_MAX_TASKS`, `AUTOSCALING_CPU_TARGET`).

### Scale to zero (save costs)

```bash
for svc in $(aws ecs list-services --cluster smart-clinic-queue --region ap-southeast-2 \
  --output text --query 'serviceArns[*]' | tr '\t' '\n' | xargs -I{} basename {}); do
  aws ecs update-service --cluster smart-clinic-queue --region ap-southeast-2 \
    --service $svc --desired-count 0 --output text --query 'service.serviceName'
done
```

### Scale back up

```bash
for svc in $(aws ecs list-services --cluster smart-clinic-queue --region ap-southeast-2 \
  --output text --query 'serviceArns[*]' | tr '\t' '\n' | xargs -I{} basename {}); do
  aws ecs update-service --cluster smart-clinic-queue --region ap-southeast-2 \
    --service $svc --desired-count 1 --output text --query 'service.serviceName'
done
```

---

## Local Development (Docker Compose)

Local development uses Docker Compose to run all 16 services together with supporting infrastructure (PostgreSQL, RabbitMQ, Redis, and Kong). Authentication is handled by BetterAuth rather than Cognito, so no AWS account is required.

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (4 GB+ RAM allocated)
- [Stripe CLI](https://stripe.com/docs/stripe-cli) (optional — only for payment testing)

> Node.js, Go, and Python are **not** required on the host — everything runs inside Docker containers.

### 1. Clone the repo

```bash
git clone https://github.com/decker757/Smart-Clinic-Queue-ESD.git
cd Smart-Clinic-Queue-ESD
```

### 2. Create environment files

Copy each `.env.example` file to its corresponding `.env` file, then update the values that require local Docker settings:

```bash
# Copy all env files at once
for f in infra/env/*.env.example; do
  cp "$f" "${f%.example}"
done
```

Then update the following files:

**`infra/env/auth.env`** — Set the local database URL and a secret:
```
DATABASE_URL=postgresql://app:app@app-db:5432/clinic
BETTER_AUTH_SECRET=any-random-string-here
BETTER_AUTH_URL=http://auth-service:3000
CORS_ORIGIN=http://localhost:5173
```

**All other services with `DATABASE_URL`** — Replace the RDS placeholder with the local database in these files: `appointment.env`, `doctor.env`, `patient.env`, `queue-coordinator.env`, `activity-log.env`, `payment.env`:
```
DATABASE_URL=postgresql://app:app@app-db:5432/clinic
```

**`infra/env/eta.env`** — Also set the local database URL. The Google Maps API key is optional; without it the ETA service falls back to a default 15-minute estimate:
```
DATABASE_URL=postgresql://app:app@app-db:5432/clinic
GOOGLE_MAPS_API_KEY=your-key-here   # optional
```

**`infra/env/appointment.env`** — Also add a JWT secret (can be any string; only used for local token validation fallback):
```
JWT_SECRET=local-dev-secret
```

**`infra/env/notification.env`** — This already defaults to `SMS_ENABLED=false`, so Twilio credentials are not needed for local development. Notifications are logged to the console instead.

**`infra/env/stripe-service.env`** — Stripe credentials are optional. Without them, consultations still complete, but automatic payment links cannot be generated and patients will not see a payable link in appointment history:
```
STRIPE_API_KEY=sk_test_...           # optional
STRIPE_WEBHOOK_SIGNING_SECRET=whsec_... # optional (get from `stripe listen`)
```

**`infra/env/activity-log.env`** — Set `ACTIVITY_LOG_URL` to point at your own OutSystems REST endpoint. The default value points at the original developer's personal OutSystems cloud, which may not be accessible:
```
ACTIVITY_LOG_URL=https://<your-outsystems-env>.outsystemscloud.com/<your-app>/rest/ActivityLogAPI/logs
```
The service POSTs every clinic event to this URL and GETs logs from it. If you do not have an OutSystems environment, events will be logged to the console as errors but will not break any other service — the failure is caught and swallowed by the RabbitMQ consumer.

**`infra/env/patient.env`** — The `AWS_*` and `S3_BUCKET` variables are used for file uploads to S3. Without them, file uploads in medical records will fail, but all other patient features will continue to work:
```
AWS_REGION=ap-southeast-2            # optional
AWS_ACCESS_KEY_ID=...                # optional
AWS_SECRET_ACCESS_KEY=...            # optional
S3_BUCKET=...                        # optional
```

**`infra/env/kong.env`** — This file is auto-generated by the bringup script (Step 3). Do not create it manually.

### 3. Start the stack (recommended — automated)

The bring-up script starts services in the correct order, extracts the BetterAuth JWKS public key for Kong, and runs integration tests:

```bash
sh infra/scripts/bringup-and-verify-local.sh
```

This script will:
1. Start PostgreSQL and RabbitMQ
2. Wait for the database and apply `schema.sql`
3. Start auth-service and wait for its JWKS endpoint
4. Extract the RSA public key and write `infra/env/kong.env`
5. Start all remaining services (Kong, frontend, atomics, composites, wrappers)
6. Run the full integration test suite

### 4. Seed test accounts

```bash
sh infra/scripts/seed-users.sh
```

This creates three accounts and inserts the doctor into the relevant database tables:

| Role | Email | Password |
|------|-------|----------|
| Doctor | `doctor@clinic.com` | `password123` |
| Staff | `staff@clinic.com` | `password123` |
| Patient | `patient@clinic.com` | `password123` |

### 5. Access the application

| Service | URL |
|---------|-----|
| **Frontend** | http://localhost:5173 |
| Kong API Gateway | http://localhost:8000 |
| RabbitMQ Management | http://localhost:15673 (guest / guest) |

Open http://localhost:5173 and sign in with one of the seeded accounts above. Patients see the patient dashboard, staff see the staff dashboard, and doctors see the doctor dashboard.

### 6. Forward Stripe webhooks (optional — for payment testing)

```bash
stripe login
stripe listen --forward-to localhost:8086/api/payments/webhook
# Copy the webhook signing secret into infra/env/stripe-service.env as STRIPE_WEBHOOK_SIGNING_SECRET
# Then restart the stripe service: docker compose restart stripe-service
```

### Alternative: Manual start

If you prefer to start services manually instead of using the bring-up script:

```bash
cd infra

# 1. Start infrastructure
docker compose up -d rabbitmq app-db redis

# 2. Wait for DB, then start auth
docker compose up -d auth-service

# 3. Once auth-service is up, extract the JWKS public key for Kong
sh scripts/extract-jwks-pem.sh http://localhost:3000 > /tmp/key.pem
echo "BETTER_AUTH_RSA_PUBLIC_KEY=\"$(cat /tmp/key.pem)\"" > env/kong.env

# 4. Start everything
docker compose up -d

# 5. Seed users
sh scripts/seed-users.sh
```

### Troubleshooting

| Problem | Fix |
|---------|-----|
| Services crash with "connection refused" | Database or RabbitMQ may not be ready yet. Use the bring-up script or wait for health checks. |
| Kong returns 401 on all requests | `kong.env` is missing or has wrong RSA key. Re-run `extract-jwks-pem.sh`. |
| Login returns 500 | Check `docker compose logs auth-service`. Usually a missing `BETTER_AUTH_SECRET`. |
| Check-in always returns "on time" | Google Maps API key not set. ETA service uses 15-min default fallback. |
| Queue not updating in real time | Check WebSocket in browser DevTools → Network → WS tab. |
| Payment link not available after consultation completion | Stripe keys not configured or Stripe webhook/session setup is invalid. Consultations still complete, but the automatic `$50` payment link cannot be generated. |

---

## CI/CD

- **PR checks** (`.github/workflows/pr-check.yml`): lint + unit tests + GitGuardian secret scan on every PR
- **Deploys are manual** via the scripts in `infra/scripts/` — see the [Service Operations](#service-operations) section above

---

## Architecture Principles

- **Atomic services** do not call each other directly — all cross-service orchestration goes through composite services
- **Composite services** call multiple atomics via gRPC and publish RabbitMQ events for side effects
- **Wrapper services** wrap external APIs (Google Maps, Stripe, Twilio) and expose gRPC or HTTP interfaces
- **Synchronous calls** for critical state changes (e.g. completing a consultation or creating a billing session before responding to the client)
- **Async MQ events** for side effects (notifications, logging, queue updates, payment history)

## Contributing

1. Create a branch from `main`
2. Make changes and push
3. Open a PR — all checks must pass before merging
4. Never commit `.env` files — use `.env.example` to document required variables
