# Smart-Clinic-Queue-ESD

A polyclinic queue management system built with an event-driven microservices architecture.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| API Gateway | AWS API Gateway (HTTP API, Cognito JWT authorizer) |
| Load Balancer | AWS Application Load Balancer |
| Message Broker | Amazon MQ (RabbitMQ) |
| Database | AWS RDS (PostgreSQL) |
| Cache | Redis (queue position cache) |
| Auth | AWS Cognito (RS256 JWT) |
| Payments | Stripe |
| Frontend | Vue 3 + Vite + Tailwind CSS |
| Infrastructure | AWS ECS Fargate (16 services) |

## Public URLs

| Endpoint | URL |
|----------|-----|
| Frontend | `http://smart-clinic-alb-2054248031.ap-southeast-1.elb.amazonaws.com` |
| API Gateway | `https://y2noszdtvi.execute-api.ap-southeast-1.amazonaws.com` |

> **Note:** Open the frontend via the **ALB URL** (HTTP), not the API Gateway URL. This allows WebSocket connections (`ws://`) for real-time queue updates. API calls from the frontend are routed to API Gateway automatically.

## Architecture

```
Browser
  │
  ├── REST/HTTP  ──► API Gateway (Cognito JWT auth)
  │                      │
  │                      ▼
  │               ALB (path-based routing)
  │                      │
  └── WebSocket ─────────┤
                         │
              ┌──────────┴──────────────────┐
              │                             │
         ECS Services              RabbitMQ (Amazon MQ)
         (Fargate)                  clinic.events exchange
```

### API Gateway Routes

| Route | Auth | Forwards to |
|-------|------|-------------|
| `ANY /api/auth/*` | None | auth-service |
| `ANY /api/queue` | Cognito JWT | queue-coordinator |
| `ANY /api/queue/*` | Cognito JWT | queue-coordinator |
| `ANY /api/composite` | Cognito JWT | composite services |
| `ANY /api/composite/*` | Cognito JWT | composite services |
| `ANY /{proxy+}` | None | frontend |

### ALB Path Routing

| Path | Service | Port |
|------|---------|------|
| `/api/auth/*` | auth-service | 3000 |
| `/api/queue/*` | queue-coordinator-service | 3002 |
| `/api/composite/appointments*` | composite-appointment | 8000 |
| `/api/composite/consultation*` | composite-consultation | 8002 |
| `/api/composite/patients*` | composite-patient-orchestrator | 8001 |
| `/api/composite/staff*` | composite-staff-orchestrator | 8004 |
| `/*` (catch-all) | frontend | 5173 |

### Internal Service Communication

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
| `auth-service` | 3000 | — | Node.js + BetterAuth | Legacy auth (superseded by Cognito) |
| `appointment-service` | 3001 | — | Go + Gin | Appointment lifecycle |
| `queue-coordinator-service` | 3002 | 50052 | Node.js + Express | Queue management + WebSocket |
| `patient-service` | 3007 | 50053 | Node.js + Express | Patient profiles, memos, MC/prescriptions |
| `doctor-service` | 3006 | 50055 | Node.js + Express | Doctor profiles, slots, consultation notes |
| `activity-log-service` | 3005 | — | Node.js + Express | Audit log |
| `payment-service` | 3008 | — | Python + FastAPI | Payment history |

### Wrapper Services

| Service | Port | gRPC Port | Language | Description |
|---------|------|-----------|----------|-------------|
| `eta-service` | — | 50054 | Node.js + TypeScript | Google Maps travel time |
| `notification-service` | 3004 | — | Node.js + TypeScript | SMS/email via Twilio |
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
| `frontend` | 5173 | Vue 3 + Vite + Tailwind CSS |

## Auth (Cognito)

All services validate RS256 JWTs issued by AWS Cognito.

- **User Pool:** `ap-southeast-1_3XvO4K1lI`
- **App Client:** `4iboa3a11vktthtupoidetvk9o` (no secret — browser-safe)
- **JWKS URL:** `https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_3XvO4K1lI/.well-known/jwks.json`
- **Role claim:** `custom:role` in the ID token (`patient` | `staff` | `doctor` | `admin`)
- **Pre-SignUp trigger:** `cognito-auto-confirm` Lambda — users are auto-confirmed (no email verification)

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
1. Patient connects to WebSocket: `ws://alb-url/api/queue/ws?appointment_id=<id>&token=<jwt>`
2. Staff connects to: `ws://alb-url/api/queue/ws/staff?token=<jwt>`
3. Queue changes (check-in, call next, deprioritize) push live updates to connected clients

## Database

Run `infra/migrations/schema.sql` against a fresh PostgreSQL database.

| Schema | Used by |
|--------|---------|
| `appointments` | appointment-service |
| `queue` | queue-coordinator-service |
| `activity_log` | activity-log-service |
| `patients` | patient-service |
| `doctors` | doctor-service |
| `payments` | payment-service |

> All services use explicit `schema.table` in SQL — required for PgBouncer/Supavisor transaction mode which strips `search_path`.

## AWS Infrastructure

| Resource | ID / Name |
|----------|-----------|
| ECS Cluster | `smart-clinic-queue` (ap-southeast-1) |
| ECR | `617341601600.dkr.ecr.ap-southeast-1.amazonaws.com/<service>` |
| RDS | PostgreSQL (ap-southeast-1) |
| Amazon MQ | RabbitMQ broker (ap-southeast-1, `.on.aws:5671` SSL) |
| ALB | `smart-clinic-alb` — `smart-clinic-alb-2054248031.ap-southeast-1.elb.amazonaws.com` |
| API Gateway | `smart-clinic-api` — `y2noszdtvi.execute-api.ap-southeast-1.amazonaws.com` |
| Cognito | User Pool `ap-southeast-1_3XvO4K1lI` |
| Cloud Map | `smart-clinic.local` (internal DNS for ECS service discovery) |

### Deploy a service update

```bash
# 1. Build and push all images
sh infra/scripts/push-to-ecr.sh

# 2. Register new task definitions
sh infra/scripts/register-task-definitions.sh

# 3. Force-deploy a specific service
aws ecs update-service --cluster smart-clinic-queue --region ap-southeast-1 \
  --service <service-name> --task-definition <service-name> --force-new-deployment
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
# repeat for other services — fill in RDS, Amazon MQ, Stripe, Google Maps credentials
```

### 3. Start all services

```bash
cd infra
docker compose up --build
```

### 4. Forward Stripe webhooks (for payment testing)

```bash
stripe login
stripe listen --forward-to localhost:8086/api/payments/webhook
# Copy the webhook signing secret → set STRIPE_WEBHOOK_SIGNING_SECRET in infra/env/stripe-service.env
```

## CI/CD

- **PR checks** (`.github/workflows/pr-check.yml`): lint + unit tests + GitGuardian secret scan on every PR
- **Per-service deploys** (`.github/workflows/deploy-*.yml`): auto-deploy to Railway on push to `main` (legacy — not used for AWS)

## Architecture Principles

- **Atomic services** do not call each other directly — all cross-service orchestration goes through composite services
- **Composite services** call multiple atomics and publish RabbitMQ events
- **Wrapper services** wrap external APIs (Google Maps, Stripe, Twilio) and expose gRPC or HTTP interfaces
- **Synchronous calls** for critical state changes (e.g. creating payment link)
- **Async MQ events** for side effects (notifications, logging, queue updates, payment history)

## Contributing

1. Create a branch from `main`
2. Make changes and push
3. Open a PR — all checks must pass before merging
4. Never commit `.env` files — use `.env.example` to document required variables
