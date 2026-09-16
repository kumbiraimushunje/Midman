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
scaffold, Git, Neon (cloud Postgres, used for both dev and prod) connected
and seeded with demo accounts.

### Phase 1 — MVP core (done)
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
- [x] Real SMTP connected (Gmail + App Password for now - swap for
      SendGrid/Resend/SES before real send volume, Gmail rate-limits and
      flags automated senders); verified with a real delivered test email
      and, separately, real app-triggered "received" and "approved" emails
      through the actual background-task code path
- [x] Alembic migrations: initial schema migration generated and verified
      against a clean database (full smoke test passing), Neon stamped as
      up to date with zero drift (`alembic check`); `app/models.py` is now
      the source of truth for schema changes, not `create_all`
- [x] Evidence storage swapped to S3: private bucket (`midmanevidencebucket`,
      eu-north-1), IAM user scoped to only `s3:PutObject`/`s3:GetObject` on
      the `evidence/` prefix, served via presigned URLs regenerated on every
      read (not a permanent public link). Local disk remains the automatic
      fallback when S3 isn't configured, for dependency-free local dev.
      Verified end-to-end: uploaded a real file through the API, confirmed
      it lands in S3, fetched it back through a presigned URL (HTTP 200,
      correct content), and confirmed the app's evidence tile opens it.

### Phase 2 — Admin / staff tooling (done, folded into Phase 1)
Delivered as the "Staff/admin screens" item above: role-based queue, status
updates, evidence, and fraud-risk flags visible before approving.

### Phase 3 — Subscriptions (tier logic done, pricing still deferred)
- [x] 30-day free trial on every new account (`trial_ends_at`), trial = PAYG
      features until a paid tier is chosen (no billing exists yet)
- [x] PAYG: blocked from saving beneficiaries (403 + in-app upgrade prompt),
      request history hides completed/closed/rejected/cancelled requests
- [x] Standard/Pro: full beneficiaries + full history
- [x] Pro: requests surface first in the staff queue ("prioritised first")
- [x] Self-service tier switch (`POST /me/subscription`) and an in-app
      Membership screen listing each tier's features
- [ ] Actual pricing per tier ("Subscriptions fees right amounts will be
      added later") and a real payment/billing flow to charge for them
- [ ] Standard's "recurring payments" as an actual automated feature (right
      now Standard+ just isn't blocked from anything - there's no recurring
      request scheduler yet)
- [ ] Pro's "free digital assistance" as an actual price waiver (depends on
      pricing existing first)

### Phase 4 — AI concierge (natural-language request creation done)
- [x] Natural-language request creation: the home screen's prompt box calls
      `POST /ai/parse-request` (`app/ai_concierge.py`), which extracts
      category/title/description/amount and matches named people against
      the customer's real saved beneficiaries (never trusts a hallucinated
      id), pre-filling the request form for the customer to review and
      submit themselves - never auto-submitted. Degrades gracefully with
      no OPENAI_API_KEY.
- [ ] Invoice / quote parsing (reading an uploaded document, not just typed text)
- [ ] Quote comparison summaries across suppliers
- [ ] General chatbot/customer support beyond request creation

### Phase 5 — Reporting & compliance (dashboard done)
- [x] Staff dashboard (`GET /reports/dashboard`, Reports tab in the staff
      shell): requests by status/category, customers by tier, requested vs
      completed amounts, new customers (30d), high-risk flags, pending
      approvals.
- [ ] A general-purpose audit log view (who changed what, when, across
      every table) - RequestEvent already covers request status-change
      history specifically, but nothing broader exists yet
- [x] KYC document review workflow: customers upload/re-upload their
      id/passport from Account (`POST /me/kyc-document`, resets status to
      pending); staff review a queue (`GET /kyc/pending`, KYC tab in the
      staff shell) and approve or decline with a reason
      (`POST /kyc/{user_id}/decision`), which emails the customer and,
      on decline, surfaces the reason back on their Account screen

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
│   ├── alembic.ini
│   ├── alembic/
│   │   ├── env.py
│   │   └── versions/        <- one file per schema migration, committed
│   └── app/
│       ├── main.py
│       ├── config.py
│       ├── database.py
│       ├── models.py
│       ├── schemas.py
│       ├── security.py
│       ├── id_generator.py
│       ├── fraud_check.py
│       ├── uploads.py
│       └── notifications.py
└── mobile/                  <- Flutter app (midman_app)
    └── lib/
        ├── main.dart
        ├── theme.dart
        ├── api_service.dart
        ├── models/
        └── screens/
```
