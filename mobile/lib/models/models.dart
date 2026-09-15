class MidManUser {
  final String id;
  final String memberId;
  final String fullName;
  final String email;
  final String phone;
  final String role;
  final String accountType;
  final String kycStatus;

  MidManUser({
    required this.id,
    required this.memberId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.accountType,
    required this.kycStatus,
  });

  factory MidManUser.fromJson(Map<String, dynamic> json) => MidManUser(
        id: json['id'],
        memberId: json['member_id'],
        fullName: json['full_name'],
        email: json['email'],
        phone: json['phone'],
        role: json['role'],
        accountType: json['account_type'],
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
  final DateTime createdAt;
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
    required this.createdAt,
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
        createdAt: DateTime.parse(json['created_at']),
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
