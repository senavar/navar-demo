#!/usr/bin/env python3
"""
Intended to run in a CronJob. It:
    * grabs a connection string (env MONGO_URI or a mounted secret file),
    * runs mongodump for a single DB,
    * runs tar compression,
    * pushes to Azure Blob (if account + container env set),
    * prunes older blobs keeping the newest N (RETENTION, default 7).

"""
import os
import sys
import json  # kept in case future debugging wants structured output
import subprocess
import datetime
import tempfile
import shutil
from azure.storage.blob import BlobServiceClient

def log(msg: str):
    
    print(f"[mongo-backup] {msg}", flush=True)


def run(cmd):
    """Run a shell command, raise if non-zero."""
    log("RUN: " + " ".join(cmd))
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode != 0:
        # show output then raise
        log(r.stdout)
        raise RuntimeError(f"command failed ({r.returncode})")
    return r.stdout


def _read_first_line(path: str):
    try:
        with open(path, 'r') as f:
            return f.readline().strip()
    except Exception:
        return None

def main():
    mongo_uri = os.getenv("MONGO_URI")
    if not mongo_uri:  # try common file mount locations
        for candidate in (
            "/mnt/secrets-store/mongo-conn-string",
            "/mnt/secrets-store/MONGO_URI",
            "/var/run/secrets/mongo/connectionString",
        ):
            val = _read_first_line(candidate)
            if val:
                mongo_uri = val
                log(f"MONGO_URI loaded from {candidate}")
                break
    if not mongo_uri:
        log("ERROR: MONGO_URI not provided (env or file)")
        return 1

    db_name   = os.getenv("MONGO_DB_NAME", "birthdays_db")
    prefix    = os.getenv("BACKUP_PREFIX", "mongo-backup")
    retention = int(os.getenv("RETENTION", "7"))  # how many recent blobs to keep

    timestamp = datetime.datetime.utcnow().strftime("%Y%m%d-%H%M%S")  # UTC keeps ordering sane
    base_name = f"{prefix}-{db_name}-{timestamp}"

    workdir = tempfile.mkdtemp(prefix="mongo-bak-")  # shorter temp prefix
    dump_dir = os.path.join(workdir, "dump")
    archive_path = os.path.join(workdir, f"{base_name}.tar.gz")

    try:
        run(["mongodump", "--uri", mongo_uri, "--db", db_name, "--out", dump_dir])  # dump
        run(["tar", "-czf", archive_path, "-C", dump_dir, "."])  # compress
        try:
            size = os.path.getsize(archive_path)
        except OSError:
            size = -1
        log(f"Archive ready: {archive_path} ({size} bytes)")

        account   = os.getenv("AZURE_STORAGE_ACCOUNT_NAME")
        container = os.getenv("AZURE_BLOB_CONTAINER")
        conn_str  = os.getenv("AZURE_STORAGE_CONNECTION_STRING")

        if account and container:
            # Connect (conn string > MSI)
            if conn_str:
                service = BlobServiceClient.from_connection_string(conn_str)
            else:  # use default credential chain
                from azure.identity import DefaultAzureCredential  # type: ignore
                service = BlobServiceClient(
                    f"https://{account}.blob.core.windows.net",
                    credential=DefaultAzureCredential(),
                )
            cc = service.get_container_client(container)
            try:
                cc.create_container()
            except Exception:
                pass  # exists

            blob_name = f"{base_name}.tar.gz"
            with open(archive_path, "rb") as fh:
                cc.upload_blob(
                    name=blob_name,
                    data=fh,
                    overwrite=True,
                    content_type="application/gzip",
                )
            log(f"Uploaded: {blob_name}")

            if retention > 0:
                # list + prune old
                blobs = list(cc.list_blobs(name_starts_with=f"{prefix}-{db_name}-"))
                blobs.sort(key=lambda b: b.last_modified, reverse=True)
                for stale in blobs[retention:]:
                    try:
                        cc.delete_blob(stale.name)
                        log(f"Pruned {stale.name}")
                    except Exception as exc:
                        log(f"Prune failed {stale.name}: {exc}")
        else:
            log("Skipping Azure upload (missing config or SDK)")
            log(f"Backup left on local FS: {archive_path}")
        return 0
    except Exception as e:
        log(f"ERROR: Backup failed: {e}")
        return 2
    finally:
        # Clean only if we uploaded somewhere (or user didn't ask to retain)
        if os.getenv("DEBUG_RETAIN") != "1" and (account and container):
            shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
