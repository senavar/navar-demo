"""Unified data access layer for birthdays with optional MongoDB (hot reload capable).

Mongo connection string (URI) precedence (implemented in ``mongo_config``):
1. ``MONGO_URI`` env var
2. Content of file at ``MONGO_URI_FILE`` (e.g. AKV CSI mount)
3. (None) -> JSON file backend fallback

Legacy variables (``MONGO_CONNECTION_STRING`` / ``MONGO_CONNECTION_STRING_FILE``) are still
honored for backward compatibility on initial init only (no hot reload).
"""
from __future__ import annotations

import json
import os
import uuid
import threading
from datetime import datetime
from typing import Any, Dict, List, Optional

from flask import current_app

_mongo_lock = threading.Lock()
_mongo_collection = None  # dynamic collection reference
_using_mongo = False
_mongo_last_error: Optional[str] = None

# Hot reload support module
from . import mongo_config


def _log(msg: str):  # lightweight logger fallback
    try:
        current_app.logger.info(msg)  # type: ignore[attr-defined]
    except Exception:
        print(msg)


def _read_file_secret(path: str) -> Optional[str]:
    try:
        if path and os.path.isfile(path):
            with open(path, "r", encoding="utf-8") as f:
                return f.read().strip()
    except Exception:
        pass
    return None


def _legacy_connection_string() -> Optional[str]:
    # Maintain backward compatibility one-time (no rotation on legacy vars)
    direct = os.getenv("MONGO_CONNECTION_STRING")
    if direct:
        return direct.strip()
    file_path = os.getenv("MONGO_CONNECTION_STRING_FILE")
    if file_path:
        return _read_file_secret(file_path)
    # Optionally Key Vault direct (unchanged)
    kv_name = os.getenv("KEY_VAULT_NAME")
    secret_name = os.getenv("KEY_VAULT_SECRET_NAME")
    if kv_name and secret_name:
        try:
            from azure.identity import DefaultAzureCredential  # lazy import
            from azure.keyvault.secrets import SecretClient
            credential = DefaultAzureCredential()
            url = f"https://{kv_name}.vault.azure.net"
            client = SecretClient(vault_url=url, credential=credential)
            secret = client.get_secret(secret_name)
            return secret.value
        except Exception as e:
            _log(f"[repository] Key Vault secret fetch failed: {e}")
    return None


def _apply_client(client) -> None:
    global _mongo_collection, _using_mongo, _mongo_last_error
    try:
        db_name = os.getenv("MONGO_DB_NAME", "birthdays_db")
        coll_name = os.getenv("MONGO_COLLECTION_NAME", "birthdays")
        collection = client[db_name][coll_name]
        collection.create_index("id", unique=True)
        _mongo_collection = collection
        _using_mongo = True
        _mongo_last_error = None
        _log(f"[repository] Mongo backend enabled (db={db_name}, collection={coll_name})")
    except Exception as e:
        _mongo_last_error = str(e)
        _log(f"[repository] Mongo collection init failed: {e}")


def _rotation_callback(new_client, uri: str):  # invoked by mongo_config watcher
    with _mongo_lock:
        _apply_client(new_client)
        _log("[repository] Mongo client rotated due to URI change")


def _init_mongo_if_possible():
    global _using_mongo
    if _using_mongo and _mongo_collection is not None:
        return
    with _mongo_lock:
        if _using_mongo and _mongo_collection is not None:
            return
        # Prefer new hot-reloadable client
        client = mongo_config.get_client()
        if client:
            _apply_client(client)
            return
        # Fallback to legacy envs once
        legacy_conn = _legacy_connection_string()
        if not legacy_conn:
            _log("[repository] Mongo URI not found; using JSON backend")
            return
        try:
            from pymongo import MongoClient
            client = MongoClient(legacy_conn, serverSelectionTimeoutMS=4000)
            client.admin.command("ping")
            _apply_client(client)
        except Exception as e:
            _log(f"[repository] Legacy Mongo init failed ({e}); using JSON backend")


# ---------------- JSON BACKEND (legacy) ----------------
def _json_db_path() -> str:
    return os.path.join(current_app.instance_path, 'birthdays.json')


def _json_read_all() -> List[Dict[str, Any]]:
    path = _json_db_path()
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def _json_write_all(birthdays: List[Dict[str, Any]]):
    path = _json_db_path()
    tmp = path + '.tmp'
    os.makedirs(current_app.instance_path, exist_ok=True)
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(birthdays, f, indent=2)
    os.replace(tmp, path)


