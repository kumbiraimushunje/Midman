from datetime import datetime

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, HTTPException, Query, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import case
from sqlalchemy.orm import Session

from . import schemas
from .ai_concierge import parse_request_text
from .database import get_db
from .fraud_check import run_fraud_check
from .id_generator import generate_member_id, generate_request_number
from .models import (
    CUSTOMER_STAGE_MAP,
    AccountType,
    Beneficiary,
    Evidence,
    EvidenceType,
    RequestEvent,
    RequestStatus,
    ServiceRequest,
    User,
    UserRole,
)
from .notifications import notify_decision, notify_status_change
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
    db.commit()


@app.post("/me/subscription", response_model=schemas.UserOut)
def change_subscription(
    payload: schemas.SubscriptionChangeRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Self-service tier switch. No payment gateway wired up yet - pricing
    for each tier hasn't been set, so this just records the choice."""
    current_user.account_type = payload.account_type
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
    db.commit()
    db.refresh(req)
    background_tasks.add_task(
        notify_status_change, req.requester, req, CUSTOMER_STAGE_MAP[payload.status]
    )
    return req
