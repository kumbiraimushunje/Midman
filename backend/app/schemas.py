import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, EmailStr, ConfigDict, field_validator

from .city_availability import categories_available_in
from .models import AccountType, BusinessRole, KYCStatus, PaymentProvider, PaymentStatus, ReminderFrequency, RequestStatus, ServiceCategory, UserRole
from .service_taxonomy import SERVICE_TYPES_BY_CATEGORY
from .uploads import resolve_file_url


class RegisterRequest(BaseModel):
    full_name: str
    date_of_birth: date
    email: EmailStr
    phone: str
    username: str
    password: str
    physical_address: Optional[str] = None
    country_of_residence: str
    primary_purpose: Optional[str] = None


class LoginRequest(BaseModel):
    # Email, username, or phone - whichever the account was found by.
    identifier: str
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
    username: Optional[str] = None
    role: UserRole
    account_type: AccountType
    trial_ends_at: Optional[datetime] = None
    kyc_status: KYCStatus
    kyc_rejection_reason: Optional[str] = None
    country_of_residence: str
    created_at: datetime
    company_id: Optional[uuid.UUID] = None
    business_role: Optional[BusinessRole] = None


class CompanyOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    business_id: str
    legal_name: str
    trading_name: Optional[str] = None
    registration_number: str
    country: str
    registered_address: str
    business_address: Optional[str] = None
    industry: str
    authorized_representative_name: str
    email: EmailStr
    phone: str
    billing_contact_name: Optional[str] = None
    billing_contact_email: Optional[str] = None
    billing_contact_phone: Optional[str] = None
    operations_contact_name: Optional[str] = None
    operations_contact_email: Optional[str] = None
    operations_contact_phone: Optional[str] = None
    tax_details: Optional[str] = None
    kyc_status: KYCStatus
    kyc_rejection_reason: Optional[str] = None
    created_at: datetime


class BusinessRegisterRequest(BaseModel):
    # The registrant - becomes the company's first employee, as Administrator.
    full_name: str
    date_of_birth: date
    email: EmailStr
    phone: str
    username: str
    password: str

    # The company itself.
    legal_name: str
    trading_name: Optional[str] = None
    registration_number: str
    country: str
    registered_address: str
    business_address: Optional[str] = None
    industry: str
    authorized_representative_name: str
    company_email: EmailStr
    company_phone: str
    billing_contact_name: Optional[str] = None
    billing_contact_email: Optional[str] = None
    billing_contact_phone: Optional[str] = None
    operations_contact_name: Optional[str] = None
    operations_contact_email: Optional[str] = None
    operations_contact_phone: Optional[str] = None
    tax_details: Optional[str] = None


class EmployeeCreate(BaseModel):
    full_name: str
    date_of_birth: date
    email: EmailStr
    phone: str
    password: str
    business_role: BusinessRole


class EmployeeRoleUpdate(BaseModel):
    business_role: BusinessRole


class CompanyKYCReviewOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    business_id: str
    legal_name: str
    registration_number: str
    country: str
    email: EmailStr
    phone: str
    kyc_status: KYCStatus
    kyc_rejection_reason: Optional[str] = None
    created_at: datetime
    document_count: int = 0


class CompanyKYCDecisionRequest(BaseModel):
    approve: bool
    reason: Optional[str] = None


class InspectionReminderCreate(BaseModel):
    frequency: ReminderFrequency
    property_label: Optional[str] = None


class InspectionReminderOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    frequency: ReminderFrequency
    property_label: Optional[str] = None
    next_reminder_at: datetime
    active: bool


class CompanyDocumentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    file_url: str
    caption: Optional[str] = None
    created_at: datetime

    @field_validator("file_url", mode="before")
    @classmethod
    def _resolve_url(cls, v):
        return resolve_file_url(v)


class BeneficiaryCreate(BaseModel):
    full_name: str
    relationship_type: str
    address: Optional[str] = None
    preferences: Optional[dict] = None
    # Member ID, email, or phone - if it matches an existing customer account,
    # that account gets linked immediately as this beneficiary's MidMan login,
    # letting them raise Family Care & Child Support requests as a beneficiary
    # with the owner as their authorizer.
    linked_member_identifier: Optional[str] = None


class LinkedAccountOut(BaseModel):
    """The MidMan account a beneficiary is linked to - shown so the owner can
    see at a glance which of their beneficiaries can act as an initiator."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: EmailStr
    phone: str
    username: Optional[str] = None


class BeneficiaryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    full_name: str
    relationship_type: str
    address: Optional[str] = None
    preferences: Optional[dict] = None
    linked_user_id: Optional[uuid.UUID] = None
    linked_user: Optional[LinkedAccountOut] = None
    created_at: datetime


class AuthorizerOut(BaseModel):
    """A registered customer who has listed the current user as a beneficiary -
    the current user can raise Family Care & Child Support requests "as a
    beneficiary" with this person as their authorizer."""

    id: uuid.UUID
    full_name: str
    member_id: str
    relationship_type: str


class ServiceRequestCreate(BaseModel):
    country: Optional[str] = None
    city: Optional[str] = None
    category: ServiceCategory
    service_type: Optional[str] = None
    title: str
    description: Optional[str] = None
    beneficiary_id: Optional[uuid.UUID] = None
    amount: Optional[Decimal] = None
    currency: str = "USD"
    # Set only when raising a Family Care & Child Support request "as a
    # beneficiary" - must be a customer who has the requester linked as their
    # beneficiary (see Beneficiary.linked_user_id). That customer must approve
    # before a MidMan admin does.
    authorizer_id: Optional[uuid.UUID] = None

    @field_validator("category")
    @classmethod
    def _validate_category_available_in_city(cls, v: ServiceCategory, info) -> ServiceCategory:
        city = info.data.get("city")
        available = categories_available_in(city)
        if available is not None and v.value not in available:
            raise ValueError(f"'{v.value}' isn't offered in {city} yet")
        return v

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
    country: Optional[str] = None
    city: Optional[str] = None
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
    authorizer_id: Optional[uuid.UUID] = None
    authorizer_approved_at: Optional[datetime] = None
    admin_approved_at: Optional[datetime] = None
    admin_approved_by_id: Optional[uuid.UUID] = None


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
