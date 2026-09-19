"""Business account role permissions.

A Business account (Company) has employees, each assigned one of five fixed
BusinessRole values (see models.py). Each role carries a fixed set of
capabilities - there's no custom permission builder:

    administrator   - everything: create, approve spend, manage employees, view reports
    finance         - approve spend/quotations, view company-wide reports - doesn't create requests
    operations      - create and manage requests day-to-day - can't approve spend
    requester       - create requests only, sees just their own
    viewer_auditor  - read-only: completed jobs and reports, no create/approve

A personal (non-business) user has company_id/business_role both None, and
every check below simply returns True for them - these rules only ever
restrict business employees, never individual customers.
"""

from .models import BusinessRole, RequestStatus, User

_COMPLETED_JOB_STATUSES = {RequestStatus.completed, RequestStatus.verified, RequestStatus.closed}

_PERMISSIONS: dict[BusinessRole, dict[str, bool]] = {
    BusinessRole.administrator: {
        "create_request": True,
        "approve_spending": True,
        "manage_employees": True,
        "view_reports": True,
        "view_all_company_requests": True,
    },
    BusinessRole.finance: {
        "create_request": False,
        "approve_spending": True,
        "manage_employees": False,
        "view_reports": True,
        "view_all_company_requests": True,
    },
    BusinessRole.operations: {
        "create_request": True,
        "approve_spending": False,
        "manage_employees": False,
        "view_reports": False,
        "view_all_company_requests": True,
    },
    BusinessRole.requester: {
        "create_request": True,
        "approve_spending": False,
        "manage_employees": False,
        "view_reports": False,
        "view_all_company_requests": False,
    },
    BusinessRole.viewer_auditor: {
        "create_request": False,
        "approve_spending": False,
        "manage_employees": False,
        "view_reports": True,
        "view_all_company_requests": True,
    },
}


def _has(user: User, capability: str) -> bool:
    if user.company_id is None or user.business_role is None:
        return True  # personal accounts aren't subject to business role gating
    return _PERMISSIONS[user.business_role][capability]


def can_create_request(user: User) -> bool:
    return _has(user, "create_request")


def can_approve_spending(user: User) -> bool:
    """Gates initiating/confirming payment on a request on the company's behalf."""
    return _has(user, "approve_spending")


def can_manage_employees(user: User) -> bool:
    return _has(user, "manage_employees")


def can_view_company_reports(user: User) -> bool:
    return _has(user, "view_reports")


def can_view_all_company_requests(user: User) -> bool:
    """False means the employee only sees requests they personally created."""
    return _has(user, "view_all_company_requests")


def visible_statuses_for_business_role(user: User) -> set[RequestStatus] | None:
    """None means no extra filtering. Viewer/Auditor only ever sees completed jobs."""
    if user.company_id is not None and user.business_role == BusinessRole.viewer_auditor:
        return _COMPLETED_JOB_STATUSES
    return None
