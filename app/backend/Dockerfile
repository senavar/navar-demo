FROM python:3.11-slim
ENV PIP_NO_CACHE_DIR=1 \
	PYTHONDONTWRITEBYTECODE=1 \
	PYTHONUNBUFFERED=1 \
	GUNICORN_WORKERS=2 \
	GUNICORN_THREADS=4 \
	APP_PORT=8000
WORKDIR /app

# Install dependencies first for better layer caching
COPY requirements.txt .
RUN pip install --upgrade pip && pip install --no-cache-dir -r requirements.txt

# Copy application source afterward
COPY . .

# Create non-root user and adjust permissions
RUN useradd --create-home --uid 10001 appuser \
	&& mkdir -p instance/uploads \
	&& chown -R appuser:appuser /app
USER appuser

EXPOSE ${APP_PORT}

# Use shell form so environment variable expansion works for APP_PORT
CMD ["sh", "-c", "gunicorn --bind 0.0.0.0:${APP_PORT} --workers=${GUNICORN_WORKERS} --threads=${GUNICORN_THREADS} --preload wsgi:app"]