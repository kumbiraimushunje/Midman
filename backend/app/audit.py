import uuid
from typing import Optional

from sqlalchemy.orm import Session

from .models import AuditLog, User


def record_audit(
    db: Session,
    actor: User,
    action: str,
    entity_type: str,
    summary: str,
    entity_id: Optional[uuid.UUID] = None,
    meta: Optional[dict] = None,
) -> None:
    """Adds an audit log row to the session without committing - callers already
    commit the rest of their transaction, so the audit entry is persisted
    atomically alongside the change it describes rather than in a second trip."""
    db.add(
        AuditLog(
            actor_id=actor.id,
            actor_name=actor.full_name,
            actor_role=actor.role.value,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            summary=summary,
            meta=meta,
        )
    )
