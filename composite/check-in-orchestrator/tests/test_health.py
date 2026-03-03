import os

from fastapi.testclient import TestClient

os.environ.setdefault("APPOINTMENT_SERVICE_URL", "http://appointment-service")
os.environ.setdefault("QUEUE_SERVICE_URL", "http://queue-service")
os.environ.setdefault("ETA_SERVICE_URL", "http://eta-service")
os.environ.setdefault("NOTIFICATION_SERVICE_URL", "http://notification-service")

from app.main import app


client = TestClient(app)


def test_health_returns_ok() -> None:
    response = client.get("/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["service"] == "check-in-orchestrator"
