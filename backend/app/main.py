from datetime import datetime
from decimal import Decimal
from pathlib import Path
from typing import Optional

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, Query, Request, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import case, or_
from sqlalchemy.orm import Session

from . import flutterwave_gateway, paynow_gateway, schemas
from .ai_concierge import answer_support_question, compare_quotes, parse_invoice_document, parse_request_text
from .audit import record_audit
from .config import settings
from .database import get_db
from .fraud_check import run_fraud_check
from .business_permissions import (
    can_approve_spending,
    can_create_request,
    can_manage_employees,
    can_view_all_company_requests,
    can_view_company_reports,
    visible_statuses_for_business_role,
)
from .id_generator import generate_business_id, generate_member_id, generate_payment_reference, generate_request_number
from .models import (
    CUSTOMER_STAGE_MAP,
    AccountType,
    AuditLog,
    Beneficiary,
    BusinessRole,
    Company,
    CompanyDocument,
    Evidence,
    EvidenceType,
    InspectionReminder,
    KYCStatus,
    Payment,
    PaymentProvider,
    PaymentStatus,
    RequestEvent,
    RequestStatus,
    ServiceRequest,
    User,
    UserRole,
)
from .notifications import (
    notify_company_kyc_decision,
    notify_decision,
    notify_kyc_decision,
    notify_payment_received,
    notify_status_change,
)
from .reminders import next_due_at, send_due_reminders
from .reports import build_dashboard_report
from .security import create_access_token, get_current_user, get_current_user_optional, hash_password, verify_password
from .subscriptions import can_manage_beneficiaries, trial_ends_at_for_new_user, visible_statuses_for
from .uploads import UPLOAD_DIR, content_type_for, read_upload_bytes, save_upload

app = FastAPI(title="MidMan API")
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten before production
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------- Auth ----------

@app.post("/auth/register", response_model=schemas.UserOut, status_code=201)
def register(payload: schemas.RegisterRequest, db: Session = Depends(get_db)):
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(400, "Email already registered")
    if db.query(User).filter(User.phone == payload.phone).first():
        raise HTTPException(400, "Phone already registered")
    if db.query(User).filter(User.username == payload.username).first():
        raise HTTPException(400, "Username already taken")

    member_id = generate_member_id(db, payload.full_name)
    user = User(
        member_id=member_id,
        full_name=payload.full_name,
        date_of_birth=payload.date_of_birth,
        email=payload.email,
        phone=payload.phone,
        username=payload.username,
        password_hash=hash_password(payload.password),
        physical_address=payload.physical_address,
        country_of_residence=payload.country_of_residence,
        primary_purpose=payload.primary_purpose,
        trial_ends_at=trial_ends_at_for_new_user(),
    )
    db.add(user)
    db.flush()  # assigns user.id before the audit row references it
    record_audit(db, user, "user.register", "user", f"{user.full_name} registered", entity_id=user.id)
    db.commit()
    db.refresh(user)
    return user


@app.post("/auth/register-business", response_model=schemas.Token, status_code=201)
def register_business(payload: schemas.BusinessRegisterRequest, db: Session = Depends(get_db)):
    """Registers a MidMan Business account: creates the Company (kyc_status
    starts pending, same as an individual's id-document review) and the
    registrant as its first employee with the administrator role - they can
    then add Sarah, John, Mary, Peter etc. from the Employees screen."""
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(400, "Email already registered")
    if db.query(User).filter(User.phone == payload.phone).first():
        raise HTTPException(400, "Phone already registered")
    if db.query(User).filter(User.username == payload.username).first():
        raise HTTPException(400, "Username already taken")

    company = Company(
        business_id=generate_business_id(db),
        legal_name=payload.legal_name,
        trading_name=payload.trading_name,
        registration_number=payload.registration_number,
        country=payload.country,
        registered_address=payload.registered_address,
        business_address=payload.business_address,
        industry=payload.industry,
        authorized_representative_name=payload.authorized_representative_name,
        email=payload.company_email,
        phone=payload.company_phone,
        billing_contact_name=payload.billing_contact_name,
        billing_contact_email=payload.billing_contact_email,
        billing_contact_phone=payload.billing_contact_phone,
        operations_contact_name=payload.operations_contact_name,
        operations_contact_email=payload.operations_contact_email,
        operations_contact_phone=payload.operations_contact_phone,
        tax_details=payload.tax_details,
    )
    db.add(company)
    db.flush()  # assigns company.id before the registrant references it

    member_id = generate_member_id(db, payload.full_name)
    user = User(
        member_id=member_id,
        full_name=payload.full_name,
        date_of_birth=payload.date_of_birth,
        email=payload.email,
        phone=payload.phone,
        username=payload.username,
        password_hash=hash_password(payload.password),
        country_of_residence=payload.country,
        primary_purpose="Business",
        trial_ends_at=trial_ends_at_for_new_user(),
        company_id=company.id,
        business_role=BusinessRole.administrator,
    )
    db.add(user)
    db.flush()
    record_audit(
        db, user, "company.register", "company",
        f"{user.full_name} registered {company.legal_name} as a Business account ({company.business_id})",
        entity_id=company.id,
    )
    db.commit()
    return schemas.Token(access_token=create_access_token(str(user.id)))


@app.post("/auth/login", response_model=schemas.Token)
def login(payload: schemas.LoginRequest, db: Session = Depends(get_db)):
    user = (
        db.query(User)
        .filter(
            or_(User.email == payload.identifier, User.username == payload.identifier, User.phone == payload.identifier),
            User.deleted_at.is_(None),
        )
        .first()
    )
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(401, "Incorrect email, username, phone, or password")
    return schemas.Token(access_token=create_access_token(str(user.id)))


