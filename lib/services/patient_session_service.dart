import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';

abstract interface class PatientTokenStorage {
  Future<String?> readToken();

  Future<void> writeToken(String token);

  Future<void> deleteToken();
}

class FlutterSecurePatientTokenStorage implements PatientTokenStorage {
  FlutterSecurePatientTokenStorage({
    this._storage = const FlutterSecureStorage(),
  });

  static const _tokenKey = 'patient_jwt';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}

enum PatientSessionRestoreStatus {
  noRememberedSession,
  authenticated,
  invalidSession,
  verificationRequired,
  retryableFailure,
}

class PatientSessionRestoreResult {
  const PatientSessionRestoreResult({
    required this.status,
    this.patient,
    this.email,
    this.message,
  });

  final PatientSessionRestoreStatus status;
  final Map<String, dynamic>? patient;
  final String? email;
  final String? message;
}

class PatientLoginResult {
  const PatientLoginResult({required this.patient, required this.token});

  final Map<String, dynamic> patient;
  final String token;
}

class PatientEmailVerificationRequired implements Exception {
  const PatientEmailVerificationRequired(this.email);

  final String email;
}

class PatientLoginException implements Exception {
  const PatientLoginException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PatientSessionService {
  PatientSessionService({
    http.Client? client,
    PatientTokenStorage? tokenStorage,
    String? baseUrl,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _tokenStorage = tokenStorage ?? FlutterSecurePatientTokenStorage(),
       _baseUrl = baseUrl ?? apiBaseUrl;

  final http.Client _client;
  final bool _ownsClient;
  final PatientTokenStorage _tokenStorage;
  final String _baseUrl;
  final Duration timeout;
  String? _token;

  String? get token => _token;

  Future<PatientLoginResult> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/patients/login'),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'email': normalizedEmail,
            'password': password,
            'rememberMe': rememberMe,
          }),
        )
        .timeout(timeout);
    final data = _decodeObject(response.body);
    final code = data?['code']?.toString();
    final patientData = _patientFromResponse(data);

    if (code == 'EMAIL_VERIFICATION_REQUIRED' ||
        data?['requires_email_verification'] == true ||
        data?['email_verified'] == false ||
        patientData?['email_verified'] == false) {
      throw PatientEmailVerificationRequired(
        (patientData?['email'] ?? data?['email'])
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? (patientData?['email'] ?? data?['email']).toString().trim()
            : normalizedEmail,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          data?['message']?.toString() ??
          data?['error']?.toString() ??
          'Login failed. Please check your details and try again.';
      throw PatientLoginException(message);
    }

    final responseData = data;
    final token = responseData?['token']?.toString().trim();
    final patient = patientData;
    if (token == null ||
        token.isEmpty ||
        patient == null ||
        _patientId(patient).isEmpty) {
      throw const PatientLoginException(
        'The server returned an incomplete login response. Please try again.',
      );
    }

    if (rememberMe) {
      await _tokenStorage.writeToken(token);
    } else {
      await _tokenStorage.deleteToken();
    }
    _token = token;
    return PatientLoginResult(patient: patient, token: token);
  }

  Future<PatientSessionRestoreResult> restoreRememberedSession() async {
    late final String? savedToken;
    try {
      savedToken = await _tokenStorage.readToken();
    } catch (_) {
      return const PatientSessionRestoreResult(
        status: PatientSessionRestoreStatus.retryableFailure,
        message: 'Unable to read your saved sign-in. Please retry.',
      );
    }
    if (savedToken == null || savedToken.trim().isEmpty) {
      return const PatientSessionRestoreResult(
        status: PatientSessionRestoreStatus.noRememberedSession,
      );
    }

    _token = savedToken;
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/api/patients/auth/me'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $savedToken',
            },
          )
          .timeout(timeout);
      if (response.statusCode == 401) {
        await clear();
        return const PatientSessionRestoreResult(
          status: PatientSessionRestoreStatus.invalidSession,
          message: 'Your saved sign-in has expired. Please sign in again.',
        );
      }

      Map<String, dynamic>? data;
      try {
        data = _decodeObject(response.body);
      } on FormatException {
        if (response.statusCode == 403) {
          await clear();
          return const PatientSessionRestoreResult(
            status: PatientSessionRestoreStatus.invalidSession,
            message: 'Your saved sign-in has expired. Please sign in again.',
          );
        }
        rethrow;
      }
      final patient = _patientFromResponse(data);
      final patientEmailVerified = patient?['email_verified'];

      if (data?['code']?.toString() == 'EMAIL_VERIFICATION_REQUIRED' ||
          data?['requires_email_verification'] == true ||
          data?['email_verified'] == false ||
          patientEmailVerified == false) {
        await clear();
        return PatientSessionRestoreResult(
          status: PatientSessionRestoreStatus.verificationRequired,
          email: (patient?['email'] ?? data?['email'])?.toString(),
        );
      }

      if (response.statusCode == 403) {
        await clear();
        return const PatientSessionRestoreResult(
          status: PatientSessionRestoreStatus.invalidSession,
          message: 'Your saved sign-in has expired. Please sign in again.',
        );
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const PatientSessionRestoreResult(
          status: PatientSessionRestoreStatus.retryableFailure,
          message: 'Unable to check your saved sign-in. Please try again.',
        );
      }

      if (patient == null || _patientId(patient).isEmpty) {
        return const PatientSessionRestoreResult(
          status: PatientSessionRestoreStatus.retryableFailure,
          message: 'The server returned an invalid account response.',
        );
      }

      return PatientSessionRestoreResult(
        status: PatientSessionRestoreStatus.authenticated,
        patient: patient,
      );
    } on TimeoutException {
      return const PatientSessionRestoreResult(
        status: PatientSessionRestoreStatus.retryableFailure,
        message: 'The request timed out. Check your connection and try again.',
      );
    } on http.ClientException {
      return const PatientSessionRestoreResult(
        status: PatientSessionRestoreStatus.retryableFailure,
        message: 'Unable to connect. Check your connection and try again.',
      );
    } on FormatException {
      return const PatientSessionRestoreResult(
        status: PatientSessionRestoreStatus.retryableFailure,
        message: 'The server returned an unreadable response. Please retry.',
      );
    } catch (_) {
      return const PatientSessionRestoreResult(
        status: PatientSessionRestoreStatus.retryableFailure,
        message: 'Unable to check your saved sign-in. Please try again.',
      );
    }
  }

  Future<void> clear() async {
    _token = null;
    await _tokenStorage.deleteToken();
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  static Map<String, dynamic>? _decodeObject(String body) {
    final decoded = jsonDecode(body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  static Map<String, dynamic>? _patientFromResponse(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final patient = data['patient'];
    if (patient is Map) return Map<String, dynamic>.from(patient);
    final nestedData = data['data'];
    if (nestedData is Map) return Map<String, dynamic>.from(nestedData);
    return data;
  }

  static String _patientId(Map<String, dynamic> patient) =>
      (patient['patient_id'] ?? patient['user_id'] ?? patient['id'])
          ?.toString()
          .trim() ??
      '';
}

final patientSessionService = PatientSessionService();
