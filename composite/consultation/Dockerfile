FROM python:3.12-slim

WORKDIR /app

COPY composite/consultation/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY composite/consultation/src ./src

# Generate gRPC stubs from .proto source files
RUN python -m grpc_tools.protoc \
    -I. \
    --python_out=. \
    --grpc_python_out=. \
    src/proto/doctor.proto \
    src/proto/patient.proto \
    src/proto/queue.proto \
    src/proto/payment.proto

ENV PYTHONPATH=/app

EXPOSE 8002

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8002"]