# ---------------- PUBLIC API (Unified) ----------------
def get_all_birthdays() -> List[Dict[str, Any]]:
    _init_mongo_if_possible()
    if _using_mongo and _mongo_collection is not None:
        docs = list(_mongo_collection.find({}, {'_id': 0}))
        return docs
    return _json_read_all()


def add_new_birthday(new_person: Dict[str, Any]) -> Dict[str, Any]:
    _init_mongo_if_possible()
    # Maintain integer id compatibility
    new_person['id'] = int(uuid.uuid4().int & (1 << 31) - 1)
    timestamp = datetime.utcnow().isoformat() + 'Z'
    new_person['created_at'] = timestamp
    new_person['updated_at'] = timestamp
    if _using_mongo and _mongo_collection is not None:
        try:
            _mongo_collection.insert_one(new_person.copy())
            doc = new_person.copy()
            return doc
        except Exception as e:
            _log(f"[repository] Mongo insert failed fallback to JSON: {e}")
    # JSON fallback
    data = _json_read_all()
    data.append(new_person)
    _json_write_all(data)
    return new_person


def get_birthday_by_id(birthday_id: int | str) -> Optional[Dict[str, Any]]:
    _init_mongo_if_possible()
    if _using_mongo and _mongo_collection is not None:
        doc = _mongo_collection.find_one({'id': int(birthday_id)}, {'_id': 0})
        return doc
    for person in _json_read_all():
        if str(person.get('id')) == str(birthday_id):
            return person
    return None


def update_birthday_in_db(birthday_id: int | str, update_data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    _init_mongo_if_possible()
    now = datetime.utcnow().isoformat() + 'Z'
    update_data['updated_at'] = now
    if _using_mongo and _mongo_collection is not None:
        try:
            result = _mongo_collection.find_one_and_update(
                {'id': int(birthday_id)},
                {'$set': update_data},
                projection={'_id': 0},
                return_document=True,
            )
            return result
        except Exception as e:
            _log(f"[repository] Mongo update failed fallback to JSON: {e}")
    # JSON fallback
    all_people = _json_read_all()
    updated = None
    for p in all_people:
        if str(p.get('id')) == str(birthday_id):
            p.update(update_data)
            updated = p
            break
    if updated:
        _json_write_all(all_people)
    return updated


def delete_birthday_from_db(birthday_id: int | str) -> bool:
    _init_mongo_if_possible()
    if _using_mongo and _mongo_collection is not None:
        try:
            res = _mongo_collection.delete_one({'id': int(birthday_id)})
            return res.deleted_count == 1
        except Exception as e:
            _log(f"[repository] Mongo delete failed fallback to JSON: {e}")
    # JSON fallback
    all_people = _json_read_all()
    new_list = [p for p in all_people if str(p.get('id')) != str(birthday_id)]
    if len(new_list) != len(all_people):
        _json_write_all(new_list)
        return True
    return False


def is_using_mongo() -> bool:
    return _using_mongo


def mongo_status() -> Dict[str, Any]:
    """Return internal mongo initialization / runtime status for diagnostics."""
    db_name = os.getenv("MONGO_DB_NAME", "birthdays_db")
    coll_name = os.getenv("MONGO_COLLECTION_NAME", "birthdays")
    uri_present = bool(mongo_config.current_uri() or _legacy_connection_string())
    return {
        "using_mongo": _using_mongo,
        "db_name": db_name,
        "collection": coll_name,
        "has_collection": _mongo_collection is not None,
        "last_error": _mongo_last_error,
        "connection_string_present": uri_present,
        "rotation_enabled": bool(os.getenv("MONGO_URI_FILE")),
        "uri_source": (
            "env" if os.getenv("MONGO_URI") else (
                "file" if os.getenv("MONGO_URI_FILE") else (
                    "legacy_env" if os.getenv("MONGO_CONNECTION_STRING") else (
                        "legacy_file" if os.getenv("MONGO_CONNECTION_STRING_FILE") else None
                    )
                )
            )
        ),
    }


# Kick off hot-reload initialization early
try:
    mongo_config.init_and_watch(_rotation_callback)
except Exception as _e:  # pragma: no cover (best-effort init)
    _log(f"[repository] mongo_config init_and_watch failed: {_e}")
