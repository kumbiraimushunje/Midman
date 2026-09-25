import enum
import uuid
from datetime import datetime

from sqlalchemy import Boolean, Column, String, ForeignKey, Numeric, DateTime, Enum, Integer, Text, Date
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship

from .database import Base


class UserRole(str, enum.Enum):
    customer = "customer"
    staff = "staff"       # concierge / ops staff who action requests, upload evidence
    admin = "admin"        # also handles approvals - there's no separate approver role


# There are no more paid membership tiers - every account is free and gets full
# benefits (saved beneficiaries, full request history, priority service). Kept
# only because the `account_type` column still exists in the database; nothing
# in the application branches on it anymore.
class AccountType(str, enum.Enum):
    payg = "payg"
    standard = "standard"
    pro = "pro"


class KYCStatus(str, enum.Enum):
    pending = "pending"
    verified = "verified"
    rejected = "rejected"


class ReminderFrequency(str, enum.Enum):
    monthly = "monthly"
    quarterly = "quarterly"
    biannual = "biannual"
    annual = "annual"


class BusinessRole(str, enum.Enum):
    """Fixed roles for employees of a Business account - see business_permissions.py
    for what each one can actually do. Only set when the user belongs to a Company."""
    administrator = "administrator"  # can do everything - create, approve spend, manage employees, view reports
    finance = "finance"              # approves spend/quotations, views reports - doesn't create requests
    operations = "operations"        # creates and manages requests day-to-day - can't approve spend
    requester = "requester"          # can create requests only, sees just their own
    viewer_auditor = "viewer_auditor"  # read-only - completed jobs and reports, no create/approve


class ServiceCategory(str, enum.Enum):
    # Retired - kept only so historical rows created before the 3-level
    # taxonomy (see service_taxonomy.py) stay valid. Never offered for new
    # requests; superseded by healthcare/education/document_collection/
    # document_delivery/tenant_coordination/property_cleaning below.
    school_fees = "school_fees"
    medical = "medical"
    prescriptions = "prescriptions"
    family_essentials = "family_essentials"
    documents = "documents"
    property_management = "property_management"
    cleaning = "cleaning"

    # Active - see service_taxonomy.py for the full Group -> Category ->
    # Service Type tree these belong to.
    groceries = "groceries"
    healthcare = "healthcare"
    education = "education"
    document_collection = "document_collection"
    document_delivery = "document_delivery"
    government_errands = "government_errands"
    property_inspection = "property_inspection"
    maintenance = "maintenance"
    tenant_coordination = "tenant_coordination"
    property_cleaning = "property_cleaning"
    building_materials = "building_materials"
    household_procurement = "household_procurement"
    procurement = "procurement"
    birthday_gifts = "birthday_gifts"
    anniversary_valentines_gifts = "anniversary_valentines_gifts"
    graduation_gifts = "graduation_gifts"
    corporate_gifts = "corporate_gifts"
    gifts = "gifts"
    transportation = "transportation"
    personal_concierge = "personal_concierge"
    other = "other"


class RequestStatus(str, enum.Enum):
    requested = "requested"
    arranging = "arranging"
    approval_required = "approval_required"
    payment_pending = "payment_pending"
    in_progress = "in_progress"
    completed = "completed"
    verified = "verified"
    closed = "closed"
    rejected = "rejected"
    cancelled = "cancelled"


# Statuses collapse to these 4 for customer-facing notifications/emails.
CUSTOMER_STAGE_MAP = {
    RequestStatus.requested: "received",
    RequestStatus.arranging: "arranging",
    RequestStatus.approval_required: "arranging",
    RequestStatus.payment_pending: "arranging",
    RequestStatus.in_progress: "in_progress",
    RequestStatus.completed: "completed",
    RequestStatus.verified: "completed",
    RequestStatus.closed: "completed",
    RequestStatus.rejected: "completed",
    RequestStatus.cancelled: "completed",
}


class EvidenceType(str, enum.Enum):
    photo = "photo"
    video = "video"
    document = "document"
    receipt = "receipt"
    quote = "quote"  # a supplier's price quote, gathered for quote-comparison


class PaymentProvider(str, enum.Enum):
    paynow = "paynow"  # Zimbabwe-local: EcoCash/OneMoney/ZimSwitch/local bank cards
    flutterwave = "flutterwave"  # international cards


