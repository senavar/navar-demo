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
SECRET_PATH="/mnt/secrets-store/mongo-conn-string"

if [[ -z "$MONGO_URI" ]] && [[ -f "$SECRET_PATH" ]]; then
  MONGO_URI=$(head -n1 "$SECRET_PATH" | tr -d '\r')
  log "Loaded MONGO_URI from $SECRET_PATH"
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

EFFECTIVE_DB="$URI_DB"
if [[ -z "$EFFECTIVE_DB" ]]; then
  log "Warning: URI did not contain a database segment; mongodump will include all databases."
  BASENAME="${PREFIX}-all-${TS}"
else
  BASENAME="${PREFIX}-${EFFECTIVE_DB}-${TS}"
fi

log "Dumping MongoDB via URI (database='${EFFECTIVE_DB:-<none>}' )"
DUMPDIR="$WORKDIR/dump"
mkdir -p "$DUMPDIR"
mongodump --uri="$MONGO_URI" --out "$DUMPDIR" >/dev/null

tar -czf "$ARCHIVE" -C "$DUMPDIR" .
SIZE=$(stat -f %z "$ARCHIVE" 2>/dev/null || stat -c %s "$ARCHIVE" 2>/dev/null || echo 0)
log "Archive created: $ARCHIVE (${SIZE} bytes)"

if [[ "$DRY_RUN" == "1" ]]; then
  log "DRY_RUN: skipping upload"
  exit 0
fi

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