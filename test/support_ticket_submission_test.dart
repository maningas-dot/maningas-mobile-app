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
  testWidgets(
    'submits the accepted payload and refreshes the inbox after success',
    (tester) async {
      final requests = <http.Request>[];
      var ticketListRequestCount = 0;
      final service = await _supportService((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          ticketListRequestCount++;
          return http.Response(
            jsonEncode({
              'success': true,
              'tickets': ticketListRequestCount == 1
                  ? <Object>[]
                  : [_ticketJson()],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'ticket': _ticketJson()}),
          201,
        );
      });

      await tester.pumpWidget(
        MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
      );
      await tester.pumpAndSettle();
      await _openAndFillTicket(tester, priority: 'Urgent');
      await tester.tap(find.byKey(const ValueKey('support-ticket-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Your support ticket was submitted.'), findsOneWidget);
      expect(find.text('New glasses question'), findsOneWidget);
      expect(ticketListRequestCount, 2);

      final creationRequest = requests.singleWhere(
        (request) => request.method == 'POST',
      );
      expect(creationRequest.url.path, '/api/patients/support/tickets');
      expect(creationRequest.headers['Authorization'], 'Bearer test-token');
      expect(jsonDecode(creationRequest.body), {
        'category': 'Eyewear / Frames',
        'subject': 'New glasses question',
        'description': 'I need help choosing frames.',
        'priority': 'Urgent',
      });
      expect(creationRequest.body, isNot(contains('patient_id')));
      expect(
        requests.where((request) => request.method == 'GET'),
        hasLength(2),
      );
    },
  );

  testWidgets('validates required fields before making a request', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final service = await _supportService((request) async {
      requests.add(request);
      return http.Response('{}', 200);
    });

    await tester.pumpWidget(
      MaterialApp(home: NewTicketScreen(supportCenterService: service)),
    );
    await tester.tap(find.byKey(const ValueKey('support-ticket-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a subject'), findsOneWidget);
    expect(find.text('Please choose a category'), findsOneWidget);
    expect(find.text('Please describe your issue'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('shows an authentication error without sending a request', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final service = await _supportService((request) async {
      requests.add(request);
      return http.Response('{}', 200);
    }, authenticate: false);

    await tester.pumpWidget(
      MaterialApp(home: NewTicketScreen(supportCenterService: service)),
    );
    await _fillTicketForm(tester);
    await tester.tap(find.byKey(const ValueKey('support-ticket-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Please sign in to your patient account before submitting a ticket.',
      ),
      findsOneWidget,
    );
    expect(requests, isEmpty);
    expect(find.text('New glasses question'), findsOneWidget);
  });

  testWidgets('prevents a second submit while the first request is pending', (
    tester,
  ) async {
    final responseCompleter = Completer<http.Response>();
    final requests = <http.Request>[];
    final service = await _supportService((request) async {
      requests.add(request);
      if (request.method == 'POST') return responseCompleter.future;
      return http.Response(jsonEncode({'success': true, 'tickets': []}), 200);
    });

    await tester.pumpWidget(
      MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
    );
    await tester.pumpAndSettle();
    await _openAndFillTicket(tester);

    final submitFinder = find.byKey(const ValueKey('support-ticket-submit'));
    await tester.tap(submitFinder);
    await tester.pump();

    expect(requests.where((request) => request.method == 'POST'), hasLength(1));
    expect(
      find.byKey(const ValueKey('support-ticket-submit-loading')),
      findsOneWidget,
    );
    expect(tester.widget<ElevatedButton>(submitFinder).onPressed, isNull);

    responseCompleter.complete(
      http.Response(
        jsonEncode({'success': true, 'ticket': _ticketJson()}),
        201,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your support ticket was submitted.'), findsOneWidget);
  });

  for (final failure in [
    (
      name: 'API rejection',
      response: http.Response(
        jsonEncode({'success': false, 'error': 'internal database detail'}),
        400,
      ),
      throwsNetworkError: false,
    ),
    (name: 'network failure', response: null, throwsNetworkError: true),
  ]) {
    testWidgets('${failure.name} retains the form and shows no success', (
      tester,
    ) async {
      final service = await _supportService((request) async {
        if (failure.throwsNetworkError) {
          throw http.ClientException('internal socket detail');
        }
        return failure.response!;
      });

      await tester.pumpWidget(
        MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
      );
      await tester.pumpAndSettle();
      await _openAndFillTicket(tester);
      await tester.tap(find.byKey(const ValueKey('support-ticket-submit')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('support-ticket-submit-error')),
        findsOneWidget,
      );
      expect(find.text('Your support ticket was submitted.'), findsNothing);
      expect(find.text('internal database detail'), findsNothing);
      expect(find.text('internal socket detail'), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'New glasses question',
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).last)
            .controller!
            .text,
        'I need help choosing frames.',
      );
      expect(find.text('Eyewear / Frames'), findsOneWidget);
    });
  }

  testWidgets('shows the confirmed ticket if inbox refresh fails', (
    tester,
  ) async {
    var ticketListRequestCount = 0;
    final service = await _supportService((request) async {
      if (request.method == 'POST') {
        return http.Response(
          jsonEncode({'success': true, 'ticket': _ticketJson()}),
          201,
        );
      }
      ticketListRequestCount++;
      if (ticketListRequestCount > 1) {
        throw http.ClientException('offline');
      }
      return http.Response(jsonEncode({'success': true, 'tickets': []}), 200);
    });

    await tester.pumpWidget(
      MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
    );
    await tester.pumpAndSettle();
    await _openAndFillTicket(tester);
    await tester.tap(find.byKey(const ValueKey('support-ticket-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Your support ticket was submitted.'), findsOneWidget);
    expect(find.text('New glasses question'), findsOneWidget);
    expect(find.text('Could not load tickets'), findsOneWidget);
  });
}

Future<void> _openAndFillTicket(
  WidgetTester tester, {
  String priority = 'Medium',
}) async {
  await tester.tap(find.text('New Ticket'));
  await tester.pumpAndSettle();

  await _fillTicketForm(tester, priority: priority);
}

Future<void> _fillTicketForm(
  WidgetTester tester, {
  String priority = 'Medium',
}) async {
  await tester.enterText(
    find.byType(TextFormField).first,
    'New glasses question',
  );
  await tester.tap(find.byType(DropdownButtonFormField<String>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Eyewear / Frames').last);
  await tester.pumpAndSettle();

  if (priority != 'Medium') {
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(priority).last);
    await tester.pumpAndSettle();
  }

  await tester.enterText(
    find.byType(TextFormField).last,
    'I need help choosing frames.',
  );
}

Future<SupportCenterService> _supportService(
  Future<http.Response> Function(http.Request) handler, {
  bool authenticate = true,
}) async {
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
  if (authenticate) {
    await session.login(
      email: 'patient@example.test',
      password: 'synthetic-password',
      rememberMe: false,
    );
  }

  return SupportCenterService(
    sessionService: session,
    client: MockClient(handler),
    baseUrl: 'https://api.example.test',
  );
}

Map<String, dynamic> _ticketJson() => {
  'ticket_id': 42,
  'patient_id': 'patient-7',
  'subject': 'New glasses question',
  'category': 'Eyewear / Frames',
  'priority': 'Urgent',
  'status': 'Open',
  'created_at': '2026-11-10T12:00:00Z',
};

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
