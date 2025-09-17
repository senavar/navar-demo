#!/usr/bin/env bash

set -euo pipefail

log() { echo "[mongo-backup-simple] $*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"; }
require mongodump
require az

MONGO_URI=${MONGO_URI:-}
DB=${MONGO_DB:-birthdays_db}
PREFIX=${BACKUP_PREFIX:-mongo-backup}
RETENTION=${RETENTION:-7}
ACCOUNT=${AZURE_STORAGE_ACCOUNT:-${AZURE_STORAGE_ACCOUNT_NAME:-}}
CONTAINER=${AZURE_STORAGE_CONTAINER:-${AZURE_BLOB_CONTAINER:-}}
DRY_RUN=${DRY_RUN:-0}

if [[ -z "$MONGO_URI" ]]; then
  # 1) Try an explicit file hint (MONGO_URI_FILE) if provided
  if [[ -n "${MONGO_URI_FILE:-}" && -f "$MONGO_URI_FILE" ]]; then
    MONGO_URI=$(head -n1 "$MONGO_URI_FILE" | tr -d '\r')
    log "Loaded MONGO_URI from $MONGO_URI_FILE"
  fi
fi

if [[ -z "$MONGO_URI" ]]; then
  # 2) Try common CSI Secrets Store mount paths
  for candidate in \
    /mnt/secrets-store/mongo-conn-string \
    /mnt/secrets-store/MONGO_URI \
    /var/run/secrets/mongo/connectionString; do
      if [[ -f "$candidate" ]]; then
        MONGO_URI=$(head -n1 "$candidate" | tr -d '\r')
        log "Loaded MONGO_URI from $candidate"
        break
      fi
    done
fi

if [[ -z "$MONGO_URI" ]]; then
  fail "MONGO_URI not set (expected via mounted secret file or MONGO_URI_FILE env var)"
fi

[[ -n "$ACCOUNT" ]] || fail "AZURE_STORAGE_ACCOUNT (or AZURE_STORAGE_ACCOUNT_NAME) required"
[[ -n "$CONTAINER" ]] || fail "AZURE_STORAGE_CONTAINER (or AZURE_BLOB_CONTAINER) required"

TS=$(date -u +%Y%m%d-%H%M%S)
BASENAME="${PREFIX}-${DB}-${TS}"
WORKDIR=$(mktemp -d)
ARCHIVE="${WORKDIR}/${BASENAME}.tar.gz"

cleanup() { rm -rf "$WORKDIR" || true; }
trap cleanup EXIT

URI_DB=""
if [[ "$MONGO_URI" =~ ^mongodb(\+srv)?:\/\/[^/]+\/([^/?]+) ]]; then
  URI_DB="${BASH_REMATCH[2]}"
fi

EFFECTIVE_DB="$DB"
MONGODUMP_ARGS=("--uri=$MONGO_URI")
if [[ -n "$URI_DB" ]]; then
  if [[ "$DB" != "$URI_DB" ]]; then
    log "Database name mismatch: URI specifies '$URI_DB' but env wants '$DB'; using URI database."
  fi
  EFFECTIVE_DB="$URI_DB"
  # Do not append --db (mongodump will use the URI DB)
else
  # URI has no explicit DB; use env/default
  MONGODUMP_ARGS+=("--db" "$EFFECTIVE_DB")
fi

log "Dumping MongoDB '$EFFECTIVE_DB'"
mongodump "${MONGODUMP_ARGS[@]}" --out "$WORKDIR/dump" >/dev/null

tar -czf "$ARCHIVE" -C "$WORKDIR/dump" .
SIZE=$(stat -f %z "$ARCHIVE" 2>/dev/null || stat -c %s "$ARCHIVE" 2>/dev/null || echo 0)
log "Archive created: $ARCHIVE (${SIZE} bytes)"

if [[ "$DRY_RUN" == "1" ]]; then
  log "DRY_RUN: skipping upload"
  exit 0
fi

# Ensure container exists (idempotent)
az storage container create \
  --name "$CONTAINER" \
  --account-name "$ACCOUNT" \
  >/dev/null || true

log "Uploading to Azure Blob ..."
az storage blob upload \
  --account-name "$ACCOUNT" \
  --container-name "$CONTAINER" \
  --name "${BASENAME}.tar.gz" \
  --file "$ARCHIVE" \
  --content-type application/gzip \
  --only-show-errors \
  --no-progress >/dev/null
log "Uploaded blob: ${BASENAME}.tar.gz"

# Retention pruning (list blobs matching prefix and keep most recent N)
if [[ "$RETENTION" =~ ^[0-9]+$ ]] && (( RETENTION > 0 )); then
  log "Applying retention policy (keep $RETENTION)"
  mapfile -t MATCHING < <(az storage blob list \
    --account-name "$ACCOUNT" \
    --container-name "$CONTAINER" \
    --prefix "${PREFIX}-${DB}-" \
    --query '[].{name:name, time:properties.lastModified}' -o tsv | sort -k2r)
  COUNT=0
  for line in "${MATCHING[@]}"; do
    name="${line%%$'\t'*}"
    (( COUNT++ ))
    if (( COUNT > RETENTION )); then
      log "Deleting old blob: $name"
      az storage blob delete --account-name "$ACCOUNT" --container-name "$CONTAINER" --name "$name" --only-show-errors >/dev/null || log "Warn: failed to delete $name"
    fi
  done
fi

log "Done"