import 'package:flutter/material.dart' show IconData, Icons;

class DashboardReport {
  final int totalRequests;
  final int totalCustomers;
  final int newCustomersLast30Days;
  final Map<String, int> requestsByStatus;
  final Map<String, int> requestsByCategory;
  final Map<String, int> customersByTier;
  final num totalAmountRequested;
  final num totalAmountCompleted;
  final int highRiskRequests;
  final int pendingApprovalCount;

  DashboardReport({
    required this.totalRequests,
    required this.totalCustomers,
    required this.newCustomersLast30Days,
    required this.requestsByStatus,
    required this.requestsByCategory,
    required this.customersByTier,
    required this.totalAmountRequested,
    required this.totalAmountCompleted,
    required this.highRiskRequests,
    required this.pendingApprovalCount,
  });

  static num _toNum(dynamic v) => switch (v) {
        null => 0,
        num n => n,
        String s => num.tryParse(s) ?? 0,
        _ => 0,
      };

  static Map<String, int> _countMap(List? items, String key) {
    final map = <String, int>{};
    for (final item in (items ?? [])) {
      map[item[key] as String] = item['count'] as int;
    }
    return map;
  }

  factory DashboardReport.fromJson(Map<String, dynamic> json) => DashboardReport(
        totalRequests: json['total_requests'],
        totalCustomers: json['total_customers'],
        newCustomersLast30Days: json['new_customers_last_30_days'],
        requestsByStatus: _countMap(json['requests_by_status'] as List?, 'status'),
        requestsByCategory: _countMap(json['requests_by_category'] as List?, 'category'),
        customersByTier: _countMap(json['customers_by_tier'] as List?, 'account_type'),
        totalAmountRequested: _toNum(json['total_amount_requested']),
        totalAmountCompleted: _toNum(json['total_amount_completed']),
        highRiskRequests: json['high_risk_requests'],
        pendingApprovalCount: json['pending_approval_count'],
      );
}

class AiParseResult {
  final String category;
  final String title;
  final String? description;
  final String? beneficiaryId;
  final String? beneficiaryNameHint;
  final num? amount;
  final List<String> missingInfo;
  final bool aiAvailable;

  AiParseResult({
    required this.category,
    required this.title,
    this.description,
    this.beneficiaryId,
    this.beneficiaryNameHint,
    this.amount,
    required this.missingInfo,
    required this.aiAvailable,
  });

  factory AiParseResult.fromJson(Map<String, dynamic> json) => AiParseResult(
        category: json['category'],
        title: json['title'],
        description: json['description'],
        beneficiaryId: json['beneficiary_id'],
        beneficiaryNameHint: json['beneficiary_name_hint'],
        amount: switch (json['amount']) {
          null => null,
          num n => n,
          String s => num.tryParse(s),
          _ => null,
        },
        missingInfo: (json['missing_info'] as List? ?? []).map((e) => e.toString()).toList(),
        aiAvailable: json['ai_available'] ?? true,
      );
}

class SupportChatReply {
  final String reply;
  final bool aiAvailable;

  SupportChatReply({required this.reply, required this.aiAvailable});

  factory SupportChatReply.fromJson(Map<String, dynamic> json) => SupportChatReply(
        reply: json['reply'] ?? '',
        aiAvailable: json['ai_available'] ?? true,
      );
}

class MidManUser {
  final String id;
  final String memberId;
  final String fullName;
  final String email;
  final String phone;
  final String? username;
  final String role;
  final String accountType;
  final DateTime? trialEndsAt;
  final String kycStatus;
  final String? kycRejectionReason;
  final String? countryOfResidence;
  final DateTime? deletedAt;
  final String? companyId;
  final String? businessRole; // administrator | finance | operations | requester | viewer_auditor

