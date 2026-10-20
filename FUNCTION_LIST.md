# MidMen - Function List

The functions the application provides, grouped by the requirement each one
answers. Requirements are taken from `PROJECT_PLAN.md`. "Status" is **Built**
(working end to end), **Partial** (built with a known gap) or **Not built**.

Layers: **API** = FastAPI endpoint in `backend/app/main.py`; **App** = Flutter
screen under `mobile/lib/screens/`.

---

## R1. Account creation and identity (KYC)

| # | Function | API | App | Status |
|---|----------|-----|-----|--------|
| 1.1 | Register a personal account (name, DOB, email, phone, username, password, country) | `POST /auth/register` | register_screen | Built |
| 1.2 | Generate a Member ID from surname + sequence (e.g. MOY000001) | id_generator.py | - | Built |
| 1.3 | Sign in with email, username or phone | `POST /auth/login` | login_screen | Built |
| 1.4 | Show/hide password on every password field | - | password_field widget | Built |
| 1.5 | Forgot password: emailed 6-digit code, then set new password | `POST /auth/forgot-password`, `/auth/reset-password` | forgot_password_screen, reset_password_screen | Built |
| 1.6 | View own profile | `GET /me` | account_screen | Built |
| 1.7 | Upload / re-upload ID or passport for verification | `POST /me/kyc-document` | account_screen | Built |
| 1.8 | Staff review queue: approve or decline ID with a reason (customer is emailed) | `GET /kyc/pending`, `POST /kyc/{id}/decision` | kyc_review_screen | Built |
| 1.9 | Delete own account (soft delete, optional reason) | `DELETE /me` | account_screen | Built |
| 1.10 | Role-based routing: customer, staff, approver, admin each get their own shell | - | role_home_shell | Built |

## R2. Business (multi-user) accounts

| # | Function | API | App | Status |
|---|----------|-----|-----|--------|
| 2.1 | Register a business: company details plus registrant as first Administrator, signed straight in | `POST /auth/register-business` | business_register_screen | Built |
| 2.2 | Generate a Business ID (e.g. BUS-000002) | id_generator.py | - | Built |
| 2.3 | View company profile | `GET /company/me` | employees_screen | Built |
| 2.4 | List employees | `GET /company/employees` | employees_screen | Built |
| 2.5 | Add an employee with a role (Administrator only) | `POST /company/employees` | employees_screen | Built |
| 2.6 | Change an employee's role (Administrator only) | `PATCH /company/employees/{id}` | employees_screen | Built |
| 2.7 | Remove an employee (soft delete; cannot remove yourself) | `DELETE /company/employees/{id}` | employees_screen | Built |
| 2.8 | Five fixed roles with server-side permission checks (create, approve spend, manage team, view reports, company-wide visibility) | business_permissions.py | models.dart | Built |
| 2.9 | Upload company registration documents | `POST /company/documents`, `GET /company/documents` | account_screen | Built |
| 2.10 | Staff review of companies: approve or decline | `GET /companies/pending`, `POST /companies/{id}/decision` | kyc_review_screen (Businesses tab) | Built |
| 2.11 | Company-wide request list for Administrator, Finance, Operations, Viewer/Auditor; Requester sees own only | `GET /service-requests/mine` | requests_screen | Built |
| 2.12 | Open a colleague's request from the company list | `GET /service-requests/{id}` | request_detail_screen | **Partial** - returns 403 for non-owners (fix in progress) |
| 2.13 | Pay button reflects the viewer's role | `POST /service-requests/{id}/pay` | request_detail_screen | **Partial** - button active for roles that cannot pay (fix in progress) |
| 2.14 | Business reports for Finance / Viewer-Auditor | - | - | **Not built** - permission exists, no company reports screen |

## R3. Services catalogue and request creation

