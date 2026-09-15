import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, EmailStr, ConfigDict, field_validator

from .models import AccountType, KYCStatus, RequestStatus, ServiceCategory, UserRole
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
    title: str
    description: Optional[str] = None
    beneficiary_id: Optional[uuid.UUID] = None
    amount: Optional[Decimal] = None
    currency: str = "USD"


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