class PaymentStatus(str, enum.Enum):
    pending = "pending"
    paid = "paid"
    failed = "failed"
    cancelled = "cancelled"


def new_uuid():
    return uuid.uuid4()


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    member_id = Column(String, unique=True, nullable=False, index=True)

    full_name = Column(String, nullable=False)
    date_of_birth = Column(Date, nullable=False)
    email = Column(String, unique=True, nullable=False, index=True)
    phone = Column(String, unique=True, nullable=False)
    # Nullable at the DB level so pre-existing rows stay valid - the
    # registration schemas require it for every new signup, and login
    # accepts it alongside email/phone as the identifier.
    username = Column(String, unique=True, nullable=True, index=True)
    password_hash = Column(String, nullable=False)

    physical_address = Column(String, nullable=True)
    country_of_residence = Column(String, nullable=False)
    primary_purpose = Column(String, nullable=True)  # children/parents/family/property/business/personal/other
    id_document_path = Column(String, nullable=True)
    kyc_status = Column(Enum(KYCStatus), default=KYCStatus.pending, nullable=False)
    kyc_rejection_reason = Column(String, nullable=True)
    kyc_reviewed_at = Column(DateTime, nullable=True)

    role = Column(Enum(UserRole), default=UserRole.customer, nullable=False)
    account_type = Column(Enum(AccountType), default=AccountType.payg, nullable=False)
    trial_ends_at = Column(DateTime, nullable=True)

    # Set only for employees of a MidMan Business account (see Company below).
    # A personal/individual customer has both of these as NULL.
    company_id = Column(UUID(as_uuid=True), ForeignKey("companies.id"), nullable=True)
    business_role = Column(Enum(BusinessRole), nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    deleted_at = Column(DateTime, nullable=True)  # soft delete - account deletion is a launch requirement
    deletion_reason = Column(String, nullable=True)  # optional feedback captured when the customer deletes their own account

    beneficiaries = relationship(
        "Beneficiary", back_populates="owner", cascade="all, delete-orphan", foreign_keys="Beneficiary.owner_id"
    )
    requests_made = relationship(
        "ServiceRequest", back_populates="requester", foreign_keys="ServiceRequest.requester_id"
    )
    company = relationship("Company", back_populates="employees", foreign_keys=[company_id])


class Company(Base):
    """A MidMan Business account. A company isn't a login itself - it's the
    umbrella a fixed set of employee Users (see BusinessRole) are created
    under, each with their own login and permissions. The registrant of the
    business automatically becomes its first employee with the
    administrator role (see /auth/register-business)."""

    __tablename__ = "companies"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    business_id = Column(String, unique=True, nullable=False, index=True)  # e.g. BUS-000001

    legal_name = Column(String, nullable=False)
    trading_name = Column(String, nullable=True)
    registration_number = Column(String, nullable=False)
    country = Column(String, nullable=False)
    registered_address = Column(String, nullable=False)
    business_address = Column(String, nullable=True)  # if different from the registered address
    industry = Column(String, nullable=False)

    authorized_representative_name = Column(String, nullable=False)
    email = Column(String, nullable=False)
    phone = Column(String, nullable=False)

    billing_contact_name = Column(String, nullable=True)
    billing_contact_email = Column(String, nullable=True)
    billing_contact_phone = Column(String, nullable=True)
    operations_contact_name = Column(String, nullable=True)
    operations_contact_email = Column(String, nullable=True)
    operations_contact_phone = Column(String, nullable=True)

    tax_details = Column(String, nullable=True)  # VAT/tax ID, where required

    kyc_status = Column(Enum(KYCStatus), default=KYCStatus.pending, nullable=False)
    kyc_rejection_reason = Column(String, nullable=True)
    kyc_reviewed_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    deleted_at = Column(DateTime, nullable=True)

    employees = relationship("User", back_populates="company", foreign_keys=[User.company_id])
    documents = relationship("CompanyDocument", back_populates="company", cascade="all, delete-orphan")


class CompanyDocument(Base):
    """Company registration documents (certificate of incorporation, tax
    clearance, etc) uploaded for the staff KYC-style review of a Business
    account - the company equivalent of User.id_document_path."""

    __tablename__ = "company_documents"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    company_id = Column(UUID(as_uuid=True), ForeignKey("companies.id"), nullable=False)
    uploaded_by_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)

    file_url = Column(String, nullable=False)
    caption = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    company = relationship("Company", back_populates="documents")


