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
- [x] Register / login (JWT), soft-delete account endpoint (`DELETE /me`,
      optional `reason` captured for staff/audit visibility - not shown to
      other customers). Wired up in the app as a "Delete account"
      confirmation dialog on the Account screen, with an optional "why are
      you leaving?" field.
- [x] Beneficiaries CRUD
- [x] Create service request, list "my requests", approve/reject, staff
      status updates, timeline events
- [x] OpenAI fraud-risk triage (background task, degrades gracefully with no key)
- [x] Email notification stubs for the 4 customer stages + approve/reject
      (logs to console until SMTP is configured)
- [x] Flutter: themed splash, login, register (KYC-lite), home shell with
      bottom nav (Home/Requests/Family/Account), requests list, new-request
      form, request detail timeline, beneficiaries screen, account screen
- [x] Help & Support contact card on Account (support email/phone, tappable
      to mailto:/tel:, plus the AI "Chat with us" support chat) - contact
      details are placeholders (`support@midman.app`, a placeholder Zimbabwe
      number) marked `// TODO` in `account_screen.dart` to swap for the
      real ones before launch
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
- [x] 3-level service taxonomy: 7 numbered Service Groups (client-side-only
      navigation, e.g. "1. Family Care & Shopping") → Category (the
      `ServiceCategory` Postgres enum, 21 active values plus 7 retired ones
      kept for historical-row compatibility since Postgres enum values can't
      be dropped) → Service Type (free-text `service_type` column,
      validated against a per-category allow-list at the Pydantic layer).
      Taxonomy data lives in `backend/app/service_taxonomy.py` and is
      hand-mirrored in `mobile/lib/models/models.dart`'s `kServiceGroups`
      (both files carry a comment flagging this and instructing to keep
      them in sync). Home screen now shows the 7 numbered group cards;
      multi-category groups drop into a `CategoryPickerScreen`,
      single-category groups (Transportation, Other) skip straight to the
      request form. The request form gained a "Specific service" dropdown,
      a warning banner for Government & Administrative Errands (ordinary
      admin assistance vs. work needing a licensed professional/Power of
      Attorney), a description-field hint for Gifts & Celebrations, and
      extra structured fields for Airport Transfers (Airport, Flight
      number, Passenger, Arrival time, Destination) folded into the
      description as labelled lines. `service_type` is shown on both the
      customer and staff request detail screens. Verified end-to-end: all
      12 new enum values + the mismatched-category-422 + AI concierge
      category vocabulary via curl against the real Neon DB, and every
      group/category/notice/hint/extra-field combination visually in the
      running app, including a real submitted request
      (`healthcare`/`Buy Medication`) round-tripped through the API.
- [x] Country + phone country-code dropdowns on registration: a ~195-entry
      `kCountries` list (`mobile/lib/country_data.dart`, ISO 3166-1 alpha-2
      + E.164 dial code, flag emoji computed from the ISO code rather than
      stored) replaced the old free-text country field and split the phone
      field into a dial-code dropdown (defaults to +263 Zimbabwe) plus a
      local-number field, concatenated before sending to the API. Verified
      by registering a real account through the running app and confirming
      via `GET /me` that `phone` and `country_of_residence` were stored
      correctly (`+263771234567`, `Afghanistan`).

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
- [x] Invoice / quote parsing: "Or upload an invoice / quote" on the home
      screen (`POST /ai/parse-invoice`, `parse_invoice_document()` in
      `app/ai_concierge.py`) reads an uploaded photo (via OpenAI vision) or
      a text-based PDF (text extracted with pypdf, then parsed the same way
      as typed text) into the same prefilled draft as the text prompt -
      still never creates or submits a request itself. A scanned/image-only
      PDF (no extractable text layer) isn't supported without adding a
      rasterizer dependency; that case degrades to a fallback message
      suggesting a photo instead, same as when the AI is unavailable.
