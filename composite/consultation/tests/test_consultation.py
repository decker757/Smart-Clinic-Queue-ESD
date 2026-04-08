"""Unit tests for the consultation orchestrator."""
import pytest
import grpc
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport
from fastapi import HTTPException

# ── Test fixtures ─────────────────────────────────────────────

VALID_TOKEN = "test.jwt.token"
VALID_PAYLOAD = {"sub": "doctor-123", "iss": "smart-clinic"}

BASE_REQUEST = {
    "appointment_id": "appt-1",
    "patient_id": "patient-1",
    "doctor_id": "doctor-123",
    "diagnosis": "Common cold",
    "consultation_notes": "Rest and fluids",
    "mc_days": 2,
    "mc_start_date": "2026-03-20",
    "prescribed_medication": "Paracetamol 500mg",
}

HEADERS = {"Authorization": f"Bearer {VALID_TOKEN}"}


class MockRpcError(grpc.RpcError):
    def details(self):
        return "mocked gRPC error"

    def code(self):
        return grpc.StatusCode.INTERNAL


@pytest.fixture(autouse=True)
def mock_rabbitmq_lifecycle():
    """Prevent real RabbitMQ connections during tests."""
    with (
        patch("src.services.rabbitmq.connect", new_callable=AsyncMock),
        patch("src.services.rabbitmq.disconnect", new_callable=AsyncMock),
    ):
        yield


@pytest.fixture
def mock_auth():
    with patch("src.services.auth.verify_token", new_callable=AsyncMock) as m:
        m.return_value = VALID_PAYLOAD
        yield m


@pytest.fixture
def mock_patient():
    with (
        patch(
            "src.controller.consultation.patient_svc.create_doctor_record",
            new_callable=AsyncMock,
        ) as create,
        patch(
            "src.controller.consultation.patient_svc.add_history",
            new_callable=AsyncMock,
        ) as add_hist,
    ):
        create.return_value = MagicMock()
        add_hist.return_value = MagicMock()
        yield create, add_hist


@pytest.fixture
def mock_doctor():
    with patch(
        "src.controller.consultation.doctor_svc.add_consultation_notes",
        new_callable=AsyncMock,
    ) as m:
        m.return_value = MagicMock()
        yield m


@pytest.fixture
def mock_appointment():
    with patch(
        "src.controller.consultation.appointment_svc.mark_complete",
        new_callable=AsyncMock,
    ) as m:
        m.return_value = {}
        yield m


@pytest.fixture
def mock_payment():
    with patch(
        "src.controller.consultation.payment_svc.create_payment_request",
        new_callable=AsyncMock,
    ) as m:
        m.return_value = {
            "payment_link": "https://checkout.stripe.com/pay/test-link",
            "amount_cents": 5000,
            "currency": "sgd",
        }
        yield m


@pytest.fixture
def mock_publish():
    with patch(
        "src.controller.consultation.rabbitmq.publish_event",
        new_callable=AsyncMock,
    ) as m:
        yield m


@pytest.fixture
def mocks(mock_auth, mock_patient, mock_doctor, mock_appointment, mock_payment, mock_publish):
    return {
        "auth": mock_auth,
        "patient_create": mock_patient[0],
        "patient_history": mock_patient[1],
        "doctor": mock_doctor,
        "appointment": mock_appointment,
        "payment": mock_payment,
        "publish": mock_publish,
    }


# ── Helpers ───────────────────────────────────────────────────

async def post(body=None, headers=None):
    from src.main import app
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        return await client.post(
            "/api/composite/consultations/complete",
            json=BASE_REQUEST if body is None else body,
            headers=HEADERS if headers is None else headers,
        )


# ── Tests ─────────────────────────────────────────────────────

async def test_happy_path(mocks):
    res = await post()

    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "completed"
    assert body["appointment_id"] == "appt-1"
    assert body["payment_link"] == "https://checkout.stripe.com/pay/test-link"

    # MC + prescription both created
    assert mocks["patient_create"].call_count == 2
    mocks["appointment"].assert_called_once_with("appt-1", VALID_TOKEN)
    mocks["payment"].assert_called_once_with(appointment_id="appt-1", token=VALID_TOKEN)
    mocks["publish"].assert_called_once()
    event = mocks["publish"].call_args[0][1]
    assert event["mc_issued"] is True
    assert event["diagnosis"] == "Common cold"
    assert event["payment_link"] == "https://checkout.stripe.com/pay/test-link"


async def test_consultation_event_includes_payment_link(mocks):
    res = await post()

    assert res.status_code == 200
    event = mocks["publish"].call_args[0][1]
    assert event["payment_link"] == "https://checkout.stripe.com/pay/test-link"


async def test_no_mc_skips_mc_record(mocks):
    body = {**BASE_REQUEST, "mc_days": None, "mc_start_date": None}
    res = await post(body)

    assert res.status_code == 200
    # Only prescription record created (no MC)
    assert mocks["patient_create"].call_count == 1
    assert mocks["publish"].call_args[0][1]["mc_issued"] is False


async def test_unauthorized_wrong_doctor(mocks):
    """doctor_id in body must match the JWT sub claim."""
    body = {**BASE_REQUEST, "doctor_id": "other-doctor"}
    res = await post(body)
    assert res.status_code == 403


async def test_missing_auth_header():
    """No Authorization header → 422 (required field missing)."""
    res = await post(headers={})
    assert res.status_code == 422


async def test_invalid_bearer_format(mocks):
    """Non-Bearer scheme → 401."""
    res = await post(headers={"Authorization": "Token some-token"})
    assert res.status_code == 401


async def test_mc_record_grpc_failure_returns_500(mocks):
    """gRPC error creating MC record aborts with 500."""
    mocks["patient_create"].side_effect = MockRpcError()

    res = await post()

    assert res.status_code == 500
    assert "MC" in res.json()["detail"]
    mocks["appointment"].assert_not_called()
    mocks["payment"].assert_not_called()
    mocks["publish"].assert_not_called()


async def test_appointment_failure_returns_500(mocks):
    """Appointment service error aborts with 500."""
    mocks["appointment"].side_effect = HTTPException(
        status_code=500, detail="appointment-service unavailable"
    )

    res = await post()

    assert res.status_code == 500
    mocks["payment"].assert_not_called()
    mocks["publish"].assert_not_called()


async def test_payment_failure_returns_error(mocks):
    mocks["payment"].side_effect = HTTPException(status_code=502, detail="payment-service unavailable")

    res = await post()

    assert res.status_code == 502
    mocks["publish"].assert_not_called()


async def test_doctor_notes_failure_is_non_critical(mocks):
    """Doctor-service failure storing notes does not fail the request."""
    mocks["doctor"].side_effect = MockRpcError()

    res = await post()

    assert res.status_code == 200
    mocks["appointment"].assert_called_once()
    mocks["publish"].assert_called_once()


async def test_diagnosis_history_failure_is_non_critical(mocks):
    """add_history failure does not fail the request."""
    mocks["patient_history"].side_effect = MockRpcError()

    res = await post()

    assert res.status_code == 200
    mocks["appointment"].assert_called_once()
    mocks["publish"].assert_called_once()


async def test_invalid_mc_start_date_rejected(mock_auth):
    """Non-date mc_start_date is rejected by pydantic before reaching the controller."""
    body = {**BASE_REQUEST, "mc_start_date": "not-a-date"}
    res = await post(body=body)
    assert res.status_code == 422
