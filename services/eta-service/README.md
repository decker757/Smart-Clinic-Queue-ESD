# ETA Service

FastAPI microservice that calculates travel ETA from a patient location to clinic coordinates using Google Maps Distance Matrix API.

## Endpoint

- `POST /eta`

Request body:

```json
{
  "patient_lat": 1.3521,
  "patient_lng": 103.8198
}
```

Response body:

```json
{
  "distance_km": 5.42,
  "duration_minutes": 14
}
```

## Environment Variables

Example values are in `.env.example`:

```env
SERVICE_NAME=eta-service
SERVICE_VERSION=1.0.0
HOST=0.0.0.0
PORT=8081
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
GOOGLE_DISTANCE_MATRIX_URL=https://maps.googleapis.com/maps/api/distancematrix/json
CLINIC_LAT=1.3000
CLINIC_LNG=103.8000
TRAVEL_MODE=driving
REQUEST_TIMEOUT_SECONDS=8
```

## Run Locally

```bash
cd services/eta-service
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload --host 0.0.0.0 --port 8081
```

## Example cURL

```bash
curl -X POST http://localhost:8081/eta \
  -H "Content-Type: application/json" \
  -d '{"patient_lat":1.3521,"patient_lng":103.8198}'
```

## Docker

```bash
cd services/eta-service
docker build -t eta-service .
docker run --env-file .env -p 8081:8081 eta-service
```