  MidManUser({
    required this.id,
    required this.memberId,
    required this.fullName,
    required this.email,
    required this.phone,
    this.username,
    required this.role,
    required this.accountType,
    this.trialEndsAt,
    required this.kycStatus,
    this.kycRejectionReason,
    this.countryOfResidence,
    this.deletedAt,
    this.companyId,
    this.businessRole,
  });

  bool get isOnTrial => trialEndsAt != null && DateTime.now().isBefore(trialEndsAt!);
  bool get isActive => deletedAt == null;
  bool get isBusinessAccount => companyId != null;

  factory MidManUser.fromJson(Map<String, dynamic> json) => MidManUser(
        id: json['id'],
        memberId: json['member_id'],
        fullName: json['full_name'],
        email: json['email'],
        phone: json['phone'],
        username: json['username'],
        role: json['role'],
        accountType: json['account_type'],
        trialEndsAt: json['trial_ends_at'] == null ? null : DateTime.parse(json['trial_ends_at']),
        kycStatus: json['kyc_status'],
        kycRejectionReason: json['kyc_rejection_reason'],
        countryOfResidence: json['country_of_residence'],
        deletedAt: json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at']),
        companyId: json['company_id'],
        businessRole: json['business_role'],
      );
}

/// Fixed employee roles for a Business account, and what each one can do -
/// mirrors backend/app/business_permissions.py exactly. There's no custom
/// permission builder: an employee's capabilities come entirely from which
/// of these five roles they're assigned.
class BusinessRoleOption {
  final String value;
  final String label;
  final String description;
  const BusinessRoleOption(this.value, this.label, this.description);
}

const kBusinessRoles = [
  BusinessRoleOption('administrator', 'Administrator', 'Full access - create, approve spend, manage employees, view reports'),
  BusinessRoleOption('finance', 'Finance', 'Approves spend/quotations and views reports - can\'t create requests'),
  BusinessRoleOption('operations', 'Operations', 'Creates and manages requests day-to-day - can\'t approve spend'),
  BusinessRoleOption('requester', 'Requester', 'Can create requests only, sees just their own'),
  BusinessRoleOption('viewer_auditor', 'Viewer / Auditor', 'Read-only - completed jobs and reports, no create/approve'),
];

String businessRoleLabel(String? value) =>
    kBusinessRoles.firstWhere((r) => r.value == value, orElse: () => const BusinessRoleOption('', 'Employee', '')).label;

// Mirrors backend/app/business_permissions.py exactly - a personal account
// (businessRole null) is never restricted by these.
const _createRoles = {'administrator', 'operations', 'requester'};
const _approveSpendingRoles = {'administrator', 'finance'};
const _manageEmployeesRoles = {'administrator'};

bool userCanCreateRequest(MidManUser user) => user.businessRole == null || _createRoles.contains(user.businessRole);
bool userCanApproveSpending(MidManUser user) =>
    user.businessRole == null || _approveSpendingRoles.contains(user.businessRole);
bool userCanManageEmployees(MidManUser user) =>
    user.businessRole == null || _manageEmployeesRoles.contains(user.businessRole);

class Company {
  final String id;
  final String businessId;
  final String legalName;
  final String? tradingName;
  final String registrationNumber;
  final String country;
  final String registeredAddress;
  final String? businessAddress;
  final String industry;
  final String authorizedRepresentativeName;
  final String email;
  final String phone;
  final String? billingContactName;
  final String? billingContactEmail;
  final String? billingContactPhone;
  final String? operationsContactName;
  final String? operationsContactEmail;
  final String? operationsContactPhone;
  final String? taxDetails;
  final String kycStatus;
  final String? kycRejectionReason;
  final DateTime createdAt;

