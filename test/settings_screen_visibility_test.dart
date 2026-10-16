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
}