| # | Function | API | App | Status |
|---|----------|-----|-----|--------|
| 3.1 | Browse 7 numbered service groups with icons | service_taxonomy.py | home_screen | Built |
| 3.2 | Pick a category within a group | - | category_picker_screen | Built |
| 3.3 | Pick a specific service type (validated per category) | `ServiceRequestCreate` validator | new_request_screen | Built |
| 3.4 | Pick country and city; categories filtered by city | city_availability.py | new_request_screen | Built |
| 3.5 | Create a request (title, details, attachment) | `POST /service-requests` | new_request_screen | Built |
| 3.6 | Extra structured fields for Airport Transfers and Document Delivery | - | new_request_screen | Built |
| 3.7 | Guidance banners (Government errands, Gifts hint) | - | new_request_screen | Built |
| 3.8 | Generate a Request Number (MID-000123) | id_generator.py | - | Built |
| 3.9 | Block request creation for roles that cannot create (banner + disabled Submit + 403) | `create_service_request` | new_request_screen | Built |
| 3.10 | Delete a request raised by mistake (only while still "requested") | `DELETE /service-requests/{id}` | request_detail_screen | Built |
| 3.11 | List my requests (full history) | `GET /service-requests/mine` | requests_screen | Built |
| 3.12 | Track a request: status timeline, evidence, payment state | `GET /service-requests/{id}` | request_detail_screen | Built |
| 3.13 | Customer-facing 4-stage view (Received, Arranging, In Progress, Completed) | CUSTOMER_STAGE_MAP | requests_screen | Built |

## R4. Family care, beneficiaries and authorizers

| # | Function | API | App | Status |
|---|----------|-----|-----|--------|
| 4.1 | Save beneficiaries (person or property) with remembered preferences | `POST /beneficiaries` | family_screen | Built |
| 4.2 | List and delete beneficiaries | `GET`, `DELETE /beneficiaries/{id}` | family_screen | Built |
| 4.3 | Link a beneficiary to a real account (with or without an account) | beneficiaries endpoints | family_screen | Built |
| 4.4 | Request on behalf of a beneficiary | `POST /service-requests` | new_request_screen | Built |
| 4.5 | List customers who can authorize my requests | `GET /me/authorizers` | new_request_screen | Built |
| 4.6 | "Send Request" directly or "start request as beneficiary" via an authorizer | `POST /service-requests` | new_request_screen (Family Care) | Built |
| 4.7 | Authorizer queue: approve or reject requests awaiting them | `GET /service-requests/pending-my-authorization`, `POST .../authorizer-approve`, `.../authorizer-reject` | authorizer_approvals_screen | Built |
| 4.8 | Authorizer is the payer for beneficiary-initiated requests | `_is_payer`, `GET .../pending-my-payment` | request_detail_screen | Built |

## R5. Approval workflow (MidMen side)

| # | Function | API | App | Status |
|---|----------|-----|-----|--------|
| 5.1 | Queue of requests awaiting admin decision | `GET /service-requests`, `GET .../pending` | staff_queue_screen | Built |
| 5.2 | Admin approve / reject a request | `POST .../admin-approve`, `.../admin-reject` | staff_request_detail_screen | Built |
| 5.3 | Approvals tab: everything admin has cleared (read-only for staff) | `GET /service-requests?admin_approved=true` | staff_approvals_screen | Built |
| 5.4 | Payment sign-off (approval_required): admin only; staff see details only | `POST .../approve`, `.../reject` | staff_approvals_screen | Built |
| 5.5 | Update status along the lifecycle (staff) | `POST .../status` | staff_request_detail_screen | Built |
| 5.6 | Attach evidence / proof of completion | `POST .../evidence` | staff_request_detail_screen | Built |
| 5.7 | Fraud-risk triage shown before approving | fraud_check.py | staff_request_detail_screen | Built |
| 5.8 | Full status lifecycle (10 states) with customer-visible event timeline | RequestEvent | request_detail_screen | Built |

## R6. Payments

| # | Function | API | App | Status |
|---|----------|-----|-----|--------|
| 6.1 | Choose a gateway and pay: Paynow (local) or Flutterwave (international cards) | `POST .../pay` | request_detail_screen | Built (needs live credentials) |
| 6.2 | Re-check payment after returning from checkout | `POST .../payment/check`, `GET .../payment` | request_detail_screen | Built |
| 6.3 | Gateway confirmations (hash/signature verified) advance the request | `POST /payments/paynow/webhook`, `/payments/flutterwave/webhook` | - | Built |
| 6.4 | Spend approval restricted to Administrator / Finance in business accounts | `can_approve_spending` | - | Built |
| 6.5 | Payment-due reminder on Home | - | home_screen | Built |
| 6.6 | Recurring / scheduled payments | - | - | **Not built** |

## R7. Subscriptions and membership

