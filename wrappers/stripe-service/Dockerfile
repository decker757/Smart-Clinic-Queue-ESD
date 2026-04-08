FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Compile protobuf stubs into app/grpc/ and fix the generated relative import
RUN python -m grpc_tools.protoc \
    -I./app/proto \
    --python_out=./app/grpc \
    --grpc_python_out=./app/grpc \
    ./app/proto/payment.proto && \
    sed -i 's/^import payment_pb2/from app.grpc import payment_pb2/' ./app/grpc/payment_pb2_grpc.py

EXPOSE 8001
EXPOSE 50051

# HTTP webhook server (uvicorn) — gRPC server starts via FastAPI lifespan
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8001"]