class Beneficiary(Base):
    """A person or property a customer creates requests on behalf of (Mum, a child, a rental property, etc)."""

    __tablename__ = "beneficiaries"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    owner_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)

    # Set when this beneficiary was matched to a real MidMan customer account
    # at creation time (looked up by member ID, email, or phone). That linked
    # customer becomes able to raise requests "as a beneficiary" with the
    # owner (`owner_id`) as their authorizer - see ServiceRequest.authorizer_id.
    linked_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)

    full_name = Column(String, nullable=False)
    relationship_type = Column(String, nullable=False)  # e.g. "mother", "child", "property", "sibling"
    address = Column(String, nullable=True)

    # Free-form remembered preferences so recurring requests don't re-ask the
    # same questions - e.g. {"preferred_pharmacy": "...", "school": "...", "student_number": "..."}
    preferences = Column(JSONB, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)

    owner = relationship("User", back_populates="beneficiaries", foreign_keys=[owner_id])
    linked_user = relationship("User", foreign_keys=[linked_user_id])
    requests = relationship("ServiceRequest", back_populates="beneficiary")


class ServiceRequest(Base):
    __tablename__ = "service_requests"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    request_number = Column(String, unique=True, nullable=False, index=True)  # e.g. MID-000123

    requester_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    beneficiary_id = Column(UUID(as_uuid=True), ForeignKey("beneficiaries.id"), nullable=True)
    approver_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    assigned_staff_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)

    # Set only for a Family Care & Child Support request the requester raised
    # "as a beneficiary" - the linked customer (see Beneficiary.linked_user_id)
    # who must sign off before this goes to a MidMan admin. Null for a normal
    # direct request.
    authorizer_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    authorizer_approved_at = Column(DateTime, nullable=True)

    # Every request needs this before staff can move it past "requested" -
    # see the admin-approve endpoint and update_status's gate on it.
    admin_approved_at = Column(DateTime, nullable=True)
    admin_approved_by_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)

    category = Column(Enum(ServiceCategory), nullable=False)
    service_type = Column(String, nullable=True)  # the specific Level-3 pick within `category` - see service_taxonomy.py
    country = Column(String, nullable=True)  # where the service is needed (defaults to the requester's own country)
    city = Column(String, nullable=True)  # only set for countries with cities modeled - see city_availability.py
    title = Column(String, nullable=False)
    description = Column(Text, nullable=True)

    amount = Column(Numeric(12, 2), nullable=True)  # null until a quote/price is known
    currency = Column(String, default="USD", nullable=False)

    status = Column(Enum(RequestStatus), default=RequestStatus.requested, nullable=False)
    decision_comment = Column(String, nullable=True)

    fraud_risk_level = Column(String, nullable=True)  # "low" | "medium" | "high"
    fraud_risk_score = Column(Integer, nullable=True)  # 0-100
    fraud_reasoning = Column(String, nullable=True)
    fraud_checked_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    decided_at = Column(DateTime, nullable=True)

    # Cached AI comparison across this request's "quote"-type evidence -
    # regenerated on demand rather than kept live, so it's just a snapshot.
    quote_comparison = Column(JSONB, nullable=True)
    quote_comparison_generated_at = Column(DateTime, nullable=True)

    requester = relationship("User", back_populates="requests_made", foreign_keys=[requester_id])
    beneficiary = relationship("Beneficiary", back_populates="requests")
    events = relationship(
        "RequestEvent", back_populates="request", cascade="all, delete-orphan", order_by="RequestEvent.created_at"
    )
    evidence = relationship("Evidence", back_populates="request", cascade="all, delete-orphan")
    payments = relationship(
        "Payment", back_populates="request", cascade="all, delete-orphan", order_by="Payment.created_at"
    )


class RequestEvent(Base):
    """Append-only timeline entry shown to the customer and used for the audit log."""

    __tablename__ = "request_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    request_id = Column(UUID(as_uuid=True), ForeignKey("service_requests.id"), nullable=False)

    status = Column(Enum(RequestStatus), nullable=False)
    note = Column(String, nullable=True)
    created_by_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    request = relationship("ServiceRequest", back_populates="events")