`PROJECT_PLAN.md` Phase 3 describes PAYG / Standard / Pro tiers and a free
trial, but the current code has no subscription endpoint, no Membership
screen and no trial reminder. Account shows a single "Free account" card
("saved beneficiaries, full request history, priority service - all
included"). Treat tiering as removed from the product unless it is reinstated.

| # | Function | Status |
|---|----------|--------|
| 7.1 | Single free account with all features included | Built |
| 7.2 | Paid tiers, free trial, tier switching, Pro queue priority, fee waiver | **Not present** - plan and code disagree; decide whether to reinstate |

## R8. AI concierge and support

| # | Function | API | App | Status |
|---|----------|-----|-----|--------|
| 8.1 | Describe a need in words; form is pre-filled, never auto-submitted | `POST /ai/parse-request` | home_screen | Built |
| 8.2 | Upload an invoice/quote (photo or text PDF) to pre-fill a request | `POST /ai/parse-invoice` | home_screen | Built |
| 8.3 | Compare supplier quotes side by side with a recommendation | `POST/GET .../quote-comparison` | staff_request_detail_screen | Built |
| 8.4 | Support chat answering FAQs and questions about own requests (read-only) | `POST /ai/support-chat` | support_chat_screen | Built |
| 8.5 | Help & Support contact card (email, phone) | - | account_screen | Built (placeholder contact details) |
| 8.6 | Voice input on the Home prompt (speech-to-text) | - | home_screen | Built (not testable in the desktop browser pane) |

## R9. Reminders and notifications

| # | Function | API | App | Status |
|---|----------|-----|-----|--------|
| 9.1 | Email on each customer stage and on approve/reject | notifications.py | - | Built |
| 9.2 | Home Reminders section (identity verification, payment due, requests awaiting my authorization/payment, next inspection) | - | home_screen | Built |
| 9.3 | Property inspection email reminder (monthly to annual), set from the request form | `GET/POST/DELETE /reminders/property-inspection` | new_request_screen | Built |
| 9.4 | Daily job emails due reminders | `POST .../run-due` (staff JWT or cron secret) | kyc_review_screen (bell) | Built |
| 9.5 | Promotions carousel (Refer a friend, Go Pro, AI concierge) | - | home_screen | Built (static placeholder copy) |
| 9.6 | WhatsApp channel | - | - | **Not built** |
| 9.7 | Push notifications | - | - | **Not built** |

## R10. Administration, reporting and audit

| # | Function | API | App | Status |
|---|----------|-----|-----|--------|
| 10.1 | Staff dashboard: requests by status and category, amounts, new customers, high-risk flags, pending approvals | `GET /reports/dashboard` | reports_screen | Built |
| 10.2 | List and search users (by role, including inactive) | `GET /admin/users` | user_management_screen | Built |
| 10.3 | Create a staff or admin account (admin only; staff cannot self-register) | `POST /admin/users` | user_management_screen | Built |
| 10.4 | Change a user's role | `POST /admin/users/{id}/role` | user_management_screen | Built |
| 10.5 | Deactivate / reactivate a user (instant login lockout; cannot target self) | `POST .../deactivate`, `.../reactivate` | user_management_screen | Built |
| 10.6 | Audit log of registrations, KYC decisions, role changes, status changes | `GET /admin/audit-log` | audit_log_screen | Built |
| 10.7 | Departments, system settings, workflow configuration | - | - | **Not built** (no concrete requirement yet) |

## R11. Platform and delivery

| # | Function | Where | Status |
|---|----------|-------|--------|
| 11.1 | Evidence storage in private S3 with presigned URLs (local-disk fallback) | uploads.py | Built |
| 11.2 | Database migrations (Alembic) | backend/alembic | Built |
| 11.3 | SMTP email delivery | notifications.py | Built (Gmail for now; swap before real volume) |
| 11.4 | Branding: visible text is "MidMen" (code and package identifiers still use "midman") | - | Built |
| 11.5 | Android release build (APK) | mobile/ | Built (points at localhost API; needs a reachable server URL for real phones) |
| 11.6 | iOS build and signing via CI | - | **Not built** |
| 11.7 | Cloud hosting (AWS) and app store submissions | - | **Not built** |

---

## Summary

- **Built:** about 90 functions across account, business, requests, family care, approvals, payments, AI, reminders and admin.
- **Partial (2 known bugs, fix in progress):** colleague request detail returns 403 (2.12); Pay button ignores business role (2.13).
- **Not built:** recurring payments, business reports screen, WhatsApp, push notifications, iOS CI build, AWS hosting, departments/system settings.
- **Plan and code disagree:** subscription tiers and free trial (R7) are described in `PROJECT_PLAN.md` but absent from the code.
