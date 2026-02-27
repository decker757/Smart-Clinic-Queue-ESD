# Smart-Clinic-Queue-ESD

A clinic queue management system built with an event-driven microservices architecture.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| API Gateway | Kong |
| Message Broker | RabbitMQ |
| Database | PostgreSQL (Supabase) |
| Auth | BetterAuth |
| Frontend | Vue 3 + Vite + Tailwind CSS |
| Infrastructure | Docker Compose |

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Node.js](https://nodejs.org/) v22+
- Git

## Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/your-org/Smart-Clinic-Queue-ESD.git
cd Smart-Clinic-Queue-ESD
```

### 2. Set up environment variables

Each service has an env file under `infra/env/`. Copy the examples and fill in the values:

```bash
cp infra/env/auth.env.example infra/env/auth.env
# repeat for other services
```

For local development, also create a `.env` in each service directory:

```bash
cp services/auth-service/.env.example services/auth-service/.env
# fill in your Supabase connection string and secrets
```

### 3. Start the infrastructure

```bash
cd infra
docker compose up kong kong-db kong-migrations kong-setup rabbitmq app-db
```

### 4. Start a service locally (example: auth-service)

```bash
cd services/auth-service
npm install
npm run dev
```

### 5. Start the frontend

```bash
cd frontend/vue-app
npm install
npm run dev
```

Frontend will be available at `http://localhost:5173`

## Services

| Service | Port | Description |
|---------|------|-------------|
| `auth-service` | 3000 | Authentication (BetterAuth) |
| `appointment-service` | 3001 | Appointment management |
| `queue-coordinator-service` | 3002 | Queue orchestration |
| `eta-service` | 3003 | Estimated wait times |
| `notification-service` | 3004 | Notifications |
| `activity-log-service` | 3005 | Audit logging |

All services are proxied through Kong on port `8000`:
```
http://localhost:8000/api/auth/*         → auth-service
http://localhost:8000/api/appointments/* → appointment-service
http://localhost:8000/api/queue/*        → queue-coordinator-service
http://localhost:8000/api/eta/*          → eta-service
http://localhost:8000/api/notifications/* → notification-service
http://localhost:8000/api/activity/*     → activity-log-service
```

## Contributing

### Workflow

1. Create a branch from `main`
   ```bash
   git checkout -b feature/your-feature
   ```
2. Make your changes
3. Push and open a Pull Request to `main`
4. All checks must pass before merging:
   - Lint
   - Unit Tests
   - Secret Scan (GitGuardian)
5. Get at least one review before merging

### ⚠️ Never commit `.env` files

Sensitive credentials are gitignored. Use `.env.example` files to document required variables without values.

## Adding a New Service

### Dockerfile requirements for Railway

Railway builds from the **repo root** as the build context. Your Dockerfile must use paths relative to the repo root, not the service directory.

**Node.js service (use this as a template):**

```dockerfile
FROM node:22-alpine

WORKDIR /app

COPY services/your-service-name/package*.json ./
RUN npm ci

COPY services/your-service-name/tsconfig.json ./
COPY services/your-service-name/src ./src

RUN npm run build

EXPOSE 3001

CMD ["npm", "run", "start"]
```

**Python service:**

```dockerfile
FROM python:3.12-slim

WORKDIR /app

COPY services/your-service-name/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY services/your-service-name/src ./src

EXPOSE 3001

CMD ["python", "src/main.py"]
```

> ⚠️ The key difference from a standard Dockerfile is that `COPY` paths must include the full path from the repo root (e.g. `services/your-service-name/src`) instead of just `src`.

### Railway setup for a new service

1. In Railway dashboard → **New Service** → **GitHub Repo**
2. **Settings → Source**:
   - Dockerfile Path: `/services/your-service-name/Dockerfile`
   - Watch Paths: `/services/your-service-name/src`
3. **Variables** → add all required env vars
4. The deploy workflow in `.github/workflows/deploy-your-service.yml` will auto-deploy on merge to `main`

## Infrastructure

- **Kong Admin UI**: `http://localhost:8001`
- **RabbitMQ Management UI**: `http://localhost:15672` (guest/guest)
