FROM python:3.11-slim

WORKDIR /app

COPY composite/staff-orchestrator/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY composite/staff-orchestrator/src ./src

RUN python -m grpc_tools.protoc \
    -I. \
    --python_out=. \
    --grpc_python_out=. \
    src/proto/doctor.proto \
    src/proto/queue.proto \
    src/proto/patient.proto

ENV PYTHONPATH=/app

EXPOSE 8004

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8004"]
