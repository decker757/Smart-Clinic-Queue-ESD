import logging
import grpc
from app.config.settings import settings
from app.proto import eta_pb2, eta_pb2_grpc

logger = logging.getLogger(__name__)

DEFAULT_ETA_MINUTES = 15  # fallback when ETA service is unavailable


async def get_travel_time(patient_location, clinic_location) -> int:
    try:
        async with grpc.aio.insecure_channel(
            f"{settings.ETA_SERVICE_HOST}:{settings.ETA_SERVICE_PORT}"
        ) as channel:
            stub = eta_pb2_grpc.ETAServiceStub(channel)
            request = eta_pb2.TravelTimeRequest(
                origin_lat=patient_location.lat,
                origin_lng=patient_location.lng,
                dest_lat=clinic_location.lat,
                dest_lng=clinic_location.lng,
            )
            response = await stub.GetTravelTime(request, timeout=2.0)
            return response.travel_minutes
    except grpc.aio.AioRpcError as e:
        logger.warning("ETA service unavailable (%s), using default %dm", e.code(), DEFAULT_ETA_MINUTES)
        return DEFAULT_ETA_MINUTES
