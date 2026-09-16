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
  final String role;
  final String accountType;
  final DateTime? trialEndsAt;
  final String kycStatus;
  final String? kycRejectionReason;
  final DateTime? deletedAt;

  MidManUser({
    required this.id,
    required this.memberId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.accountType,
    this.trialEndsAt,
    required this.kycStatus,
    this.kycRejectionReason,
    this.deletedAt,
  });

  bool get isOnTrial => trialEndsAt != null && DateTime.now().isBefore(trialEndsAt!);
  bool get isActive => deletedAt == null;

  factory MidManUser.fromJson(Map<String, dynamic> json) => MidManUser(
        id: json['id'],
        memberId: json['member_id'],
        fullName: json['full_name'],
        email: json['email'],
        phone: json['phone'],
        role: json['role'],
        accountType: json['account_type'],
        trialEndsAt: json['trial_ends_at'] == null ? null : DateTime.parse(json['trial_ends_at']),
        kycStatus: json['kyc_status'],
        kycRejectionReason: json['kyc_rejection_reason'],
        deletedAt: json['deleted_at'] == null ? null : DateTime.parse(json['deleted_at']),
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
  final String category;
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
    required this.category,
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
        category: json['category'],
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

/// Service categories shown on the Services grid, mapped to the backend enum.
class ServiceCategoryOption {
  final String value;
  final String label;
  final String subtitle;

  const ServiceCategoryOption(this.value, this.label, this.subtitle);
}

const kServiceCategories = [
  ServiceCategoryOption('school_fees', 'School Fees', 'Tuition, registration, exams'),
  ServiceCategoryOption('medical', 'Medical', 'Hospital, clinic, specialist bills'),
  ServiceCategoryOption('prescriptions', 'Prescriptions', 'Medication & pharmacy'),
  ServiceCategoryOption('groceries', 'Groceries', 'Household & family essentials'),
  ServiceCategoryOption('documents', 'Documents', 'Collection & delivery'),
  ServiceCategoryOption('property_management', 'Property', 'Inspections & management'),
  ServiceCategoryOption('maintenance', 'Maintenance', 'Repairs, cleaning, contractors'),
  ServiceCategoryOption('procurement', 'Procurement', 'Building materials, shopping'),
  ServiceCategoryOption('gifts', 'Gifts & Celebrations', 'Flowers, cakes, hampers'),
  ServiceCategoryOption('transportation', 'Transport', 'Airport transfers & rides'),
  ServiceCategoryOption('personal_concierge', 'Personal Concierge', 'Anything else - just ask'),
  ServiceCategoryOption('other', 'Other', 'Tell us what you need'),
];

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
