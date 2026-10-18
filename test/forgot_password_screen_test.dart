import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/forgot_password_screen.dart';
import 'package:optcare_app/main.dart';

void main() {
  group('ApiPasswordRecoveryService', () {
    test('requests an OTP using the patient endpoint and email field', () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return _jsonResponse(200, {
          'success': true,
          'message':
              'If an account exists for this email, a verification code has been sent.',
        });
      });
      final service = ApiPasswordRecoveryService(client: client);

      await service.requestOtp(email: 'synthetic@example.test');

      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.url.path,
        endsWith('/api/patients/forgot-password'),
      );
      expect(
        capturedRequest.headers['content-type'],
        contains('application/json'),
      );
      expect(jsonDecode(capturedRequest.body), {
        'email': 'synthetic@example.test',
      });
      client.close();
    });

    test(
      'resets password using exactly the patient API request fields',
      () async {
        late http.Request capturedRequest;
        final client = MockClient((request) async {
          capturedRequest = request;
          return _jsonResponse(200, {
            'success': true,
            'message': 'Password changed successfully.',
          });
        });
        final service = ApiPasswordRecoveryService(client: client);

        await service.resetPassword(
          email: 'synthetic@example.test',
          otp: '123456',
          newPassword: 'SyntheticPass1',
        );

        expect(capturedRequest.method, 'POST');
        expect(
          capturedRequest.url.path,
          endsWith('/api/patients/reset-password'),
        );
        expect(jsonDecode(capturedRequest.body), {
          'email': 'synthetic@example.test',
          'otp': '123456',
          'newPassword': 'SyntheticPass1',
        });
        client.close();
      },
    );

    test('does not accept a 200 response without success true', () async {
      final client = MockClient(
        (_) async => _jsonResponse(200, {
          'success': false,
          'message': 'Unable to reset password.',
        }),
      );
      final service = ApiPasswordRecoveryService(client: client);

      await expectLater(
        service.resetPassword(
          email: 'synthetic@example.test',
          otp: '123456',
          newPassword: 'SyntheticPass1',
        ),
        throwsA(isA<PasswordRecoveryException>()),
      );
      client.close();
    });

    test('does not accept a failed generic OTP response', () async {
      final client = MockClient(
        (_) async => _jsonResponse(200, {
          'success': false,
          'message': 'Unable to process password reset request.',
        }),
      );
      final service = ApiPasswordRecoveryService(client: client);

      await expectLater(
        service.requestOtp(email: 'synthetic@example.test'),
        throwsA(isA<PasswordRecoveryException>()),
      );
      client.close();
    });

    test('surfaces invalid and expired OTP response messages', () async {
      for (final message in [
        'Invalid verification code.',
        'The verification code has expired. Please request a new one.',
      ]) {
        final client = MockClient(
          (_) async =>
              _jsonResponse(400, {'success': false, 'message': message}),
        );
        final service = ApiPasswordRecoveryService(client: client);

        await expectLater(
          service.resetPassword(
            email: 'synthetic@example.test',
            otp: '123456',
            newPassword: 'SyntheticPass1',
          ),
          throwsA(
            isA<PasswordRecoveryException>().having(
              (error) => error.message,
              'message',
              message,
            ),
          ),
        );
        client.close();
      }
    });

    test('reports network, timeout, and server failures', () async {
      final networkClient = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      final networkService = ApiPasswordRecoveryService(client: networkClient);
      await expectLater(
        networkService.requestOtp(email: 'synthetic@example.test'),
        throwsA(
          isA<PasswordRecoveryException>().having(
            (error) => error.message,
            'message',
            contains('Network error'),
          ),
        ),
      );
      networkClient.close();

      final responseCompleter = Completer<http.Response>();
      final timeoutClient = MockClient((_) => responseCompleter.future);
      final timeoutService = ApiPasswordRecoveryService(
        client: timeoutClient,
        timeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        timeoutService.requestOtp(email: 'synthetic@example.test'),
        throwsA(
          isA<PasswordRecoveryException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      responseCompleter.complete(_jsonResponse(200, {'success': true}));
      timeoutClient.close();

      final serverClient = MockClient(
        (_) async => _jsonResponse(500, {
          'success': false,
          'message': 'Unable to reset password.',
        }),
      );
      final serverService = ApiPasswordRecoveryService(client: serverClient);
      await expectLater(
        serverService.resetPassword(
          email: 'synthetic@example.test',
          otp: '123456',
          newPassword: 'SyntheticPass1',
        ),
        throwsA(
          isA<PasswordRecoveryException>().having(
            (error) => error.message,
            'message',
            contains('server could not reset'),
          ),
        ),
      );
      serverClient.close();
    });
  });

  testWidgets('login Forgot Password link opens the recovery form', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.pumpAndSettle();

    final forgotPasswordLink = find.byKey(
      const ValueKey('forgot-password-link'),
    );
    await tester.ensureVisible(forgotPasswordLink);
    await tester.tap(forgotPasswordLink);
    await tester.pumpAndSettle();

    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.byKey(const ValueKey('forgot-password-email')), findsOneWidget);
  });

  testWidgets(
    'generic OTP request response advances without account disclosure',
    (tester) async {
      final service = _FakePasswordRecoveryService();
      await tester.pumpWidget(
        MaterialApp(home: ForgotPasswordScreen(service: service)),
      );
      await tester.enterText(
        find.byKey(const ValueKey('forgot-password-email')),
        'synthetic@example.test',
      );
      await tester.tap(find.byKey(const ValueKey('forgot-password-continue')));
      await tester.pump();
      await tester.pump();

      expect(service.requestedEmails, ['synthetic@example.test']);
      expect(
        find.byKey(const ValueKey('forgot-password-otp-0')),
        findsOneWidget,
      );
      expect(
        find.text('If an account exists for this email, a code has been sent.'),
        findsOneWidget,
      );
      expect(find.textContaining('email exists'), findsNothing);
    },
  );

  testWidgets('resend repeats the forgot-password request with same email', (
    tester,
  ) async {
    final service = _FakePasswordRecoveryService();
    await _enterOtpStep(tester, service);

    await tester.tap(find.byKey(const ValueKey('forgot-password-resend')));
    await tester.pump();
    await tester.pump();

    expect(service.requestedEmails, [
      'synthetic@example.test',
      'synthetic@example.test',
    ]);
  });

  testWidgets('reset submits OTP and password then shows confirmed success', (
    tester,
  ) async {
    final service = _FakePasswordRecoveryService();
    await _enterResetStep(tester, service);
    await tester.enterText(
      find.byKey(const ValueKey('forgot-password-new')),
      'SyntheticPass1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('forgot-password-confirm')),
      'SyntheticPass1',
    );
    await tester.tap(find.byKey(const ValueKey('forgot-password-reset')));
    await tester.pump();
    await tester.pump();

    expect(service.resetRequest, {
      'email': 'synthetic@example.test',
      'otp': '123456',
      'newPassword': 'SyntheticPass1',
    });
    expect(
      find.byKey(const ValueKey('forgot-password-success')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('forgot-password-back-to-login')),
      findsOneWidget,
    );
  });

  testWidgets(
    'invalid or expired OTP leaves reset unsuccessful and retryable',
    (tester) async {
      final service = _FakePasswordRecoveryService(
        resetError: const PasswordRecoveryException(
          'The verification code has expired. Please request a new one.',
        ),
      );
      await _enterResetStep(tester, service);
      await tester.enterText(
        find.byKey(const ValueKey('forgot-password-new')),
        'SyntheticPass1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('forgot-password-confirm')),
        'SyntheticPass1',
      );
      await tester.tap(find.byKey(const ValueKey('forgot-password-reset')));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('code has expired'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('forgot-password-success')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('forgot-password-reset')),
        findsOneWidget,
      );
    },
  );

  testWidgets('network request failure is shown without advancing', (
    tester,
  ) async {
    final service = _FakePasswordRecoveryService(
      requestError: const PasswordRecoveryException(
        'Network error. Check your connection and try again.',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: ForgotPasswordScreen(service: service)),
    );
    await tester.enterText(
      find.byKey(const ValueKey('forgot-password-email')),
      'synthetic@example.test',
    );
    await tester.tap(find.byKey(const ValueKey('forgot-password-continue')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Network error'), findsOneWidget);
    expect(find.byKey(const ValueKey('forgot-password-otp-0')), findsNothing);
  });

  testWidgets('password fields enforce website rules and match confirmation', (
    tester,
  ) async {
    final service = _FakePasswordRecoveryService();
    await _enterResetStep(tester, service);

    final newPassword = find.byKey(const ValueKey('forgot-password-new'));
    final confirmPassword = find.byKey(
      const ValueKey('forgot-password-confirm'),
    );
    final resetButton = find.byKey(const ValueKey('forgot-password-reset'));
    final invalidPasswords = <(String, String)>[
      ('Short1a', 'Password must be at least 8 characters.'),
      ('Aa1${'x' * 126}', 'Password must not exceed 128 characters.'),
      ('Aa1 abcde', 'Password must not contain spaces.'),
      ('ABCDEF12', 'Password must contain a lowercase letter.'),
      ('abcdef12', 'Password must contain an uppercase letter.'),
      ('Abcdefgh', 'Password must contain a number.'),
    ];

    for (final (password, error) in invalidPasswords) {
      await tester.enterText(newPassword, password);
      await tester.enterText(confirmPassword, password);
      await tester.ensureVisible(resetButton);
      await tester.tap(resetButton);
      await tester.pump();
      expect(find.text(error), findsOneWidget);
    }

    await tester.enterText(newPassword, 'SyntheticPass1');
    await tester.enterText(confirmPassword, 'DifferentPass1');
    await tester.ensureVisible(resetButton);
    await tester.tap(resetButton);
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(service.resetRequest, isNull);
  });

  testWidgets('password visibility toggles independently for each field', (
    tester,
  ) async {
    final service = _FakePasswordRecoveryService();
    await _enterResetStep(tester, service);

    final newPasswordField = find.descendant(
      of: find.byKey(const ValueKey('forgot-password-new')),
      matching: find.byType(TextField),
    );
    final confirmPasswordField = find.descendant(
      of: find.byKey(const ValueKey('forgot-password-confirm')),
      matching: find.byType(TextField),
    );
    final newPasswordVisibility = find.byKey(
      const ValueKey('forgot-password-new-visibility'),
    );
    final confirmPasswordVisibility = find.byKey(
      const ValueKey('forgot-password-confirm-visibility'),
    );

    expect(tester.widget<TextField>(newPasswordField).obscureText, isTrue);
    expect(tester.widget<TextField>(confirmPasswordField).obscureText, isTrue);

    await tester.tap(newPasswordVisibility);
    await tester.pump();
    expect(tester.widget<TextField>(newPasswordField).obscureText, isFalse);
    expect(tester.widget<TextField>(confirmPasswordField).obscureText, isTrue);

    await tester.tap(confirmPasswordVisibility);
    await tester.pump();
    expect(tester.widget<TextField>(newPasswordField).obscureText, isFalse);
    expect(tester.widget<TextField>(confirmPasswordField).obscureText, isFalse);
  });
}

http.Response _jsonResponse(int statusCode, Object body) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Future<void> _enterOtpStep(
  WidgetTester tester,
  _FakePasswordRecoveryService service,
) async {
  await tester.pumpWidget(
    MaterialApp(home: ForgotPasswordScreen(service: service)),
  );
  await tester.enterText(
    find.byKey(const ValueKey('forgot-password-email')),
    'synthetic@example.test',
  );
  await tester.tap(find.byKey(const ValueKey('forgot-password-continue')));
  await tester.pump();
  await tester.pump();
}

Future<void> _enterResetStep(
  WidgetTester tester,
  _FakePasswordRecoveryService service,
) async {
  await _enterOtpStep(tester, service);
  for (var index = 0; index < 6; index++) {
    await tester.enterText(
      find.byKey(ValueKey('forgot-password-otp-$index')),
      '123456'[index],
    );
  }
  await tester.tap(
    find.byKey(const ValueKey('forgot-password-continue-to-reset')),
  );
  await tester.pump();
}

class _FakePasswordRecoveryService implements PasswordRecoveryService {
  _FakePasswordRecoveryService({this.requestError, this.resetError});

  final PasswordRecoveryException? requestError;
  final PasswordRecoveryException? resetError;
  final requestedEmails = <String>[];
  Map<String, String>? resetRequest;

  @override
  Future<void> requestOtp({required String email}) async {
    requestedEmails.add(email);
    if (requestError != null) throw requestError!;
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    resetRequest = {'email': email, 'otp': otp, 'newPassword': newPassword};
    if (resetError != null) throw resetError!;
  }

  @override
  void close() {}
}
