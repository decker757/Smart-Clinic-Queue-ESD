FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir grpcio grpcio-tools
COPY services/payment-service-stub/server.py .
EXPOSE 50056
CMD ["python", "server.py"]
