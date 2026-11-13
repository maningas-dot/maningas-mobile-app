import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/main.dart';
import 'package:optcare_app/services/patient_session_service.dart';

void main() {
  group('Registration ZIP code handling', () {
    test('accepts four ASCII digits after trimming', () {
      expect(isValidRegistrationZipCode('8013'), isTrue);
      expect(isValidRegistrationZipCode(' 8013 '), isTrue);
    });

    test('rejects ZIP codes that are not exactly four ASCII digits', () {
      for (final zipCode in [
        '',
        '   ',
        '801',
        '80135',
        '80A3',
        '８０１３',
      ]) {
        expect(
          isValidRegistrationZipCode(zipCode),
          isFalse,
          reason: zipCode,
        );
      }
    });

    test('formats split address components into the existing API fields', () {
      final address = buildRegistrationAddress(
        houseUnit: ' Unit 12 ',
        street: ' Main Street ',
        zipCode: ' 8013 ',
        province: ' Davao Occidental ',
        city: ' Sample City ',
        barangay: ' Sample Barangay ',
      );

      expect(
        registrationAddressFields(address: address, zipCode: ' 8013 '),
        {
          'address':
              'Unit 12, Main Street, Zip Code: 8013, '
              'Province: Davao Occidental, City/Municipality: Sample City, '
              'Barangay: Sample Barangay',
          'address_zip_code': '8013',
        },
      );
    });
  });

  testWidgets(
    'registration separates optional house/unit and required street',
    (tester) async {
      final sessionService = PatientSessionService(
        client: MockClient((request) async => http.Response('{}', 500)),
        tokenStorage: _MemoryTokenStorage(),
        baseUrl: 'https://api.example.test',
      );

      await tester.pumpWidget(
        MaterialApp(home: AuthScreen(sessionService: sessionService)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create an account? Register'));
      await tester.tap(find.text('Create an account? Register'));
      await tester.pump();

      final houseUnitField = find.byKey(
        const ValueKey('registration-house-unit'),
      );
      final streetField = find.byKey(const ValueKey('registration-street'));
      expect(houseUnitField, findsOneWidget);
      expect(streetField, findsOneWidget);

      final houseUnitValidator = tester
          .widget<TextFormField>(houseUnitField)
          .validator;
      final streetValidator = tester
          .widget<TextFormField>(streetField)
          .validator!;
      expect(houseUnitValidator?.call(''), isNull);
      expect(streetValidator('  '), 'Enter street address');
      expect(streetValidator('Main Street'), isNull);

      sessionService.close();
    },
  );

  group('Gmail registration address validation', () {
    test('accepts lowercase, mixed-case, and surrounding whitespace', () {
      for (final email in [
        'patient@gmail.com',
        'Patient.Name@gmail.com',
        'patient123@gmail.com',
        '  Patient.Name@GMAIL.COM  ',
      ]) {
        expect(isValidGmailAddress(email), isTrue, reason: email);
      }

      expect(
        normalizeGmailAddress('  Patient.Name@GMAIL.COM  '),
        'patient.name@gmail.com',
      );
    });

    test('rejects other providers and Gmail lookalike domains', () {
      for (final email in [
        'patient@yahoo.com',
        'patient@outlook.com',
        'patient@hotmail.com',
        'patient@icloud.com',
        'patient@protonmail.com',
        'patient@mailinator.com',
        'patient@gmail.com.example',
        'patient@notgmail.com',
        'patient@gmail.co',
      ]) {
        expect(isValidGmailAddress(email), isFalse, reason: email);
      }
    });

    test('rejects malformed Gmail addresses', () {
      for (final email in [
        '',
        'patient',
        '@gmail.com',
        'patient@@gmail.com',
        'patient @gmail.com',
        'patient..name@gmail.com',
        '.patient@gmail.com',
        'patient.@gmail.com',
        'patient@gmail.com.',
      ]) {
        expect(isValidGmailAddress(email), isFalse, reason: email);
      }
    });
  });

  test('registration verification requires explicit verified status', () {
    expect(
      registrationEmailVerificationState({
        'email_verified': true,
        'requires_email_verification': false,
      }),
      RegistrationEmailVerificationState.verified,
    );
    expect(
      registrationEmailVerificationState({'requires_email_verification': true}),
      RegistrationEmailVerificationState.requiresOtp,
    );
    expect(
      registrationEmailVerificationState({'email_verified': false}),
      RegistrationEmailVerificationState.requiresOtp,
    );
    expect(
      registrationEmailVerificationState({
        'requires_email_verification': false,
      }),
      RegistrationEmailVerificationState.unknown,
    );
    expect(
      registrationEmailVerificationState(const {}),
      RegistrationEmailVerificationState.unknown,
    );
  });

  testWidgets('registration rejects non-Gmail without an API request', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{}', 500);
    });
    final sessionService = PatientSessionService(
      client: client,
      tokenStorage: _MemoryTokenStorage(),
      baseUrl: 'https://api.example.test',
    );

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(home: AuthScreen(sessionService: sessionService)),
      );
      await tester.pumpAndSettle();

      final registerMode = find.text('Create an account? Register');
      await tester.ensureVisible(registerMode);
      await tester.tap(registerMode);
      await tester.pump();

      await tester.ensureVisible(find.text('Terms and Conditions').last);
      await tester.tap(find.text('Terms and Conditions').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 500));

      final emailField = find.byType(TextFormField).at(3);
      await tester.ensureVisible(emailField);
      await tester.enterText(emailField, 'patient@yahoo.com');
      final submit = find.widgetWithText(ElevatedButton, 'Register');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.textContaining('Only @gmail.com addresses are accepted.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
    }, () => client);

    sessionService.close();
  });

  testWidgets('invalid ZIP prevents registration API request', (tester) async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response('{}', 500);
    });
    final sessionService = PatientSessionService(
      client: client,
      tokenStorage: _MemoryTokenStorage(),
      baseUrl: 'https://api.example.test',
    );

    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(home: AuthScreen(sessionService: sessionService)),
      );
      await tester.pumpAndSettle();

      final registerMode = find.text('Create an account? Register');
      await tester.ensureVisible(registerMode);
      await tester.tap(registerMode);
      await tester.pump();
      final termsLink = find.text('Terms and Conditions').last;
      await tester.ensureVisible(termsLink);
      await tester.tap(termsLink);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 500));

      final zipField = find.byKey(const ValueKey('registration-zip-code'));
      await tester.ensureVisible(zipField);
      await tester.enterText(zipField, '801');
      final zipValidator = tester.widget<TextFormField>(zipField).validator!;
      expect(zipValidator('801'), 'ZIP code must be exactly 4 digits.');

      final submit = find.widgetWithText(ElevatedButton, 'Register');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();

      expect(find.text('ZIP code must be exactly 4 digits.'), findsOneWidget);
      expect(requests, isEmpty);
    }, () => client);

    sessionService.close();
  });

  testWidgets('login does not default a missing email_verified to true', (
    tester,
  ) async {
    Map<String, dynamic>? authenticatedProfile;
    final sessionService = PatientSessionService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/patients/login');
        return http.Response(
          jsonEncode({
            'token': 'synthetic-token',
            'patient': {
              'patient_id': 'patient-1',
              'email': 'patient@gmail.com',
            },
          }),
          200,
        );
      }),
      tokenStorage: _MemoryTokenStorage(),
      baseUrl: 'https://api.example.test',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          sessionService: sessionService,
          onAuthenticated: (profile) => authenticatedProfile = profile,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'patient@gmail.com',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'synthetic-password',
    );
    await tester.ensureVisible(find.text('Sign In'));
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(authenticatedProfile?['email_verified'], isFalse);
    sessionService.close();
  });
}

class _MemoryTokenStorage implements PatientTokenStorage {
  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> writeToken(String token) async {}
}
