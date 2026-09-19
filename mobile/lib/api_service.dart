import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'models/models.dart';

/// 10.0.2.2 is how the Android emulator reaches the host machine's localhost.
/// On web, a physical device, or an iOS simulator, point this at your
/// machine's LAN IP or the deployed API URL instead. Uses defaultTargetPlatform
/// (not dart:io Platform, which throws UnsupportedError on web builds).
String get _baseUrl =>
    (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, {this.statusCode = 0});
  @override
  String toString() => message;
}

class ApiService {
  static final _storage = const FlutterSecureStorage();

  static String get baseUrl => _baseUrl;

  /// Evidence file_url is either an absolute URL (S3 presigned link) or a
  /// path relative to the API (local-disk dev fallback, e.g. "/uploads/x.pdf").
  static String resolveFileUrl(String fileUrl) =>
      fileUrl.startsWith('http') ? fileUrl : '$_baseUrl$fileUrl';

  static Future<String?> get _token => _storage.read(key: 'access_token');

  static Future<Map<String, String>> _authHeaders() async {
    final token = await _token;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static dynamic _decode(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    String detail = res.body;
    try {
      detail = (jsonDecode(res.body)['detail'] ?? res.body).toString();
    } catch (_) {}
    throw ApiException(detail, statusCode: res.statusCode);
  }

  static Future<void> register({
    required String fullName,
    required String dateOfBirth, // yyyy-MM-dd
    required String email,
    required String phone,
    required String password,
    required String countryOfResidence,
    String? primaryPurpose,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'full_name': fullName,
        'date_of_birth': dateOfBirth,
        'email': email,
        'phone': phone,
        'password': password,
        'country_of_residence': countryOfResidence,
        'primary_purpose': primaryPurpose,
      }),
    );
    _decode(res);
  }

  /// Registers a MidMan Business account: the company itself plus the
  /// registrant as its first employee (Administrator role). Logs the
  /// registrant straight in - unlike personal [register], no separate
  /// sign-in step is needed before they can start inviting their team.
  static Future<void> registerBusiness({
    required String fullName,
    required String dateOfBirth,
    required String email,
    required String phone,
    required String password,
    required String legalName,
    String? tradingName,
    required String registrationNumber,
    required String country,
    required String registeredAddress,
    String? businessAddress,
    required String industry,
    required String authorizedRepresentativeName,
    required String companyEmail,
    required String companyPhone,
    String? billingContactName,
    String? billingContactEmail,
    String? billingContactPhone,
    String? operationsContactName,
    String? operationsContactEmail,
    String? operationsContactPhone,
    String? taxDetails,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/auth/register-business'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'full_name': fullName,
        'date_of_birth': dateOfBirth,
        'email': email,
        'phone': phone,
        'password': password,
        'legal_name': legalName,
        'trading_name': tradingName,
        'registration_number': registrationNumber,
        'country': country,
        'registered_address': registeredAddress,
        'business_address': businessAddress,
        'industry': industry,
        'authorized_representative_name': authorizedRepresentativeName,
        'company_email': companyEmail,
        'company_phone': companyPhone,
        'billing_contact_name': billingContactName,
        'billing_contact_email': billingContactEmail,
        'billing_contact_phone': billingContactPhone,
        'operations_contact_name': operationsContactName,
        'operations_contact_email': operationsContactEmail,
        'operations_contact_phone': operationsContactPhone,
        'tax_details': taxDetails,
      }),
    );
    final data = _decode(res);
    await _storage.write(key: 'access_token', value: data['access_token']);
  }

  static Future<void> login({required String email, required String password}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _decode(res);
    await _storage.write(key: 'access_token', value: data['access_token']);
  }

  static Future<void> logout() => _storage.delete(key: 'access_token');

  static Future<bool> isLoggedIn() async => (await _token) != null;

  static Future<MidManUser> me() async {
    final res = await http.get(Uri.parse('$_baseUrl/me'), headers: await _authHeaders());
    return MidManUser.fromJson(_decode(res));
  }

  /// Permanently (soft-)deletes the signed-in customer's own account.
  /// [reason] is optional feedback shown only to staff, never required.
  static Future<void> deleteAccount({String? reason}) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/me'),
      headers: await _authHeaders(),
      body: jsonEncode({'reason': reason}),
    );
    _decode(res);
  }

  /// [accountType] is one of 'payg' | 'standard' | 'pro'.
  static Future<MidManUser> changeSubscription(String accountType) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/me/subscription'),
      headers: await _authHeaders(),
      body: jsonEncode({'account_type': accountType}),
    );
    return MidManUser.fromJson(_decode(res));
  }

  /// Turns free text into a structured request draft. Never creates or
  /// submits anything itself - the customer still reviews and confirms
  /// every field before it becomes a real request.
  static Future<AiParseResult> parseRequestText(String text) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/ai/parse-request'),
      headers: await _authHeaders(),
      body: jsonEncode({'text': text}),
    );
    return AiParseResult.fromJson(_decode(res));
  }

  /// Same idea as [parseRequestText], but reads an uploaded invoice or price
  /// quote (a photo, or a text-based PDF) instead of typed text. Never
  /// creates or submits a request itself - the customer still reviews the
  /// prefilled draft before anything is sent.
  static Future<AiParseResult> parseInvoiceDocument({required List<int> bytes, required String filename}) async {
    final token = await _token;
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/ai/parse-invoice'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return AiParseResult.fromJson(_decode(res));
  }

  /// General help/FAQ chatbot - stateless server-side, so the client resends
  /// recent [history] (role/content pairs, oldest first) with every message.
  static Future<SupportChatReply> supportChat({
    required String message,
    required List<Map<String, String>> history,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/ai/support-chat'),
      headers: await _authHeaders(),
      body: jsonEncode({'message': message, 'history': history}),
    );
    return SupportChatReply.fromJson(_decode(res));
  }

  static Future<DashboardReport> dashboardReport() async {
    final res = await http.get(Uri.parse('$_baseUrl/reports/dashboard'), headers: await _authHeaders());
    return DashboardReport.fromJson(_decode(res));
  }

  /// Uploads (or re-uploads, after a rejection) the customer's id/passport.
  /// Always resets kyc_status to pending server-side.
  static Future<MidManUser> uploadKycDocument({required List<int> bytes, required String filename}) async {
    final token = await _token;
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/me/kyc-document'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return MidManUser.fromJson(_decode(res));
  }

  static Future<List<KYCReview>> pendingKycReviews() async {
    final res = await http.get(Uri.parse('$_baseUrl/kyc/pending'), headers: await _authHeaders());
    final data = _decode(res) as List;
    return data.map((e) => KYCReview.fromJson(e)).toList();
  }

  static Future<void> decideKyc({required String userId, required bool approve, String? reason}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/kyc/$userId/decision'),
      headers: await _authHeaders(),
      body: jsonEncode({'approve': approve, 'reason': reason}),
    );
    _decode(res);
  }

  // ---------- Business accounts ----------

  static Future<Company> myCompany() async {
    final res = await http.get(Uri.parse('$_baseUrl/company/me'), headers: await _authHeaders());
    return Company.fromJson(_decode(res));
  }

  static Future<List<MidManUser>> listEmployees() async {
    final res = await http.get(Uri.parse('$_baseUrl/company/employees'), headers: await _authHeaders());
    final data = _decode(res) as List;
    return data.map((e) => MidManUser.fromJson(e)).toList();
  }

  static Future<void> createEmployee({
    required String fullName,
    required String dateOfBirth,
    required String email,
    required String phone,
    required String password,
    required String businessRole,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/company/employees'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'full_name': fullName,
        'date_of_birth': dateOfBirth,
        'email': email,
        'phone': phone,
        'password': password,
        'business_role': businessRole,
      }),
    );
    _decode(res);
  }

  static Future<void> updateEmployeeRole({required String userId, required String businessRole}) async {
    final res = await http.patch(
      Uri.parse('$_baseUrl/company/employees/$userId'),
      headers: await _authHeaders(),
      body: jsonEncode({'business_role': businessRole}),
    );
    _decode(res);
  }

  static Future<void> removeEmployee(String userId) async {
    final res = await http.delete(Uri.parse('$_baseUrl/company/employees/$userId'), headers: await _authHeaders());
    _decode(res);
  }

  static Future<List<CompanyDocumentOut>> companyDocuments() async {
    final res = await http.get(Uri.parse('$_baseUrl/company/documents'), headers: await _authHeaders());
    final data = _decode(res) as List;
    return data.map((e) => CompanyDocumentOut.fromJson(e)).toList();
  }

  static Future<void> uploadCompanyDocument({required List<int> bytes, required String filename, String? caption}) async {
    final token = await _token;
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/company/documents'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (caption != null) request.fields['caption'] = caption;
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _decode(res);
  }

  /// Staff review queue - Business accounts awaiting verification.
  static Future<List<CompanyKYCReview>> pendingCompanyReviews() async {
    final res = await http.get(Uri.parse('$_baseUrl/companies/pending'), headers: await _authHeaders());
    final data = _decode(res) as List;
    return data.map((e) => CompanyKYCReview.fromJson(e)).toList();
  }

  static Future<void> decideCompanyKyc({required String companyId, required bool approve, String? reason}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/companies/$companyId/decision'),
      headers: await _authHeaders(),
      body: jsonEncode({'approve': approve, 'reason': reason}),
    );
    _decode(res);
  }

  // ---------- Property inspection reminders ----------

  /// null if the customer has never set one up.
  static Future<InspectionReminder?> getInspectionReminder() async {
    final res = await http.get(Uri.parse('$_baseUrl/reminders/property-inspection'), headers: await _authHeaders());
    final data = _decode(res);
    return data == null ? null : InspectionReminder.fromJson(data);
  }

  static Future<InspectionReminder> setInspectionReminder({required String frequency, String? propertyLabel}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/reminders/property-inspection'),
      headers: await _authHeaders(),
      body: jsonEncode({'frequency': frequency, 'property_label': propertyLabel}),
    );
    return InspectionReminder.fromJson(_decode(res));
  }

  static Future<void> cancelInspectionReminder() async {
    final res = await http.delete(Uri.parse('$_baseUrl/reminders/property-inspection'), headers: await _authHeaders());
    _decode(res);
  }

  /// Admin only - the full user directory, optionally filtered by [role] or a
  /// name/email/member-id [search] substring. Deactivated accounts are
  /// excluded unless [includeInactive] is set.
  static Future<List<MidManUser>> listAdminUsers({
    String? role,
    String? search,
    bool includeInactive = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/admin/users').replace(queryParameters: {
      if (role != null) 'role': role,
      if (search != null && search.isNotEmpty) 'search': search,
      if (includeInactive) 'include_inactive': 'true',
    });
    final res = await http.get(uri, headers: await _authHeaders());
    final data = _decode(res) as List;
    return data.map((e) => MidManUser.fromJson(e)).toList();
  }

  static Future<MidManUser> changeUserRole({required String userId, required String role}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/admin/users/$userId/role'),
      headers: await _authHeaders(),
      body: jsonEncode({'role': role}),
    );
    return MidManUser.fromJson(_decode(res));
  }

  static Future<MidManUser> deactivateUser(String userId) async {
    final res = await http.post(Uri.parse('$_baseUrl/admin/users/$userId/deactivate'), headers: await _authHeaders());
    return MidManUser.fromJson(_decode(res));
  }

  static Future<MidManUser> reactivateUser(String userId) async {
    final res = await http.post(Uri.parse('$_baseUrl/admin/users/$userId/reactivate'), headers: await _authHeaders());
    return MidManUser.fromJson(_decode(res));
  }

  /// Admin only - the system-wide "who changed what, when" trail (registrations,
  /// role/subscription changes, KYC and approval decisions, ...), optionally
  /// filtered by [entityType] (e.g. 'user', 'service_request') or [action].
  static Future<List<AuditLogEntry>> listAuditLog({String? entityType, String? action, int limit = 100}) async {
    final uri = Uri.parse('$_baseUrl/admin/audit-log').replace(queryParameters: {
      if (entityType != null) 'entity_type': entityType,
      if (action != null) 'action': action,
      'limit': '$limit',
    });
    final res = await http.get(uri, headers: await _authHeaders());
    final data = _decode(res) as List;
    return data.map((e) => AuditLogEntry.fromJson(e)).toList();
  }

  static Future<List<Beneficiary>> listBeneficiaries() async {
    final res = await http.get(Uri.parse('$_baseUrl/beneficiaries'), headers: await _authHeaders());
    final data = _decode(res) as List;
    return data.map((e) => Beneficiary.fromJson(e)).toList();
  }

  static Future<Beneficiary> createBeneficiary({
    required String fullName,
    required String relationshipType,
    String? address,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/beneficiaries'),
      headers: await _authHeaders(),
      body: jsonEncode({'full_name': fullName, 'relationship_type': relationshipType, 'address': address}),
    );
    return Beneficiary.fromJson(_decode(res));
  }

  static Future<List<ServiceRequest>> myRequests() async {
    final res = await http.get(Uri.parse('$_baseUrl/service-requests/mine'), headers: await _authHeaders());
    final data = _decode(res) as List;
    return data.map((e) => ServiceRequest.fromJson(e)).toList();
  }

  /// Staff/admin/approver only - the full work queue, optionally filtered by status
  /// (a RequestStatus value like 'approval_required', 'in_progress', ...).
  static Future<List<ServiceRequest>> allRequests({String? status}) async {
    final uri = Uri.parse('$_baseUrl/service-requests').replace(
      queryParameters: status != null ? {'status': status} : null,
    );
    final res = await http.get(uri, headers: await _authHeaders());
    final data = _decode(res) as List;
    return data.map((e) => ServiceRequest.fromJson(e)).toList();
  }

  static Future<ServiceRequest> decideRequest({
    required String requestId,
    required bool approve,
    String? comment,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/service-requests/$requestId/${approve ? 'approve' : 'reject'}'),
      headers: await _authHeaders(),
      body: jsonEncode({'comment': comment}),
    );
    return ServiceRequest.fromJson(_decode(res));
  }

  static Future<ServiceRequest> updateRequestStatus({
    required String requestId,
    required String status,
    String? note,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/service-requests/$requestId/status'),
      headers: await _authHeaders(),
      body: jsonEncode({'status': status, 'note': note}),
    );
    return ServiceRequest.fromJson(_decode(res));
  }

  static Future<ServiceRequest> createServiceRequest({
    String? country,
    String? city,
    required String category,
    String? serviceType,
    required String title,
    String? description,
    String? beneficiaryId,
    num? amount,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/service-requests'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'country': country,
        'city': city,
        'category': category,
        'service_type': serviceType,
        'title': title,
        'description': description,
        'beneficiary_id': beneficiaryId,
        'amount': amount,
      }),
    );
    return ServiceRequest.fromJson(_decode(res));
  }

  static Future<ServiceRequest> getRequest(String id) async {
    final res = await http.get(Uri.parse('$_baseUrl/service-requests/$id'), headers: await _authHeaders());
    return ServiceRequest.fromJson(_decode(res));
  }

  /// Starts a payment attempt on an approved (payment_pending) request.
  /// [provider] is 'paynow' or 'flutterwave'. [method]/[phone] are for
  /// Paynow's EcoCash/OneMoney express checkout only - omit both for the
  /// web-redirect flow (Paynow's own hosted page, or Flutterwave's).
  static Future<Payment> initiatePayment({
    required String requestId,
    required String provider,
    String? method,
    String? phone,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/service-requests/$requestId/pay'),
      headers: await _authHeaders(),
      body: jsonEncode({'provider': provider, 'method': method, 'phone': phone}),
    );
    return Payment.fromJson(_decode(res));
  }

  /// The most recent payment attempt for a request, or null if none yet.
  static Future<Payment?> getLatestPayment(String requestId) async {
    final res = await http.get(Uri.parse('$_baseUrl/service-requests/$requestId/payment'), headers: await _authHeaders());
    final data = _decode(res);
    return data == null ? null : Payment.fromJson(data);
  }

  /// Actively re-checks the latest payment's status - useful right after the
  /// customer returns from the gateway's page, before a webhook has
  /// necessarily arrived yet.
  static Future<Payment> checkPayment(String requestId) async {
    final res = await http.post(Uri.parse('$_baseUrl/service-requests/$requestId/payment/check'), headers: await _authHeaders());
    return Payment.fromJson(_decode(res));
  }

  /// [fileType] is one of 'photo' | 'video' | 'document' | 'receipt' | 'quote' (matches
  /// the backend's EvidenceType). [supplierName] only applies to fileType 'quote'. Takes
  /// raw bytes (not a dart:io File) so it works on web, mobile, and desktop alike.
  static Future<void> uploadEvidence({
    required String requestId,
    required List<int> bytes,
    required String filename,
    required String fileType,
    String? caption,
    String? supplierName,
  }) async {
    final token = await _token;
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/service-requests/$requestId/evidence'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['file_type'] = fileType;
    if (caption != null) request.fields['caption'] = caption;
    if (supplierName != null) request.fields['supplier_name'] = supplierName;
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _decode(res);
  }

  /// Staff only. Returns null until someone has generated a comparison for this
  /// request (see [generateQuoteComparison]) - does not trigger generation itself.
  static Future<QuoteComparison?> getQuoteComparison(String requestId) async {
    final res = await http.get(Uri.parse('$_baseUrl/service-requests/$requestId/quote-comparison'), headers: await _authHeaders());
    final data = _decode(res);
    return data == null ? null : QuoteComparison.fromJson(data);
  }

  /// Staff only. (Re)generates the AI comparison across every quote-type evidence
  /// file attached to this request - the backend requires at least 2.
  static Future<QuoteComparison> generateQuoteComparison(String requestId) async {
    final res = await http.post(Uri.parse('$_baseUrl/service-requests/$requestId/quote-comparison'), headers: await _authHeaders());
    return QuoteComparison.fromJson(_decode(res));
  }
}
