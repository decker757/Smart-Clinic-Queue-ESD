FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN python -m grpc_tools.protoc \
    -I./src/proto \
    --python_out=./src/proto \
    --grpc_python_out=./src/proto \
    ./src/proto/doctor.proto \
    ./src/proto/queue.proto \
    ./src/proto/patient.proto

ENV PYTHONPATH=/app

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8004"]
