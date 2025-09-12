"""Azure Blob Storage helper utilities.

Uploads images if Azure Storage is configured; otherwise exposes a no-op
interface so the rest of the app can transparently fall back to local file
storage. A container with public read access is assumed for simplicity.

Configuration options (env vars):
AZURE_STORAGE_ACCOUNT_NAME (required for URL building if using credential auth)
AZURE_BLOB_CONTAINER (required if using Azure storage)
AZURE_STORAGE_CONNECTION_STRING (optional; if absent, DefaultAzureCredential is used)
AZURE_BLOB_URL_FORMAT (optional override, e.g. https://cdn.example.com/{container}/{blob})

Deletion operations are best-effort; failures are logged and ignored.
"""
from __future__ import annotations

import os
import mimetypes
from typing import Optional, Tuple

from flask import current_app

_blob_client_cache = None
_container_client_cache = None
_available = None


def _log(msg: str):
	try:
		current_app.logger.info(msg)  # type: ignore[attr-defined]
	except Exception:
		print(msg)


def _ensure_initialized():
	global _blob_client_cache, _container_client_cache, _available
	if _available is not None:
		return
	account = os.getenv("AZURE_STORAGE_ACCOUNT_NAME")
	container = os.getenv("AZURE_BLOB_CONTAINER")
	if not account or not container:
		_available = False
		return
	try:
		from azure.storage.blob import BlobServiceClient
		conn = os.getenv("AZURE_STORAGE_CONNECTION_STRING")
		if conn:
			service = BlobServiceClient.from_connection_string(conn)
		else:
			from azure.identity import DefaultAzureCredential
			credential = DefaultAzureCredential()
			service = BlobServiceClient(
				f"https://{account}.blob.core.windows.net", credential=credential
			)
		_blob_client_cache = service
		_container_client_cache = service.get_container_client(container)
		# create container silently if it doesn't exist (idempotent)
		try:
			_container_client_cache.create_container(public_access="blob")
		except Exception:
			pass
		_available = True
		_log(f"[azure_blob] Azure blob storage enabled (container={container})")
	except Exception as e:
		_available = False
		_log(f"[azure_blob] Initialization failed: {e}. Falling back to local storage.")


def is_configured() -> bool:
	_ensure_initialized()
	return bool(_available)


def upload_image(file_storage, blob_name: str) -> Tuple[Optional[str], Optional[str]]:
	"""Uploads a FileStorage object to blob storage.

	Returns (blob_name, url) on success; (None, None) if azure not configured or failure.
	"""
	_ensure_initialized()
	if not _available:
		return None, None
	try:
		if not blob_name:
			raise ValueError("blob_name required")
		ct, _ = mimetypes.guess_type(blob_name)
		_container_client_cache.upload_blob(
			name=blob_name,
			data=file_storage.stream,
			content_type=ct or 'application/octet-stream',
			overwrite=True,
		)
		return blob_name, get_blob_url(blob_name)
	except Exception as e:
		_log(f"[azure_blob] Upload failed ({blob_name}): {e}")
		return None, None


def delete_blob(blob_name: str):
	_ensure_initialized()
	if not _available or not blob_name:
		return
	try:
		_container_client_cache.delete_blob(blob_name)
	except Exception:
		# best effort
		pass


def get_blob_url(blob_name: str) -> Optional[str]:
	_ensure_initialized()
	if not _available or not blob_name:
		return None
	fmt = os.getenv("AZURE_BLOB_URL_FORMAT")
	container = os.getenv("AZURE_BLOB_CONTAINER")
	account = os.getenv("AZURE_STORAGE_ACCOUNT_NAME")
	if fmt:
		return fmt.format(container=container, blob=blob_name)
	return f"https://{account}.blob.core.windows.net/{container}/{blob_name}"
