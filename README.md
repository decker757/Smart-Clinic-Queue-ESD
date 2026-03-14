# Smart-Clinic-Queue-ESD

A polyclinic queue management system built with an event-driven microservices architecture.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| API Gateway | Kong (DB-less, declarative config) |
| Message Broker | RabbitMQ (CloudAMQP) |
| Database | PostgreSQL (Supabase) |
| Cache | Redis |
| Auth | BetterAuth (RS256 JWT) |
| Frontend | Vue 3 + Vite + Tailwind CSS |
| Infrastructure | Docker Compose (local) / Railway (production) |

## Architecture

```
Client (Vue 3)
  │
  ▼ GraphQL (planned) / REST
Kong API Gateway  (RS256 JWT validation)
  ├── /api/auth/*                    → auth-service:3000
  ├── /api/composite/appointments    → composite-appointment:8000
  ├── /api/composite/consultation    → composite-consultation (planned)
  └── /api/queue/*                   → queue-coordinator-service:3002

Composite Services
  ├── composite-appointment          → appointment-service, RabbitMQ
  └── composite-consultation         → patient-service, doctor-service,
                                        appointment-service, payment-service, RabbitMQ

RabbitMQ clinic.events (topic exchange)
  ├── appointment.booked             → queue-coordinator-service
  ├── appointment.cancelled          → queue-coordinator-service
  └── consultation.completed         → notification-service, queue-coordinator-service,
                                        activity-log-service
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

### Wrapper Services

| Service | Port | gRPC Port | Language | Description |
|---------|------|-----------|----------|-------------|
| `eta-service` | — | 50054 | Node.js + TypeScript | Google Maps travel time |
| `notification-service` | 3004 | — | Node.js + TypeScript | SMS/email via Twilio |
| `payment-service` | — | — | TBD | Stripe payment links (planned) |

### Composite Services

| Service | Port | Language | Description |
|---------|------|----------|-------------|
| `composite-appointment` | 8000 | Python + FastAPI | Patient books/cancels appointments |
| `composite-consultation` | TBD | Python + FastAPI | Doctor completes consultation, issues MC, triggers payment |

### Frontend

| Service | Port | Language |
|---------|------|----------|
| `frontend` | 5173 | Vue 3 + Vite + Tailwind CSS |

## Scenarios

### Scenario 1 — Patient Books Appointment
1. Patient submits booking via frontend
2. `composite-appointment` calls `appointment-service` → creates appointment
3. Publishes `appointment.booked` → `queue-coordinator` adds patient to queue
4. ETA service tracks travel time + queue wait time to notify patient when to leave

### Scenario 3 — Doctor Completes Consultation
1. Doctor submits consultation notes, MC, prescription via staff dashboard
2. `composite-consultation` (synchronously):
   - Calls `patient-service` → stores MC + prescription as patient records
   - Calls `doctor-service` → stores consultation notes
   - Calls `appointment-service` → marks appointment as `completed`
   - Calls `payment-service` → creates Stripe payment link
3. Publishes `consultation.completed` with payment link
4. `notification-service` sends patient payment link + MC/prescription
5. `queue-coordinator` removes patient from queue
6. `activity-log-service` logs the event

## Database Schemas (Supabase)

| Schema | Used by | Migration |
|--------|---------|-----------|
| `betterauth` | auth-service | BetterAuth auto-migration |
| `appointments` | appointment-service | `infra/migrations/001_appointments.sql` |
| `queue` | queue-coordinator-service | `infra/migrations/002_queue.sql` |
| `activity_log` | activity-log-service | `infra/migrations/003_activity_log.sql` |
| `patients` | patient-service | `infra/migrations/004_patients.sql` |
| `doctors` | doctor-service | `infra/migrations/005_doctors.sql` |

### patients.memos record_type values
| record_type | Created by | Visible to |
|-------------|------------|------------|
| `memo` | Patient (upload/text) | Patient |
| `mc` | Doctor (via composite-consultation) | Patient |
| `prescription` | Doctor (via composite-consultation) | Patient |

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
  -H "Cookie: __Secure-better-auth.session_token=<session-token>"

# 3. Use JWT on protected routes
curl -H "Authorization: Bearer <jwt>" https://kong-production-5d53.up.railway.app/api/...
```

