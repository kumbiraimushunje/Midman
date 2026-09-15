import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, EmailStr, ConfigDict

from .models import AccountType, KYCStatus, RequestStatus, ServiceCategory, UserRole


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
    kyc_status: KYCStatus
    country_of_residence: str
    created_at: datetime


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
    events: list[RequestEventOut] = []
    evidence: list[EvidenceOut] = []


class DecisionRequest(BaseModel):
    comment: Optional[str] = None


class StatusUpdateRequest(BaseModel):
    status: RequestStatus
    note: Optional[str] = None
