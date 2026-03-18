FROM python:3.13-slim

WORKDIR /app

COPY composite/consultation/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY composite/consultation/src ./src

EXPOSE 8002

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8002"]
