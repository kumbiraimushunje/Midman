"""Email notifications for the 4 customer-facing stages: Received, Arranging,
In Progress, Completed - plus approve/reject decisions.

Degrades gracefully: with no SMTP configured, it just logs instead of
sending, so local dev never needs a real mail server.
"""

import logging
import smtplib
from email.message import EmailMessage

from .config import settings
from .models import RequestStatus, ServiceRequest, User

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
