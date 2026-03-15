FROM python:3.13-slim

WORKDIR /app

COPY composite/patient-orchestrator/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY composite/patient-orchestrator/src ./src

EXPOSE 8001

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8001"]
