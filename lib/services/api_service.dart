import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';

/// API service for CollBus backend integration.
///
/// Set [Constants.baseUrl] to your backend URL (e.g. https://api.yourapp.com or
/// http://10.0.2.2:3000 for Android emulator pointing to localhost).
///
/// Expected backend endpoints:
/// - POST /auth/login - { mobile/id, password?, role } -> { otpSent?, token? }
/// - POST /auth/verify-otp - { mobile, otp } -> { token }
/// - GET /student/:id/bus - -> { busNumber, routeName, driverName }
/// - POST /driver/:id/location - { lat, lng }
/// - GET /buses - -> [{ id, busNumber, route }]
/// - POST /buses - { busNumber, route } -> { id, busNumber, route }
/// - PUT /buses/:id - { busNumber, route }
/// - DELETE /buses/:id
/// - GET /drivers - -> [{ id, driverId, name }]
/// - POST /drivers - { driverId, name } -> { id, driverId, name }
/// - DELETE /drivers/:id
class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;

  late final String _baseUrl;

  ApiService._() {
    final url = Constants.baseUrl;
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  bool get _isMock => _baseUrl.isEmpty || _baseUrl.contains('your-backend');

  Future<Map<String, String>> _headers({String? token}) async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri _uri(String path, [Map<String, String>? queryParams]) {
    final uri = Uri.parse('$_baseUrl$path');
    return queryParams != null ? uri.replace(queryParameters: queryParams) : uri;
  }

  /// Throws [ApiException] on non-2xx responses.
  void _checkResponse(http.Response res, {String? context}) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    final msg = context ?? 'Request failed';
    try {
      final body = jsonDecode(res.body);
      throw ApiException(
        statusCode: res.statusCode,
        message: body['message'] ?? body['error'] ?? msg,
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(statusCode: res.statusCode, message: res.body);
    }
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// Login: sends OTP for student, returns token for driver/admin.
  Future<Map<String, dynamic>> login({
    required String idOrMobile,
    String? password,
    required String role,
  }) async {
    if (_isMock) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (role == 'Student') {
        return {'otpSent': true};
      }
      return {'token': 'mock-token-${role.toLowerCase()}'};
    }

    final res = await http.post(
      _uri('/auth/login'),
      headers: await _headers(),
      body: jsonEncode({
        'id': idOrMobile,
        if (password != null) 'password': password,
        'role': role.toLowerCase(),
      }),
    );
    _checkResponse(res, context: 'Login failed');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Verify OTP for student login.
  Future<Map<String, dynamic>> verifyOtp({required String mobile, required String otp}) async {
    if (_isMock) {
      await Future.delayed(const Duration(milliseconds: 500));
      return {'token': 'mock-student-token', 'studentId': 'S001'};
    }

    final res = await http.post(
      _uri('/auth/verify-otp'),
      headers: await _headers(),
      body: jsonEncode({'mobile': mobile, 'otp': otp}),
    );
    _checkResponse(res, context: 'Invalid OTP');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // Student
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> getStudentBusInfo(String studentId) async {
    if (_isMock) {
      await Future.delayed(const Duration(milliseconds: 500));
      return {
        'busNumber': 'KL-10-AB-1234',
        'routeName': 'Campus – City',
        'driverName': 'John Doe',
      };
    }

    final res = await http.get(_uri('/student/$studentId/bus'), headers: await _headers());
    _checkResponse(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return {
      'busNumber': data['busNumber']?.toString() ?? '',
      'routeName': data['routeName']?.toString() ?? '',
      'driverName': data['driverName']?.toString() ?? '',
    };
  }

  // ---------------------------------------------------------------------------
  // Driver
  // ---------------------------------------------------------------------------

  Future<void> updateDriverLocation(String driverId, double lat, double lng) async {
    if (_isMock) {
      return; // LocationStreamService handles mock updates
    }

    final res = await http.post(
      _uri('/driver/$driverId/location'),
      headers: await _headers(),
      body: jsonEncode({'lat': lat, 'lng': lng}),
    );
    _checkResponse(res);
  }

  // ---------------------------------------------------------------------------
  // Admin - Buses
  // ---------------------------------------------------------------------------

  Future<List<Map<String, String>>> getBuses() async {
    if (_isMock) {
      await Future.delayed(const Duration(milliseconds: 500));
      return [
        {'id': '1', 'busNumber': 'KL-10-AB-1234', 'route': 'Campus – City'},
        {'id': '2', 'busNumber': 'KL-20-CD-5678', 'route': 'Campus – Town'},
      ];
    }

    final res = await http.get(_uri('/buses'), headers: await _headers());
    _checkResponse(res);
    final list = jsonDecode(res.body) as List;
    return list
        .map((e) => {
              'id': (e as Map)['id']?.toString(),
              'busNumber': e['busNumber']?.toString() ?? '',
              'route': e['route']?.toString() ?? '',
            })
        .where((m) => m['id'] != null)
        .map((m) => Map<String, String>.from(m))
        .toList();
  }

  Future<Map<String, String>> addBus(String busNumber, String route) async {
    if (_isMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      return {'id': DateTime.now().millisecondsSinceEpoch.toString(), 'busNumber': busNumber, 'route': route};
    }

    final res = await http.post(
      _uri('/buses'),
      headers: await _headers(),
      body: jsonEncode({'busNumber': busNumber, 'route': route}),
    );
    _checkResponse(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return {
      'id': data['id']?.toString() ?? '',
      'busNumber': data['busNumber']?.toString() ?? busNumber,
      'route': data['route']?.toString() ?? route,
    };
  }

  Future<void> updateBus(String id, String busNumber, String route) async {
    if (_isMock) return;

    final res = await http.put(
      _uri('/buses/$id'),
      headers: await _headers(),
      body: jsonEncode({'busNumber': busNumber, 'route': route}),
    );
    _checkResponse(res);
  }

  Future<void> deleteBus(String id) async {
    if (_isMock) return;

    final res = await http.delete(_uri('/buses/$id'), headers: await _headers());
    _checkResponse(res);
  }

  // ---------------------------------------------------------------------------
  // Admin - Drivers
  // ---------------------------------------------------------------------------

  Future<List<Map<String, String>>> getDrivers() async {
    if (_isMock) {
      await Future.delayed(const Duration(milliseconds: 500));
      return [
        {'id': '1', 'driverId': 'D101', 'name': 'John Doe'},
        {'id': '2', 'driverId': 'D102', 'name': 'Jane Smith'},
      ];
    }

    final res = await http.get(_uri('/drivers'), headers: await _headers());
    _checkResponse(res);
    final list = jsonDecode(res.body) as List;
    return list
        .map((e) => {
              'id': (e as Map)['id']?.toString(),
              'driverId': e['driverId']?.toString() ?? '',
              'name': e['name']?.toString() ?? '',
            })
        .where((m) => m['id'] != null)
        .map((m) => Map<String, String>.from(m))
        .toList();
  }

  Future<Map<String, String>> addDriver(String driverId, String name) async {
    if (_isMock) {
      await Future.delayed(const Duration(milliseconds: 300));
      return {'id': DateTime.now().millisecondsSinceEpoch.toString(), 'driverId': driverId, 'name': name};
    }

    final res = await http.post(
      _uri('/drivers'),
      headers: await _headers(),
      body: jsonEncode({'driverId': driverId, 'name': name}),
    );
    _checkResponse(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return {
      'id': data['id']?.toString() ?? '',
      'driverId': data['driverId']?.toString() ?? driverId,
      'name': data['name']?.toString() ?? name,
    };
  }

  Future<void> updateDriver(String id, String driverId, String name) async {
    if (_isMock) return;

    final res = await http.put(
      _uri('/drivers/$id'),
      headers: await _headers(),
      body: jsonEncode({'driverId': driverId, 'name': name}),
    );
    _checkResponse(res);
  }

  Future<void> deleteDriver(String id) async {
    if (_isMock) return;

    final res = await http.delete(_uri('/drivers/$id'), headers: await _headers());
    _checkResponse(res);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}