class Evidence(Base):
    """Photos/documents/receipts staff or the platform attach as proof of work done."""

    __tablename__ = "evidence"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    request_id = Column(UUID(as_uuid=True), ForeignKey("service_requests.id"), nullable=False)

    file_url = Column(String, nullable=False)
    file_type = Column(Enum(EvidenceType), nullable=False)
    caption = Column(String, nullable=True)
    supplier_name = Column(String, nullable=True)  # set on quote-type evidence, used by quote comparison
    uploaded_by_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    request = relationship("ServiceRequest", back_populates="evidence")


class Payment(Base):
    """One attempt to pay for a request through a gateway. A request can have
    several rows here if an earlier attempt failed/was abandoned and the
    customer tried again - the request's own status only advances once one
    of these actually reaches `paid`."""

    __tablename__ = "payments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    request_id = Column(UUID(as_uuid=True), ForeignKey("service_requests.id"), nullable=False)

    provider = Column(Enum(PaymentProvider), nullable=False)
    method = Column(String, nullable=True)  # e.g. "ecocash", "onemoney", "card"
    merchant_reference = Column(String, unique=True, nullable=False, index=True)  # our own reference, e.g. MIDPAY-000123
    provider_reference = Column(String, nullable=True, index=True)  # the gateway's own transaction id/reference

    amount = Column(Numeric(12, 2), nullable=False)
    currency = Column(String, nullable=False)
    status = Column(Enum(PaymentStatus), default=PaymentStatus.pending, nullable=False)
    raw_status = Column(String, nullable=True)  # last raw provider status text, for support/debugging

    checkout_url = Column(String, nullable=True)  # web-redirect flow (both providers)
    poll_url = Column(String, nullable=True)  # Paynow only

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    paid_at = Column(DateTime, nullable=True)

    request = relationship("ServiceRequest", back_populates="payments")


class MemberIdCounter(Base):
    """Per-prefix sequence used to generate Member IDs like MUS000001. See id_generator.py."""

    __tablename__ = "member_id_counters"

    prefix = Column(String(3), primary_key=True)
    next_seq = Column(Integer, nullable=False, default=1)


class AuditLog(Base):
    """Append-only record of who changed what, when, across the whole system -
    the general-purpose counterpart to RequestEvent, which only covers a
    single service request's status timeline. Actor details are denormalized
    (stored as plain strings, not a live join) so a row stays accurate and
    readable even if the actor is later renamed or deactivated."""

    __tablename__ = "audit_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)

    actor_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    actor_name = Column(String, nullable=False)
    actor_role = Column(String, nullable=False)

    action = Column(String, nullable=False)  # e.g. "user.role_change", "kyc.decision", "request.approve"
    entity_type = Column(String, nullable=False)  # e.g. "user", "service_request"
    entity_id = Column(UUID(as_uuid=True), nullable=True)
    summary = Column(String, nullable=False)  # human-readable one-liner shown in the log
    meta = Column(JSONB, nullable=True)  # structured before/after detail, when useful

    created_at = Column(DateTime, default=datetime.utcnow, index=True)


class InspectionReminder(Base):
    """A customer's opt-in recurring email nudge to book their next property
    inspection - "Property Inspections choose timer monthly... for email
    reminders, optional." Deliberately just an email nudge, not an
    auto-created request: it links back into the app so the customer still
    reviews and confirms every field themselves, same as everywhere else in
    MidMan a request gets created.

    One active reminder per user for now (a second POST just updates this
    row) - see app/reminders.py for the frequency -> interval mapping and
    the send loop that advances next_reminder_at after each email."""

    __tablename__ = "inspection_reminders"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), unique=True, nullable=False)

    frequency = Column(Enum(ReminderFrequency), nullable=False)
    property_label = Column(String, nullable=True)  # optional free-text, e.g. "Borrowdale rental"
    next_reminder_at = Column(DateTime, nullable=False)
    active = Column(Boolean, default=True, nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow)
    last_sent_at = Column(DateTime, nullable=True)


class PasswordResetOTP(Base):
    """A one-time 6-digit code emailed to a customer who's forgotten their
    password - see /auth/forgot-password and /auth/reset-password.
    Single-use (consumed_at) and short-lived (expires_at); attempts is a
    brute-force guard - too many wrong tries on one code invalidates it,
    same as it expiring, so the customer has to request a fresh one."""

    __tablename__ = "password_reset_otps"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)

    code = Column(String, nullable=False)
    attempts = Column(Integer, default=0, nullable=False)
    consumed_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)
