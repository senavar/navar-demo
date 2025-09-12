#!/bin/bash
set -euo pipefail

KV_NAME="${kv_name}"
SECRET_NAME="${secret_name}"
APP_USER="${app_user}"
PRIVATE_IP="${private_ip}"
UAMI_CLIENT_ID="${uami_client_id}" # injected by terraform template (may be empty)

MONGO_VERSION="6.0.0"
PKG="mongodb-linux-x86_64-ubuntu1804-$MONGO_VERSION.tgz"
URL="https://fastdl.mongodb.org/linux/$PKG"
# Separate shell (mongosh) - legacy 'mongo' client not bundled with server 6.x
MONGOSH_VERSION="2.2.10"
MONGOSH_PKG="mongosh-$MONGOSH_VERSION-linux-x64.tgz"
MONGOSH_URL="https://downloads.mongodb.com/compass/$MONGOSH_PKG"
INSTALL_DIR="/opt/mongodb-$MONGO_VERSION"
PASS_FILE="/root/.mongo_credentials"

log(){ echo "[$(date +'%F %T')] $*"; }

log "Starting MongoDB $MONGO_VERSION bootstrap."

apt-get update -y
apt-get install -y curl tar jq wget ca-certificates || true

if ! command -v mongod >/dev/null 2>&1; then
  log "Installing MongoDB binaries (tarball)..."
  curl -fSL "$URL" -o "/tmp/$PKG"
  mkdir -p "$INSTALL_DIR"
  tar -xzf "/tmp/$PKG" -C "$INSTALL_DIR" --strip-components=1
  ln -sf "$INSTALL_DIR"/bin/* /usr/local/bin/
  rm -f "/tmp/$PKG"
else
  log "MongoDB already present; skipping binary install."
fi

# Install mongosh if not present
if ! command -v mongosh >/dev/null 2>&1; then
  log "Installing mongosh shell $MONGOSH_VERSION..."
  curl -fSL "$MONGOSH_URL" -o "/tmp/$MONGOSH_PKG"
  tar -xzf "/tmp/$MONGOSH_PKG" -C /tmp
  install -m 0755 "/tmp/mongosh-$MONGOSH_VERSION-linux-x64/bin/mongosh" /usr/local/bin/mongosh
  ln -sf /usr/local/bin/mongosh /usr/local/bin/mongo || true
  rm -rf "/tmp/mongosh-$MONGOSH_VERSION-linux-x64" "/tmp/$MONGOSH_PKG"
else
  log "mongosh already installed; skipping."
fi

MONGO_SHELL="mongosh"

id -u mongod >/dev/null 2>&1 || useradd --system --no-create-home --shell /bin/false mongod
mkdir -p /var/lib/mongo /var/log/mongodb
chown -R mongod:mongod /var/lib/mongo /var/log/mongodb
rm -f /var/lib/mongo/mongod.lock || true

cat >/etc/mongod.conf <<'EOF'
storage:
  dbPath: /var/lib/mongo
  journal:
    enabled: true
systemLog:
  destination: file
  path: /var/log/mongodb/mongod.log
  logAppend: true
net:
  port: 27017
  bindIp: 0.0.0.0
security:
  authorization: enabled
EOF
chown mongod:mongod /etc/mongod.conf

cat >/etc/systemd/system/mongod.service <<'EOF'
[Unit]
Description=MongoDB (tarball)
After=network.target

[Service]
User=mongod
Group=mongod
ExecStart=/usr/local/bin/mongod --config /etc/mongod.conf
Restart=on-failure
LimitNOFILE=64000
Type=simple

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mongod
systemctl restart mongod || systemctl start mongod

log "Waiting for mongod readiness..."
for i in $(seq 1 30); do
  if $MONGO_SHELL --quiet --eval 'db.runCommand({ping:1})' >/dev/null 2>&1; then
    log "mongod ready (attempt $i)"
    break
  fi
  sleep 2
  if [ "$i" = 30 ]; then
    log "ERROR: mongod failed to become ready"
    journalctl -u mongod --no-pager | tail -n 80 || true
    exit 1
  fi
done

# Persist / reuse password
if [ ! -f "$PASS_FILE" ]; then
  head -c 48 /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32 > "$PASS_FILE"
  chmod 600 "$PASS_FILE"
fi
APP_PASS=$(cat "$PASS_FILE")

# Create admin user if missing
if ! $MONGO_SHELL admin --quiet --eval "db.system.users.find({user:'admin'}).count()" | grep -q '^1$'; then
  log "Creating admin user."
  $MONGO_SHELL admin --quiet --eval "db.createUser({user:'admin',pwd:'$APP_PASS',roles:[{role:'root',db:'admin'}]})"
else
  log "Admin user exists."
fi

# Create app user if missing
if ! $MONGO_SHELL admin -u admin -p "$APP_PASS" --quiet --authenticationDatabase admin --eval "db.getSiblingDB('app').getUser('$APP_USER') != null" | grep -q 'true'; then
  log "Creating app user '$APP_USER'."
  $MONGO_SHELL admin -u admin -p "$APP_PASS" --authenticationDatabase admin --quiet --eval "db.getSiblingDB('app').createUser({user:'$APP_USER',pwd:'$APP_PASS',roles:[{role:'readWriteAnyDatabase',db:'admin'}]})"
else
  log "App user '$APP_USER' exists."
fi

CONN_STR="mongodb://$APP_USER:$APP_PASS@$PRIVATE_IP:27017/app?authSource=app"
log "Pushing connection string to Key Vault '$KV_NAME' (secret: $SECRET_NAME)."

KV_FQDN="$KV_NAME.vault.azure.net"
PAYLOAD=$(jq -n --arg v "$CONN_STR" '{"value":$v,"contentType":"mongodb-uri"}')
# 
for i in $(seq 1 20); do
  if [ -n "$UAMI_CLIENT_ID" ]; then
  TOKEN=$(curl -sS -H Metadata:true "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net&client_id=$UAMI_CLIENT_ID" | jq -r .access_token || true)
  else
    TOKEN=$(curl -sS -H Metadata:true "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net" | jq -r .access_token || true)
  fi
  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    log "[attempt $i] Managed identity token not yet available."
    sleep 5
    continue
  fi

  RESP_FILE="/tmp/kv_put_resp.json"
  CODE=$(curl -sS -D - -o "$RESP_FILE" -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
  "https://$KV_FQDN/secrets/$SECRET_NAME?api-version=7.3" \
    | awk 'NR==1 {print $2}' || echo "000")

  if [ "$CODE" = "200" ] || [ "$CODE" = "201" ]; then
    log "Secret stored successfully (HTTP $CODE)."
    rm -f "$RESP_FILE"
    exit 0
  fi

  # Extract error message if possible
  if [ -s "$RESP_FILE" ]; then
    ERR=$(jq -r '.error.message // .error // empty' "$RESP_FILE" 2>/dev/null || true)
  else
    ERR="(empty response)"
  fi
  if [ -n "$ERR" ]; then
    log "[attempt $i] Secret push failed (HTTP $CODE) - $ERR"
  else
    log "[attempt $i] Secret push failed (HTTP $CODE)"
  fi
  sleep 5
done

log "WARNING: Secret not stored after retries; leaving without failing VM provisioning."
exit 0