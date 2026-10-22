import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/services/patient_session_service.dart';

void main() {
  group('PatientSessionService login', () {
    test('sends Remember Me and securely stores the returned token', () async {
      final storage = _MemoryTokenStorage();
      Map<String, dynamic>? requestBody;
      final client = MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'token': 'synthetic-jwt',
            'patient_id': 'patient-1',
            'email': 'patient@example.test',
          }),
          200,
        );
      });
      final service = PatientSessionService(
        client: client,
        tokenStorage: storage,
        baseUrl: 'https://api.example.test',
      );

      final result = await service.login(
        email: ' Patient@Example.Test ',
        password: 'synthetic-password',
        rememberMe: true,
      );

      expect(requestBody, {
        'email': 'patient@example.test',
        'password': 'synthetic-password',
        'rememberMe': true,
      });
      expect(result.token, 'synthetic-jwt');
      expect(result.patient['patient_id'], 'patient-1');
      expect(service.token, 'synthetic-jwt');
      expect(storage.value, 'synthetic-jwt');
      client.close();
    });

    test('unchecked Remember Me keeps token only in memory', () async {
      final storage = _MemoryTokenStorage()..value = 'previous-jwt';
      Map<String, dynamic>? requestBody;
      final client = MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'token': 'memory-jwt', 'id': 2}),
          200,
        );
      });
      final service = PatientSessionService(
        client: client,
        tokenStorage: storage,
        baseUrl: 'https://api.example.test',
      );

      await service.login(
        email: 'patient@example.test',
        password: 'synthetic-password',
        rememberMe: false,
      );

      expect(requestBody?['rememberMe'], isFalse);
      expect(service.token, 'memory-jwt');
      expect(storage.value, isNull);
      client.close();
    });

    test('rejects a 2xx response without a token or patient ID', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'message': 'ok'}), 200),
      );
      final service = PatientSessionService(
        client: client,
        tokenStorage: _MemoryTokenStorage(),
        baseUrl: 'https://api.example.test',
      );

      await expectLater(
        service.login(
          email: 'patient@example.test',
          password: 'synthetic-password',
          rememberMe: false,
        ),
        throwsA(isA<PatientLoginException>()),
      );
      client.close();
    });

    test('preserves email verification response for the existing flow', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'EMAIL_VERIFICATION_REQUIRED',
            'email': 'patient@example.test',
          }),
          403,
        ),
      );
      final service = PatientSessionService(
        client: client,
        tokenStorage: _MemoryTokenStorage(),
        baseUrl: 'https://api.example.test',
      );

      await expectLater(
        service.login(
          email: 'patient@example.test',
          password: 'synthetic-password',
          rememberMe: false,
        ),
        throwsA(
          isA<PatientEmailVerificationRequired>().having(
            (error) => error.email,
            'email',
            'patient@example.test',
          ),
        ),
      );
      client.close();
    });
  });

  group('PatientSessionService restoration', () {
    test('validates saved JWT before returning patient profile', () async {
      final storage = _MemoryTokenStorage()..value = 'saved-jwt';
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/patients/auth/me');
        expect(request.headers['Authorization'], 'Bearer saved-jwt');
        return http.Response(
          jsonEncode({
            'patient': {
              'patient_id': 'patient-1',
              'email': 'patient@example.test',
            },
          }),
          200,
        );
      });
      final service = PatientSessionService(
        client: client,
        tokenStorage: storage,
        baseUrl: 'https://api.example.test',
      );

      final result = await service.restoreRememberedSession();

      expect(result.status, PatientSessionRestoreStatus.authenticated);
      expect(result.patient?['patient_id'], 'patient-1');
      expect(storage.value, 'saved-jwt');
      client.close();
    });

    test('clears saved credentials after unauthorized validation', () async {
      final storage = _MemoryTokenStorage()..value = 'expired-jwt';
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'error': 'Unauthorized'}), 401),
      );
      final service = PatientSessionService(
        client: client,
        tokenStorage: storage,
        baseUrl: 'https://api.example.test',
      );

      final result = await service.restoreRememberedSession();

      expect(result.status, PatientSessionRestoreStatus.invalidSession);
      expect(storage.value, isNull);
      expect(service.token, isNull);
      client.close();
    });

    test('clears saved credentials after unreadable 401 response', () async {
      final storage = _MemoryTokenStorage()..value = 'expired-jwt';
      final client = MockClient((_) async => http.Response('not-json', 401));
      final service = PatientSessionService(
        client: client,
        tokenStorage: storage,
        baseUrl: 'https://api.example.test',
      );

      final result = await service.restoreRememberedSession();

      expect(result.status, PatientSessionRestoreStatus.invalidSession);
      expect(storage.value, isNull);
      client.close();
    });

    test('preserves saved token and permits retry after network failure', () async {
      final storage = _MemoryTokenStorage()..value = 'saved-jwt';
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        if (requests == 1) {
          throw http.ClientException('offline');
        }
        return http.Response(
          jsonEncode({'patient_id': 'patient-1'}),
          200,
        );
      });
      final service = PatientSessionService(
        client: client,
        tokenStorage: storage,
        baseUrl: 'https://api.example.test',
      );

      final firstResult = await service.restoreRememberedSession();
      final retryResult = await service.restoreRememberedSession();

      expect(firstResult.status, PatientSessionRestoreStatus.retryableFailure);
      expect(storage.value, 'saved-jwt');
      expect(retryResult.status, PatientSessionRestoreStatus.authenticated);
      expect(requests, 2);
      client.close();
    });
  });
}

class _MemoryTokenStorage implements PatientTokenStorage {
  String? value;

  @override
  Future<void> deleteToken() async {
    value = null;
  }

  @override
  Future<String?> readToken() async => value;

  @override
  Future<void> writeToken(String token) async {
    value = token;
  }
}