- [x] Quote comparison summaries across suppliers: staff attach one evidence
      file per supplier (file_type=quote, with a supplier_name) from the
      Request Detail screen's "Add a supplier quote" button, then
      "Compare quotes" (`POST /service-requests/{id}/quote-comparison`,
      `compare_quotes()` in `app/ai_concierge.py`) reads all of them
      together - photos via vision, text-based PDFs via pypdf - into one
      side-by-side summary (per-supplier price/notes, an overall summary,
      and an optional recommendation), cached on the request
      (`quote_comparison` JSONB column) until staff regenerate it. Staff/
      admin/approver only; requires at least 2 quotes. Same anti-
      hallucination guard as invoice parsing: a supplier's amount/notes are
      only ever what the model could actually read from that supplier's
      own quote, never inferred or borrowed from another one.
- [x] General chatbot/customer support: "Help & Support" on the Account
      screen opens a chat (`POST /ai/support-chat`,
      `answer_support_question()` in `app/ai_concierge.py`) that answers
      platform FAQs (membership tiers, KYC, the 4-stage request timeline)
      and questions about the customer's own recent requests, using only
      the account context it's actually given - never invents order/amount
      details. It's read-only: if asked to cancel/change/approve something,
      it explains it can't act and points to where in the app to do it, or
      that staff will handle it. Stateless server-side (the client resends
      recent turns each message, nothing is persisted), and open to every
      signed-in role, not just customers.

### Phase 5 — Reporting & compliance (dashboard done)
- [x] Staff dashboard (`GET /reports/dashboard`, Reports tab in the staff
      shell): requests by status/category, customers by tier, requested vs
      completed amounts, new customers (30d), high-risk flags, pending
      approvals.
- [x] A general-purpose audit log (`audit_logs` table, `app/audit.py`'s
      `record_audit` helper, `GET /admin/audit-log` filterable by
      entity_type/action, Audit Log screen opened from the Users tab's
      history icon) - the counterpart to RequestEvent, which only covers a
      single request's status timeline. Actor name/role are denormalized
      onto each row so entries stay readable even if the actor is later
      renamed or deactivated. Instrumented so far: registration,
      self-deletion, subscription changes, KYC decisions, admin role
      changes and activate/deactivate, and request approve/reject/status
      changes.
- [x] KYC document review workflow: customers upload/re-upload their
      id/passport from Account (`POST /me/kyc-document`, resets status to
      pending); staff review a queue (`GET /kyc/pending`, KYC tab in the
      staff shell) and approve or decline with a reason
      (`POST /kyc/{user_id}/decision`), which emails the customer and,
      on decline, surfaces the reason back on their Account screen
- [x] Admin System split from the Staff Dashboard: `staff`/`approver` keep
      the day-to-day work-queue shell (Queue/Approvals/KYC/Reports/Account);
      `admin` now gets a distinct `AdminHomeShell` with everything staff has
      plus a Users tab (`GET /admin/users`, filterable by role/search,
      inactive accounts included on demand) for changing a user's role
      (`POST /admin/users/{id}/role`) and deactivating/reactivating accounts
      (`POST /admin/users/{id}/deactivate` `/reactivate`, reusing the
      existing soft-delete column so a deactivated user is instantly locked
      out of login). Admins can't change their own role or deactivate
      themselves, to avoid a self-lockout. Departments, system settings, and
      workflow configuration from the original admin spec aren't built -
      there's no concrete requirement for them yet at this app's size.

