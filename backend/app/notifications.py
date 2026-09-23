"""Email notifications for the 4 customer-facing stages: Received, Arranging,
In Progress, Completed - plus approve/reject decisions.

Degrades gracefully: with no SMTP configured, it just logs instead of
sending, so local dev never needs a real mail server.
"""

import logging
import smtplib
from email.message import EmailMessage

from .config import settings
from .models import Company, RequestStatus, ServiceRequest, User

logger = logging.getLogger(__name__)

_STAGE_SUBJECT = {
    "received": "We've received your request",
    "arranging": "We're arranging your request",
    "in_progress": "Your request is in progress",
    "completed": "Your request is complete",
}


def notify_status_change(user: User, request: ServiceRequest, stage: str) -> None:
    subject = f"{_STAGE_SUBJECT.get(stage, 'Update on your request')} - {request.request_number}"
    body = (
        f"Hi {user.full_name},\n\n"
        f"Your request \"{request.title}\" ({request.request_number}) is now: {stage.replace('_', ' ').title()}.\n\n"
        f"Track it any time in the MidMan app.\n\nMidMan"
    )
    _send(user.email, subject, body)


def notify_decision(user: User, request: ServiceRequest, approved: bool, comment: str | None) -> None:
    subject = f"Your request was {'approved' if approved else 'declined'} - {request.request_number}"
    body = (
        f"Hi {user.full_name},\n\n"
        f"Your request \"{request.title}\" ({request.request_number}) was "
        f"{'approved' if approved else 'declined'}."
        + (f"\n\nComment: {comment}" if comment else "")
        + "\n\nMidMan"
    )
    _send(user.email, subject, body)


def notify_authorizer_approval_needed(authorizer: User, initiator: User, request: ServiceRequest) -> None:
    """Sent to the authorizer (e.g. the parent/relative paying) when their
    beneficiary raises a Family Care & Child Support request that needs the
    authorizer's sign-off before MidMan reviews it."""
    subject = f"{initiator.full_name} needs your approval - {request.request_number}"
    body = (
        f"Hi {authorizer.full_name},\n\n"
        f"{initiator.full_name}, who has you listed as their authorizer on MidMan, has raised a request "
        f"\"{request.title}\" ({request.request_number}) that needs your approval before MidMan can review it.\n\n"
        f"Open the MidMan app to approve or decline it.\n\nMidMan"
    )
    _send(authorizer.email, subject, body)


def notify_authorizer_decision(initiator: User, authorizer: User, request: ServiceRequest, approved: bool, comment: str | None) -> None:
    """Sent to the beneficiary/initiator once their authorizer has decided."""
    subject = f"{authorizer.full_name} {'approved' if approved else 'declined'} your request - {request.request_number}"
    body = (
        f"Hi {initiator.full_name},\n\n"
        f"{authorizer.full_name} has {'approved' if approved else 'declined'} your request "
        f"\"{request.title}\" ({request.request_number})."
        + (f"\n\nComment: {comment}" if comment else "")
        + (
            "\n\nIt now moves on to MidMan for final review."
            if approved
            else ""
        )
        + "\n\nMidMan"
    )
    _send(initiator.email, subject, body)


def notify_admin_approval(user: User, request: ServiceRequest, approved: bool, comment: str | None) -> None:
    """Every request needs a MidMan admin's approval before staff can start
    executing it - this confirms that decision to the customer."""
    subject = f"Your request was {'approved' if approved else 'declined'} by MidMan - {request.request_number}"
    body = (
        f"Hi {user.full_name},\n\n"
        f"Your request \"{request.title}\" ({request.request_number}) has been "
        f"{'approved by our team and staff will now start arranging it' if approved else 'declined by our team'}."
        + (f"\n\nComment: {comment}" if comment else "")
        + "\n\nMidMan"
    )
    _send(user.email, subject, body)


def notify_admin_request_pending(admin: User, requester: User, request: ServiceRequest) -> None:
    """Sent to every MidMan admin as soon as a request is actually ready for
    admin review - immediately for a direct request, or once the beneficiary's
    authorizer has signed off for one raised "as a beneficiary"."""
    subject = f"Request needs your approval - {request.request_number}"
    body = (
        f"Hi {admin.full_name},\n\n"
        f"{requester.full_name} raised a request \"{request.title}\" ({request.request_number}) that's "
        f"ready for your approval before staff can start on it.\n\n"
        f"Open the MidMan app to review it.\n\nMidMan"
    )
    _send(admin.email, subject, body)


def notify_payment_received(user: User, request: ServiceRequest, amount, currency: str) -> None:
    subject = f"Payment received - {request.request_number}"
    body = (
        f"Hi {user.full_name},\n\n"
        f"We've received your payment of {currency} {amount} for \"{request.title}\" "
        f"({request.request_number}). We're now moving it forward.\n\nMidMan"
    )
    _send(user.email, subject, body)


def notify_kyc_decision(user: User, approved: bool, reason: str | None) -> None:
    subject = f"Your identity verification was {'approved' if approved else 'declined'}"
    body = (
        f"Hi {user.full_name},\n\n"
        + (
            "Your identity document has been verified - you're all set.\n\n"
            if approved
            else "We weren't able to verify your identity document."
            + (f"\n\nReason: {reason}" if reason else "")
            + "\n\nPlease upload a clearer copy in the MidMan app and we'll take another look.\n\n"
        )
        + "MidMan"
    )
    _send(user.email, subject, body)


def notify_company_kyc_decision(company: Company, approved: bool, reason: str | None) -> None:
    subject = f"Your Business account verification was {'approved' if approved else 'declined'}"
    body = (
        f"Hi {company.authorized_representative_name},\n\n"
        + (
            f"{company.legal_name}'s registration documents have been verified - your Business account "
            f"({company.business_id}) is now fully active.\n\n"
            if approved
            else f"We weren't able to verify {company.legal_name}'s registration documents."
            + (f"\n\nReason: {reason}" if reason else "")
            + "\n\nPlease upload clearer copies in the MidMan app and we'll take another look.\n\n"
        )
        + "MidMan"
    )
    _send(company.email, subject, body)


def notify_inspection_reminder(user: User, property_label: str | None) -> None:
    subject = "Time to book your next property inspection"
    where = f" for {property_label}" if property_label else ""
    body = (
        f"Hi {user.full_name},\n\n"
        f"This is your reminder to book a property inspection{where}. "
        "Open the MidMan app and request one under Property Management & Home "
        "Centre whenever you're ready - we'll take it from there.\n\n"
        "MidMan"
    )
    _send(user.email, subject, body)


def _send(to_email: str, subject: str, body: str) -> None:
    if not settings.smtp_host:
        logger.info("[email skipped - no SMTP configured] To: %s | %s\n%s", to_email, subject, body)
        return

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = settings.smtp_from_email
    msg["To"] = to_email
    msg.set_content(body)

    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as server:
            server.starttls()
            if settings.smtp_username:
                server.login(settings.smtp_username, settings.smtp_password)
            server.send_message(msg)
    except Exception:
        logger.exception("Failed to send email to %s", to_email)
