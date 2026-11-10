import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/services/patient_session_service.dart';
import 'package:optcare_app/services/support_center_service.dart';
import 'package:optcare_app/support_service_preview.dart';

void main() {
  testWidgets('New Ticket action is blue, readable, and opens the form', (
    tester,
  ) async {
    final service = SupportCenterService(
      sessionService: PatientSessionService(
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'success': true, 'tickets': <Object>[]}),
          200,
        ),
      ),
      baseUrl: 'https://api.example.test',
    );
    await tester.pumpWidget(
      MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
    );

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
