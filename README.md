# Smart-Clinic-Queue-ESD

A polyclinic queue management system built with an event-driven microservices architecture.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| API Gateway | Kong (DB-less, declarative config) |
| Message Broker | RabbitMQ (CloudAMQP) |
| Database | PostgreSQL (Supabase) |
| Cache | Redis (queue position cache) |
| Auth | BetterAuth (RS256 JWT) |
| Payments | Stripe |
| Frontend | Vue 3 + Vite + Tailwind CSS |
| Infrastructure | Docker Compose (local) / Railway (production) |

## Architecture

```
Client (Vue 3)
  │
  ▼ REST
Kong API Gateway  (RS256 JWT validation)
  ├── /api/auth/*                        → auth-service:3000
  ├── /api/composite/appointments        → composite-appointment:8000
  ├── /api/composite/patients            → composite-patient-orchestrator:8001
  ├── /api/composite/consultations       → composite-consultation:8002
  ├── /api/composite/staff               → composite-staff-orchestrator:8004
  ├── /api/check-in                      → checkin-orchestrator:8000
  ├── /api/queue/*                       → queue-coordinator-service:3002
  ├── /api/payments                      → payment-service:3008
  └── /api/doctors                       → doctor-service:3006

RabbitMQ clinic.events (topic exchange)
  ├── appointment.booked                 → queue-coordinator-service
  ├── appointment.cancelled              → queue-coordinator-service
  ├── queue.checked_in                   → queue-coordinator-service
  ├── queue.late_detected                → notification-service
  ├── queue.deprioritized                → notification-service, queue-coordinator-service
  ├── queue.removed                      → notification-service, queue-coordinator-service
  ├── consultation.completed             → notification-service, queue-coordinator-service, activity-log-service
  ├── payment.pending                    → payment-service
  ├── payment.completed                  → payment-service
  └── payment.failed                     → payment-service
```

## Services

### Atomic Services

| Service | Port | gRPC Port | Language | Description |
|---------|------|-----------|----------|-------------|
| `auth-service` | 3000 | — | Node.js + BetterAuth | Auth, JWT issuance |
| `appointment-service` | 3001 | — | Go + Gin | Appointment lifecycle |
| `queue-coordinator-service` | 3002 | 50052 | Node.js + Express | Queue management |
| `patient-service` | 3007 | 50053 | Node.js + Express | Patient profiles, memos, MC/prescriptions |
| `doctor-service` | 3006 | 50055 | Node.js + Express | Doctor profiles, slots, consultation notes |
| `activity-log-service` | 3005 | — | Node.js + Express | Audit log |
| `payment-service` | 3008 | — | Python + FastAPI | Payment history (consumes RabbitMQ payment events) |

### Wrapper Services

| Service | Port | gRPC Port | Language | Description |
|---------|------|-----------|----------|-------------|
| `eta-service` | — | 50054 | Node.js + TypeScript | Google Maps travel time |
| `notification-service` | 3004 | — | Node.js + TypeScript | SMS/email via Twilio |
| `stripe-service` | 8086 (webhook) | 50060 | Python + FastAPI | Stripe checkout sessions + webhook handling |

### Composite Services

| Service | Port | Language | Description |
|---------|------|----------|-------------|
| `composite-appointment` | 8000 | Python + FastAPI | Patient books/cancels appointments |
| `composite-patient-orchestrator` | 8001 | Python + FastAPI | Patient profile, history, memos (via gRPC to patient-service) |
| `composite-consultation` | 8002 | Python + FastAPI | Doctor completes consultation, issues MC, triggers payment |
| `composite-staff-orchestrator` | 8004 | Python + FastAPI | Staff views queue, calls next patient |
| `checkin-orchestrator` | 8085 (host) | Python + FastAPI | Patient check-in, late detection via ETA |

### Frontend

| Service | Port | Language |
|---------|------|----------|
| `frontend` | 5173 | Vue 3 + Vite + Tailwind CSS |

## Scenarios

### Scenario 1 — Patient Books Appointment
1. Patient submits booking via frontend
2. `composite-appointment` calls `appointment-service` → creates appointment
3. Publishes `appointment.booked` → `queue-coordinator` adds patient to queue

### Scenario 2 — Patient Check-In
1. Patient checks in via frontend (with location)
2. `checkin-orchestrator` calls `eta-service` via gRPC to get travel time
3. If on time → publishes `queue.checked_in` → queue-coordinator updates status
4. If late → publishes `queue.late_detected` → notification sent; patient must confirm
5. Patient responds YES → `queue.deprioritized` → moved to back of queue
6. Patient responds NO / no response (TTL) → `queue.removed` → removed from queue

### Scenario 3 — Doctor Completes Consultation
1. Doctor submits consultation notes, MC, prescription via staff dashboard
2. `composite-consultation` (synchronously):
   - Calls `patient-service` via gRPC → stores MC + prescription
   - Calls `doctor-service` via gRPC → stores consultation notes
   - Calls `appointment-service` → marks appointment as `completed`
   - Calls `stripe-service` via gRPC → creates Stripe checkout session, returns payment link