### Queue flow

```bash
# Book appointment (composite service, JWT required)
POST /api/composite/appointments
{ "patient_id": "...", "session": "morning" }
# → creates appointment, fires appointment.booked RabbitMQ event
# → queue-coordinator adds patient to queue

# Check queue position (Redis-cached, 10s TTL)
GET /api/queue/position/:appointment_id

# Check in
POST /api/queue/checkin/:appointment_id

# Doctor calls next
POST /api/queue/call-next
{ "session": "morning" }

# Mark no-show
POST /api/queue/no-show/:appointment_id

# Reset queue (end of day)
POST /api/queue/reset
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

### composite-appointment
| Variable | Value |
|----------|-------|
| `AUTH_SERVICE_URL` | `http://smart-clinic-queue-esd.railway.internal:3000` |
| `APPOINTMENT_SERVICE_URL` | `http://laudable-nourishment.railway.internal:3001` |
| `RABBITMQ_URL` | CloudAMQP connection string |

### queue-coordinator-service
| Variable | Value |
|----------|-------|
| `DATABASE_URL` | Supabase connection string |
| `RABBITMQ_URL` | CloudAMQP connection string |
| `REDIS_URL` | Railway Redis connection string |
| `PORT` | `3002` |

### patient-service
| Variable | Value |
|----------|-------|
| `DATABASE_URL` | Supabase connection string (`search_path=patients`) |
| `AUTH_SERVICE_URL` | `http://smart-clinic-queue-esd.railway.internal:3000` |
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | Supabase service role key |
| `SUPABASE_BUCKET` | `patient-memos` |
| `PORT` | `3007` |
| `GRPC_PORT` | `50053` |

### doctor-service
| Variable | Value |
|----------|-------|
| `DATABASE_URL` | Supabase connection string (`search_path=doctors`) |
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
| `PATIENT_SERVICE_GRPC_URL` | `patient-service:50053` |

### kong
| Variable | Value |
|----------|-------|
| `AUTH_SERVICE_URL` | `http://smart-clinic-queue-esd.railway.internal:3000` |
| `COMPOSITE_APPOINTMENT_URL` | `http://appointment-composite.railway.internal:8000` |
| `QUEUE_COORDINATOR_URL` | `http://queue-coordinator-service.railway.internal:3002` |
| `BETTER_AUTH_RSA_PUBLIC_KEY` | RSA public key PEM (from `infra/scripts/extract-jwks-pem.sh`) |
| `PORT` | `8000` |

## Local Development

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Node.js](https://nodejs.org/) v22+
- [Go](https://golang.org/) 1.22+
- [Python](https://www.python.org/) 3.13+

### 1. Clone the repo

```bash
git clone https://github.com/your-org/Smart-Clinic-Queue-ESD.git
cd Smart-Clinic-Queue-ESD
```

### 2. Set up environment variables

```bash
cp infra/env/auth.env.example infra/env/auth.env
# repeat for other services, fill in Supabase + CloudAMQP credentials
```

### 3. Start all services

```bash
cd infra
docker compose up --build
```

### 4. Run a service individually

```bash
# auth-service
cd services/auth-service && npm install && npm run dev

# appointment-service
cd services/appointment-service && go run .

# composite-appointment
cd composite/appointment && pip install -r requirements.txt && uvicorn src.main:app --reload --port 8080

# queue-coordinator
cd services/queue-coordinator-service && npm install && npm run dev

# patient-service
cd services/patient-service && npm install && npm run dev

# doctor-service
cd services/doctor-service && npm install && npm run dev

# eta-service
cd wrappers/eta-service && npm install && npm run dev

# notification-service
cd wrappers/notification-service && npm install && npm run dev
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
- **Synchronous calls** for critical state changes that must succeed before proceeding
- **Async MQ events** for side effects (notifications, logging, queue updates)

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
COPY services/your-service/tsconfig.json ./
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
