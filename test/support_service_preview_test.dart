import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optcare_app/support_service_preview.dart';

void main() {
  testWidgets('New Ticket action is blue, readable, and opens the form', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SupportServiceScreen()));

    final buttonFinder = find.ancestor(
      of: find.text('New Ticket'),
      matching: find.byType(ElevatedButton),
    );
    final button = tester.widget<ElevatedButton>(buttonFinder);

    expect(button.onPressed, isNotNull);
    expect(
      button.style?.backgroundColor?.resolve(const <WidgetState>{}),
      const Color(0xFF0F76FF),
    );
    expect(
      button.style?.foregroundColor?.resolve(const <WidgetState>{}),
      Colors.white,
    );

    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();

    expect(find.text('Tell us what you need help with.'), findsOneWidget);
  });
}