@app.get("/me", response_model=schemas.UserOut)
def read_me(current_user: User = Depends(get_current_user)):
    return current_user


@app.delete("/me", status_code=204)
def delete_me(
    payload: schemas.DeleteAccountRequest = schemas.DeleteAccountRequest(),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    current_user.deleted_at = datetime.utcnow()
    current_user.deletion_reason = payload.reason
    record_audit(
        db, current_user, "user.self_delete", "user",
        f"{current_user.full_name} deleted their own account", entity_id=current_user.id,
        meta={"reason": payload.reason} if payload.reason else None,
    )
    db.commit()


@app.post("/me/subscription", response_model=schemas.UserOut)
def change_subscription(
    payload: schemas.SubscriptionChangeRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Self-service tier switch. No payment gateway wired up yet - pricing
    for each tier hasn't been set, so this just records the choice."""
    old_tier = current_user.account_type.value
    current_user.account_type = payload.account_type
    record_audit(
        db,
        current_user,
        "user.subscription_change",
        "user",
        f"{current_user.full_name} switched from {old_tier} to {payload.account_type.value}",
        entity_id=current_user.id,
        meta={"from": old_tier, "to": payload.account_type.value},
    )
    db.commit()
    db.refresh(current_user)
    return current_user


@app.post("/me/kyc-document", response_model=schemas.UserOut)
async def upload_kyc_document(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Customer uploads (or re-uploads, after a rejection) their id/passport.
    Always resets status to pending - staff review it from there."""
    file_url = await save_upload(file)
    current_user.id_document_path = file_url
    current_user.kyc_status = KYCStatus.pending
    current_user.kyc_rejection_reason = None
    current_user.kyc_reviewed_at = None
    db.commit()
    db.refresh(current_user)
    return current_user


# ---------- AI concierge ----------

@app.post("/ai/parse-request", response_model=schemas.AiParseResponse)
def ai_parse_request(
    payload: schemas.AiParseRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Turns free text ("Pay my daughter's school fees") into a structured
    draft the customer reviews and edits before submitting - this endpoint
    never creates a request itself."""
    beneficiaries = db.query(Beneficiary).filter(Beneficiary.owner_id == current_user.id).all()
    return parse_request_text(payload.text, beneficiaries)


_INVOICE_MAX_BYTES = 10 * 1024 * 1024
_INVOICE_CONTENT_TYPES = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".heic": "image/heic",
    ".pdf": "application/pdf",
}


@app.post("/ai/parse-invoice", response_model=schemas.AiParseResponse)
async def ai_parse_invoice(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Same idea as /ai/parse-request, but reads an uploaded invoice or price
    quote (a photo, or a text-based PDF) instead of typed text - still never
    creates or submits a request itself. The file is only held in memory for
    parsing, not stored - if the customer wants to keep it as proof, they
    attach it as evidence after creating the request, same as any other file."""
    suffix = Path(file.filename or "").suffix.lower()
    content_type = _INVOICE_CONTENT_TYPES.get(suffix)
    if content_type is None:
        raise HTTPException(400, f"Unsupported file type '{suffix}'. Upload a photo (jpg/png/webp/heic) or a PDF.")

    contents = await file.read()
    if not contents:
        raise HTTPException(400, "Empty file")
    if len(contents) > _INVOICE_MAX_BYTES:
        raise HTTPException(400, "File too large (max 10 MB)")

    beneficiaries = db.query(Beneficiary).filter(Beneficiary.owner_id == current_user.id).all()
    return parse_invoice_document(contents, file.filename or "invoice", content_type, beneficiaries)


@app.post("/ai/support-chat", response_model=schemas.SupportChatResponse)
def ai_support_chat(
    payload: schemas.SupportChatRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """General help/FAQ chatbot - answers questions about the platform and the
    customer's own recent requests. Read-only: it never creates, changes, or
    cancels anything itself, and the conversation isn't persisted server-side -
    the client resends recent history with each message."""
    recent = (
        db.query(ServiceRequest)
        .filter(ServiceRequest.requester_id == current_user.id)
        .order_by(ServiceRequest.created_at.desc())
        .limit(5)
        .all()
    )
    context = {
        "full_name": current_user.full_name,
        "member_id": current_user.member_id,
        "role": current_user.role.value,
        "account_type": current_user.account_type.value,
        "kyc_status": current_user.kyc_status.value,
        "recent_requests": [
            {
                "request_number": r.request_number,
                "title": r.title,
                "status": r.status.value,
                "created_at": r.created_at.isoformat(),
            }
            for r in recent
        ],
    }
    history = [h.model_dump() for h in payload.history]
    return answer_support_question(payload.message, history, context)


# ---------- Beneficiaries ----------

@app.post("/beneficiaries", response_model=schemas.BeneficiaryOut, status_code=201)
def create_beneficiary(
    payload: schemas.BeneficiaryCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not can_manage_beneficiaries(current_user):
        raise HTTPException(
            403,
            "PAYG doesn't support saved beneficiaries - upgrade to Standard or Pro "
            "to save the people you look after instead of re-entering details each time.",
        )
    beneficiary = Beneficiary(owner_id=current_user.id, **payload.model_dump())
    db.add(beneficiary)
    db.commit()
    db.refresh(beneficiary)
    return beneficiary


@app.get("/beneficiaries", response_model=list[schemas.BeneficiaryOut])
def list_beneficiaries(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return db.query(Beneficiary).filter(Beneficiary.owner_id == current_user.id).all()


# ---------- Service requests ----------

@app.post("/service-requests", response_model=schemas.ServiceRequestOut, status_code=201)
def create_service_request(
    payload: schemas.ServiceRequestCreate,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not can_create_request(current_user):
        raise HTTPException(403, "Your role isn't allowed to create requests - ask your Administrator")
    if payload.beneficiary_id is not None:
        beneficiary = (
            db.query(Beneficiary)
            .filter(Beneficiary.id == payload.beneficiary_id, Beneficiary.owner_id == current_user.id)
            .first()
        )
        if beneficiary is None:
            raise HTTPException(404, "Beneficiary not found")

    req = ServiceRequest(
        request_number=generate_request_number(db),
        requester_id=current_user.id,
        beneficiary_id=payload.beneficiary_id,
        country=payload.country or current_user.country_of_residence,
        city=payload.city,
        category=payload.category,
        service_type=payload.service_type,
        title=payload.title,
        description=payload.description,
        amount=payload.amount,
        currency=payload.currency,
    )
    db.add(req)
    db.flush()
    db.add(RequestEvent(request_id=req.id, status=RequestStatus.requested, created_by_id=current_user.id))
    db.commit()
    db.refresh(req)

    background_tasks.add_task(run_fraud_check, req.id)
    background_tasks.add_task(
        notify_status_change, current_user, req, CUSTOMER_STAGE_MAP[RequestStatus.requested]
    )
    return req


@app.get("/service-requests", response_model=list[schemas.ServiceRequestOut])
def list_all_requests(
    status_filter: RequestStatus | None = Query(None, alias="status"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The staff/admin work queue - every request, optionally filtered by
    status. Pro customers' requests surface first ("prioritised first")."""
    if current_user.role not in (UserRole.staff, UserRole.admin, UserRole.approver):
        raise HTTPException(403, "Staff only")
    query = db.query(ServiceRequest).join(User, ServiceRequest.requester_id == User.id)
    if status_filter is not None:
        query = query.filter(ServiceRequest.status == status_filter)
    priority = case((User.account_type == AccountType.pro, 0), else_=1)
    return query.order_by(priority, ServiceRequest.created_at.desc()).all()


@app.get("/service-requests/mine", response_model=list[schemas.ServiceRequestOut])
def my_requests(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """PAYG only sees requests still in flight ("no list of previous transactions").
    Business employees with company-wide visibility (Administrator, Finance,
    Operations, Viewer/Auditor) see every request raised by anyone in their
    company; a Requester only ever sees their own."""
    if current_user.company_id is not None and can_view_all_company_requests(current_user):
        query = (
            db.query(ServiceRequest)
            .join(User, ServiceRequest.requester_id == User.id)
            .filter(User.company_id == current_user.company_id)
        )
    else:
        query = db.query(ServiceRequest).filter(ServiceRequest.requester_id == current_user.id)
    allowed_statuses = visible_statuses_for(current_user)
    if allowed_statuses is not None:
        query = query.filter(ServiceRequest.status.in_(allowed_statuses))
    business_statuses = visible_statuses_for_business_role(current_user)
    if business_statuses is not None:
        query = query.filter(ServiceRequest.status.in_(business_statuses))
    return query.order_by(ServiceRequest.created_at.desc()).all()


@app.get("/service-requests/pending", response_model=list[schemas.ServiceRequestOut])
def pending_for_approval(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if current_user.role not in (UserRole.approver, UserRole.admin, UserRole.staff):
        raise HTTPException(403, "Not an approver")
    return (
        db.query(ServiceRequest)
        .filter(ServiceRequest.status == RequestStatus.approval_required)
        .order_by(ServiceRequest.created_at.asc())
        .all()
    )


def _get_request_or_404(request_id, db: Session) -> ServiceRequest:
    req = db.query(ServiceRequest).filter(ServiceRequest.id == request_id).first()
    if req is None:
        raise HTTPException(404, "Request not found")
    return req


@app.get("/service-requests/{request_id}", response_model=schemas.ServiceRequestOut)
def get_request(
    request_id,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    req = _get_request_or_404(request_id, db)
    is_owner = req.requester_id == current_user.id
    is_staff = current_user.role in (UserRole.staff, UserRole.admin, UserRole.approver)
    if not (is_owner or is_staff):
        raise HTTPException(403, "Not your request")
    return req


@app.delete("/service-requests/{request_id}", status_code=204)
def delete_request(
    request_id,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lets a customer remove a request they raised by mistake. Only while
    it's still in the initial 'requested' stage - once staff have started
    arranging it, approval/payment/completion records depend on it existing,
    so from there on the customer can only wait it out or ask staff to
    reject it. Hard-deletes the row (events/evidence/payments cascade) since
    there's nothing worth keeping for a request nobody ever acted on."""
    req = _get_request_or_404(request_id, db)
    if req.requester_id != current_user.id:
        raise HTTPException(403, "Not your request")
    if req.status != RequestStatus.requested:
        raise HTTPException(400, "This request is already being processed and can no longer be deleted")
    record_audit(
        db, current_user, "request.delete", "service_request",
        f"{current_user.full_name} deleted request {req.request_number} ({req.title})",
        entity_id=req.id,
    )
    db.delete(req)
    db.commit()


@app.post("/service-requests/{request_id}/evidence", response_model=schemas.EvidenceOut, status_code=201)
async def upload_evidence(
    request_id,
    file: UploadFile = File(...),
    file_type: EvidenceType = Form(...),
    caption: str | None = Form(None),
    supplier_name: str | None = Form(None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The requester can attach an invoice/photo when submitting a request; staff attach
    completion proof (photos, receipts, delivery confirmation) as work progresses, or a
    supplier's price quote (file_type=quote, with supplier_name) to compare later."""
    req = _get_request_or_404(request_id, db)
    is_owner = req.requester_id == current_user.id
    is_staff = current_user.role in (UserRole.staff, UserRole.admin, UserRole.approver)
    if not (is_owner or is_staff):
        raise HTTPException(403, "Not your request")

    file_url = await save_upload(file)
    evidence = Evidence(
        request_id=req.id,
        file_url=file_url,
        file_type=file_type,
        caption=caption,
        supplier_name=supplier_name if file_type == EvidenceType.quote else None,
        uploaded_by_id=current_user.id,
    )
    db.add(evidence)
    db.commit()
    db.refresh(evidence)
    return evidence


@app.get("/service-requests/{request_id}/quote-comparison", response_model=schemas.QuoteComparisonOut | None)
def get_quote_comparison(
    request_id,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role not in (UserRole.staff, UserRole.admin, UserRole.approver):
        raise HTTPException(403, "Staff only")
    req = _get_request_or_404(request_id, db)
    if req.quote_comparison is None:
        return None
    return {**req.quote_comparison, "generated_at": req.quote_comparison_generated_at}


@app.post("/service-requests/{request_id}/quote-comparison", response_model=schemas.QuoteComparisonOut)
def generate_quote_comparison(
    request_id,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """(Re)generates an AI comparison across every quote-type evidence file attached to
    this request - just an aid for staff deciding which supplier to go with, never
    binding and never surfaced to the customer directly."""
    if current_user.role not in (UserRole.staff, UserRole.admin, UserRole.approver):
        raise HTTPException(403, "Staff only")
    req = _get_request_or_404(request_id, db)

    quote_evidence = (
        db.query(Evidence)
        .filter(Evidence.request_id == req.id, Evidence.file_type == EvidenceType.quote)
        .order_by(Evidence.created_at.asc())
        .all()
    )
    if len(quote_evidence) < 2:
        raise HTTPException(400, "Need at least 2 supplier quotes attached to compare them.")

    quotes = [
        {
            "supplier_name": e.supplier_name or "Unnamed supplier",
            "content_type": content_type_for(e.file_url),
            "data": read_upload_bytes(e.file_url),
        }
        for e in quote_evidence
    ]
    result = compare_quotes(quotes)

    req.quote_comparison = result
    req.quote_comparison_generated_at = datetime.utcnow()
    db.commit()
    return {**result, "generated_at": req.quote_comparison_generated_at}


@app.post("/service-requests/{request_id}/approve", response_model=schemas.ServiceRequestOut)
def approve_request(
    request_id,
    payload: schemas.DecisionRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role not in (UserRole.approver, UserRole.admin, UserRole.staff):
        raise HTTPException(403, "Not an approver")
    req = _get_request_or_404(request_id, db)
    req.status = RequestStatus.payment_pending
    req.approver_id = current_user.id
    req.decision_comment = payload.comment
    req.decided_at = datetime.utcnow()
    db.add(RequestEvent(request_id=req.id, status=req.status, note=payload.comment, created_by_id=current_user.id))
    record_audit(
        db, current_user, "request.approve", "service_request",
        f"{current_user.full_name} approved {req.request_number}", entity_id=req.id,
    )
    db.commit()
    db.refresh(req)
    background_tasks.add_task(notify_decision, req.requester, req, True, payload.comment)
    return req


@app.post("/service-requests/{request_id}/reject", response_model=schemas.ServiceRequestOut)
def reject_request(
    request_id,
    payload: schemas.DecisionRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role not in (UserRole.approver, UserRole.admin, UserRole.staff):
        raise HTTPException(403, "Not an approver")
    req = _get_request_or_404(request_id, db)
    req.status = RequestStatus.rejected
    req.approver_id = current_user.id
    req.decision_comment = payload.comment
    req.decided_at = datetime.utcnow()
    db.add(RequestEvent(request_id=req.id, status=req.status, note=payload.comment, created_by_id=current_user.id))
    record_audit(
        db, current_user, "request.reject", "service_request",
        f"{current_user.full_name} rejected {req.request_number}", entity_id=req.id,
    )
    db.commit()
    db.refresh(req)
    background_tasks.add_task(notify_decision, req.requester, req, False, payload.comment)
    return req


@app.post("/service-requests/{request_id}/status", response_model=schemas.ServiceRequestOut)
def update_status(
    request_id,
    payload: schemas.StatusUpdateRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Staff move a request through Arranging -> In Progress -> Completed -> Verified -> Closed."""
    if current_user.role not in (UserRole.staff, UserRole.admin):
        raise HTTPException(403, "Staff only")
    req = _get_request_or_404(request_id, db)
    req.status = payload.status
    db.add(RequestEvent(request_id=req.id, status=payload.status, note=payload.note, created_by_id=current_user.id))
    record_audit(
        db, current_user, "request.status_change", "service_request",
        f"{current_user.full_name} moved {req.request_number} to {payload.status.value}", entity_id=req.id,
    )
    db.commit()
    db.refresh(req)
    background_tasks.add_task(
        notify_status_change, req.requester, req, CUSTOMER_STAGE_MAP[payload.status]
    )
    return req


# ---------- Payments ----------

def _mark_paid(db: Session, payment: Payment, background_tasks: BackgroundTasks) -> None:
    """Advances a request past payment_pending once its payment is confirmed -
    called from both the customer-triggered status check (Paynow) and the two
    provider webhooks. Safe to call more than once for the same payment."""
    if payment.status == PaymentStatus.paid:
        return
    payment.status = PaymentStatus.paid
    payment.paid_at = datetime.utcnow()

    req = payment.request
    if req.status == RequestStatus.payment_pending:
        req.status = RequestStatus.in_progress
        db.add(RequestEvent(request_id=req.id, status=req.status, note=f"Payment received via {payment.provider.value}"))

    record_audit(
        db, req.requester, "payment.received", "service_request",
        f"{req.requester.full_name} paid {payment.currency} {payment.amount} for {req.request_number} via {payment.provider.value}",
        entity_id=req.id,
        meta={"provider": payment.provider.value, "amount": str(payment.amount), "currency": payment.currency},
    )
    db.commit()
    background_tasks.add_task(notify_payment_received, req.requester, req, payment.amount, payment.currency)
    background_tasks.add_task(notify_status_change, req.requester, req, CUSTOMER_STAGE_MAP[RequestStatus.in_progress])


@app.post("/service-requests/{request_id}/pay", response_model=schemas.PaymentOut, status_code=201)
def initiate_payment(
    request_id,
    payload: schemas.InitiatePaymentRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Starts a payment attempt for an approved (payment_pending) request. The
    customer picks the gateway themselves - Paynow for mobile money/local
    cards, Flutterwave for international cards - their country is only ever
    used client-side as a suggested default, never to force one or the other."""
    req = _get_request_or_404(request_id, db)
    if current_user.company_id is not None:
        # Business accounts: paying is a spend-approval action, not an
        # ownership one - only Administrator/Finance can trigger it, even
        # for a request they raised themselves (e.g. a Requester can't).
        allowed = req.requester.company_id == current_user.company_id and can_approve_spending(current_user)
    else:
        allowed = req.requester_id == current_user.id
    if not allowed:
        raise HTTPException(403, "Not your request")
    if req.status != RequestStatus.payment_pending:
        raise HTTPException(400, "This request isn't awaiting payment")
    if req.amount is None or req.amount <= 0:
        raise HTTPException(400, "This request doesn't have an amount yet - contact staff")

    reference = generate_payment_reference(db)
    payment = Payment(
        request_id=req.id,
        provider=payload.provider,
        method=payload.method,
        merchant_reference=reference,
        amount=req.amount,
        currency=req.currency,
    )

    amount = float(req.amount)
    if payload.provider == PaymentProvider.paynow:
        if payload.method:
            if not payload.phone:
                raise HTTPException(400, "A phone number is required for mobile money payments")
            result = paynow_gateway.create_mobile_checkout(
                reference, current_user.email, req.title, amount, payload.phone, payload.method
            )
            payment.poll_url = result.get("poll_url")
        else:
            result = paynow_gateway.create_checkout(reference, current_user.email, req.title, amount)
            payment.checkout_url = result.get("redirect_url")
            payment.poll_url = result.get("poll_url")
    else:
        result = flutterwave_gateway.create_checkout(
            reference, current_user.email, current_user.full_name, amount, req.currency, req.title
        )
        payment.checkout_url = result.get("checkout_url")

    if not result.get("success"):
        payment.status = PaymentStatus.failed
        payment.raw_status = result.get("error")
        db.add(payment)
        db.commit()
        raise HTTPException(502, result.get("error") or "The payment gateway rejected this request")

    db.add(payment)
    db.commit()
    db.refresh(payment)
    return payment


@app.get("/service-requests/{request_id}/payment", response_model=schemas.PaymentOut | None)
def latest_payment(
    request_id,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    req = _get_request_or_404(request_id, db)
    is_owner = req.requester_id == current_user.id
    is_staff = current_user.role in (UserRole.staff, UserRole.admin, UserRole.approver)
    if not (is_owner or is_staff):
        raise HTTPException(403, "Not your request")
    return (
        db.query(Payment)
        .filter(Payment.request_id == req.id)
        .order_by(Payment.created_at.desc())
        .first()
    )


@app.post("/service-requests/{request_id}/payment/check", response_model=schemas.PaymentOut)
def check_payment(
    request_id,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lets the client actively re-check the latest payment's status - useful
    right after the customer returns from the gateway's page, before any
    webhook has necessarily arrived. Paynow only: Flutterwave has no
    customer-facing poll url, so confirmation there relies on its webhook
    (which itself re-verifies with Flutterwave before trusting anything)."""
    req = _get_request_or_404(request_id, db)
    if req.requester_id != current_user.id:
        raise HTTPException(403, "Not your request")
    payment = (
        db.query(Payment)
        .filter(Payment.request_id == req.id)
        .order_by(Payment.created_at.desc())
        .first()
    )
    if payment is None:
        raise HTTPException(404, "No payment attempt found")
    if payment.status != PaymentStatus.paid and payment.provider == PaymentProvider.paynow and payment.poll_url:
        result = paynow_gateway.check_status(payment.poll_url)
        if result.get("paid"):
            _mark_paid(db, payment, background_tasks)
        elif result.get("success"):
            payment.raw_status = result.get("status")
            db.commit()
    db.refresh(payment)
    return payment


@app.post("/payments/paynow/webhook")
async def paynow_webhook(request: Request, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    """Server-to-server callback from Paynow - not authenticated with our
    JWT scheme, since Paynow itself is calling this, not a signed-in user.
    Trust is instead established by validating the request's hash."""
    form = await request.form()
    fields = list(form.multi_items())
    if not paynow_gateway.verify_result_hash(fields):
        raise HTTPException(400, "Invalid hash")

    data = dict(fields)
    payment = db.query(Payment).filter(Payment.merchant_reference == data.get("reference")).first()
    if payment is None:
        raise HTTPException(404, "Unknown payment reference")

    payment.provider_reference = data.get("paynowreference")
    payment.raw_status = data.get("status")
    if (data.get("status") or "").lower() in ("paid", "awaiting delivery"):
        _mark_paid(db, payment, background_tasks)
    else:
        db.commit()
    return {"received": True}


@app.post("/payments/flutterwave/webhook")
async def flutterwave_webhook(request: Request, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    """Server-to-server callback from Flutterwave. The webhook body itself is
    never trusted for the actual status/amount - only used to learn which
    transaction to look up, then re-verified with a fresh call to
    Flutterwave's own API (their documented recommendation) before anything
    is marked paid."""
    if not flutterwave_gateway.verify_webhook_signature(request.headers.get("verif-hash")):
        raise HTTPException(400, "Invalid signature")

    body = await request.json()
    data = body.get("data") or {}
    transaction_id = data.get("id")
    tx_ref = data.get("tx_ref")
    if transaction_id is None or tx_ref is None:
        raise HTTPException(400, "Malformed webhook payload")

    payment = db.query(Payment).filter(Payment.merchant_reference == tx_ref).first()
    if payment is None:
        raise HTTPException(404, "Unknown payment reference")

    verified = flutterwave_gateway.verify_transaction(str(transaction_id))
    payment.provider_reference = str(transaction_id)
    payment.raw_status = verified.get("status")

    amount_ok = verified.get("amount") is not None and Decimal(str(verified["amount"])) >= payment.amount
    if (
        verified.get("success")
        and verified.get("status") == "successful"
        and verified.get("tx_ref") == payment.merchant_reference
        and amount_ok
        and verified.get("currency") == payment.currency
    ):
        _mark_paid(db, payment, background_tasks)
    else:
        db.commit()
    return {"received": True}


# ---------- Reports ----------

@app.get("/reports/dashboard", response_model=schemas.DashboardReport)
def dashboard_report(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if current_user.role not in (UserRole.staff, UserRole.admin, UserRole.approver):
        raise HTTPException(403, "Staff only")
    return build_dashboard_report(db)


# ---------- Property inspection reminders ----------

@app.get("/reminders/property-inspection", response_model=Optional[schemas.InspectionReminderOut])
def get_inspection_reminder(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return db.query(InspectionReminder).filter(InspectionReminder.user_id == current_user.id).first()


@app.post("/reminders/property-inspection", response_model=schemas.InspectionReminderOut)
def set_inspection_reminder(
    payload: schemas.InspectionReminderCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Upserts the customer's single recurring reminder - optional, set from
    the New Request form when the Property Inspections category is picked."""
    reminder = db.query(InspectionReminder).filter(InspectionReminder.user_id == current_user.id).first()
    if reminder is None:
        reminder = InspectionReminder(
            user_id=current_user.id,
            frequency=payload.frequency,
            property_label=payload.property_label,
            next_reminder_at=next_due_at(payload.frequency),
        )
        db.add(reminder)
    else:
        reminder.frequency = payload.frequency
        reminder.property_label = payload.property_label
        reminder.next_reminder_at = next_due_at(payload.frequency)
        reminder.active = True
    db.commit()
    db.refresh(reminder)
    return reminder


@app.delete("/reminders/property-inspection", status_code=204)
def cancel_inspection_reminder(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    reminder = db.query(InspectionReminder).filter(InspectionReminder.user_id == current_user.id).first()
    if reminder is not None:
        reminder.active = False
        db.commit()


@app.post("/reminders/property-inspection/run-due")
def run_due_inspection_reminders(
    x_cron_secret: Optional[str] = Header(default=None, alias="X-Cron-Secret"),
    current_user: Optional[User] = Depends(get_current_user_optional),
    db: Session = Depends(get_db),
):
    """Processes every due reminder. Staff/admin trigger this from the KYC
    Review bell icon (JWT auth); the Render cron job (see render.yaml,
    scripts/trigger_reminders.py) triggers it headlessly instead, since it
    has no staff login of its own - it authenticates with X-Cron-Secret,
    checked against CRON_SECRET, rather than a bearer token."""
    is_cron = bool(settings.cron_secret) and x_cron_secret == settings.cron_secret
    is_staff = current_user is not None and current_user.role in (UserRole.staff, UserRole.admin, UserRole.approver)
    if not is_cron and not is_staff:
        raise HTTPException(403, "Staff only")
    return {"sent": send_due_reminders(db)}


# ---------- KYC review ----------

@app.get("/kyc/pending", response_model=list[schemas.KYCReviewOut])
def pending_kyc_reviews(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """The staff review queue - customers who've submitted an id/passport and are awaiting a decision."""
    if current_user.role not in (UserRole.staff, UserRole.admin, UserRole.approver):
        raise HTTPException(403, "Staff only")
    return (
        db.query(User)
        .filter(User.kyc_status == KYCStatus.pending, User.id_document_path.isnot(None), User.deleted_at.is_(None))
        .order_by(User.created_at.asc())
        .all()
    )


@app.post("/kyc/{user_id}/decision", response_model=schemas.KYCReviewOut)
def decide_kyc(
    user_id,
    payload: schemas.KYCDecisionRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role not in (UserRole.staff, UserRole.admin, UserRole.approver):
        raise HTTPException(403, "Staff only")
    target = db.query(User).filter(User.id == user_id).first()
    if target is None:
        raise HTTPException(404, "User not found")

    target.kyc_status = KYCStatus.verified if payload.approve else KYCStatus.rejected
    target.kyc_rejection_reason = None if payload.approve else payload.reason
    target.kyc_reviewed_at = datetime.utcnow()
    record_audit(
        db, current_user, "kyc.decision", "user",
        f"{current_user.full_name} {'approved' if payload.approve else 'declined'} {target.full_name}'s KYC document",
        entity_id=target.id,
        meta={"approved": payload.approve, "reason": payload.reason},
    )
    db.commit()
    db.refresh(target)
    background_tasks.add_task(notify_kyc_decision, target, payload.approve, payload.reason)
    return target


# ---------- Business / Company accounts ----------

def _require_company(current_user: User) -> Company:
    if current_user.company_id is None:
        raise HTTPException(403, "Not a Business account")
    return current_user.company


@app.get("/company/me", response_model=schemas.CompanyOut)
def my_company(current_user: User = Depends(get_current_user)):
    return _require_company(current_user)


@app.get("/company/employees", response_model=list[schemas.UserOut])
def list_employees(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _require_company(current_user)
    return (
        db.query(User)
        .filter(User.company_id == current_user.company_id, User.deleted_at.is_(None))
        .order_by(User.created_at.asc())
        .all()
    )


@app.post("/company/employees", response_model=schemas.UserOut, status_code=201)
def create_employee(
    payload: schemas.EmployeeCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    company = _require_company(current_user)
    if not can_manage_employees(current_user):
        raise HTTPException(403, "Only an Administrator can add employees")
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(400, "Email already registered")
    if db.query(User).filter(User.phone == payload.phone).first():
        raise HTTPException(400, "Phone already registered")

    member_id = generate_member_id(db, payload.full_name)
    employee = User(
        member_id=member_id,
        full_name=payload.full_name,
        date_of_birth=payload.date_of_birth,
        email=payload.email,
        phone=payload.phone,
        password_hash=hash_password(payload.password),
        country_of_residence=company.country,
        primary_purpose="Business",
        trial_ends_at=trial_ends_at_for_new_user(),
        company_id=company.id,
        business_role=payload.business_role,
    )
    db.add(employee)
    db.flush()
    record_audit(
        db, current_user, "company.employee_added", "user",
        f"{current_user.full_name} added {employee.full_name} to {company.legal_name} as {payload.business_role.value}",
        entity_id=employee.id,
    )
    db.commit()
    db.refresh(employee)
    return employee


@app.patch("/company/employees/{user_id}", response_model=schemas.UserOut)
def update_employee_role(
    user_id,
    payload: schemas.EmployeeRoleUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _require_company(current_user)
    if not can_manage_employees(current_user):
        raise HTTPException(403, "Only an Administrator can change employee roles")
    employee = (
        db.query(User)
        .filter(User.id == user_id, User.company_id == current_user.company_id)
        .first()
    )
    if employee is None:
        raise HTTPException(404, "Employee not found")

    old_role = employee.business_role.value if employee.business_role else None
    employee.business_role = payload.business_role
    record_audit(
        db, current_user, "company.employee_role_changed", "user",
        f"{current_user.full_name} changed {employee.full_name}'s role from {old_role} to {payload.business_role.value}",
        entity_id=employee.id,
    )
    db.commit()
    db.refresh(employee)
    return employee


@app.delete("/company/employees/{user_id}", status_code=204)
def remove_employee(
    user_id,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _require_company(current_user)
    if not can_manage_employees(current_user):
        raise HTTPException(403, "Only an Administrator can remove employees")
    if str(user_id) == str(current_user.id):
        raise HTTPException(400, "You can't remove yourself")
    employee = (
        db.query(User)
        .filter(User.id == user_id, User.company_id == current_user.company_id)
        .first()
    )
    if employee is None:
        raise HTTPException(404, "Employee not found")

    employee.deleted_at = datetime.utcnow()
    record_audit(
        db, current_user, "company.employee_removed", "user",
        f"{current_user.full_name} removed {employee.full_name} from {current_user.company.legal_name}",
        entity_id=employee.id,
    )
    db.commit()


@app.post("/company/documents", response_model=schemas.CompanyDocumentOut, status_code=201)
async def upload_company_document(
    caption: str = Form(None),
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """An Administrator uploads (or re-uploads) a company registration
    document - resets the company to pending review, same as an
    individual's id/passport re-upload."""
    company = _require_company(current_user)
    if not can_manage_employees(current_user):
        raise HTTPException(403, "Only an Administrator can upload company documents")

    file_url = await save_upload(file)
    doc = CompanyDocument(company_id=company.id, uploaded_by_id=current_user.id, file_url=file_url, caption=caption)
    db.add(doc)
    company.kyc_status = KYCStatus.pending
    company.kyc_rejection_reason = None
    company.kyc_reviewed_at = None
    db.commit()
    db.refresh(doc)
    return doc


@app.get("/company/documents", response_model=list[schemas.CompanyDocumentOut])
def list_company_documents(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    company = _require_company(current_user)
    return (
        db.query(CompanyDocument)
        .filter(CompanyDocument.company_id == company.id)
        .order_by(CompanyDocument.created_at.desc())
        .all()
    )


@app.get("/companies/pending", response_model=list[schemas.CompanyKYCReviewOut])
def pending_company_reviews(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """The staff review queue - Business accounts awaiting verification."""
    if current_user.role not in (UserRole.staff, UserRole.admin, UserRole.approver):
        raise HTTPException(403, "Staff only")
    companies = (
        db.query(Company)
        .filter(Company.kyc_status == KYCStatus.pending, Company.deleted_at.is_(None))
        .order_by(Company.created_at.asc())
        .all()
    )
    results = []
    for company in companies:
        out = schemas.CompanyKYCReviewOut.model_validate(company)
        out.document_count = len(company.documents)
        results.append(out)
    return results


@app.post("/companies/{company_id}/decision", response_model=schemas.CompanyOut)
def decide_company_kyc(
    company_id,
    payload: schemas.CompanyKYCDecisionRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role not in (UserRole.staff, UserRole.admin, UserRole.approver):
        raise HTTPException(403, "Staff only")
    company = db.query(Company).filter(Company.id == company_id).first()
    if company is None:
        raise HTTPException(404, "Company not found")

    company.kyc_status = KYCStatus.verified if payload.approve else KYCStatus.rejected
    company.kyc_rejection_reason = None if payload.approve else payload.reason
    company.kyc_reviewed_at = datetime.utcnow()
    record_audit(
        db, current_user, "company.kyc_decision", "company",
        f"{current_user.full_name} {'approved' if payload.approve else 'declined'} {company.legal_name}'s Business verification",
        entity_id=company.id,
        meta={"approved": payload.approve, "reason": payload.reason},
    )
    db.commit()
    db.refresh(company)
    background_tasks.add_task(notify_company_kyc_decision, company, payload.approve, payload.reason)
    return company


# ---------- Admin: user management ----------

def _require_admin(current_user: User) -> None:
    if current_user.role != UserRole.admin:
        raise HTTPException(403, "Admin only")


@app.get("/admin/users", response_model=list[schemas.AdminUserOut])
def list_users(
    role: UserRole | None = None,
    search: str | None = None,
    include_inactive: bool = False,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _require_admin(current_user)
    query = db.query(User)
    if not include_inactive:
        query = query.filter(User.deleted_at.is_(None))
    if role is not None:
        query = query.filter(User.role == role)
    if search:
        like = f"%{search}%"
        query = query.filter(
            or_(User.full_name.ilike(like), User.email.ilike(like), User.member_id.ilike(like))
        )
    return query.order_by(User.created_at.desc()).limit(500).all()


@app.post("/admin/users/{user_id}/role", response_model=schemas.AdminUserOut)
def change_user_role(
    user_id,
    payload: schemas.RoleChangeRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _require_admin(current_user)
    if str(user_id) == str(current_user.id):
        raise HTTPException(400, "Cannot change your own role")
    target = db.query(User).filter(User.id == user_id).first()
    if target is None:
        raise HTTPException(404, "User not found")
    old_role = target.role.value
    target.role = payload.role
    record_audit(
        db, current_user, "user.role_change", "user",
        f"{current_user.full_name} changed {target.full_name}'s role from {old_role} to {payload.role.value}",
        entity_id=target.id,
        meta={"from": old_role, "to": payload.role.value},
    )
    db.commit()
    db.refresh(target)
    return target


@app.post("/admin/users/{user_id}/deactivate", response_model=schemas.AdminUserOut)
def deactivate_user(
    user_id,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Soft-deletes the account (same mechanism as self-deletion) - deactivated
    users are excluded from login and from every deleted_at.is_(None) query."""
    _require_admin(current_user)
    if str(user_id) == str(current_user.id):
        raise HTTPException(400, "Cannot deactivate your own account")
    target = db.query(User).filter(User.id == user_id).first()
    if target is None:
        raise HTTPException(404, "User not found")
    target.deleted_at = datetime.utcnow()
    record_audit(
        db, current_user, "user.deactivate", "user",
        f"{current_user.full_name} deactivated {target.full_name}'s account", entity_id=target.id,
    )
    db.commit()
    db.refresh(target)
    return target


@app.post("/admin/users/{user_id}/reactivate", response_model=schemas.AdminUserOut)
def reactivate_user(
    user_id,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _require_admin(current_user)
    target = db.query(User).filter(User.id == user_id).first()
    if target is None:
        raise HTTPException(404, "User not found")
    target.deleted_at = None
    record_audit(
        db, current_user, "user.reactivate", "user",
        f"{current_user.full_name} reactivated {target.full_name}'s account", entity_id=target.id,
    )
    db.commit()
    db.refresh(target)
    return target


# ---------- Admin: audit log ----------

@app.get("/admin/audit-log", response_model=list[schemas.AuditLogOut])
def list_audit_log(
    entity_type: str | None = None,
    action: str | None = None,
    limit: int = Query(100, ge=1, le=500),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Read-only, chronological trail of consequential changes across the
    system (registrations, role/status/subscription changes, KYC and
    approval decisions) - the general-purpose counterpart to a single
    request's status timeline (RequestEvent)."""
    _require_admin(current_user)
    query = db.query(AuditLog)
    if entity_type is not None:
        query = query.filter(AuditLog.entity_type == entity_type)
    if action is not None:
        query = query.filter(AuditLog.action == action)
    return query.order_by(AuditLog.created_at.desc()).limit(limit).all()
