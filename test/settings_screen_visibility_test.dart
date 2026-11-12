import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/services/password_recovery_service.dart';
import 'package:optcare_app/services/patient_session_service.dart';
import 'package:optcare_app/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('password visibility controls work in both flow stages', (
    tester,
  ) async {
    final harness = await _pumpSettings(tester);

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('currentPasswordField')))
          .obscureText,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('currentPasswordToggle')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('currentPasswordField')))
          .obscureText,
      isFalse,
    );

    await _requestOtp(tester);
    for (final toggle in ['newPasswordToggle', 'confirmPasswordToggle']) {
      expect(
        tester
            .widget<TextField>(
              find.byKey(
                ValueKey(
                  toggle == 'newPasswordToggle'
                      ? 'newPasswordField'
                      : 'confirmPasswordField',
                ),
              ),
            )
            .obscureText,
        isTrue,
      );
      await tester.tap(find.byKey(ValueKey(toggle)));
      await tester.pump();
    }

    expect(harness.recovery.requestEmails, ['patient@example.test']);
  });

  testWidgets('missing password or email prevents API requests', (
    tester,
  ) async {
    final noPassword = await _pumpSettings(tester);
    await _tap(tester, 'continuePasswordButton');
    await tester.pump();
    expect(find.text('Enter your current password.'), findsOneWidget);
    expect(noPassword.loginRequests, 0);
    expect(noPassword.recovery.requestEmails, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final noEmail = await _pumpSettings(tester, email: null);
    await tester.enterText(
      find.byKey(const ValueKey('currentPasswordField')),
      'correct-current',
    );
    await _tap(tester, 'continuePasswordButton');
    await tester.pump();
    expect(
      find.textContaining('registered email is unavailable'),
      findsOneWidget,
    );
    expect(noEmail.loginRequests, 0);
    expect(noEmail.recovery.requestEmails, isEmpty);
  });

  testWidgets('incorrect current password does not request an OTP', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      loginStatus: 401,
      loginResponse: {'message': 'Current password is incorrect.'},
    );
    await tester.enterText(
      find.byKey(const ValueKey('currentPasswordField')),
      'incorrect-current',
    );
    await _tap(tester, 'continuePasswordButton');
    await _pumpAsync(tester);

    expect(find.text('Current password is incorrect.'), findsOneWidget);
    expect(harness.loginRequests, 1);
    expect(harness.recovery.requestEmails, isEmpty);
    expect(find.byKey(const ValueKey('passwordChangeOtpField')), findsNothing);
  });

  testWidgets(
    'successful verification requests OTP and starts resend cooldown',
    (tester) async {
      final harness = await _pumpSettings(tester);
      await tester.enterText(
        find.byKey(const ValueKey('currentPasswordField')),
        '  CurrentPass1  ',
      );
      await _tap(tester, 'continuePasswordButton');
      await _pumpAsync(tester);

      expect(harness.loginBody, {
        'email': 'patient@example.test',
        'password': '  CurrentPass1  ',
        'rememberMe': false,
      });
      expect(harness.recovery.requestEmails, ['patient@example.test']);
      expect(
        find.byKey(const ValueKey('passwordChangeOtpField')),
        findsOneWidget,
      );
      expect(find.text('Resend code in 60s'), findsOneWidget);
      expect(harness.recovery.resetRequests, isEmpty);
    },
  );

  testWidgets('OTP request failure leaves the current-password stage intact', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      recovery: _FakePasswordRecoveryService(
        requestError: const PasswordRecoveryException('OTP unavailable.'),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('currentPasswordField')),
      'current-pass',
    );
    await _tap(tester, 'continuePasswordButton');
    await tester.pumpAndSettle();

    expect(find.text('OTP unavailable.'), findsOneWidget);
    expect(find.byKey(const ValueKey('passwordChangeOtpField')), findsNothing);
    expect(harness.recovery.requestEmails, ['patient@example.test']);
  });

  testWidgets('resend is blocked for 60 seconds and enabled afterward', (
    tester,
  ) async {
    final harness = await _pumpSettings(tester);
    await _requestOtp(tester);
    final resend = find.byKey(const ValueKey('passwordChangeResend'));
    expect(tester.widget<TextButton>(resend).onPressed, isNull);

    await tester.pump(const Duration(seconds: 60));
    expect(tester.widget<TextButton>(resend).onPressed, isNotNull);
    await tester.tap(resend);
    await _pumpAsync(tester);
    expect(harness.recovery.requestEmails, [
      'patient@example.test',
      'patient@example.test',
    ]);
    expect(find.text('Resend code in 60s'), findsOneWidget);
  });

  testWidgets('invalid OTP and all password policy failures block reset', (
    tester,
  ) async {
    final harness = await _pumpSettings(tester);
    await _requestOtp(tester);
    final cases = <(String, String, String)>[
      ('12345', 'ValidPass1', 'ValidPass1'),
      ('12345x', 'ValidPass1', 'ValidPass1'),
      ('123456', 'short1A', 'short1A'),
      (
        '123456',
        '${String.fromCharCodes(List.filled(127, 97))}A1',
        '${String.fromCharCodes(List.filled(127, 97))}A1',
      ),
      ('123456', 'Valid Pass1', 'Valid Pass1'),
      ('123456', 'VALIDPASS1', 'VALIDPASS1'),
      ('123456', 'validpass1', 'validpass1'),
      ('123456', 'ValidPass', 'ValidPass'),
      ('123456', 'CurrentPass1', 'CurrentPass1'),
      ('123456', 'ValidPass1', 'DifferentPass1'),
    ];

    for (final (otp, password, confirmation) in cases) {
      await tester.enterText(
        find.byKey(const ValueKey('passwordChangeOtpField')),
        otp,
      );
      await tester.enterText(
        find.byKey(const ValueKey('newPasswordField')),
        password,
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirmPasswordField')),
        confirmation,
      );
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('continuePasswordButton')),
          )
          .onPressed!
          .call();
      await _pumpAsync(tester);
      expect(harness.recovery.resetRequests, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 500));
    }
  });

  testWidgets(
    'successful reset sends exact payload and clears sensitive input',
    (tester) async {
      final harness = await _pumpSettings(tester);
      await _requestOtp(tester);
      await _enterResetFields(tester);
      await _tap(tester, 'continuePasswordButton');
      await tester.pumpAndSettle();

      expect(harness.recovery.resetRequests, [
        {
          'email': 'patient@example.test',
          'otp': '123456',
          'newPassword': 'ValidPass2',
        },
      ]);
      expect(find.text('Password changed successfully.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('currentPasswordField')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('newPasswordField')), findsNothing);
      expect(
        find.byKey(const ValueKey('passwordChangeOtpField')),
        findsNothing,
      );
    },
  );

  testWidgets('accepts a 128-character password', (tester) async {
    final harness = await _pumpSettings(tester);
    await _requestOtp(tester);
    final password = '${String.fromCharCodes(List.filled(126, 97))}A1';
    await tester.enterText(
      find.byKey(const ValueKey('passwordChangeOtpField')),
      '123456',
    );
    await tester.enterText(
      find.byKey(const ValueKey('newPasswordField')),
      password,
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirmPasswordField')),
      password,
    );
    await _tap(tester, 'continuePasswordButton');
    await _pumpAsync(tester);

    expect(harness.recovery.resetRequests, hasLength(1));
    expect(harness.recovery.resetRequests.single['newPassword'], password);
  });

  testWidgets('reset API failures retain inputs and show the API error', (
    tester,
  ) async {
    final harness = await _pumpSettings(
      tester,
      recovery: _FakePasswordRecoveryService(
        resetError: const PasswordRecoveryException(
          'The code is invalid or has expired.',
        ),
      ),
    );
    await _requestOtp(tester);
    await _enterResetFields(tester);
    await _tap(tester, 'continuePasswordButton');
    await tester.pumpAndSettle();

    expect(find.text('The code is invalid or has expired.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('passwordChangeOtpField')),
      findsOneWidget,
    );
    expect(harness.recovery.resetRequests, hasLength(1));
  });

  testWidgets('duplicate Continue taps do not duplicate OTP requests', (
    tester,
  ) async {
    final completer = Completer<void>();
    final recovery = _FakePasswordRecoveryService(requestCompleter: completer);
    final harness = await _pumpSettings(tester, recovery: recovery);
    await tester.enterText(
      find.byKey(const ValueKey('currentPasswordField')),
      'current-pass',
    );
    await _tap(tester, 'continuePasswordButton');
    await tester.pump();
    await _tap(tester, 'continuePasswordButton');

    expect(harness.recovery.requestEmails, ['patient@example.test']);
    completer.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('passwordChangeOtpField')),
      findsOneWidget,
    );
  });

  testWidgets('duplicate reset taps do not submit twice', (tester) async {
    final completer = Completer<void>();
    final recovery = _FakePasswordRecoveryService(resetCompleter: completer);
    final harness = await _pumpSettings(tester, recovery: recovery);
    await _requestOtp(tester);
    await _enterResetFields(tester);
    await _tap(tester, 'continuePasswordButton');
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const ValueKey('continuePasswordButton')),
          )
          .onPressed,
      isNull,
    );

    expect(harness.recovery.resetRequests, hasLength(1));
    completer.complete();
    await _pumpAsync(tester);
    expect(find.text('Password changed successfully.'), findsOneWidget);
  });
}

