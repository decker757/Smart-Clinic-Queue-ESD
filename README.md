# Smart-Clinic-Queue-ESD

A polyclinic queue management system built with an event-driven microservices architecture.

## Tech Stack

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
| Infrastructure | AWS ECS Fargate (16 services) |

## Public URLs

| Endpoint | URL |
|----------|-----|
| Frontend | `https://d2qwgyxb2qmggu.cloudfront.net` |
| API Gateway | `https://y2noszdtvi.execute-api.ap-southeast-1.amazonaws.com` |
| API Docs | Open `docs/index.html` locally via `npx serve docs/` |

## Architecture

```
Browser / Mobile
       │
       ▼
  CloudFront  (HTTPS termination, CDN)
  ├── /*  ──────────────────────────► S3 (Vue SPA static files)
  ├── /api/* ──────────────────────► API Gateway (HTTP API)
  │                                        │
  │                                   JWT Authorizer
  │                                   (Cognito RS256)
  │                                        │
  │                                        ▼
  │                                  ALB (path routing)
  │                                        │
  └── /api/queue/ws* ──────────────► ALB (WebSocket bypass)
                                           │
                                           ▼
                                     ECS Fargate Tasks
                                           │
                              ┌────────────┴────────────┐
                         gRPC (internal)         RabbitMQ events
                     (via Cloud Map DNS)        clinic.events exchange
```

> WebSocket connections use `wss://` to CloudFront. CloudFront forwards them as `ws://` to the ALB — this handles the mixed-content restriction when the frontend is served over HTTPS.

### API Gateway Routes

Method-specific routes are used (not `ANY`) so OPTIONS preflight requests bypass the JWT authorizer and are handled by API Gateway's built-in CORS support.

| Route | Auth | Forwards to |
|-------|------|-------------|
| `GET/POST /api/auth/{proxy+}` | None | auth-service |
| `POST /api/composite/appointments` | Cognito JWT | composite-appointment |
| `GET/DELETE /api/composite/appointments/{proxy+}` | Cognito JWT | composite-appointment |
| `POST /api/check-in` | Cognito JWT | checkin-orchestrator |
| `POST /api/check-in/{proxy+}` | Cognito JWT | checkin-orchestrator |
| `GET/POST /api/queue/{proxy+}` | Cognito JWT | queue-coordinator |
| `GET/POST /api/consultation/{proxy+}` | Cognito JWT | composite-consultation |
| `GET/POST /api/staff/{proxy+}` | Cognito JWT | composite-staff-orchestrator |
| `GET/POST/PUT /api/patient/{proxy+}` | Cognito JWT | composite-patient-orchestrator |
| `GET/POST /api/payments/{proxy+}` | Cognito JWT | payment-service |
| `POST /api/stripe/webhook` | None (Stripe signature) | stripe-service |

### ALB Path Routing

The ALB receives traffic from both API Gateway and CloudFront (WebSocket path only).

| Path Pattern | Service | Port |
|-------------|---------|------|
| `/api/queue/ws*` | queue-coordinator-service | 3002 |
| `/api/queue/*` | queue-coordinator-service | 3002 |
| `/api/composite/appointments*` | composite-appointment | 8000 |
| `/api/check-in*` | checkin-orchestrator | 8000 |
| `/api/consultation*` | composite-consultation | 8002 |
| `/api/staff*` | composite-staff-orchestrator | 8004 |
| `/api/patient*` | composite-patient-orchestrator | 8001 |
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

## Services

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
| `checkin-orchestrator` | 8000 | Python + FastAPI | Patient check-in, late detection via ETA |

### Frontend

| Service | Port | Language |
|---------|------|----------|
| `frontend` | 5173 | Vue 3 + Vite + Tailwind CSS v4 |

## Auth (Cognito)

All services validate RS256 JWTs issued by AWS Cognito.

