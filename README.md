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

## Infrastructure

- **Kong Admin UI**: `http://localhost:8001`
- **RabbitMQ Management UI**: `http://localhost:15672` (guest/guest)
