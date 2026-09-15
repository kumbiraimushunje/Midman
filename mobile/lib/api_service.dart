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
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  static final _storage = const FlutterSecureStorage();

  /// Exposed so screens can build full URLs for evidence files (e.g. '$baseUrl${evidence.fileUrl}').
  static String get baseUrl => _baseUrl;

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
    throw ApiException(detail);
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

  static Future<ServiceRequest> createServiceRequest({
    required String category,
    required String title,
    String? description,
    String? beneficiaryId,
    num? amount,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/service-requests'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'category': category,
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

  /// [fileType] is one of 'photo' | 'document' | 'receipt' (matches the backend's EvidenceType).
  /// Takes raw bytes (not a dart:io File) so it works on web, mobile, and desktop alike.
  static Future<void> uploadEvidence({
    required String requestId,
    required List<int> bytes,
    required String filename,
    required String fileType,
    String? caption,
  }) async {
    final token = await _token;
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/service-requests/$requestId/evidence'),
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['file_type'] = fileType;
    if (caption != null) request.fields['caption'] = caption;
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _decode(res);
  }
}
