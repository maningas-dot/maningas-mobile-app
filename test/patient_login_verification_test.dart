import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/main.dart';
import 'package:optcare_app/services/patient_session_service.dart';

void main() {
  testWidgets('login keeps the existing email-verification prompt', (
    tester,
  ) async {
    final tokenStorage = _MemoryTokenStorage();
    Map<String, dynamic>? loginPayload;
    final sessionService = PatientSessionService(
      client: MockClient((request) async {
        if (request.url.path == '/api/patients/login') {
          loginPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'code': 'EMAIL_VERIFICATION_REQUIRED',
              'email': 'patient@example.test',
            }),
            403,
          );
        }
        return http.Response('[]', 200);
      }),
      tokenStorage: tokenStorage,
      baseUrl: 'https://api.example.test',
    );

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(home: AuthScreen(sessionService: sessionService)),
      );
      await tester.pumpAndSettle();

      final rememberMe = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('remember-me-checkbox')),
      );
      expect(rememberMe.value, isFalse);

      await tester.enterText(find.byType(TextFormField).at(0), 'Patient@test');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'not-a-real-password',
      );
      await tester.ensureVisible(find.text('Sign In'));
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(loginPayload?['rememberMe'], isFalse);
      expect(
        find.text(
          'This email still needs verification. Please complete registration verification first.',
        ),
        findsOneWidget,
      );
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(tokenStorage.value, isNull);
    }, () => MockClient((_) async => http.Response('[]', 200)));

    sessionService.close();
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