3. `stripe-service` publishes `payment.pending` → `payment-service` records status
4. Publishes `consultation.completed` with payment link
5. `notification-service` sends patient the payment link
6. `queue-coordinator` removes patient from queue
7. Patient pays on Stripe → webhook hits `stripe-service` → publishes `payment.completed`/`payment.failed` → `payment-service` updates record

### Scenario 4 — Patient Views Profile
1. Patient requests profile via frontend
2. `composite-patient-orchestrator` verifies JWT, calls `patient-service` via gRPC
3. Returns patient profile, medical history, or memos

## Database

Run `infra/migrations/schema.sql` against a fresh Supabase database for a clean install.

| Schema | Used by |
|--------|---------|
| `betterauth` | auth-service (auto-migrated by BetterAuth) |
| `appointments` | appointment-service |
| `queue` | queue-coordinator-service |
| `activity_log` | activity-log-service |
| `patients` | patient-service |
| `doctors` | doctor-service |
| `payments` | payment-service |

> All services use explicit `schema.table` in SQL queries — Supabase Supavisor (transaction mode) strips `SET search_path`.

## Production (Railway)

**Base URL:** `https://kong-production-5d53.up.railway.app`

### Auth flow

```bash
# 1. Sign in → get session token
curl -X POST https://kong-production-5d53.up.railway.app/api/auth/sign-in/email \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"password"}'

# 2. Exchange session token for JWT
curl https://kong-production-5d53.up.railway.app/api/auth/token \
  -H "Authorization: Bearer <session-token>"

# 3. Use JWT on protected routes
curl -H "Authorization: Bearer <jwt>" https://kong-production-5d53.up.railway.app/api/...
```

### Key endpoints

```bash
# Book appointment
POST /api/composite/appointments
{ "patient_id": "...", "session": "morning" }

# Check queue position
GET /api/queue/position/:appointment_id

# Check in
POST /api/check-in
{ "patient_id": "...", "appointment_id": "...", "appointment_time": "...", "patient_location": {...}, "clinic_location": {...} }

# Complete consultation (doctor)
POST /api/composite/consultations
{ "appointment_id": "...", "patient_id": "...", "doctor_id": "...", "notes": "...", "diagnosis": "...", "medications": [...] }

# Payment history
GET /api/payments/consultation/:consultation_id
GET /api/payments/patient/:patient_id
```

## Railway Environment Variables

### auth-service
| Variable | Value |
|----------|-------|
| `DATABASE_URL` | Supabase connection string |

### appointment-service
| Variable | Value |
|----------|-------|
| `DATABASE_URL` | Supabase connection string |
| `AUTH_SERVICE_URL` | `http://smart-clinic-queue-esd.railway.internal:3000` |
| `PORT` | `3001` |

### queue-coordinator-service
| Variable | Value |
|----------|-------|
| `DATABASE_URL` | Supabase connection string |
| `RABBITMQ_URL` | CloudAMQP connection string |
| `REDIS_URL` | Redis connection string |
| `PORT` | `3002` |

### patient-service
| Variable | Value |
|----------|-------|
| `DATABASE_URL` | Supabase connection string |
| `AUTH_SERVICE_URL` | `http://smart-clinic-queue-esd.railway.internal:3000` |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | Supabase service role key |
| `SUPABASE_BUCKET` | `patient-memos` |
| `PORT` | `3007` |
| `GRPC_PORT` | `50053` |

### doctor-service
| Variable | Value |
|----------|-------|
| `DATABASE_URL` | Supabase connection string |
| `AUTH_SERVICE_URL` | `http://smart-clinic-queue-esd.railway.internal:3000` |
| `PORT` | `3006` |
| `GRPC_PORT` | `50055` |

### eta-service
| Variable | Value |
|----------|-------|
| `GOOGLE_MAPS_API_KEY` | Google Maps API key |
| `CLINIC_LAT` | Clinic latitude (e.g. `1.4172`) |
| `CLINIC_LNG` | Clinic longitude (e.g. `103.8330`) |
| `GRPC_PORT` | `50054` |

### notification-service
| Variable | Value |
|----------|-------|
| `RABBITMQ_URL` | CloudAMQP connection string |
| `PATIENT_SERVICE_GRPC_URL` | `patient-service.railway.internal:50053` |

### stripe-service
| Variable | Value |
|----------|-------|
| `STRIPE_API_KEY` | Stripe secret key |
| `STRIPE_WEBHOOK_SIGNING_SECRET` | Stripe webhook signing secret |
| `RABBITMQ_URL` | CloudAMQP connection string |
| `FRONTEND_BASE_URL` | Frontend URL (for success/cancel redirects) |

### payment-service
| Variable | Value |
|----------|-------|
| `DATABASE_URL` | Supabase connection string |
| `RABBITMQ_URL` | CloudAMQP connection string |

### composite-appointment
| Variable | Value |
|----------|-------|
| `AUTH_SERVICE_URL` | `http://smart-clinic-queue-esd.railway.internal:3000` |
| `APPOINTMENT_SERVICE_URL` | `http://laudable-nourishment.railway.internal:3001` |
| `RABBITMQ_URL` | CloudAMQP connection string |

