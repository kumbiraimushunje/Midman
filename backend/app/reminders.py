"""Property Inspection reminders - "choose timer monthly... for email
reminders, optional."

Deliberately just an email nudge on the chosen schedule ("Time to book your
next inspection"), never an auto-created request - the customer still comes
into the app and confirms every field themselves, same as everywhere else.

The Render deployment (see ../../render.yaml) runs this daily via the
midman-reminder-cron job, which calls send_due_reminders() below through
POST /reminders/property-inspection/run-due (scripts/trigger_reminders.py).
Locally, or if CRON_SECRET is left unset, nothing calls it automatically -
staff can still trigger it by hand from the KYC Review screen's bell icon.
"""

from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from .models import InspectionReminder, ReminderFrequency, User
from .notifications import notify_inspection_reminder

_INTERVALS: dict[ReminderFrequency, timedelta] = {
    ReminderFrequency.monthly: timedelta(days=30),
    ReminderFrequency.quarterly: timedelta(days=91),
    ReminderFrequency.biannual: timedelta(days=182),
    ReminderFrequency.annual: timedelta(days=365),
}


def next_due_at(frequency: ReminderFrequency, from_time: datetime | None = None) -> datetime:
    return (from_time or datetime.utcnow()) + _INTERVALS[frequency]


def send_due_reminders(db: Session) -> int:
    """Emails everyone whose active reminder is due, then reschedules each
    for its next interval. Returns how many were sent."""
    due = (
        db.query(InspectionReminder)
        .filter(InspectionReminder.active.is_(True), InspectionReminder.next_reminder_at <= datetime.utcnow())
        .all()
    )
    sent = 0
    for reminder in due:
        user = db.query(User).filter(User.id == reminder.user_id).first()
        if user is None or user.deleted_at is not None:
            continue
        notify_inspection_reminder(user, reminder.property_label)
        reminder.last_sent_at = datetime.utcnow()
        reminder.next_reminder_at = next_due_at(reminder.frequency, reminder.last_sent_at)
        sent += 1
    db.commit()
    return sent
