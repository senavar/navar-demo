FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    MONGO_MAJOR=7.0 \
    MONGO_TOOLS_PKG=mongodb-database-tools \
    MONGO_SHELL_PKG=mongosh \
    AZ_REPO_CODENAME=bookworm \
    LANG=C.UTF-8

RUN set -eux; \
    if id -u backup >/dev/null 2>&1; then \
        echo "User 'backup' already exists"; \
    else \
        useradd -r -u 1001 -d /opt/backup backup; \
    fi; \
    mkdir -p /opt/backup; \
    chown -R 1001:1001 /opt/backup

RUN set -eux; \
    apt-get update -o Acquire::Retries=3; \
    apt-get install -y --no-install-recommends ca-certificates curl bash gnupg lsb-release; \
    arch="$(dpkg --print-architecture)"; \
    codename="$(. /etc/os-release; echo "$VERSION_CODENAME")"; \
    if [ "$codename" = "trixie" ]; then codename=bookworm; fi; \
    # MongoDB repo
    curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGO_MAJOR}.asc | gpg --dearmor -o /usr/share/keyrings/mongodb.gpg; \
    echo "deb [ arch=${arch} signed-by=/usr/share/keyrings/mongodb.gpg ] https://repo.mongodb.org/apt/debian ${codename}/mongodb-org/${MONGO_MAJOR} main" > /etc/apt/sources.list.d/mongodb-org.list; \
    # Azure CLI repo
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg; \
    echo "deb [arch=${arch} signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${codename} main" > /etc/apt/sources.list.d/azure-cli.list; \
    # Update & upgrade security fixes
    apt-get update -o Acquire::Retries=3; \
    apt-get dist-upgrade -y --no-install-recommends; \
    # Install runtime tools
    apt-get install -y --no-install-recommends "${MONGO_TOOLS_PKG}" "${MONGO_SHELL_PKG}" azure-cli; \
    # Remove apt cruft & build keys
    apt-get purge -y --auto-remove gnupg lsb-release; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/.cache; \
    # Basic sanity checks
    command -v mongodump >/dev/null; \
    command -v az >/dev/null

WORKDIR /opt/backup
COPY --chown=backup:backup mongo_backup_simple.sh /opt/backup/mongo_backup_simple.sh
RUN chmod 0755 /opt/backup/mongo_backup_simple.sh

USER backup
ENTRYPOINT ["/opt/backup/mongo_backup_simple.sh"]