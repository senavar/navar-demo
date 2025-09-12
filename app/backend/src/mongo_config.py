
from __future__ import annotations
import os
import threading
import time
import hashlib
from pathlib import Path
from typing import Optional, Callable

from pymongo import MongoClient
from pymongo.errors import PyMongoError

_client: Optional[MongoClient] = None
_uri: Optional[str] = None
_lock = threading.RLock()


def _hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _build_client(uri: str) -> MongoClient:
    client = MongoClient(uri, serverSelectionTimeoutMS=3000)
    # Verify connectivity quickly (will raise if bad)
    client.admin.command("ping")
    return client


def resolve_initial_uri() -> Optional[str]:
    if os.getenv("MONGO_URI"):
        return os.getenv("MONGO_URI").strip()  # type: ignore[union-attr]
    file_path = os.getenv("MONGO_URI_FILE")
    if file_path:
        p = Path(file_path)
        if p.is_file():
            content = p.read_text(encoding="utf-8").strip()
            if content:
                return content
    return None


def init_and_watch(on_rotate: Optional[Callable[[MongoClient, str], None]] = None) -> None:
    """Initialize the Mongo client (if possible) and start watcher if file-based.

    Silently returns if no URI can be resolved or initial connection fails.
    """
    global _client, _uri
    uri = resolve_initial_uri()
    if not uri:
        return
    try:
        c = _build_client(uri)
    except Exception:
        return
    with _lock:
        _client = c
        _uri = uri
    if on_rotate:
        try:
            on_rotate(c, uri)
        except Exception:
            pass
    if os.getenv("MONGO_URI_FILE"):
        interval = int(os.getenv("MONGO_URI_REFRESH_SECONDS", "60"))
        t = threading.Thread(target=_watch_loop, args=(interval, on_rotate), daemon=True)
        t.start()


def _watch_loop(interval: int, on_rotate: Optional[Callable[[MongoClient, str], None]]):
    file_path = os.getenv("MONGO_URI_FILE")
    if not file_path:
        return
    path = Path(file_path)
    last_hash = None
    while True:
        try:
            if path.is_file():
                content = path.read_text(encoding="utf-8").strip()
                if content:
                    h = _hash(content)
                    if last_hash is None:
                        last_hash = h
                    elif h != last_hash:
                        try:
                            new_client = _build_client(content)
                            with _lock:
                                global _client, _uri
                                old = _client
                                _client = new_client
                                _uri = content
                            if on_rotate:
                                try:
                                    on_rotate(new_client, content)
                                except Exception:
                                    pass
                            if old:
                                try:
                                    old.close()
                                except Exception:
                                    pass
                            last_hash = h
                        except PyMongoError:
                            # Leave current client intact on failure
                            pass
        except Exception:
            pass
        time.sleep(interval)


def get_client() -> Optional[MongoClient]:
    with _lock:
        return _client


def current_uri() -> Optional[str]:
    with _lock:
        return _uri
