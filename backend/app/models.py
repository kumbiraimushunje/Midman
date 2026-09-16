import enum
import uuid
from datetime import datetime

from sqlalchemy import Column, String, ForeignKey, Numeric, DateTime, Enum, Integer, Text, Date
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship

from .database import Base


class UserRole(str, enum.Enum):
    customer = "customer"
    staff = "staff"       # concierge / ops staff who action requests, upload evidence
    approver = "approver"  # approves/rejects on behalf of a customer (e.g. company manager)
    admin = "admin"


class AccountType(str, enum.Enum):
    payg = "payg"
    standard = "standard"
    pro = "pro"


class KYCStatus(str, enum.Enum):
    pending = "pending"
    verified = "verified"
    rejected = "rejected"


class ServiceCategory(str, enum.Enum):
    school_fees = "school_fees"
    medical = "medical"
    prescriptions = "prescriptions"
    groceries = "groceries"
    family_essentials = "family_essentials"
    documents = "documents"
    government_errands = "government_errands"
    property_management = "property_management"
    property_inspection = "property_inspection"
    maintenance = "maintenance"
    cleaning = "cleaning"
    procurement = "procurement"
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

    created_at = Column(DateTime, default=datetime.utcnow)
    deleted_at = Column(DateTime, nullable=True)  # soft delete - account deletion is a launch requirement

    beneficiaries = relationship("Beneficiary", back_populates="owner", cascade="all, delete-orphan")
    requests_made = relationship(
        "ServiceRequest", back_populates="requester", foreign_keys="ServiceRequest.requester_id"
    )


class Beneficiary(Base):
    """A person or property a customer creates requests on behalf of (Mum, a child, a rental property, etc)."""

    __tablename__ = "beneficiaries"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    owner_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)

    full_name = Column(String, nullable=False)
    relationship_type = Column(String, nullable=False)  # e.g. "mother", "child", "property", "sibling"
    address = Column(String, nullable=True)

    # Free-form remembered preferences so recurring requests don't re-ask the
    # same questions - e.g. {"preferred_pharmacy": "...", "school": "...", "student_number": "..."}
    preferences = Column(JSONB, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)

    owner = relationship("User", back_populates="beneficiaries")
    requests = relationship("ServiceRequest", back_populates="beneficiary")


class ServiceRequest(Base):
    __tablename__ = "service_requests"

    id = Column(UUID(as_uuid=True), primary_key=True, default=new_uuid)
    request_number = Column(String, unique=True, nullable=False, index=True)  # e.g. MID-000123

    requester_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    beneficiary_id = Column(UUID(as_uuid=True), ForeignKey("beneficiaries.id"), nullable=True)
    approver_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    assigned_staff_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)

    category = Column(Enum(ServiceCategory), nullable=False)
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