  Company({
    required this.id,
    required this.businessId,
    required this.legalName,
    this.tradingName,
    required this.registrationNumber,
    required this.country,
    required this.registeredAddress,
    this.businessAddress,
    required this.industry,
    required this.authorizedRepresentativeName,
    required this.email,
    required this.phone,
    this.billingContactName,
    this.billingContactEmail,
    this.billingContactPhone,
    this.operationsContactName,
    this.operationsContactEmail,
    this.operationsContactPhone,
    this.taxDetails,
    required this.kycStatus,
    this.kycRejectionReason,
    required this.createdAt,
  });

  factory Company.fromJson(Map<String, dynamic> json) => Company(
        id: json['id'],
        businessId: json['business_id'],
        legalName: json['legal_name'],
        tradingName: json['trading_name'],
        registrationNumber: json['registration_number'],
        country: json['country'],
        registeredAddress: json['registered_address'],
        businessAddress: json['business_address'],
        industry: json['industry'],
        authorizedRepresentativeName: json['authorized_representative_name'],
        email: json['email'],
        phone: json['phone'],
        billingContactName: json['billing_contact_name'],
        billingContactEmail: json['billing_contact_email'],
        billingContactPhone: json['billing_contact_phone'],
        operationsContactName: json['operations_contact_name'],
        operationsContactEmail: json['operations_contact_email'],
        operationsContactPhone: json['operations_contact_phone'],
        taxDetails: json['tax_details'],
        kycStatus: json['kyc_status'],
        kycRejectionReason: json['kyc_rejection_reason'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class ReminderFrequencyOption {
  final String value;
  final String label;
  const ReminderFrequencyOption(this.value, this.label);
}

const kReminderFrequencies = [
  ReminderFrequencyOption('monthly', 'Monthly'),
  ReminderFrequencyOption('quarterly', 'Every 3 months'),
  ReminderFrequencyOption('biannual', 'Every 6 months'),
  ReminderFrequencyOption('annual', 'Yearly'),
];

String reminderFrequencyLabel(String value) =>
    kReminderFrequencies.firstWhere((f) => f.value == value, orElse: () => ReminderFrequencyOption(value, value)).label;

class InspectionReminder {
  final String id;
  final String frequency;
  final String? propertyLabel;
  final DateTime nextReminderAt;
  final bool active;

  InspectionReminder({
    required this.id,
    required this.frequency,
    this.propertyLabel,
    required this.nextReminderAt,
    required this.active,
  });

  factory InspectionReminder.fromJson(Map<String, dynamic> json) => InspectionReminder(
        id: json['id'],
        frequency: json['frequency'],
        propertyLabel: json['property_label'],
        nextReminderAt: DateTime.parse(json['next_reminder_at']),
        active: json['active'],
      );
}

class CompanyDocumentOut {
  final String id;
  final String fileUrl;
  final String? caption;
  final DateTime createdAt;

  CompanyDocumentOut({required this.id, required this.fileUrl, this.caption, required this.createdAt});

  factory CompanyDocumentOut.fromJson(Map<String, dynamic> json) => CompanyDocumentOut(
        id: json['id'],
        fileUrl: json['file_url'],
        caption: json['caption'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class CompanyKYCReview {
  final String id;
  final String businessId;
  final String legalName;
  final String registrationNumber;
  final String country;
  final String email;
  final String phone;
  final String kycStatus;
  final String? kycRejectionReason;
  final DateTime createdAt;
  final int documentCount;

  CompanyKYCReview({
    required this.id,
    required this.businessId,
    required this.legalName,
    required this.registrationNumber,
    required this.country,
    required this.email,
    required this.phone,
    required this.kycStatus,
    this.kycRejectionReason,
    required this.createdAt,
    required this.documentCount,
  });

  factory CompanyKYCReview.fromJson(Map<String, dynamic> json) => CompanyKYCReview(
        id: json['id'],
        businessId: json['business_id'],
        legalName: json['legal_name'],
        registrationNumber: json['registration_number'],
        country: json['country'],
        email: json['email'],
        phone: json['phone'],
        kycStatus: json['kyc_status'],
        kycRejectionReason: json['kyc_rejection_reason'],
        createdAt: DateTime.parse(json['created_at']),
        documentCount: json['document_count'] ?? 0,
      );
}

class AuditLogEntry {
  final String id;
  final String actorName;
  final String actorRole;
  final String action;
  final String entityType;
  final String? entityId;
  final String summary;
  final Map<String, dynamic>? meta;
  final DateTime createdAt;

  AuditLogEntry({
    required this.id,
    required this.actorName,
    required this.actorRole,
    required this.action,
    required this.entityType,
    this.entityId,
    required this.summary,
    this.meta,
    required this.createdAt,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
        id: json['id'],
        actorName: json['actor_name'],
        actorRole: json['actor_role'],
        action: json['action'],
        entityType: json['entity_type'],
        entityId: json['entity_id'],
        summary: json['summary'],
        meta: json['meta'] == null ? null : Map<String, dynamic>.from(json['meta']),
        createdAt: DateTime.parse(json['created_at']),
      );
}

class KYCReview {
  final String id;
  final String memberId;
  final String fullName;
  final String email;
  final String phone;
  final String countryOfResidence;
  final String documentUrl;
  final String kycStatus;
  final DateTime createdAt;

  KYCReview({
    required this.id,
    required this.memberId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.countryOfResidence,
    required this.documentUrl,
    required this.kycStatus,
    required this.createdAt,
  });

  factory KYCReview.fromJson(Map<String, dynamic> json) => KYCReview(
        id: json['id'],
        memberId: json['member_id'],
        fullName: json['full_name'],
        email: json['email'],
        phone: json['phone'],
        countryOfResidence: json['country_of_residence'],
        documentUrl: json['id_document_path'],
        kycStatus: json['kyc_status'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class Payment {
  final String id;
  final String provider; // "paynow" | "flutterwave"
  final String? method;
  final String merchantReference;
  final String? providerReference;
  final num amount;
  final String currency;
  final String status; // "pending" | "paid" | "failed" | "cancelled"
  final String? checkoutUrl;
  final DateTime createdAt;
  final DateTime? paidAt;

  Payment({
    required this.id,
    required this.provider,
    this.method,
    required this.merchantReference,
    this.providerReference,
    required this.amount,
    required this.currency,
    required this.status,
    this.checkoutUrl,
    required this.createdAt,
    this.paidAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'],
        provider: json['provider'],
        method: json['method'],
        merchantReference: json['merchant_reference'],
        providerReference: json['provider_reference'],
        amount: switch (json['amount']) {
          num n => n,
          String s => num.tryParse(s) ?? 0,
          _ => 0,
        },
        currency: json['currency'],
        status: json['status'],
        checkoutUrl: json['checkout_url'],
        createdAt: DateTime.parse(json['created_at']),
        paidAt: json['paid_at'] == null ? null : DateTime.parse(json['paid_at']),
      );
}

class Beneficiary {
  final String id;
  final String fullName;
  final String relationshipType;
  final String? address;

  Beneficiary({required this.id, required this.fullName, required this.relationshipType, this.address});

  factory Beneficiary.fromJson(Map<String, dynamic> json) => Beneficiary(
        id: json['id'],
        fullName: json['full_name'],
        relationshipType: json['relationship_type'],
        address: json['address'],
      );
}

class RequestEvent {
  final String status;
  final String? note;
  final DateTime createdAt;

  RequestEvent({required this.status, this.note, required this.createdAt});

  factory RequestEvent.fromJson(Map<String, dynamic> json) => RequestEvent(
        status: json['status'],
        note: json['note'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class EvidenceOut {
  final String id;
  final String fileUrl;
  final String fileType; // "photo" | "video" | "document" | "receipt" | "quote"
  final String? caption;
  final String? supplierName;
  final DateTime createdAt;

  EvidenceOut({
    required this.id,
    required this.fileUrl,
    required this.fileType,
    this.caption,
    this.supplierName,
    required this.createdAt,
  });

  factory EvidenceOut.fromJson(Map<String, dynamic> json) => EvidenceOut(
        id: json['id'],
        fileUrl: json['file_url'],
        fileType: json['file_type'],
        caption: json['caption'],
        supplierName: json['supplier_name'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class SupplierQuoteSummary {
  final String supplierName;
  final num? amount;
  final String? notes;

  SupplierQuoteSummary({required this.supplierName, this.amount, this.notes});

  factory SupplierQuoteSummary.fromJson(Map<String, dynamic> json) => SupplierQuoteSummary(
        supplierName: json['supplier_name'],
        amount: switch (json['amount']) {
          null => null,
          num n => n,
          String s => num.tryParse(s),
          _ => null,
        },
        notes: json['notes'],
      );
}

class QuoteComparison {
  final DateTime generatedAt;
  final String summary;
  final String? recommendation;
  final List<SupplierQuoteSummary> suppliers;
  final bool aiAvailable;

  QuoteComparison({
    required this.generatedAt,
    required this.summary,
    this.recommendation,
    required this.suppliers,
    required this.aiAvailable,
  });

  factory QuoteComparison.fromJson(Map<String, dynamic> json) => QuoteComparison(
        generatedAt: DateTime.parse(json['generated_at']),
        summary: json['summary'] ?? '',
        recommendation: json['recommendation'],
        suppliers: (json['suppliers'] as List? ?? []).map((e) => SupplierQuoteSummary.fromJson(e)).toList(),
        aiAvailable: json['ai_available'] ?? true,
      );
}

class ServiceRequest {
  final String id;
  final String requestNumber;
  final String? country;
  final String? city;
  final String category;
  final String? serviceType;
  final String title;
  final String? description;
  final num? amount;
  final String currency;
  final String status;
  final String? fraudRiskLevel;
  final int? fraudRiskScore;
  final String? fraudReasoning;
  final DateTime createdAt;
  final MidManUser requester;
  final Beneficiary? beneficiary;
  final List<RequestEvent> events;
  final List<EvidenceOut> evidence;

  ServiceRequest({
    required this.id,
    required this.requestNumber,
    this.country,
    this.city,
    required this.category,
    this.serviceType,
    required this.title,
    this.description,
    this.amount,
    required this.currency,
    required this.status,
    this.fraudRiskLevel,
    this.fraudRiskScore,
    this.fraudReasoning,
    required this.createdAt,
    required this.requester,
    this.beneficiary,
    required this.events,
    required this.evidence,
  });

  factory ServiceRequest.fromJson(Map<String, dynamic> json) => ServiceRequest(
        id: json['id'],
        requestNumber: json['request_number'],
        country: json['country'],
        city: json['city'],
        category: json['category'],
        serviceType: json['service_type'],
        title: json['title'],
        description: json['description'],
        // The backend serializes Decimal as a JSON string (e.g. "450.00") to preserve precision.
        amount: switch (json['amount']) {
          null => null,
          num n => n,
          String s => num.tryParse(s),
          _ => null,
        },
        currency: json['currency'],
        status: json['status'],
        fraudRiskLevel: json['fraud_risk_level'],
        fraudRiskScore: json['fraud_risk_score'],
        fraudReasoning: json['fraud_reasoning'],
        createdAt: DateTime.parse(json['created_at']),
        requester: MidManUser.fromJson(json['requester'] as Map<String, dynamic>),
        beneficiary: json['beneficiary'] == null
            ? null
            : Beneficiary.fromJson(json['beneficiary'] as Map<String, dynamic>),
        events: (json['events'] as List? ?? [])
            .map((e) => RequestEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        evidence: (json['evidence'] as List? ?? [])
            .map((e) => EvidenceOut.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// The 3-level service taxonomy: Service (group, numbered on the Home
/// screen) -> Category (a button under a group, maps to the backend's
/// `category` field) -> Service Type (a dropdown of specific options under
/// a category, maps to the backend's free-text `service_type` field).
/// Mirrored by hand in backend/app/service_taxonomy.py - keep both in sync.
class ServiceCategoryOption {
  final String value; // matches the backend ServiceCategory enum
  final String label;
  final String subtitle;
  final List<String> serviceTypes; // Level-3 dropdown options; empty if none
  final String? notice; // shown as an info banner when this category is picked
  final List<String> extraFields; // structured fields collected in addition to the description
  final String titleHint; // shown as the "What needs to be done?" field's hint
  final String detailsHint; // shown as the "Details (optional)" field's hint

  const ServiceCategoryOption(
    this.value,
    this.label,
    this.subtitle, {
    this.serviceTypes = const [],
    this.notice,
    this.extraFields = const [],
    required this.titleHint,
    required this.detailsHint,
  });
}

class ServiceGroup {
  final String number;
  final String label;
  final List<ServiceCategoryOption> categories;
  final IconData icon; // shown on the Home screen's group card, in place of the plain number badge

  const ServiceGroup(this.number, this.label, this.categories, {required this.icon});
}

const kServiceGroups = [
  ServiceGroup('1', 'Family Care & Child Support', [
    ServiceCategoryOption(
      'groceries',
      'Groceries',
      'Food, personal care, baby & household supplies',
      serviceTypes: ['Food Supplies', 'Personal Care Products', 'Baby Products', 'Household Supplies', 'Other'],
      titleHint: 'e.g. Weekly groceries for Mum',
      detailsHint: 'e.g. Preferred store, delivery date, dietary preferences',
    ),
    ServiceCategoryOption(
      'healthcare',
      'Healthcare',
      'Hospital bills, medication, appointments',
      serviceTypes: [
        'Pay Hospital Bill',
        'Buy Medication',
        'Specialist Appointments',
        'Medical Procedures',
        'Laboratory Tests',
        'Other Healthcare-Related Expenses',
      ],
      titleHint: 'e.g. Pay hospital bill for Dad',
      detailsHint: 'e.g. Hospital name, patient name, amount due',
    ),
    ServiceCategoryOption(
      'education',
      'Education',
      'Tuition, exams, uniforms, transport',
      serviceTypes: ['Tuition Fees', 'Exam Fees', 'Uniforms', 'Transport', 'Stationery', 'Other Education-Related Expenses'],
      titleHint: 'e.g. Term 3 school fees',
      detailsHint: "e.g. School name, deadline, student's name",
    ),
  ], icon: Icons.family_restroom),
  ServiceGroup('2', 'Documents & Administration', [
    ServiceCategoryOption(
      'document_collection',
      'Document Collection',
      'Collecting documents on your behalf',
      serviceTypes: ['Document Collection', 'Other'],
      titleHint: 'e.g. Collect birth certificate from Registry',
      detailsHint: 'e.g. Document type, collection point, reference number',
    ),
    ServiceCategoryOption(
      'document_delivery',
      'Document Delivery',
      'Delivering or submitting documents',
      serviceTypes: ['Document Submission', 'Other'],
      titleHint: 'e.g. Deliver passport application to Home Affairs',
      detailsHint: 'e.g. Document type, delivery address, deadline',
    ),
    ServiceCategoryOption(
      'government_errands',
      'Administrative Errands',
      'Application follow-ups, certificate collection',
      serviceTypes: ['Application Follow-ups', 'Certificate Collection'],
      notice: "MidMan provides ordinary administrative assistance only (queuing, form submission, "
          "collection). Anything requiring a licensed professional (e.g. a lawyer) or Power of "
          "Attorney isn't covered here and needs separate arrangement.",
      titleHint: 'e.g. Follow up on my ID application',
      detailsHint: 'e.g. Application reference number, office, deadline',
    ),
  ], icon: Icons.description_outlined),
  ServiceGroup('3', 'Property Management & Home Services', [
    ServiceCategoryOption(
      'property_inspection',
      'Property Inspections',
      'Condition reports, utility coordination',
      serviceTypes: ['Condition Reporting', 'Utility Coordination', 'Occupancy Confirmation', 'Other'],
      titleHint: 'e.g. Inspect rental property in Borrowdale',
      detailsHint: 'e.g. Property address, tenant contact, what to check',
    ),
    ServiceCategoryOption(
      'maintenance',
      'Maintenance',
      'Repairs, contractors, general upkeep',
      serviceTypes: [
        'Plumbing',
        'Electrical',
        'Air Conditioning',
        'Painting',
        'Carpentry',
        'Appliance Repairs',
        'General Repairs',
        'Cleaning',
        'Landscaping',
        'Other',
      ],
      titleHint: 'e.g. Fix leaking kitchen tap',
      detailsHint: 'e.g. Property address, contractor preference, urgency',
    ),
    ServiceCategoryOption(
      'tenant_coordination',
      'Tenant Coordination',
      'Move-in/out, key handovers',
      serviceTypes: ['Move-in/Move-out Inspections', 'Key Collection', 'Key Handover', 'Rent Collection'],
      titleHint: 'e.g. Hand over keys to new tenant',
      detailsHint: 'e.g. Property address, tenant name, move-in date',
    ),
    ServiceCategoryOption(
      'property_cleaning',
      'Property Cleaning',
      'Deep cleaning, move-in/move-out',
      serviceTypes: ['Deep Cleaning', 'Move-In / Move-Out'],
      titleHint: 'e.g. Deep clean before move-in',
      detailsHint: 'e.g. Property address, size, preferred date',
    ),
    ServiceCategoryOption(
      'building_materials',
      'Building Materials',
      'Cement, bricks, steel, hardware',
      serviceTypes: [
        'Cement',
        'Bricks',
        'Sand',
        'Steel',
        'Roofing Materials',
        'Plumbing Materials',
        'Electrical Materials',
        'Paint',
        'Tiles',
        'Hardware',
      ],
      titleHint: 'e.g. Buy cement and bricks for boundary wall',
      detailsHint: 'e.g. Quantities, delivery address, supplier preference',
    ),
    ServiceCategoryOption(
      'household_procurement',
      'Household Procurement',
      'Appliances, furniture, electronics',
      serviceTypes: ['Appliances', 'Furniture', 'Electronics', 'Household Goods', 'Office Equipment', 'Other Approved Products'],
      titleHint: 'e.g. Buy a fridge for the house',
      detailsHint: 'e.g. Brand/model preference, budget, delivery address',
    ),
    ServiceCategoryOption(
      'procurement',
      'Other',
      'General procurement',
      serviceTypes: ['General Procurement'],
      titleHint: 'e.g. Source office chairs',
      detailsHint: 'e.g. Item, quantity, budget',
    ),
  ], icon: Icons.home_work_outlined),
  ServiceGroup(
    '4',
    'Gifts & Celebrations',
    [
      ServiceCategoryOption(
        'birthday_gifts',
        'Birthday Gifts',
        'Cake, flowers, gifts, event coordination',
        serviceTypes: ['Cake Only', 'Cake & Flowers', 'Cake + Flowers & Gift', 'Restaurant/Event Coordination'],
        titleHint: 'e.g. Birthday cake and flowers for Mum',
        detailsHint: 'e.g. Recipient, delivery address, date needed',
      ),
      ServiceCategoryOption(
        'anniversary_valentines_gifts',
        'Anniversary/Valentines Gifts',
        'Cake, flowers, gifts, event coordination',
        serviceTypes: ['Cake Only', 'Cake & Flowers', 'Cake + Flowers & Gift', 'Restaurant/Event Coordination'],
        titleHint: "e.g. Valentine's flowers and cake",
        detailsHint: 'e.g. Recipient, delivery address, date needed',
      ),
      ServiceCategoryOption(
        'graduation_gifts',
        'Graduation Gifts',
        'Cake, flowers, gifts, photoshoot',
        serviceTypes: ['Cake Only', 'Cake & Flowers', 'Cake + Flowers & Gift', 'Restaurant/Event Coordination', 'Photoshoot'],
        titleHint: 'e.g. Graduation cake and photoshoot',
        detailsHint: 'e.g. Recipient, venue, date and time',
      ),
      ServiceCategoryOption(
        'corporate_gifts',
        'Corporate Gifts',
        'Employee, client & partner gifts',
        serviceTypes: ['Employee Gifts', 'Client Gifts', 'Business Partner Gifts', 'Executive Gifts', 'Special Occasions'],
        titleHint: 'e.g. Year-end gifts for 10 staff',
        detailsHint: 'e.g. Recipients, quantity, budget per gift',
      ),
      ServiceCategoryOption(
        'gifts',
        'Other Celebrations',
        'Cake, flowers, gifts, photoshoot',
        serviceTypes: ['Cake Only', 'Cake & Flowers', 'Cake + Flowers & Gift', 'Restaurant/Event Coordination', 'Photoshoot'],
        titleHint: 'e.g. Congratulations gift for a promotion',
        detailsHint: 'e.g. Recipient, occasion, delivery address',
      ),
    ],
    icon: Icons.card_giftcard_outlined,
  ),
  ServiceGroup('5', 'Transportation & Mobility', [
    ServiceCategoryOption(
      'transportation',
      'Airport Transfers',
      'Airport drop off or pick up',
      serviceTypes: ['Airport Drop off', 'Airport Pick up'],
      extraFields: ['Airport', 'Flight number', 'Passenger', 'Arrival time', 'Destination'],
      titleHint: 'e.g. Airport pickup for my sister',
      detailsHint: 'e.g. Number of bags, vehicle preference, any special instructions',
    ),
  ], icon: Icons.flight_outlined),
  ServiceGroup('6', 'Other', [
    ServiceCategoryOption(
      'personal_concierge',
      'Personal Concierge/Errands',
      'Collections, deliveries, local errands',
      serviceTypes: ['Collections', 'Deliveries', 'Purchases', 'Appointments', 'Local Errands', 'Personal Administration'],
      titleHint: 'e.g. Pick up dry cleaning',
      detailsHint: 'e.g. Location, timing, any special instructions',
    ),
  ], icon: Icons.miscellaneous_services_outlined),
];

/// Flattened list of every category across every group - for places that
/// just need "all categories" regardless of grouping (e.g. report labels).
final kServiceCategories = kServiceGroups.expand((g) => g.categories).toList();

ServiceCategoryOption? findServiceCategory(String value) {
  for (final c in kServiceCategories) {
    if (c.value == value) return c;
  }
  return null;
}

/// Membership tier metadata for the plan picker. Pricing isn't set yet -
/// "Subscriptions fees right amounts will be added later".
class SubscriptionTier {
  final String value; // matches the backend AccountType enum
  final String label;
  final List<String> features;

  const SubscriptionTier(this.value, this.label, this.features);
}

const kSubscriptionTiers = [
  SubscriptionTier('payg', 'Pay As You Go', [
    'Unlimited use, charged per service',
    'No saved beneficiaries - enter details each time',
    'No history of past requests',
  ]),
  SubscriptionTier('standard', 'Standard', [
    'Save beneficiaries you look after',
    'Full history of past requests',
    'Faster processing than PAYG',
    'Recurring payments allowed',
  ]),
  SubscriptionTier('pro', 'Pro', [
    'Everything in Standard',
    'Priority - served first in the queue',
    'Free digital assistance (e.g. document help)',
  ]),
];