### Phase 6 — Channels & payments
- [x] Real payment gateway integration, replacing the approve-then-manual-
      payment flow. A `payments` table tracks each attempt against a
      request; once staff approve a request (status `payment_pending`), the
      customer picks a gateway themselves on the Order Tracking screen -
      Paynow (`app/paynow_gateway.py`, official SDK: EcoCash/OneMoney/
      ZimSwitch/local bank cards) or Flutterwave (`app/flutterwave_gateway.py`,
      plain REST: international cards) - with their own country only ever
      used as a suggested default, never to force one over the other.
      `POST /service-requests/{id}/pay` creates the payment and returns a
      checkout link the app opens in a browser tab; `POST
      .../payment/check` lets the customer manually re-confirm after
      returning (mainly useful for Paynow, and essential wherever the
      backend isn't reachable from the internet, e.g. local dev);
      `POST /payments/paynow/webhook` and `POST /payments/flutterwave/webhook`
      are the real server-to-server confirmations - Paynow's verified by
      recomputing its documented SHA512 hash by hand (its SDK's own
      webhook parser is an unimplemented stub), Flutterwave's by checking
      the `verif-hash` header and then re-verifying the transaction with a
      fresh call to Flutterwave's API rather than ever trusting the webhook
      body's amount/status directly. A confirmed payment advances the
      request to `in_progress`, logs a RequestEvent and an audit entry, and
      emails the customer. Verified end-to-end against the real Neon DB:
      every guard (ownership, request status, missing amount, bad webhook
      hash/signature, unknown reference, double-processing), the "gateway
      not configured" fallback, and a full simulated Paynow webhook
      round-trip whose hash was checked against Paynow's own documented
      worked example before ever touching the live endpoint. Needs real
      Paynow/Flutterwave credentials in `.env` (see `.env.example`) before
      going live - none were available while building this, so live
      checkout completion itself is unverified beyond the protocol-level
      checks above.
- [ ] WhatsApp channel
- [ ] Push notifications

### Phase 7 — Business (multi-user) accounts & city-aware requests
- [x] MidMan Business accounts: a company isn't one login - registering via
      "Register a Business account" on the login screen (`POST
      /auth/register-business`) creates a `Company` (legal name, trading
      name, registration number, country, registered/business address,
      industry, authorized representative, company email/phone, billing
      and operations contacts, tax details) and its registrant as the
      first employee with the `administrator` role, auto-logged in. The
      company gets a Business ID (`BUS-000123`, `id_generator.py`'s
      counter pattern) and starts `kyc_status=pending` - mirrors an
      individual's id-document review exactly: staff verify it from a new
      "Businesses" tab on the staff KYC Review screen (`GET
      /companies/pending`, `POST /companies/{id}/decision`), and an
      Administrator can (re-)upload registration documents from the app
      (`POST /company/documents`) which resets it to pending, same as an
      individual's id/passport re-upload. Employees can be added and the
      app used immediately while verification is pending - it isn't a
      hard gate on activity, same as individual KYC today.
- [x] Fixed employee roles, not a custom permission builder
      (`app/business_permissions.py`, mirrored in
      `mobile/lib/models/models.dart`): **Administrator** (everything),
      **Finance** (approves spend/quotations, views reports, can't
      create requests), **Operations** (creates/manages requests, can't
      approve spend), **Requester** (creates only, sees just their own),
      **Viewer/Auditor** (read-only - completed jobs and reports only,
      via a status filter on `/service-requests/mine`). An Administrator
      manages the team from a new Employees ("Team") screen reachable
      from Account - add an employee with a role, change a role, or
      remove someone (an Administrator can't remove themselves). Business
      employees use the exact same customer app (Home/Services/Requests/
      Family/Account) as an individual - no separate app or shell, since
      `role` stays `customer`; only `company_id`/`business_role` differ.
      Permission enforcement is server-side (`create_service_request` 403s
      a Finance/Viewer employee who lacks `create_request`; `.../pay`
      requires `can_approve_spending` for a business employee regardless
      of who raised the request, so a Requester can't pay even their own
      request) with matching client-side gating (a blocking banner and a
      disabled Submit button on New Request; the Pay button relies on the
      same server error surfaced inline, consistent with how PAYG's
      beneficiary restriction is already handled). Verified end-to-end via
      curl against the real Neon DB: registration, Business ID
      generation, all 5 roles' create/approve/manage-employee gates (both
      allow and 403 cases), company-wide `mine` visibility for
      Administrator vs a Requester only seeing their own, staff company
      review (pending list + approve), and Finance successfully paying on
      behalf of a Requester's request while the Requester themselves is
      blocked from paying it.
- [x] Country + city on each request: a `country`/`city` pair (nullable
      columns on `service_requests`) is picked on the New Request form
      itself (not account-level, since one customer might request in
      different places) - Country defaults to the customer's own
      `country_of_residence` but is editable per request; a City dropdown
      appears only for Zimbabwe (the only country with cities modeled so
      far - Harare, Bulawayo, Mutare, `app/city_availability.py` /
      `mobile/lib/city_data.dart`) and the Category dropdown is disabled
      until a city is chosen, then filtered to that city's available
      categories - enforced both client-side (filtered dropdown items)
      and server-side (a Pydantic validator on `ServiceRequestCreate`
      rejects a category not offered in the given city). Every category
      currently defaults to available in all 3 cities - the per-city
      restriction mechanism is built and wired end-to-end, but which
      specific categories should actually be restricted to which city
      hasn't been specified yet, so nothing is excluded until that data
      is provided. City/country show on both the customer and staff
      request detail screens. Verified via curl: country defaults
      correctly when omitted, an explicit country/city round-trips
      correctly, and the availability validator runs without error.
- [x] Service group icons: the numbered gold badges on Home's Services
      grid ("1", "2", ...) were replaced with relatable Material icons per
      group (family icon for Family Care & Shopping, a document for
      Documents & Administration, a house for Property Management, a
      shopping cart for Procurement, a gift for Gifts & Celebrations, a
      plane for Transportation & Mobility, etc) - `ServiceGroup` gained a
      required `icon` field alongside the existing `number`.
- [x] Property Inspection reminders: an optional recurring email nudge -
      "choose timer monthly... for email reminders, optional" - deliberately
      just an email ("time to book your next inspection"), never an
      auto-created request. `InspectionReminder` (one active row per user,
      `app/models.py`) with a fixed frequency (monthly/quarterly/biannual/
      annual, `app/reminders.py` maps each to an interval) and an optional
      free-text property label. Set from a self-contained card on the New
      Request form when Property Inspections is picked - toggle on, choose
      frequency, "Save reminder" - independent of actually submitting a
      request. `GET/POST/DELETE /reminders/property-inspection` (upsert +
      cancel) plus a staff/admin-only `POST .../run-due` that emails
      everyone whose reminder is due and reschedules them - there's no
      cron/scheduler in this project yet, so nothing calls that
      automatically; a real periodic trigger (a cron job hitting it, or AWS
      EventBridge) is needed before launch, the same "needs real
      infrastructure before going live" caveat as the payment gateways.
      Verified via curl end-to-end (create/get/cancel/staff run-due, and a
      non-staff 403 on run-due) and visually in the app.
- [x] Home screen Reminders + Promotions: a "Reminders" section derived
      client-side from data already fetched elsewhere (no new aggregation
      endpoint) - identity verification pending/declined, free trial ending
      within 7 days (links to the Membership screen), any request(s)
      awaiting payment (jumps straight to that request's detail screen when
      there's exactly one, otherwise to the Requests list), and the next
      property inspection reminder date if one's active. Each source fails
      independently (caught separately) so one broken piece never blocks
      the others, and the whole section hides itself when there's nothing
      to show. Below it, a "Promotions" carousel of MidMan's own static
      marketing banners (Refer a friend / Go Pro / Try the AI concierge) -
      TODO-flagged placeholder copy, same pattern as the support contact
      details, ready to swap for a real backend-driven campaigns feed
      later. Caught and fixed in testing: the payment-due reminder
      originally pushed `RequestsScreen` as a standalone route, but that
      screen has no `Scaffold` of its own (it's normally a HomeShell tab
      body) and crashed with a "no Material ancestor" error - fixed by
      routing to the specific request's own detail screen instead (which
      has a proper Scaffold/AppBar), falling back to a Scaffold-wrapped
      RequestsScreen only when there's more than one pending request.

### Phase 8 — Launch
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