Future<_SettingsHarness> _pumpSettings(
  WidgetTester tester, {
  String? email = ' Patient@Example.Test ',
  int loginStatus = 200,
  Map<String, dynamic> loginResponse = const {
    'token': 'verification-token',
    'patient_id': 'patient-123',
  },
  _FakePasswordRecoveryService? recovery,
}) async {
  SharedPreferences.setMockInitialValues({});
  final harness = _SettingsHarness(
    recovery: recovery ?? _FakePasswordRecoveryService(),
  );
  harness.session = PatientSessionService(
    client: MockClient((request) async {
      harness.loginRequests++;
      harness.loginBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(loginResponse), loginStatus);
    }),
    tokenStorage: harness.storage,
    baseUrl: 'https://api.example.test',
  );
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        patientId: 'patient-123',
        patientEmail: email,
        sessionService: harness.session,
        passwordRecoveryService: harness.recovery,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _requestOtp(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('currentPasswordField')),
    'CurrentPass1',
  );
  await _tap(tester, 'continuePasswordButton');
  await _pumpAsync(tester);
}

Future<void> _enterResetFields(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('passwordChangeOtpField')),
    '123456',
  );
  await tester.enterText(
    find.byKey(const ValueKey('newPasswordField')),
    'ValidPass2',
  );
  await tester.enterText(
    find.byKey(const ValueKey('confirmPasswordField')),
    'ValidPass2',
  );
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _pumpAsync(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

class _SettingsHarness {
  _SettingsHarness({required this.recovery});

  final _FakePasswordRecoveryService recovery;
  final _MemoryTokenStorage storage = _MemoryTokenStorage();
  late PatientSessionService session;
  int loginRequests = 0;
  Map<String, dynamic>? loginBody;
}

class _FakePasswordRecoveryService implements PasswordRecoveryService {
  _FakePasswordRecoveryService({
    this.requestError,
    this.resetError,
    this.requestCompleter,
    this.resetCompleter,
  });

  final PasswordRecoveryException? requestError;
  final PasswordRecoveryException? resetError;
  final Completer<void>? requestCompleter;
  final Completer<void>? resetCompleter;
  final requestEmails = <String>[];
  final resetRequests = <Map<String, String>>[];

  @override
  Future<void> requestOtp({required String email}) async {
    requestEmails.add(email);
    await requestCompleter?.future;
    if (requestError != null) throw requestError!;
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    resetRequests.add({'email': email, 'otp': otp, 'newPassword': newPassword});
    await resetCompleter?.future;
    if (resetError != null) throw resetError!;
  }

  @override
  void close() {}
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
