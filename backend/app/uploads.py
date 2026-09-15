"""File storage for evidence (invoices, photos, receipts, documents).

Two backends, chosen automatically by whether S3_BUCKET_NAME is set:

- S3 (production): objects go to a private bucket under an "evidence/"
  prefix. save_upload() returns the bare object key (e.g.
  "evidence/<uuid>.pdf"); resolve_file_url() turns that into a time-limited
  presigned GET URL at read time. The bucket is never made public - this
  works with AWS's current default-private bucket settings with no need to
  disable Block Public Access or change Object Ownership.
- Local disk (dev fallback, no AWS needed): files land in backend/uploads/
  and are served back via the /uploads static mount in main.py.
  save_upload() returns "/uploads/<name>"; resolve_file_url() is a no-op
  for these (a leading "/" is how the two are told apart).
"""

import uuid
from pathlib import Path

import boto3
from botocore.exceptions import ClientError
from fastapi import HTTPException, UploadFile

from .config import settings

UPLOAD_DIR = Path(__file__).resolve().parent.parent / "uploads"
UPLOAD_DIR.mkdir(exist_ok=True)

_MAX_BYTES = 10 * 1024 * 1024  # 10 MB
_CONTENT_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".heic": "image/heic",
    ".pdf": "application/pdf",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
}
_ALLOWED_EXTENSIONS = set(_CONTENT_TYPES)

_S3_PRESIGNED_TTL_SECONDS = 3600


def _s3_enabled() -> bool:
    return bool(settings.s3_bucket_name)


def _s3_client():
    return boto3.client(
        "s3",
        region_name=settings.aws_region,
        aws_access_key_id=settings.aws_access_key_id or None,
        aws_secret_access_key=settings.aws_secret_access_key or None,
    )


async def save_upload(file: UploadFile) -> str:
    """Validates and saves an uploaded file. Returns a stored reference - an
    S3 object key when S3 is configured, or a local static path otherwise.
    Pass this to resolve_file_url() to get something a client can fetch."""
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in _ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Unsupported file type '{suffix}'. Allowed: {sorted(_ALLOWED_EXTENSIONS)}")

    contents = await file.read()
    if len(contents) > _MAX_BYTES:
        raise HTTPException(400, "File too large (max 10 MB)")
    if not contents:
        raise HTTPException(400, "Empty file")

    stored_name = f"{uuid.uuid4().hex}{suffix}"

    if _s3_enabled():
        key = f"evidence/{stored_name}"
        try:
            _s3_client().put_object(
                Bucket=settings.s3_bucket_name,
                Key=key,
                Body=contents,
                ContentType=_CONTENT_TYPES[suffix],
            )
        except ClientError as e:
            raise HTTPException(502, f"Could not upload to S3: {e}")
        return key

    (UPLOAD_DIR / stored_name).write_bytes(contents)
    return f"/uploads/{stored_name}"


def resolve_file_url(stored_value: str) -> str:
    """Turns a stored reference (from save_upload) into a URL a client can
    fetch right now. Local paths pass through unchanged (served by the
    /uploads static mount); S3 keys become a 1-hour presigned URL, generated
    fresh on every read so it's always valid regardless of when it was
    originally uploaded."""
    if stored_value.startswith("/"):
        return stored_value
    try:
        return _s3_client().generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.s3_bucket_name, "Key": stored_value},
            ExpiresIn=_S3_PRESIGNED_TTL_SECONDS,
        )
    except ClientError:
        return stored_value  # degrade to the raw key rather than fail the whole response
