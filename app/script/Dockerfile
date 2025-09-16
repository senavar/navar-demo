# Minimal image for Mongo backup job
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install system deps (mongodb-clients provides mongodump)
RUN apt-get update \
    && apt-get install -y --no-install-recommends mongodb-clients ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /opt/backup

# Copy script
COPY mongo_backup.py ./

# Install Python dependencies (pin loosely; adjust if you need repeatable build via hash constraints)
RUN pip install --no-cache-dir azure-identity==1.* azure-storage-blob==12.* pymongo==4.*

# Non-root user for better security
RUN useradd -r -u 1001 backup && chown -R backup:backup /opt/backup
USER backup

ENTRYPOINT ["python","/opt/backup/mongo_backup.py"]
