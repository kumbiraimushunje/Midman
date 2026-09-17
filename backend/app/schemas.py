import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, EmailStr, ConfigDict, field_validator

from .models import AccountType, KYCStatus, PaymentProvider, PaymentStatus, RequestStatus, ServiceCategory, UserRole
from .service_taxonomy import SERVICE_TYPES_BY_CATEGORY
from .uploads import resolve_file_url


class RegisterRequest(BaseModel):
    full_name: str
    date_of_birth: date
    email: EmailStr
    phone: str
    password: str
    physical_address: Optional[str] = None
    country_of_residence: str
    primary_purpose: Optional[str] = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class DeleteAccountRequest(BaseModel):
    reason: Optional[str] = None


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    member_id: str
    full_name: str
    email: EmailStr
    phone: str
    role: UserRole
    account_type: AccountType
    trial_ends_at: Optional[datetime] = None
    kyc_status: KYCStatus
    kyc_rejection_reason: Optional[str] = None
    country_of_residence: str
    created_at: datetime


class SubscriptionChangeRequest(BaseModel):
    account_type: AccountType


class BeneficiaryCreate(BaseModel):
    full_name: str
    relationship_type: str
    address: Optional[str] = None
    preferences: Optional[dict] = None


class BeneficiaryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    relationship_type: str
    address: Optional[str] = None
    preferences: Optional[dict] = None
    created_at: datetime


class ServiceRequestCreate(BaseModel):
    category: ServiceCategory
    service_type: Optional[str] = None
    title: str
    description: Optional[str] = None
    beneficiary_id: Optional[uuid.UUID] = None
    amount: Optional[Decimal] = None
    currency: str = "USD"

    @field_validator("service_type")
    @classmethod
    def _validate_service_type(cls, v: Optional[str], info) -> Optional[str]:
        if not v:
            return v
        category = info.data.get("category")
        allowed = SERVICE_TYPES_BY_CATEGORY.get(category.value) if category else None
        if allowed and v not in allowed:
            raise ValueError(f"'{v}' isn't a valid service type for category '{category.value}'")
        return v


class RequestEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    status: RequestStatus
    note: Optional[str] = None
    created_at: datetime


class EvidenceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    file_url: str
    file_type: str
    caption: Optional[str] = None
    supplier_name: Optional[str] = None
    created_at: datetime

    @field_validator("file_url")
    @classmethod
    def _resolve_url(cls, stored_value: str) -> str:
        """DB stores a stable reference (local path or S3 key); this turns it
        into a URL that's actually fetchable right now, generating a fresh
        presigned S3 URL on every read rather than a static one that expires."""
        return resolve_file_url(stored_value)


class ServiceRequestOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    request_number: str
    category: ServiceCategory
    service_type: Optional[str] = None
    title: str
    description: Optional[str] = None
    amount: Optional[Decimal] = None
    currency: str
    status: RequestStatus
    decision_comment: Optional[str] = None
    fraud_risk_level: Optional[str] = None
    fraud_risk_score: Optional[int] = None
    fraud_reasoning: Optional[str] = None
    created_at: datetime
    requester: UserOut
    beneficiary: Optional[BeneficiaryOut] = None
    events: list[RequestEventOut] = []
    evidence: list[EvidenceOut] = []


class DecisionRequest(BaseModel):
    comment: Optional[str] = None


class StatusUpdateRequest(BaseModel):
    status: RequestStatus
    note: Optional[str] = None


class AiParseRequest(BaseModel):
    text: str


class AiParseResponse(BaseModel):
    category: ServiceCategory
    title: str
    description: Optional[str] = None
    beneficiary_id: Optional[uuid.UUID] = None
    beneficiary_name_hint: Optional[str] = None
    amount: Optional[Decimal] = None
    missing_info: list[str] = []
    ai_available: bool = True


class StatusCount(BaseModel):
    status: str
    count: int


class CategoryCount(BaseModel):
    category: str
    count: int


class TierCount(BaseModel):
    account_type: str
    count: int


class DashboardReport(BaseModel):
    total_requests: int
    total_customers: int
    new_customers_last_30_days: int
    requests_by_status: list[StatusCount]
    requests_by_category: list[CategoryCount]
    customers_by_tier: list[TierCount]
    total_amount_requested: Decimal
    total_amount_completed: Decimal
    high_risk_requests: int
    pending_approval_count: int


class KYCReviewOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    member_id: str
    full_name: str
    email: EmailStr
    phone: str
    country_of_residence: str
    id_document_path: str
    kyc_status: KYCStatus
    kyc_rejection_reason: Optional[str] = None
    created_at: datetime

    @field_validator("id_document_path", mode="before")
    @classmethod
    def _resolve_url(cls, stored_value: Optional[str]) -> str:
        """Despite the name (matching the ORM column), this is resolved into
        a fetchable URL - a local path passes through, an S3 key becomes a
        presigned link - before it ever reaches the client."""
        return resolve_file_url(stored_value) if stored_value else ""


class KYCDecisionRequest(BaseModel):
    approve: bool
    reason: Optional[str] = None


class AdminUserOut(UserOut):
    deleted_at: Optional[datetime] = None


class RoleChangeRequest(BaseModel):
    role: UserRole


class AuditLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    actor_name: str
    actor_role: str
    action: str
    entity_type: str
    entity_id: Optional[uuid.UUID] = None
    summary: str
    meta: Optional[dict] = None
    created_at: datetime


class SupplierQuoteSummary(BaseModel):
    supplier_name: str
    amount: Optional[Decimal] = None
    notes: Optional[str] = None


class QuoteComparisonOut(BaseModel):
    generated_at: datetime
    summary: str
    recommendation: Optional[str] = None
    suppliers: list[SupplierQuoteSummary]
    ai_available: bool = True


class ChatMessage(BaseModel):
    role: str  # "user" | "assistant"
    content: str


class SupportChatRequest(BaseModel):
    message: str
    history: list[ChatMessage] = []


class SupportChatResponse(BaseModel):
    reply: str
    ai_available: bool = True


class PaymentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    provider: PaymentProvider
    method: Optional[str] = None
    merchant_reference: str
    provider_reference: Optional[str] = None
    amount: Decimal
    currency: str
    status: PaymentStatus
    checkout_url: Optional[str] = None
    created_at: datetime
    paid_at: Optional[datetime] = None


class InitiatePaymentRequest(BaseModel):
    provider: PaymentProvider
    method: Optional[str] = None  # Paynow mobile only: "ecocash" | "onemoney"
    phone: Optional[str] = None  # required when method is set
