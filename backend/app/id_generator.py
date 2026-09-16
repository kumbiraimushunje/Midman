"""Generates permanent, human-readable Member IDs like MUS000001.

Scheme: the first 3 alphabetic characters of the customer's surname
(uppercased), followed by a 6-digit sequence number that is scoped to that
prefix. The first "Mshunje" account is MUS000001, the second is MUS000002;
a completely different surname like "Moyo" gets its own MOY000001 counter.
Uniqueness is guaranteed by (prefix, seq) even though many people can share
a prefix - it never depends on the name alone.

The prefix's counter is stored in member_id_counters and incremented inside
a row-locked transaction (SELECT ... FOR UPDATE) so two simultaneous
registrations with the same prefix can never be handed the same number.
"""

import re

from sqlalchemy.orm import Session

from .models import MemberIdCounter

_ALPHA_RE = re.compile(r"[A-Za-z]")


def _prefix_from_name(full_name: str) -> str:
    parts = full_name.strip().split()
    surname = parts[-1] if len(parts) > 1 else parts[0]
    letters = "".join(_ALPHA_RE.findall(surname)).upper()

    if len(letters) < 3:
        # Surname too short (or not alphabetic) - fall back to the first name too.
        first_name = parts[0] if len(parts) > 1 else ""
        letters = (letters + "".join(_ALPHA_RE.findall(first_name)).upper())

    letters = (letters + "XXX")[:3]  # pad if still short, e.g. a 2-letter surname
    return letters


def generate_member_id(db: Session, full_name: str) -> str:
    prefix = _prefix_from_name(full_name)

    counter = (
        db.query(MemberIdCounter)
        .filter(MemberIdCounter.prefix == prefix)
        .with_for_update()
        .first()
    )
    if counter is None:
        counter = MemberIdCounter(prefix=prefix, next_seq=1)
        db.add(counter)
        db.flush()
        seq = 1
    else:
        seq = counter.next_seq

    counter.next_seq = seq + 1
    db.flush()

    return f"{prefix}{seq:06d}"


def generate_payment_reference(db: Session) -> str:
    """MIDPAY-000123 - a single global sequence shared by every payment attempt.
    This is what's sent to the gateway as the merchant-side transaction reference."""
    counter = (
        db.query(MemberIdCounter)
        .filter(MemberIdCounter.prefix == "PAY")
        .with_for_update()
        .first()
    )
    if counter is None:
        counter = MemberIdCounter(prefix="PAY", next_seq=1)
        db.add(counter)
        db.flush()
        seq = 1
    else:
        seq = counter.next_seq

    counter.next_seq = seq + 1
    db.flush()

    return f"MIDPAY-{seq:06d}"


def generate_request_number(db: Session) -> str:
    """MID-000123 - a single global sequence shared by every request, regardless of category."""
    counter = (
        db.query(MemberIdCounter)
        .filter(MemberIdCounter.prefix == "REQ")
        .with_for_update()
        .first()
    )
    if counter is None:
        counter = MemberIdCounter(prefix="REQ", next_seq=1)
        db.add(counter)
        db.flush()
        seq = 1
    else:
        seq = counter.next_seq

    counter.next_seq = seq + 1
    db.flush()

    return f"MID-{seq:06d}"
