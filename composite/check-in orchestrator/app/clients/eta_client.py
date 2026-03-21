import grpc
from app.config.settings import settings
from app.proto import eta_pb2, eta_pb2_grpc

async def get_travel_time(patient_location, clinic_location):
    async with grpc.aio.insecure_channel(
        f"{settings.ETA_SERVICE_HOST}:{settings.ETA_SERVICE_PORT}"
    ) as channel:

        stub = eta_pb2_grpc.ETAServiceStub(channel)

        response = await stub.GetTravelTime(
            eta_pb2.TravelRequest(
                patient_location=patient_location,
                clinic_location=clinic_location,
            ),
            timeout=2.0
        )

        return response.minutes