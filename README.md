# Smart-Clinic-Queue-ESD

A clinic queue management system built with an event-driven microservices architecture.

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
Client
  │
  ▼
Kong API Gateway  (RS256 JWT validation)
  ├── /api/auth/*              → auth-service:3000
  ├── /api/composite/appointments → composite-appointment:8000
  └── /api/queue/*             → queue-coordinator-service:3002

composite-appointment
  ├── calls → appointment-service:3001  (atomic)
  └── publishes → RabbitMQ clinic.events exchange

RabbitMQ clinic.events (topic exchange)
  ├── appointment.booked   → queue-coordinator-service
  └── appointment.cancelled → queue-coordinator-service

queue-coordinator-service
  ├── Postgres (queue schema) — persistent queue state
  └── Redis — cached queue positions (10s TTL)
```

## Services

| Service | Port | Language | Status |
|---------|------|----------|--------|
| `auth-service` | 3000 | Node.js + BetterAuth | Deployed |
| `appointment-service` | 3001 | Go + Gin | Deployed |
| `composite-appointment` | 8000 | Python + FastAPI | Deployed |
| `queue-coordinator-service` | 3002 | Node.js + Express | Deployed |
| `kong` | 8000 | Kong (DB-less) | Deployed |
| `eta-service` | 3003 | TBD | Not started |
| `notification-service` | 3004 | TBD | Not started |
| `activity-log-service` | 3005 | TBD | Not started |
| `frontend` | 5173 | Vue 3 | Not started |

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

## Database Schemas (Supabase)

| Schema | Used by | Migration |
|--------|---------|-----------|
| `betterauth` | auth-service | BetterAuth auto-migration |
| `appointments` | appointment-service | `infra/migrations/001_appointments.sql` |
| `queue` | queue-coordinator-service | `infra/migrations/002_queue.sql` |

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

### 3. Start infrastructure

```bash
cd infra
docker compose up kong rabbitmq app-db
```

### 4. Run a service

```bash
# auth-service
cd services/auth-service && npm install && npm run dev

# appointment-service
cd services/appointment-service && go run .

# composite-appointment
cd composite/appointment && pip install -r requirements.txt && uvicorn src.main:app --reload

# queue-coordinator
cd services/queue-coordinator-service && npm install && npm run dev
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
