## Minimal bash-only image for Mongo backups to Azure Blob Storage
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl bash gnupg lsb-release; \
    arch="$(dpkg --print-architecture)"; \
    release="$(lsb_release -cs)"; \
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb.gpg; \
    echo "deb [ arch=${arch} signed-by=/usr/share/keyrings/mongodb.gpg ] https://repo.mongodb.org/apt/debian ${release}/mongodb-org/7.0 main" > /etc/apt/sources.list.d/mongodb-org-7.0.list; \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg; \
    echo "deb [arch=${arch} signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${release} main" > /etc/apt/sources.list.d/azure-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends mongodb-database-tools mongosh azure-cli; \
    apt-get purge -y --auto-remove gnupg; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/.cache;

WORKDIR /opt/backup

COPY mongo_backup_simple.sh ./
RUN chmod +x /opt/backup/mongo_backup_simple.sh

# Create non-root user
RUN useradd -r -u 1001 -d /opt/backup backup && chown -R backup:backup /opt/backup
USER backup

ENTRYPOINT ["/opt/backup/mongo_backup_simple.sh"]
