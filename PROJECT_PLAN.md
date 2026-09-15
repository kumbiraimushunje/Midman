# MidMan — Project Plan

A premium remote-execution and concierge platform. Customers give instructions
(not just money) and MidMan takes care of the execution — school fees,
medical bills, property inspections, groceries, gifts, procurement, transport
and more — with a transparent status timeline and proof of completion.

## 1. Tech stack

| Layer          | Choice                                                        |
|-----------------|-----------------------------------------------------------------|
| Mobile app       | Flutter (Dart) — one codebase for Android & iOS (iOS build/signing needs a Mac or CI; see §7) |
| Backend API      | Python — FastAPI                                                |
| Database         | PostgreSQL (Neon, serverless — used for both dev and prod)      |
| Auth             | JWT (issued by FastAPI, stored in flutter_secure_storage on device) |
| AI / automation  | OpenAI API — fraud/risk triage now; request parsing & quote comparison later |
| IDE              | VS Code (Dart/Flutter + Python extensions — already installed)   |
| Eventual hosting | AWS (backend + RDS, once past early validation)                 |

## 2. How a request becomes a Member ID / Request Number

**Member ID** (e.g. `MUS000001`): first 3 letters of the customer's surname
(uppercase) + a 6-digit sequence scoped to that prefix, assigned atomically
via a row-locked counter table (`member_id_counters`) at registration. See
`backend/app/id_generator.py`. Two different "Moyo"s get `MOY000001` and
`MOY000002`; a completely different surname gets its own counter from 1.

**Request Number** (e.g. `MID-000123`): one global sequence shared by every
service request, regardless of category.

## 3. Data model (see `backend/app/models.py` for the full SQLAlchemy source)

```
User            - member_id, KYC fields, role (customer/staff/approver/admin),
                  account_type (payg/standard/pro), soft-deletable
Beneficiary     - a person or property a customer requests things for
                  (Mum, a child, a rental property...), with remembered
                  preferences (JSONB) so recurring requests don't re-ask
ServiceRequest  - category, title/description, amount, status, fraud-risk
                  fields, linked to a requester + optional beneficiary
RequestEvent    - append-only status timeline entry (customer-visible + audit log)
Evidence        - photos/documents/receipts proving work was done
MemberIdCounter - per-prefix sequence used by both ID generators above
```

## 4. Status lifecycle

Internal (`RequestStatus`, 10 states) →

```
REQUESTED → ARRANGING → APPROVAL_REQUIRED → PAYMENT_PENDING → IN_PROGRESS
→ COMPLETED → VERIFIED → CLOSED        (or REJECTED / CANCELLED at any point)
```

Collapses to the **4 customer-facing stages** for the app UI and emails
(`CUSTOMER_STAGE_MAP` in `models.py`):

```
Received → Arranging → In Progress → Completed
```

## 5. Roadmap

### Phase 0 — Environment (done)
Flutter, Python, PostgreSQL client libs, VS Code extensions, project
scaffold, Git.

### Phase 1 — MVP core (in progress, scaffolded this session)
- [x] Data model: User, Beneficiary, ServiceRequest, RequestEvent, Evidence
- [x] Member ID + Request Number generation
- [x] Register / login (JWT), soft-delete account endpoint
- [x] Beneficiaries CRUD
- [x] Create service request, list "my requests", approve/reject, staff
      status updates, timeline events
- [x] OpenAI fraud-risk triage (background task, degrades gracefully with no key)
- [x] Email notification stubs for the 4 customer stages + approve/reject
      (logs to console until SMTP is configured)
- [x] Flutter: themed splash, login, register (KYC-lite), home shell with
      bottom nav (Home/Requests/Family/Account), requests list, new-request
      form, request detail timeline, beneficiaries screen, account screen
- [x] Evidence & document uploads: requester attaches an invoice/photo when
      creating a request, staff attach completion proof; local-disk storage
      behind `/service-requests/{id}/evidence`, shown in the app as photo
      thumbnails / tappable document rows
- [x] Staff/admin screens: role-based routing sends staff/admin/approver
      accounts to a separate shell (Queue / Approvals / Account) instead of
      the customer app - full request queue, one-tap approve/reject, status
      lifecycle dropdown, evidence attachment
- [ ] Real SMTP provider connected
- [ ] Alembic migrations (currently using `create_all` for dev speed)
- [ ] Swap local-disk evidence storage for S3 (or equivalent) before production

### Phase 2 — Admin / staff tooling
Web or app-based queue for staff to pick up requests, update status, attach
evidence, and see fraud-risk flags before approving.

### Phase 3 — Subscriptions
Free 1-month trial → PAYG / Standard / Pro. PAYG: no beneficiaries list,
higher per-service pricing. Standard: recurring payments, faster processing.
Pro: priority queue, free document assistance. Gate features by
`User.account_type` server-side.

### Phase 4 — AI concierge
Natural-language request creation ("Pay my daughter's school fees"), invoice
/ quote parsing, quote comparison summaries, chatbot support. AI never
initiates money movement directly — it only prepares structured requests for
human approval.

### Phase 5 — Reporting & compliance
Dashboards, audit log views, KYC document review workflow.

### Phase 6 — Channels & payments
WhatsApp channel, real payment gateway integration (replacing the
approve-then-manual-payment flow), push notifications.

### Phase 7 — Launch
iOS build via CI (Codemagic or GitHub Actions macOS runner — this dev
machine is Windows and cannot build/sign iOS locally), AWS deployment
(backend + RDS), app store submissions.

## 6. Repo layout

```
midman/
├── PROJECT_PLAN.md
├── backend/                 <- FastAPI + PostgreSQL (Neon)
│   ├── requirements.txt
│   ├── .env.example
│   ├── seed.py
│   └── app/
│       ├── main.py
│       ├── config.py
│       ├── database.py
│       ├── models.py
│       ├── schemas.py
│       ├── security.py
│       ├── id_generator.py
│       ├── fraud_check.py
│       └── notifications.py
└── mobile/                  <- Flutter app (midman_app)
    └── lib/
        ├── main.dart
        ├── theme.dart
        ├── api_service.dart
        ├── models/
        └── screens/
```
