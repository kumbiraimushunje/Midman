from datetime import datetime
from pathlib import Path

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, HTTPException, Query, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import case, or_
from sqlalchemy.orm import Session

from . import schemas
from .ai_concierge import parse_invoice_document, parse_request_text
from .audit import record_audit
from .database import get_db
from .fraud_check import run_fraud_check
from .id_generator import generate_member_id, generate_request_number
from .models import (
    CUSTOMER_STAGE_MAP,
    AccountType,
    AuditLog,
    Beneficiary,
    Evidence,
    EvidenceType,
    KYCStatus,
    RequestEvent,
    RequestStatus,
    ServiceRequest,
    User,
    UserRole,
)
from .notifications import notify_decision, notify_kyc_decision, notify_status_change
from .reports import build_dashboard_report
from .security import create_access_token, get_current_user, hash_password, verify_password
from .subscriptions import can_manage_beneficiaries, trial_ends_at_for_new_user, visible_statuses_for
from .uploads import UPLOAD_DIR, save_upload

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

    member_id = generate_member_id(db, payload.full_name)
    user = User(
        member_id=member_id,
        full_name=payload.full_name,
        date_of_birth=payload.date_of_birth,
        email=payload.email,
        phone=payload.phone,
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


@app.post("/auth/login", response_model=schemas.Token)
def login(payload: schemas.LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email, User.deleted_at.is_(None)).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(401, "Incorrect email or password")
    return schemas.Token(access_token=create_access_token(str(user.id)))


@app.get("/me", response_model=schemas.UserOut)
def read_me(current_user: User = Depends(get_current_user)):
    return current_user


@app.delete("/me", status_code=204)
def delete_me(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    current_user.deleted_at = datetime.utcnow()
    record_audit(db, current_user, "user.self_delete", "user", f"{current_user.full_name} deleted their own account", entity_id=current_user.id)
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
        category=payload.category,
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
    """PAYG only sees requests still in flight ("no list of previous transactions")."""
    query = db.query(ServiceRequest).filter(ServiceRequest.requester_id == current_user.id)
    allowed_statuses = visible_statuses_for(current_user)
    if allowed_statuses is not None:
        query = query.filter(ServiceRequest.status.in_(allowed_statuses))
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


@app.post("/service-requests/{request_id}/evidence", response_model=schemas.EvidenceOut, status_code=201)
async def upload_evidence(
    request_id,
    file: UploadFile = File(...),
    file_type: EvidenceType = Form(...),
    caption: str | None = Form(None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """The requester can attach an invoice/photo when submitting a request; staff attach
    completion proof (photos, receipts, delivery confirmation) as work progresses."""
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
        uploaded_by_id=current_user.id,
    )
    db.add(evidence)
    db.commit()
    db.refresh(evidence)
    return evidence


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


# ---------- Reports ----------

@app.get("/reports/dashboard", response_model=schemas.DashboardReport)
def dashboard_report(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if current_user.role not in (UserRole.staff, UserRole.admin, UserRole.approver):
        raise HTTPException(403, "Staff only")
    return build_dashboard_report(db)


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