- **User Pool:** `ap-southeast-1_3XvO4K1lI`
- **App Client:** `4iboa3a11vktthtupoidetvk9o` (no secret — browser-safe)
- **JWKS URL:** `https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json`
- **Role claim:** `custom:role` in the ID token (`patient` | `staff` | `doctor` | `admin`)
- **Pre-SignUp trigger:** `cognito-auto-confirm` Lambda — users are auto-confirmed (no email verification required)

### Sign in

```bash
curl -X POST https://cognito-idp.ap-southeast-1.amazonaws.com/ \
  -H "Content-Type: application/x-amz-json-1.1" \
  -H "X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth" \
  -d '{
    "AuthFlow": "USER_PASSWORD_AUTH",
    "ClientId": "4iboa3a11vktthtupoidetvk9o",
    "AuthParameters": { "USERNAME": "<email>", "PASSWORD": "<password>" }
  }'
# Use AuthenticationResult.IdToken as the Bearer token
```

### Test accounts

| Role | Username | Password |
|------|----------|----------|
| Patient | `test-patient` | `Test1234!` |
| Staff | `test-staff` | `Staff1234!` |

> Password policy: min 8 chars, uppercase + lowercase + number + symbol.

### Create staff/doctor accounts (admin only)

```bash
aws cognito-idp admin-create-user \
  --user-pool-id ap-southeast-1_3XvO4K1lI \
  --username <username> \
  --user-attributes Name=email,Value=<email> Name=name,Value="<Full Name>" \
    Name="custom:role",Value=doctor Name=email_verified,Value=true \
  --message-action SUPPRESS \
  --temporary-password "Temp1234!"

aws cognito-idp admin-set-user-password \
  --user-pool-id ap-southeast-1_3XvO4K1lI \
  --username <username> \
  --password "<permanent-password>" \
  --permanent
```

### Local Docker demo accounts

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

## Scenarios

### Scenario 1 — Patient Books Appointment
1. Patient signs in → receives Cognito ID token
2. Submits booking via frontend → API Gateway validates token → `composite-appointment`
3. `composite-appointment` calls `appointment-service` → creates appointment
4. Publishes `appointment.booked` → `queue-coordinator` adds patient to queue

### Scenario 2 — Patient Check-In
1. Patient checks in via frontend (with location)
2. `checkin-orchestrator` calls `eta-service` via gRPC for travel time
3. On time → `queue.checked_in` → queue-coordinator updates status
4. Late → `queue.late_detected` → notification sent; patient must confirm
5. Patient YES → `queue.deprioritized` → moved to back of queue
6. Patient NO / no response (TTL 5 min) → `queue.removed` → removed from queue

### Scenario 3 — Doctor Completes Consultation
1. Doctor submits notes, MC, prescription via staff dashboard
2. `composite-consultation` (synchronously):
   - Calls `patient-service` via gRPC → stores MC + prescription
   - Calls `doctor-service` via gRPC → stores consultation notes
   - Calls `appointment-service` → marks appointment `completed`
   - Calls `stripe-service` via gRPC → creates Stripe checkout session
3. `stripe-service` publishes `payment.pending` → `payment-service` records it
4. Publishes `consultation.completed` → notification-service sends patient the payment link
5. `queue-coordinator` removes patient from queue
6. Patient pays → Stripe webhook → `payment.completed` / `payment.failed`

### Scenario 4 — Real-Time Queue Updates

Patient WebSocket (tracks own position):
```
wss://d2qwgyxb2qmggu.cloudfront.net/api/queue/ws?appointment_id=<id>&token=<jwt>
```

Staff WebSocket (full queue snapshot + live updates):
```
wss://d2qwgyxb2qmggu.cloudfront.net/api/queue/ws/staff?token=<jwt>
```

Both use `token` as a query parameter because browsers cannot set custom headers on WebSocket connections.

## Database

Run `infra/migrations/schema.sql` against a fresh PostgreSQL database.
For local Docker, the `app-db` container auto-loads this schema on a fresh volume.

