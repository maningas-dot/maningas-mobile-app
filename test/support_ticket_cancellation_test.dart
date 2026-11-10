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
  testWidgets('shows cancellation only for open tickets', (tester) async {
    final service = await _supportService((request) async {
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse([
          _ticketJson('11', 'open'),
          _ticketJson('12', 'in_progress'),
          _ticketJson('13', 'pending'),
          _ticketJson('14', 'resolved'),
          _ticketJson('15', 'closed'),
          _ticketJson('16', 'cancelled'),
          _ticketJson('17'),
          _ticketJson('18', 'awaiting_review'),
        ]);
      }
      return http.Response('{}', 200);
    });

    await _openInbox(tester, service);

    expect(
      find.byKey(const ValueKey('support-ticket-cancel-11')),
      findsOneWidget,
    );
    for (final ticketId in ['12', '13', '14', '15', '16', '17', '18']) {
      expect(
        find.byKey(ValueKey('support-ticket-cancel-$ticketId')),
        findsNothing,
        reason: 'Ticket $ticketId is not confirmed open',
      );
    }
  });

  testWidgets(
    'filters patient-cancelled tickets but preserves other ticket statuses',
    (tester) async {
      final service = await _supportService((request) async {
        if (request.url.path.endsWith('/my-tickets')) {
          return _ticketListResponse([
            _ticketJson('11', 'open'),
            _ticketJson('12', 'in_progress'),
            _ticketJson('13', 'pending'),
            _ticketJson('14', 'resolved', {'resolution': 'resolved by clinic'}),
            _ticketJson('15', 'closed', {'close_reason': 'closed by clinic'}),
            _ticketJson('16', 'cancelled'),
            _ticketJson('17', 'open', {
              'resolution_note': 'cancelled by patient',
            }),
            _ticketJson('18', 'open', {'cancellation_reason': 'Cancelled'}),
            _ticketJson('19', 'open', {'close_reason': 'CANCELLED BY PATIENT'}),
          ]);
        }
        return http.Response('{}', 200);
      });

      await _openInbox(tester, service);

      final inboxScrollable = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      for (final ticketId in ['11', '12', '13', '14', '15']) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('support-ticket-$ticketId')),
          300,
          scrollable: inboxScrollable,
        );
        expect(
          find.byKey(ValueKey('support-ticket-$ticketId')),
          findsOneWidget,
          reason: 'Ticket $ticketId is not patient-cancelled',
        );
      }
      await tester.scrollUntilVisible(
        find.text('Ticket history is loaded from your patient account.'),
        300,
        scrollable: inboxScrollable,
      );
      for (final ticketId in ['16', '17', '18', '19']) {
        expect(
          find.byKey(ValueKey('support-ticket-$ticketId')),
          findsNothing,
          reason: 'Ticket $ticketId matches Website patient-cancelled rules',
        );
      }
    },
  );

  testWidgets(
    'refreshes inbox status after returning from an updated conversation',
    (tester) async {
      for (final acceptedStatus in ['in_progress', 'pending']) {
        var ticketListRequestCount = 0;
        final service = await _supportService((request) async {
          if (request.method == 'GET' &&
              request.url.path.endsWith('/my-tickets')) {
            ticketListRequestCount++;
            return _ticketListResponse([
              _ticketJson(
                '11',
                ticketListRequestCount == 1 ? 'open' : acceptedStatus,
              ),
            ]);
          }
          if (request.method == 'GET' &&
              request.url.path.endsWith('/tickets/11/messages')) {
            return http.Response(
              jsonEncode({
                'success': true,
                'messages': [_messageJson()],
                'chatAvailable': true,
                'readOnly': false,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'success': true, 'updatedCount': 1}),
            200,
          );
        });

        await _openInbox(tester, service);
        expect(
          find.byKey(const ValueKey('support-ticket-cancel-11')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('support-ticket-11')));
        await tester.pumpAndSettle();
        expect(
          find.text('Ticket #11 · ${_statusLabel(acceptedStatus)}'),
          findsOneWidget,
        );
        expect(find.text('Existing clinic reply'), findsOneWidget);

        await tester.tap(find.byTooltip('Back to Support Service'));
        await tester.pumpAndSettle();

        expect(find.text(_statusLabel(acceptedStatus)), findsOneWidget);
        expect(
          find.byKey(const ValueKey('support-ticket-cancel-11')),
          findsNothing,
        );
        expect(ticketListRequestCount, 3);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('shows confirmation and dismissing it sends no API request', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final service = await _supportService((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse([_ticketJson('11', 'open')]);
      }
      return http.Response('{}', 200);
    });

    await _openInbox(tester, service);
    await tester.tap(find.byKey(const ValueKey('support-ticket-cancel-11')));
    await tester.pumpAndSettle();

    expect(find.text('Cancel Support Ticket?'), findsOneWidget);
    expect(
      find.textContaining('conversation will become read-only'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('support-ticket-cancel-dismiss')),
    );
    await tester.pumpAndSettle();

    expect(
      requests.where((request) => request.url.path.endsWith('/cancel')),
      isEmpty,
    );
    expect(
      requests.where((request) => request.url.path.endsWith('/my-tickets')),
      hasLength(1),
    );
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets(
    'confirmed cancellation removes the ticket from the visible inbox',
    (tester) async {
      final requests = <http.Request>[];
      var cancelled = false;
      final service = await _supportService((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/my-tickets')) {
          return _ticketListResponse([
            _ticketJson('11', cancelled ? 'cancelled' : 'open'),
            _ticketJson('12', 'open'),
          ]);
        }
        if (request.method == 'PUT' &&
            request.url.path.endsWith('/tickets/11/cancel')) {
          cancelled = true;
          return http.Response('', 204);
        }
        if (request.method == 'GET' &&
            request.url.path.endsWith('/tickets/12/messages')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'messages': [_messageJson('12')],
              'chatAvailable': true,
              'readOnly': false,
            }),
            200,
          );
        }
        if (request.method == 'PUT' &&
            request.url.path.endsWith('/messages/read')) {
          return http.Response(
            jsonEncode({'success': true, 'updatedCount': 1}),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      await _openInbox(tester, service);
      await tester.tap(find.byKey(const ValueKey('support-ticket-cancel-11')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('support-ticket-cancel-confirm')),
      );
      await tester.pumpAndSettle();

      final cancelRequest = requests.singleWhere(
        (request) => request.url.path.endsWith('/tickets/11/cancel'),
      );
      expect(cancelRequest.method, 'PUT');
      expect(cancelRequest.headers['Authorization'], 'Bearer test-token');
      expect(find.text('Support ticket cancelled.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('support-ticket-cancel-11')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('support-ticket-11')), findsNothing);
      expect(find.byKey(const ValueKey('support-ticket-12')), findsOneWidget);
      expect(
        requests.where(
          (request) =>
              request.method == 'GET' &&
              request.url.path.endsWith('/tickets/11/messages'),
        ),
        isEmpty,
      );

      await tester.tap(find.byKey(const ValueKey('support-ticket-12')));
      await tester.pumpAndSettle();
      expect(find.text('Existing clinic reply'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to Support Service'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('support-ticket-11')), findsNothing);
      expect(find.byKey(const ValueKey('support-ticket-12')), findsOneWidget);
    },
  );

  testWidgets('rechecks ticket eligibility before cancelling', (tester) async {
    final requests = <http.Request>[];
    var ticketListRequestCount = 0;
    final service = await _supportService((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/my-tickets')) {
        ticketListRequestCount++;
        return _ticketListResponse([
          _ticketJson(
            '11',
            ticketListRequestCount == 1 ? 'open' : 'in_progress',
          ),
        ]);
      }
      return http.Response('{}', 200);
    });

    await _openInbox(tester, service);
    await tester.tap(find.byKey(const ValueKey('support-ticket-cancel-11')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('support-ticket-cancel-confirm')),
    );
    await tester.pumpAndSettle();

    expect(
      requests.where((request) => request.url.path.endsWith('/cancel')),
      isEmpty,
    );
    expect(find.text('In Progress'), findsOneWidget);
    expect(
      find.text('This ticket is no longer eligible for cancellation.'),
      findsOneWidget,
    );
    expect(
      requests.where((request) => request.url.path.endsWith('/my-tickets')),
      hasLength(2),
    );
  });

  testWidgets('cancellation failure preserves the open ticket state', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final service = await _supportService((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse([_ticketJson('11', 'open')]);
      }
      if (request.url.path.endsWith('/tickets/11/cancel')) {
        return http.Response('{}', 500);
      }
      return http.Response('{}', 200);
    });

    await _openInbox(tester, service);
    await tester.tap(find.byKey(const ValueKey('support-ticket-cancel-11')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('support-ticket-cancel-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('support-ticket-cancel-11')),
      findsOneWidget,
    );
    expect(
      find.text(
        'The support ticket could not be cancelled right now. Please try again.',
      ),
      findsOneWidget,
    );
    expect(
      requests.where((request) => request.url.path.endsWith('/cancel')),
      hasLength(1),
    );
  });

  testWidgets('prevents duplicate cancellation requests', (tester) async {
    final cancellationResponse = Completer<http.Response>();
    var cancellationRequestCount = 0;
    final service = await _supportService((request) async {
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse([_ticketJson('11', 'open')]);
      }
      if (request.url.path.endsWith('/tickets/11/cancel')) {
        cancellationRequestCount++;
        return cancellationResponse.future;
      }
      return http.Response('{}', 200);
    });

    await _openInbox(tester, service);
    await tester.tap(find.byKey(const ValueKey('support-ticket-cancel-11')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('support-ticket-cancel-confirm')),
    );
    await tester.pump();

    expect(cancellationRequestCount, 1);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('support-ticket-cancel-11')),
          )
          .onPressed,
      isNull,
    );

    cancellationResponse.complete(http.Response('', 204));
    await tester.pumpAndSettle();
    expect(cancellationRequestCount, 1);
  });
}

Future<void> _openInbox(
  WidgetTester tester,
  SupportCenterService service,
) async {
  await tester.pumpWidget(
    MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
  );
  await tester.pumpAndSettle();
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

http.Response _ticketListResponse(List<Map<String, Object?>> tickets) =>
    http.Response(jsonEncode({'success': true, 'tickets': tickets}), 200);

Map<String, Object?> _ticketJson(
  String ticketId, [
  String? status,
  Map<String, Object?> extra = const {},
]) => {
  'ticket_id': ticketId,
  'patient_id': 'patient-7',
  'subject': 'Appointment assistance',
  'category': 'Appointment',
  'priority': 'Medium',
  ...?(status == null ? null : {'status': status}),
  ...extra,
  'created_at': '2026-11-10T10:00:00Z',
};

String _statusLabel(String status) => status
    .replaceAll('_', ' ')
    .split(' ')
    .map((word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
    .join(' ');

Map<String, Object?> _messageJson([String ticketId = '11']) => {
  'message_id': 'message-1',
  'ticket_id': ticketId,
  'sender_id': 'staff-1',
  'sender_patient_id': null,
  'sender_name': 'Clinic Administrator',
  'sender_role': 'staff',
  'sender_type': 'staff',
  'message': 'Existing clinic reply',
  'is_read': false,
  'created_at': '2026-11-10T10:01:00Z',
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
