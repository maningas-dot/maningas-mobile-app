import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/main.dart';
import 'package:optcare_app/services/patient_session_service.dart';

void main() {
  testWidgets('restores only after saved JWT is validated', (tester) async {
    final storage = _MemoryTokenStorage()..value = 'saved-jwt';
    final service = PatientSessionService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/patients/auth/me');
        expect(request.headers['Authorization'], 'Bearer saved-jwt');
        return http.Response(
          jsonEncode({'patient_id': 'patient-1', 'email': 'patient@test'}),
          200,
        );
      }),
      tokenStorage: storage,
      baseUrl: 'https://api.example.test',
    );

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(home: SessionStartupScreen(sessionService: service)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Dashboard'), findsWidgets);
      expect(storage.value, 'saved-jwt');
    }, () => MockClient((_) async => http.Response('[]', 200)));
    service.close();
  });

  testWidgets('unauthorized saved JWT is cleared and login is shown', (
    tester,
  ) async {
    final storage = _MemoryTokenStorage()..value = 'expired-jwt';
    final service = PatientSessionService(
      client: MockClient(
        (_) async => http.Response('{"error":"Unauthorized"}', 401),
      ),
      tokenStorage: storage,
      baseUrl: 'https://api.example.test',
    );

    await tester.pumpWidget(
      MaterialApp(home: SessionStartupScreen(sessionService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.text('Sign In'), findsOneWidget);
    expect(storage.value, isNull);
    service.close();
  });

  testWidgets('network failure preserves token and Retry restores login', (
    tester,
  ) async {
    final storage = _MemoryTokenStorage()..value = 'saved-jwt';
    var validationRequests = 0;
    final service = PatientSessionService(
      client: MockClient((_) async {
        validationRequests++;
        if (validationRequests == 1) {
          throw http.ClientException('offline');
        }
        return http.Response(jsonEncode({'patient_id': 'patient-1'}), 200);
      }),
      tokenStorage: storage,
      baseUrl: 'https://api.example.test',
    );

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(home: SessionStartupScreen(sessionService: service)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Sign in instead'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(storage.value, 'saved-jwt');

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(validationRequests, 2);
      expect(storage.value, 'saved-jwt');
    }, () => MockClient((_) async => http.Response('[]', 200)));
    service.close();
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