| Schema | Used by |
|--------|---------|
| `appointments` | appointment-service |
| `queue` | queue-coordinator-service |
| `activity_log` | activity-log-service |
| `patients` | patient-service |
| `doctors` | doctor-service |
| `payments` | payment-service |

> All services use explicit `schema.table` in SQL (e.g. `queue.queue_entries`) — required because RDS Proxy / PgBouncer transaction mode strips `search_path`.

---

## AWS Infrastructure Setup

This section documents how to recreate the AWS infrastructure from scratch.

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
https://cognito-idp.ap-southeast-1.amazonaws.com/<USER_POOL_ID>/.well-known/jwks.json
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
aws ecr get-login-password --region ap-southeast-1 \
  | docker login --username AWS --password-stdin \
    617341601600.dkr.ecr.ap-southeast-1.amazonaws.com

# Build and push all images (always --platform linux/amd64 — ECS is x86-64)
sh infra/scripts/push-to-ecr.sh
```

> **Critical:** Always use `--platform linux/amd64`. If you build on Apple Silicon (arm64) without this flag, the container will silently crash on Fargate with no error logs.

### 7. ECS Cluster + Cloud Map

**CloudWatch log group:**
```bash
aws logs create-log-group --log-group-name /ecs/smart-clinic --region ap-southeast-1
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

2. Create service discovery entries for all 16 services:
```bash
sh infra/scripts/create-service-discovery.sh
# Note the Service IDs printed — needed for the next step
```

**Task Definitions:**

Edit `infra/scripts/register-task-definitions.sh` to fill in your credentials (RDS, MQ, Redis, Stripe, Twilio, Google Maps, Cognito User Pool ID), then:
```bash
sh infra/scripts/register-task-definitions.sh
```

Each task: Fargate, 0.25 vCPU, 512 MB, `ecsTaskExecutionRole`.

**ECS Services:**

Edit `infra/scripts/create-ecs-services.sh` with the Service IDs from Cloud Map, then:
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
| 1 | `/api/queue/ws*` | queue-coordinator |
| 2 | `/api/queue/*` | queue-coordinator |
| 3 | `/api/composite/appointments*` | composite-appointment |
| 4 | `/api/check-in*` | checkin-orchestrator |
| 5 | `/api/consultation*` | composite-consultation |
| 6 | `/api/staff*` | composite-staff-orchestrator |
| 7 | `/api/patient*` | composite-patient-orchestrator |
| 8 | `/api/payments*` | payment-service |
| 9 | `/api/appointments*` | appointment-service |

4. Register ECS task IPs to their target groups (ECS handles this automatically when services are created with `--load-balancers`).

### 9. API Gateway (HTTP API)

1. Go to **API Gateway → Create API → HTTP API**
   - Name: `smart-clinic-api`

2. **JWT Authorizer:**
   - Type: JWT
   - Issuer: `https://cognito-idp.ap-southeast-1.amazonaws.com/<USER_POOL_ID>`
   - Audience: your App Client ID

3. **Routes:** Create method-specific routes (not `ANY`) pointing at the ALB URL as an HTTP proxy integration. Attach the JWT authorizer to all routes except `/api/auth/*` and the Stripe webhook. See the API Gateway Routes table above.

4. **CORS:**
   - Allow origins: `https://<cloudfront-domain>`
   - Allow methods: `GET, POST, PUT, DELETE, OPTIONS`
   - Allow headers: `Authorization, Content-Type`

### 10. S3 (Frontend)

1. Create bucket: `esd-smart-clinic-queue-prod-ap-southeast-1`
   - Region: `ap-southeast-1`
   - Block all public access: **On** (CloudFront uses OAC)

