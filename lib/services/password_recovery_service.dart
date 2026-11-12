import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants.dart';

abstract interface class PasswordRecoveryService {
  Future<void> requestOtp({required String email});

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  });

  void close();
}

class PasswordRecoveryException implements Exception {
  const PasswordRecoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiPasswordRecoveryService implements PasswordRecoveryService {
  ApiPasswordRecoveryService({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  Uri _endpoint(String path) => Uri.parse('$apiBaseUrl/api/patients/$path');

  Future<(http.Response, Map<String, dynamic>?)> _post(
    String path,
    Map<String, String> body,
  ) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint(path),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const PasswordRecoveryException(
        'The request timed out. Please try again.',
      );
    } on http.ClientException {
      throw const PasswordRecoveryException(
        'Network error. Check your connection and try again.',
      );
    }

    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      data = null;
    }
    return (response, data);
  }

  @override
  Future<void> requestOtp({required String email}) async {
    final (response, data) = await _post('forgot-password', {'email': email});
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        data?['success'] == true) {
      return;
    }
    if (response.statusCode >= 500) {
      throw const PasswordRecoveryException(
        'The server could not process the request. Please try again later.',
      );
    }
    throw const PasswordRecoveryException(
      'Could not request a password reset code. Please try again.',
    );
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final (response, data) = await _post('reset-password', {
      'email': email,
      'otp': otp,
      'newPassword': newPassword,
    });
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        data?['success'] == true) {
      return;
    }
    if (response.statusCode == 400) {
      final message = data?['message'];
      if (message is String && message.trim().isNotEmpty) {
        throw PasswordRecoveryException(message.trim());
      }
      throw const PasswordRecoveryException(
        'The code is invalid or has expired. Request a new code and try again.',
      );
    }
    if (response.statusCode >= 500) {
      throw const PasswordRecoveryException(
        'The server could not reset your password. Please try again later.',
      );
    }
    throw const PasswordRecoveryException(
      'Could not reset the password. Check your details and try again.',
    );
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
