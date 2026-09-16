"""Staff/admin reporting: aggregate platform metrics for a dashboard view.

Read-only aggregation queries only - nothing here mutates data. Audit logs
(a distinct feature - a durable record of who changed what, when) are
tracked separately via RequestEvent for status changes; a general-purpose
audit log covering every table is deferred (see PROJECT_PLAN.md Phase 5).
"""

from datetime import datetime, timedelta
from decimal import Decimal

from sqlalchemy import func
from sqlalchemy.orm import Session

from .models import RequestStatus, ServiceRequest, User, UserRole

_COMPLETED_STATUSES = (RequestStatus.completed, RequestStatus.verified, RequestStatus.closed)


def build_dashboard_report(db: Session) -> dict:
    requests_by_status = dict(
        db.query(ServiceRequest.status, func.count(ServiceRequest.id)).group_by(ServiceRequest.status).all()
    )
    requests_by_category = dict(
        db.query(ServiceRequest.category, func.count(ServiceRequest.id)).group_by(ServiceRequest.category).all()
    )
    customers_by_tier = dict(
        db.query(User.account_type, func.count(User.id))
        .filter(User.role == UserRole.customer, User.deleted_at.is_(None))
        .group_by(User.account_type)
        .all()
    )

    total_requested = db.query(func.coalesce(func.sum(ServiceRequest.amount), 0)).scalar() or Decimal(0)
    total_completed = (
        db.query(func.coalesce(func.sum(ServiceRequest.amount), 0))
        .filter(ServiceRequest.status.in_(_COMPLETED_STATUSES))
        .scalar()
        or Decimal(0)
    )

    total_customers = (
        db.query(func.count(User.id)).filter(User.role == UserRole.customer, User.deleted_at.is_(None)).scalar() or 0
    )
    thirty_days_ago = datetime.utcnow() - timedelta(days=30)
    new_customers_last_30_days = (
        db.query(func.count(User.id))
        .filter(User.role == UserRole.customer, User.deleted_at.is_(None), User.created_at >= thirty_days_ago)
        .scalar()
        or 0
    )

    high_risk_requests = db.query(func.count(ServiceRequest.id)).filter(ServiceRequest.fraud_risk_level == "high").scalar() or 0
    pending_approval_count = requests_by_status.get(RequestStatus.approval_required, 0)

    return {
        "total_requests": sum(requests_by_status.values()),
        "total_customers": total_customers,
        "new_customers_last_30_days": new_customers_last_30_days,
        "requests_by_status": [{"status": s.value, "count": c} for s, c in requests_by_status.items()],
        "requests_by_category": [{"category": cat.value, "count": c} for cat, c in requests_by_category.items()],
        "customers_by_tier": [{"account_type": t.value, "count": c} for t, c in customers_by_tier.items()],
        "total_amount_requested": total_requested,
        "total_amount_completed": total_completed,
        "high_risk_requests": high_risk_requests,
        "pending_approval_count": pending_approval_count,
    }
