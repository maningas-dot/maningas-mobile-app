import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/models/support_ticket.dart';
import 'package:optcare_app/services/patient_session_service.dart';
import 'package:optcare_app/services/support_center_service.dart';

void main() {
  group('Support models', () {
    test('parses and serializes ticket fields safely', () {
      final ticket = SupportTicket.fromJson({
        'ticket_id': 42,
        'patient_id': 'patient-7',
        'subject': 'Appointment question',
        'category': 'Appointment',
        'priority': 'Medium',
        'status': 'In Progress',
        'resolution': null,
        'created_at': '2026-10-28T01:00:00Z',
        'updated_at': '2026-10-28T01:02:00Z',
      });

      expect(ticket.ticketId, '42');
      expect(ticket.patientId, 'patient-7');
      expect(ticket.subject, 'Appointment question');
      expect(ticket.category, 'Appointment');
      expect(ticket.priority, 'Medium');
      expect(ticket.status, 'In Progress');
      expect(ticket.resolution, isNull);
      expect(ticket.createdAt, DateTime.parse('2026-10-28T01:00:00Z'));
      expect(ticket.updatedAt, DateTime.parse('2026-10-28T01:02:00Z'));
      expect(ticket.toJson()['ticket_id'], '42');
    });

    test('matches Website patient-cancelled status and resolution rules', () {
      final cancelledTickets = [
        {'ticket_id': 1, 'status': 'cancelled'},
        {'ticket_id': 2, 'resolution': ' cancelled '},
        {'ticket_id': 3, 'resolution_note': 'Cancelled by Patient'},
        {'ticket_id': 4, 'cancellation_reason': 'cancelled'},
        {'ticket_id': 5, 'close_reason': 'cancelled by patient'},
      ];

      for (final json in cancelledTickets) {
        expect(
          SupportTicket.fromJson(json).isPatientCancelled,
          isTrue,
          reason: json.toString(),
        );
      }

      for (final json in [
        {'ticket_id': 6, 'status': 'open'},
        {'ticket_id': 7, 'status': 'in_progress'},
        {'ticket_id': 8, 'status': 'pending'},
        {'ticket_id': 9, 'status': 'resolved', 'resolution': 'resolved'},
        {'ticket_id': 10, 'status': 'closed', 'close_reason': 'clinic closed'},
      ]) {
        expect(
          SupportTicket.fromJson(json).isPatientCancelled,
          isFalse,
          reason: json.toString(),
        );
      }
    });

    test('parses message identity, sender, read status, and timestamp', () {
      final message = SupportMessage.fromJson({
        'message_id': 91,
        'ticket_id': 42,
        'sender_id': null,
        'sender_patient_id': 'patient-7',
        'sender_name': 'Patient Name',
        'sender_role': 'patient',
        'sender_type': 'patient',
        'message': 'Please help.',
        'is_read': 1,
        'created_at': '2026-10-28T01:03:00Z',
      });

      expect(message.messageId, '91');
      expect(message.ticketId, '42');
      expect(message.senderId, isNull);
      expect(message.senderPatientId, 'patient-7');
      expect(message.senderName, 'Patient Name');
      expect(message.senderRole, 'patient');
      expect(message.senderType, 'patient');
      expect(message.message, 'Please help.');
      expect(message.isRead, isTrue);
      expect(message.createdAt, DateTime.parse('2026-10-28T01:03:00Z'));
    });

    test('parses and serializes nullable attachment metadata', () {
      final message = SupportMessage.fromJson({
        'message_id': 93,
        'ticket_id': 42,
        'message': 'See attached.',
        'attachment_url': 'https://cdn.example.test/support/photo.webp',
        'attachment_name': 'photo.webp',
        'attachment_mime_type': 'image/webp',
      });

      expect(
        message.attachmentUrl,
        'https://cdn.example.test/support/photo.webp',
      );
      expect(message.attachmentName, 'photo.webp');
      expect(message.attachmentMimeType, 'image/webp');
      expect(message.toJson()['attachment_url'], message.attachmentUrl);
      expect(message.toJson()['attachment_name'], 'photo.webp');
      expect(message.toJson()['attachment_mime_type'], 'image/webp');

      final textOnlyMessage = SupportMessage.fromJson({
        'message_id': 94,
        'ticket_id': 42,
      });
      expect(textOnlyMessage.attachmentUrl, isNull);
      expect(textOnlyMessage.attachmentName, isNull);
      expect(textOnlyMessage.attachmentMimeType, isNull);
    });

    test('preserves nullable message fields and parses read booleans', () {
      final message = SupportMessage.fromJson({
        'message_id': 92,
        'ticket_id': 42,
        'is_read': false,
        'created_at': 'not-a-date',
      });

      expect(message.messageId, '92');
      expect(message.senderName, isNull);
      expect(message.message, isNull);
      expect(message.isRead, isFalse);
      expect(message.createdAt, isNull);
    });

    test('rejects records without required identifiers', () {
      expect(
        () => SupportTicket.fromJson({'subject': 'Missing ID'}),
        throwsFormatException,
      );
      expect(
        () => SupportMessage.fromJson({'message_id': 1}),
        throwsFormatException,
      );
      expect(
        () => SupportMessage.fromJson({'ticket_id': 42}),
        throwsFormatException,
      );
    });
  });

  group('SupportCenterService', () {
    test('uses the patient API routes, payloads, and bearer token', () async {
      final requests = <http.Request>[];
      final session = await _authenticatedSession();
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.headers['Accept'], 'application/json');
        return switch ('${request.method} ${request.url.path}') {
          'GET /api/patients/support/my-tickets' => http.Response(
            jsonEncode({
              'success': true,
              'tickets': [_ticketJson()],
            }),
            200,
          ),
          'GET /api/patients/support/tickets/42/messages' => http.Response(
            jsonEncode({
              'success': true,
              'messages': [_messageJson()],
              'chatAvailable': true,
              'readOnly': false,
            }),
            200,
          ),
          'POST /api/patients/support/tickets' => http.Response(
            jsonEncode({'success': true, 'ticket': _ticketJson()}),
            201,
          ),
          'PUT /api/patients/support/tickets/42/cancel' => http.Response(
            '',
            204,
          ),
          'POST /api/patients/support/tickets/42/messages' => http.Response(
            jsonEncode({'success': true, 'chatMessage': _messageJson()}),
            201,
          ),
          'PUT /api/patients/support/tickets/42/messages/read' => http.Response(
            jsonEncode({'success': true, 'updatedCount': 3}),
            200,
          ),
          _ => http.Response('{}', 404),
        };
      });
      final service = _service(session, client);

      final tickets = await service.getMyTickets();
      expect(tickets, hasLength(1));
      expect(tickets.single.ticketId, '42');

      final conversation = await service.getMessages('42');
      expect(conversation.messages.single.messageId, '91');
      expect(conversation.chatAvailable, isTrue);
      expect(conversation.readOnly, isFalse);

      final created = await service.createTicket(
        category: 'General Inquiry',
        subject: 'New concern',
        description: 'Please help.',
        priority: 'Medium',
      );
      expect(created.ticketId, '42');
      expect(jsonDecode(requests[2].body), {
        'category': 'General Inquiry',
        'subject': 'New concern',
        'description': 'Please help.',
        'priority': 'Medium',
      });
      expect(requests[2].body, isNot(contains('patient_id')));

      await service.cancelTicket('42');

      final sent = await service.sendMessage(
        ticketId: '42',
        message: 'A reply',
      );
      expect(sent.messageId, '91');
      expect(jsonDecode(requests[4].body), {'message': 'A reply'});

      expect(await service.markMessagesRead('42'), 3);

      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        [
          'GET /api/patients/support/my-tickets',
          'GET /api/patients/support/tickets/42/messages',
          'POST /api/patients/support/tickets',
          'PUT /api/patients/support/tickets/42/cancel',
          'POST /api/patients/support/tickets/42/messages',
          'PUT /api/patients/support/tickets/42/messages/read',
        ],
      );
    });

    test('sends image-only and text-plus-image multipart messages', () async {
      final session = await _authenticatedSession();
      for (final scenario in [
        (message: '', expectedMessage: false),
        (message: 'Image details', expectedMessage: true),
      ]) {
        http.Request? sentRequest;
        final service = _service(
          session,
          MockClient((request) async {
            sentRequest = request;
            return http.Response(
              jsonEncode({
                'success': true,
                'chatMessage': {
                  ..._messageJson(),
                  'message': scenario.expectedMessage ? scenario.message : '',
                  'attachment_url':
                      'https://cdn.example.test/support/photo.png',
                  'attachment_name': 'photo.png',
                  'attachment_mime_type': 'image/png',
                },
              }),
              201,
            );
          }),
        );

        final sent = await service.sendMessage(
          ticketId: '42',
          message: scenario.message,
          attachmentBytes: Uint8List.fromList([1, 2, 3]),
          attachmentName: 'photo.png',
          attachmentMimeType: 'image/png',
        );

        expect(
          sent.attachmentUrl,
          'https://cdn.example.test/support/photo.png',
        );
        expect(sent.attachmentName, 'photo.png');
        expect(sent.attachmentMimeType, 'image/png');
        expect(sentRequest, isNotNull);
        expect(sentRequest!.method, 'POST');
        expect(
          sentRequest!.url.path,
          '/api/patients/support/tickets/42/messages',
        );
        final authorization = sentRequest!.headers.entries
            .singleWhere(
              (header) => header.key.toLowerCase() == 'authorization',
            )
            .value;
        expect(authorization, startsWith('Bearer '));
        expect(authorization, endsWith('test-token'));
        expect(sentRequest!.headers['Accept'], 'application/json');
        expect(
          sentRequest!.headers['Content-Type'],
          startsWith('multipart/form-data; boundary='),
        );
        expect(
          sentRequest!.headers['Content-Type'],
          isNot(contains('application/json')),
        );
        expect(
          sentRequest!.body,
          contains('name="attachment"; filename="photo.png"'),
        );
        expect(
          sentRequest!.body.toLowerCase(),
          contains('content-type: image/png'),
        );
        if (scenario.expectedMessage) {
          expect(sentRequest!.body, contains('name="message"'));
          expect(sentRequest!.body, contains('Image details'));
        } else {
          expect(sentRequest!.body, isNot(contains('name="message"')));
        }
      }
    });

    test('supports data collection fallbacks and encoded ticket IDs', () async {
      final session = await _authenticatedSession();
      final client = MockClient((request) async {
        expect(request.url.path, contains('case%2F9'));
        return http.Response(
          jsonEncode({
            'success': true,
            'data': [_messageJson(ticketId: 'case/9')],
          }),
          200,
        );
      });
      final service = _service(session, client);

      final result = await service.getMessages('case/9');

      expect(result.messages.single.ticketId, 'case/9');
    });

    test(
      'supports top-level ticket and message collection responses',
      () async {
        final session = await _authenticatedSession();
        var requestCount = 0;
        final service = _service(
          session,
          MockClient((_) async {
            requestCount++;
            return http.Response(
              jsonEncode(
                requestCount == 1 ? [_ticketJson()] : [_messageJson()],
              ),
              200,
            );
          }),
        );

        expect(await service.getMyTickets(), hasLength(1));
        expect((await service.getMessages('42')).messages, hasLength(1));
      },
    );

    test('rejects missing authentication without making a request', () async {
      final sessionClient = MockClient((_) async => http.Response('{}', 500));
      final session = PatientSessionService(
        client: sessionClient,
        tokenStorage: _MemoryTokenStorage(),
        baseUrl: 'https://api.example.test',
      );
      var requests = 0;
      final service = _service(
        session,
        MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        service.getMyTickets(),
        throwsA(
          isA<SupportServiceException>().having(
            (error) => error.kind,
            'kind',
            SupportServiceFailureKind.missingAuthentication,
          ),
        ),
      );
      expect(requests, 0);
    });

    test('exposes unauthorized, forbidden, and server failures', () async {
      for (final entry in {
        401: SupportServiceFailureKind.unauthorized,
        403: SupportServiceFailureKind.forbidden,
        503: SupportServiceFailureKind.server,
      }.entries) {
        final session = await _authenticatedSession();
        final service = _service(
          session,
          MockClient(
            (_) async => http.Response(
              jsonEncode({'success': false, 'error': 'Backend error'}),
              entry.key,
            ),
          ),
        );

        await expectLater(
          service.getMyTickets(),
          throwsA(
            isA<SupportServiceException>()
                .having((error) => error.kind, 'kind', entry.value)
                .having((error) => error.statusCode, 'statusCode', entry.key)
                .having((error) => error.message, 'message', 'Backend error'),
          ),
        );
      }
    });

    test('rejects unsuccessful and malformed response structures', () async {
      final session = await _authenticatedSession();
      final client = MockClient((_) async => http.Response('{}', 200));
      final service = _service(session, client);

      await expectLater(
        service.getMyTickets(),
        throwsA(
          isA<SupportServiceException>().having(
            (error) => error.kind,
            'kind',
            SupportServiceFailureKind.invalidResponse,
          ),
        ),
      );

      final unsuccessful = _service(
        session,
        MockClient(
          (_) async => http.Response(
            jsonEncode({'success': false, 'error': 'Request rejected'}),
            200,
          ),
        ),
      );
      await expectLater(
        unsuccessful.getMyTickets(),
        throwsA(
          isA<SupportServiceException>()
              .having((error) => error.message, 'message', 'Request rejected')
              .having(
                (error) => error.kind,
                'kind',
                SupportServiceFailureKind.requestRejected,
              ),
        ),
      );

      final malformedTicket = _service(
        session,
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': true,
              'tickets': [
                {'subject': 'Missing ID'},
              ],
            }),
            200,
          ),
        ),
      );
      await expectLater(
        malformedTicket.getMyTickets(),
        throwsA(
          isA<SupportServiceException>().having(
            (error) => error.kind,
            'kind',
            SupportServiceFailureKind.invalidResponse,
          ),
        ),
      );
    });

    test('reports network errors and timeouts', () async {
      final session = await _authenticatedSession();
      final offline = _service(
        session,
        MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        offline.getMyTickets(),
        throwsA(
          isA<SupportServiceException>().having(
            (error) => error.kind,
            'kind',
            SupportServiceFailureKind.network,
          ),
        ),
      );

      final slow = _service(
        session,
        MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return http.Response('{}', 200);
        }),
        timeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        slow.getMyTickets(),
        throwsA(
          isA<SupportServiceException>().having(
            (error) => error.kind,
            'kind',
            SupportServiceFailureKind.timeout,
          ),
        ),
      );
    });
  });
}

