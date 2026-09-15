"""Subscription tier rules.

Pricing isn't set yet (deferred - "Subscriptions fees right amounts will be
added later"). This module covers the non-price feature gates that were
specified: PAYG's restrictions, Pro's queue priority, and the 30-day free
trial every new account starts on.

    PAYG      - unlimited use but each service costs more (pricing TBD);
                no history of past requests; can't save beneficiaries,
                has to re-enter who/where every time.
    Standard  - recurring payments allowed, faster processing than PAYG.
    Pro       - served first in the staff queue; free digital assistance
                (e.g. document help at no extra charge - pricing TBD).

Every new account gets a 30-day free trial. The trial is about billing,
not features: during it a user is simply on PAYG (no subscription has
been chosen or charged yet) until they pick Standard or Pro.
"""

from datetime import datetime, timedelta

from .models import AccountType, RequestStatus, User

TRIAL_DAYS = 30

# PAYG: "no list of previous transactions" - once a request reaches one of
# these terminal statuses it drops out of the customer's own list. Staff
# still see everything regardless of the requester's tier.
_PAYG_HIDDEN_STATUSES = {
    RequestStatus.completed,
    RequestStatus.verified,
    RequestStatus.closed,
    RequestStatus.rejected,
    RequestStatus.cancelled,
}


def trial_ends_at_for_new_user() -> datetime:
    return datetime.utcnow() + timedelta(days=TRIAL_DAYS)


def can_manage_beneficiaries(user: User) -> bool:
    """PAYG: "cannot create beneficiaries list instead enter details all the time"."""
    return user.account_type != AccountType.payg


def visible_statuses_for(user: User) -> set[RequestStatus] | None:
    """None means no filtering (see every request). PAYG only sees requests still in flight."""
    if user.account_type == AccountType.payg:
        return set(RequestStatus) - _PAYG_HIDDEN_STATUSES
    return None