2. Build and deploy:
```bash
cd frontend/vue-app
npm run build -- --mode production
aws s3 sync dist s3://esd-smart-clinic-queue-prod-ap-southeast-1 --delete
aws cloudfront create-invalidation --distribution-id E11KZ18SBDDTZ9 --paths "/*"
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
| AWS Region | `ap-southeast-1` |
| AWS Account | `617341601600` |
| Cognito User Pool | `ap-southeast-1_3XvO4K1lI` |
| ECR Registry | `617341601600.dkr.ecr.ap-southeast-1.amazonaws.com` |
| ECS Cluster | `smart-clinic-queue` |
| Cloud Map Namespace | `smart-clinic.local` |
| ALB | `smart-clinic-alb-2054248031.ap-southeast-1.elb.amazonaws.com` |
| API Gateway | `https://y2noszdtvi.execute-api.ap-southeast-1.amazonaws.com` |
| CloudFront | `https://d2qwgyxb2qmggu.cloudfront.net` (dist `E11KZ18SBDDTZ9`) |
| S3 Bucket | `esd-smart-clinic-queue-prod-ap-southeast-1` |
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
aws ecs update-service --cluster smart-clinic-queue --region ap-southeast-1 \
  --service <service-name> --task-definition <service-name> --force-new-deployment
```

### View logs

```bash
aws logs tail /ecs/smart-clinic --log-stream-name-prefix <service-name> --follow
```

### Scale to zero (save costs)

```bash
for svc in $(aws ecs list-services --cluster smart-clinic-queue --region ap-southeast-1 \
  --output text --query 'serviceArns[*]' | tr '\t' '\n' | xargs -I{} basename {}); do
  aws ecs update-service --cluster smart-clinic-queue --region ap-southeast-1 \
    --service $svc --desired-count 0 --output text --query 'service.serviceName'
done
```

### Scale back up

```bash
for svc in $(aws ecs list-services --cluster smart-clinic-queue --region ap-southeast-1 \
  --output text --query 'serviceArns[*]' | tr '\t' '\n' | xargs -I{} basename {}); do
  aws ecs update-service --cluster smart-clinic-queue --region ap-southeast-1 \
    --service $svc --desired-count 1 --output text --query 'service.serviceName'
done
```

---

## Local Development

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Node.js](https://nodejs.org/) v22+
- [Go](https://golang.org/) 1.22+
- [Python](https://www.python.org/) 3.13+
- [Stripe CLI](https://stripe.com/docs/stripe-cli) (for local webhook forwarding)

### 1. Clone the repo

```bash
git clone https://github.com/your-org/Smart-Clinic-Queue-ESD.git
cd Smart-Clinic-Queue-ESD
```

### 2. Set up environment variables

```bash
cp infra/env/auth.env.example infra/env/auth.env
# Repeat for other services — fill in RDS, Amazon MQ, Stripe, Google Maps credentials
```

### 3. Start all services

```bash
cd infra
docker compose up --build
```

On a fresh local Docker volume, Postgres auto-loads `infra/migrations/schema.sql`.

### 4. Forward Stripe webhooks (for payment testing)

```bash
stripe login
stripe listen --forward-to localhost:8086/api/payments/webhook
# Copy the webhook signing secret → set STRIPE_WEBHOOK_SIGNING_SECRET in infra/env/stripe-service.env
```

---

## CI/CD

- **PR checks** (`.github/workflows/pr-check.yml`): lint + unit tests + GitGuardian secret scan on every PR
- **Per-service deploys** (`.github/workflows/deploy-*.yml`): legacy Railway workflows — AWS deploys are manual via the scripts above

---

## Architecture Principles

- **Atomic services** do not call each other directly — all cross-service orchestration goes through composite services
- **Composite services** call multiple atomics via gRPC and publish RabbitMQ events for side effects
- **Wrapper services** wrap external APIs (Google Maps, Stripe, Twilio) and expose gRPC or HTTP interfaces
- **Synchronous calls** (gRPC) for critical state changes (e.g. creating a payment link before responding to the client)
- **Async MQ events** for side effects (notifications, logging, queue updates, payment history)

## Contributing

1. Create a branch from `main`
2. Make changes and push
3. Open a PR — all checks must pass before merging
4. Never commit `.env` files — use `.env.example` to document required variables
