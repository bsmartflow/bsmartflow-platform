# ============================================================
# ✅ BsmartFlow ACC Bridge - Cloud Run Deployment (Stable)
# ============================================================

FROM python:3.11-slim
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY . .
ENV PORT=8080
ENV PYTHONUNBUFFERED=1
EXPOSE 8080

# Start Flask app via Gunicorn (Cloud Run compatible)
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 bridge_main:app
