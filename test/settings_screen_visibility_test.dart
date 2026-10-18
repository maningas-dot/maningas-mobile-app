import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optcare_app/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Change password fields toggle visibility', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(home: SettingsScreen(patientId: 'patient-123')),
    );

    await tester.pumpAndSettle();

    final currentField = tester.widget<TextField>(
      find.byKey(const ValueKey('currentPasswordField')),
    );
    expect(currentField.obscureText, isTrue);

    await tester.tap(find.byKey(const ValueKey('currentPasswordToggle')));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('currentPasswordField')))
          .obscureText,
      isFalse,
    );

    final newField = tester.widget<TextField>(
      find.byKey(const ValueKey('newPasswordField')),
    );
    expect(newField.obscureText, isTrue);

    await tester.tap(find.byKey(const ValueKey('newPasswordToggle')));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('newPasswordField')))
          .obscureText,
      isFalse,
    );

    final confirmField = tester.widget<TextField>(
      find.byKey(const ValueKey('confirmPasswordField')),
    );
    expect(confirmField.obscureText, isTrue);

    await tester.tap(find.byKey(const ValueKey('confirmPasswordToggle')));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('confirmPasswordField')))
          .obscureText,
      isFalse,
    );
  });

  testWidgets(
    'Change password shows unavailable backend message without OTP calls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        const MaterialApp(home: SettingsScreen(patientId: 'patient-123')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('currentPasswordField')),
        'oldpass',
      );
      await tester.enterText(
        find.byKey(const ValueKey('newPasswordField')),
        'newpass123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirmPasswordField')),
        'newpass123',
      );

      final listView = find.byType(ListView);
      await tester.drag(listView, const Offset(0, -400));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('continuePasswordButton')));
      await tester.pump();

      expect(
        find.text(
          'Change Password is temporarily unavailable because the backend does not currently support patient password-change OTP verification. Please contact support or wait for backend support.',
        ),
        findsOneWidget,
      );
    },
  );
}
