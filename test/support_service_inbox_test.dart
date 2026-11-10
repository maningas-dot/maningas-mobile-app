import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/services/patient_session_service.dart';
import 'package:optcare_app/services/support_center_service.dart';
import 'package:optcare_app/support_service_preview.dart';

void main() {
  testWidgets('loads authenticated patient tickets into the existing inbox', (
    tester,
  ) async {
    final responseCompleter = Completer<http.Response>();
    final requests = <http.Request>[];
    final service = await _supportService((request) async {
      requests.add(request);
      return responseCompleter.future;
    });

    await tester.pumpWidget(
      MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
    );

    expect(
      find.byKey(const ValueKey('support-tickets-loading')),
      findsOneWidget,
    );
    responseCompleter.complete(
      http.Response(
        jsonEncode({
          'success': true,
          'tickets': [
            {
              'ticket_id': 42,
              'patient_id': 'patient-7',
              'subject': 'Appointment question',
              'category': 'Appointment',
              'priority': 'Medium',
              'status': 'in_progress',
              'created_at': '2026-10-28T12:00:00Z',
            },
          ],
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Appointment question'), findsOneWidget);
    expect(find.text('Appointment'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.text('Fictional demo tickets'), findsNothing);
    expect(find.byKey(const ValueKey('support-tickets-loading')), findsNothing);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/patients/support/my-tickets');
    expect(requests.single.headers['Authorization'], 'Bearer test-token');
  });

  testWidgets('shows the existing empty-ticket state for an empty response', (
    tester,
  ) async {
    final service = await _supportService(
      (_) async => http.Response(
        jsonEncode({'success': true, 'tickets': <Object>[]}),
        200,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No tickets yet'), findsOneWidget);
    expect(find.text('Appointment question'), findsNothing);
  });

  testWidgets('shows a network error and retries ticket loading', (
    tester,
  ) async {
    var requestCount = 0;
    final service = await _supportService((_) async {
      requestCount++;
      if (requestCount == 1) {
        throw http.ClientException('offline');
      }
      return http.Response(
        jsonEncode({'success': true, 'tickets': <Object>[]}),
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load tickets'), findsOneWidget);
    expect(
      find.text('Unable to reach the clinic service. Check your connection.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('support-tickets-retry')));
    await tester.pumpAndSettle();

    expect(requestCount, 2);
    expect(find.text('No tickets yet'), findsOneWidget);
    expect(find.text('Could not load tickets'), findsNothing);
  });

  testWidgets('does not update state after the inbox is disposed', (
    tester,
  ) async {
    final responseCompleter = Completer<http.Response>();
    final service = await _supportService(
      (_) async => responseCompleter.future,
    );

    await tester.pumpWidget(
      MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    responseCompleter.complete(
      http.Response(jsonEncode({'success': true, 'tickets': <Object>[]}), 200),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

Future<SupportCenterService> _supportService(
  Future<http.Response> Function(http.Request) handler,
) async {
  final session = PatientSessionService(
    client: MockClient(
      (_) async => http.Response(
        jsonEncode({
          'token': 'test-token',
          'patient': {'patient_id': 'patient-7'},
        }),
        200,
      ),
    ),
    tokenStorage: _MemoryTokenStorage(),
    baseUrl: 'https://api.example.test',
  );
  await session.login(
    email: 'patient@example.test',
    password: 'synthetic-password',
    rememberMe: false,
  );

  return SupportCenterService(
    sessionService: session,
    client: MockClient(handler),
    baseUrl: 'https://api.example.test',
  );
}

class _MemoryTokenStorage implements PatientTokenStorage {
  String? _token;

  @override
  Future<void> deleteToken() async {
    _token = null;
  }

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async {
    _token = token;
  }
}
