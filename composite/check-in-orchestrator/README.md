# Check-In Orchestrator

Production-ready FastAPI microservice that orchestrates clinic check-in flow across Appointment, ETA, Queue, and Notification services using HTTP-only communication.

## Features

- REST API with FastAPI
- Pydantic request/response validation
- HTTPX inter-service calls with retry and exponential backoff
- Structured JSON logging
- Centralized error handling
- Idempotent `POST /check-in` (per `appointment_id`, in-process)
- `GET /health` endpoint
- Docker support
- Environment variables via `python-dotenv`

## Folder Structure

```text
check-in-orchestrator/
├── app/
│   ├── api/
│   │   └── routes.py
│   ├── services/
│   │   └── checkin_service.py
│   ├── clients/
│   │   ├── base_client.py
│   │   ├── appointment_client.py
│   │   ├── queue_client.py
│   │   ├── eta_client.py
│   │   └── notification_client.py
│   ├── models/
│   │   └── checkin_models.py
│   ├── core/
│   │   ├── config.py
│   │   ├── logging.py
│   │   └── exceptions.py
│   └── main.py
├── tests/
├── Dockerfile
├── requirements.txt
├── .env.example
└── README.md
```

## Run Locally

```bash
cd composite/check-in-orchestrator
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8080
```

## API

### Health Check

```bash
curl -X GET http://localhost:8080/health
```

Response:

```json
{
  "status": "ok",
  "service": "check-in-orchestrator",
  "version": "1.0.0"
}
```

### Check-In

```bash
curl -X POST http://localhost:8080/check-in \
  -H "Content-Type: application/json" \
  -d '{
    "appointment_id": "appt-123",
    "live_location": {"lat": 1.3521, "lng": 103.8198}
  }'
```

Example response:

```json
{
  "appointment_id": "appt-123",
  "queue_status": "CHECKED_IN",
  "eta_minutes": 12,
  "notification_sent": true,
  "idempotent_replay": false,
  "checked_in_at": "2026-03-03T10:00:00Z"
}
```

Repeated calls for the same `appointment_id` return the previously computed response with `idempotent_replay=true` without re-triggering side effects.

## Docker

```bash
cd composite/check-in-orchestrator
docker build -t check-in-orchestrator .
docker run --env-file .env -p 8080:8080 check-in-orchestrator
```

## Notes

- No direct imports from other microservices.
- Uses HTTP-only boundaries for service interaction.
- Current idempotency implementation is in-memory for simplicity. In multi-instance production, replace with Redis or database-backed idempotency storage.
