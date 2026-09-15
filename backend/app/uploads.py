"""Local-disk file storage for evidence (invoices, photos, receipts, documents).

MVP-only: files land in backend/uploads/ and are served back via the /uploads
static mount in main.py. Swap _save_to_disk for an S3 (or equivalent) upload
before production - nothing above this module needs to change since callers
only ever see the returned relative URL.
"""

import uuid
from pathlib import Path

from fastapi import HTTPException, UploadFile

UPLOAD_DIR = Path(__file__).resolve().parent.parent / "uploads"
UPLOAD_DIR.mkdir(exist_ok=True)

_MAX_BYTES = 10 * 1024 * 1024  # 10 MB
_ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".pdf", ".doc", ".docx"}


async def save_upload(file: UploadFile) -> str:
    """Validates and saves an uploaded file, returning its relative URL (e.g. /uploads/<name>)."""
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in _ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Unsupported file type '{suffix}'. Allowed: {sorted(_ALLOWED_EXTENSIONS)}")

    contents = await file.read()
    if len(contents) > _MAX_BYTES:
        raise HTTPException(400, "File too large (max 10 MB)")
    if not contents:
        raise HTTPException(400, "Empty file")

    stored_name = f"{uuid.uuid4().hex}{suffix}"
    (UPLOAD_DIR / stored_name).write_bytes(contents)

    return f"/uploads/{stored_name}"
