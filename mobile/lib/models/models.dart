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
  });

  bool get isOnTrial => trialEndsAt != null && DateTime.now().isBefore(trialEndsAt!);

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
  final String fileType; // "photo" | "document" | "receipt"
  final String? caption;
  final DateTime createdAt;

  EvidenceOut({required this.id, required this.fileUrl, required this.fileType, this.caption, required this.createdAt});

  factory EvidenceOut.fromJson(Map<String, dynamic> json) => EvidenceOut(
        id: json['id'],
        fileUrl: json['file_url'],
        fileType: json['file_type'],
        caption: json['caption'],
        createdAt: DateTime.parse(json['created_at']),
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
