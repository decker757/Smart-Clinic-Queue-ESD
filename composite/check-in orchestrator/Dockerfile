# Use official Python image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy requirements first (for caching layers)
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the full app code
COPY app ./app

# Compile protobuf definitions and fix the generated relative import
RUN python -m grpc_tools.protoc \
    -I./app/proto \
    --python_out=./app/proto \
    --grpc_python_out=./app/proto \
    ./app/proto/eta.proto && \
    sed -i 's/^import eta_pb2/from app.proto import eta_pb2/' ./app/proto/eta_pb2_grpc.py

# Expose FastAPI port
EXPOSE 8000

# Command to run FastAPI
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]