SupportCenterService _service(
  PatientSessionService session,
  http.Client client, {
  Duration timeout = const Duration(seconds: 15),
}) {
  return SupportCenterService(
    sessionService: session,
    client: client,
    baseUrl: 'https://api.example.test',
    timeout: timeout,
  );
}

Future<PatientSessionService> _authenticatedSession() async {
  final client = MockClient(
    (_) async => http.Response(
      jsonEncode({
        'token': 'test-token',
        'patient': {'patient_id': 'patient-7'},
      }),
      200,
    ),
  );
  final session = PatientSessionService(
    client: client,
    tokenStorage: _MemoryTokenStorage(),
    baseUrl: 'https://api.example.test',
  );
  await session.login(
    email: 'patient@example.test',
    password: 'synthetic-password',
    rememberMe: false,
  );
  return session;
}

Map<String, dynamic> _ticketJson() => {
  'ticket_id': 42,
  'patient_id': 'patient-7',
  'subject': 'Appointment question',
  'category': 'Appointment',
  'priority': 'Medium',
  'status': 'In Progress',
  'resolution': null,
  'created_at': '2026-10-28T01:00:00Z',
  'updated_at': '2026-10-28T01:02:00Z',
};

Map<String, dynamic> _messageJson({String ticketId = '42'}) => {
  'message_id': 91,
  'ticket_id': ticketId,
  'sender_id': null,
  'sender_patient_id': 'patient-7',
  'sender_name': 'Patient Name',
  'sender_role': 'patient',
  'sender_type': 'patient',
  'message': 'Please help.',
  'is_read': 1,
  'created_at': '2026-10-28T01:03:00Z',
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
