## Minimal bash-only image for Mongo backups to Azure Blob Storage
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl bash gnupg lsb-release mongodb-clients; \
    curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/azure-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends azure-cli; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*;

WORKDIR /opt/backup

COPY mongo_backup_simple.sh ./
RUN chmod +x /opt/backup/mongo_backup_simple.sh

# Create non-root user
RUN useradd -r -u 1001 -d /opt/backup backup && chown -R backup:backup /opt/backup
USER backup

ENTRYPOINT ["/opt/backup/mongo_backup_simple.sh"]