### composite-patient-orchestrator
| Variable | Value |
|----------|-------|
| `AUTH_SERVICE_URL` | `http://smart-clinic-queue-esd.railway.internal:3000` |
| `PATIENT_SERVICE_GRPC` | `patient-service.railway.internal:50053` |
| `RABBITMQ_URL` | CloudAMQP connection string |
| `PORT` | `8001` |

### composite-consultation
| Variable | Value |
|----------|-------|
| `AUTH_SERVICE_URL` | `http://smart-clinic-queue-esd.railway.internal:3000` |
| `APPOINTMENT_SERVICE_URL` | appointment-service internal URL |
| `PATIENT_SERVICE_GRPC` | `patient-service.railway.internal:50053` |
| `DOCTOR_SERVICE_GRPC` | `doctor-service.railway.internal:50055` |
| `PAYMENT_SERVICE_GRPC` | `stripe-service.railway.internal:50051` |
| `RABBITMQ_URL` | CloudAMQP connection string |

### kong
| Variable | Value |
|----------|-------|
| `AUTH_SERVICE_URL` | `http://smart-clinic-queue-esd.railway.internal:3000` |
| `COMPOSITE_APPOINTMENT_URL` | `http://appointment-composite.railway.internal:8000` |
| `COMPOSITE_PATIENT_URL` | `http://composite-patient-orchestrator.railway.internal:8001` |
| `COMPOSITE_CONSULTATION_URL` | composite-consultation internal URL |
| `COMPOSITE_STAFF_URL` | composite-staff-orchestrator internal URL |
| `CHECKIN_ORCHESTRATOR_URL` | checkin-orchestrator internal URL |
| `QUEUE_COORDINATOR_URL` | `http://queue-coordinator-service.railway.internal:3002` |
| `PAYMENT_SERVICE_URL` | payment-service internal URL |
| `DOCTOR_SERVICE_URL` | doctor-service internal URL |
| `BETTER_AUTH_RSA_PUBLIC_KEY` | RSA public key PEM (from `infra/scripts/extract-jwks-pem.sh`) |

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
# repeat for other services — fill in Supabase, CloudAMQP, Stripe credentials
```

### 3. Run the database migration

Run `infra/migrations/schema.sql` against your Supabase database once.

### 4. Seed test users

```bash
sh infra/scripts/seed-users.sh
```

Creates a doctor, staff, and patient account for testing.

### 5. Start all services

```bash
cd infra
docker compose up --build
```

### 6. Forward Stripe webhooks (for payment testing)

```bash
stripe login
stripe listen --forward-to localhost:8086/api/payments/webhook
# Copy the webhook signing secret → set STRIPE_WEBHOOK_SIGNING_SECRET in infra/env/stripe-service.env
# Then: docker compose up -d --build stripe-service
```

### 7. Run E2E tests

```bash
sh infra/tests/test-patient-journey.sh
sh infra/tests/test-consultation.sh
```

## Kong Configuration

Kong runs in **DB-less mode** with a declarative config generated at startup.

- Template: `infra/kong/kong.yml` (processed by `infra/kong/entrypoint.sh`)
- Entrypoint converts the multiline RSA PEM to a single-line `\n`-escaped string and runs `envsubst`
- JWT plugin validates RS256 tokens on all non-auth routes using the BetterAuth public key

To extract the RSA public key after deploying auth-service:
```bash
sh infra/scripts/extract-jwks-pem.sh https://your-auth-service-url.railway.app
# Copy the PEM output → set as BETTER_AUTH_RSA_PUBLIC_KEY in Kong's Railway env vars
```

## CI/CD

- **PR checks** (`.github/workflows/pr-check.yml`): lint + unit tests + GitGuardian secret scan
- **Per-service deploys** (`.github/workflows/deploy-*.yml`): auto-deploy to Railway on push to `main`

> Deploy workflows only trigger on `main`. For feature branches, use `railway up --service <name> --detach` or push an empty commit after merging.

## Architecture Principles

- **Atomic services** do not call each other directly — all cross-service orchestration goes through composite services
- **Composite services** call multiple atomics and publish RabbitMQ events
- **Wrapper services** wrap external APIs (Google Maps, Stripe, Twilio) and expose gRPC or HTTP interfaces
- **Synchronous calls** for critical state changes that must succeed before proceeding (e.g. creating payment link)
- **Async MQ events** for side effects (notifications, logging, queue updates, payment history)

## Contributing

1. Create a branch from `main`
2. Make changes and push
3. Open a PR — all checks must pass before merging
4. Never commit `.env` files — use `.env.example` to document required variables

## Adding a New Service

### Dockerfile (Railway requires repo-root build context)

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY services/your-service/package*.json ./
RUN npm ci
COPY services/your-service/src ./src
RUN npm run build
EXPOSE 3001
CMD ["npm", "run", "start"]
```

### Railway setup

1. Dashboard → **New Service** → **GitHub Repo**
2. Settings → Source → Dockerfile Path: `/services/your-service/Dockerfile`
3. Add required env vars
4. Create `.github/workflows/deploy-your-service.yml` (copy an existing one)
