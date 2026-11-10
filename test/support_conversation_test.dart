import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:optcare_app/services/patient_session_service.dart';
import 'package:optcare_app/services/support_center_service.dart';
import 'package:optcare_app/support_service_preview.dart';

void main() {
  testWidgets(
    'opens the selected ticket, orders real messages, and marks them read',
    (tester) async {
      final requests = <http.Request>[];
      final service = await _supportService((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path.endsWith('/my-tickets')) {
          return _ticketListResponse();
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'success': true,
              'messages': [
                _messageJson(
                  id: 2,
                  senderType: 'staff',
                  senderName: 'Clinic Staff',
                  text: 'Staff reply',
                  createdAt: '2026-11-10T10:02:00Z',
                  attachmentUrl: 'https://cdn.example.test/reply.png',
                  attachmentName: 'reply.png',
                  attachmentMimeType: 'image/png',
                ),
                _messageJson(
                  id: 1,
                  senderType: 'patient',
                  senderPatientId: 'patient-7',
                  text: 'Patient question',
                  createdAt: '2026-11-10T10:01:00Z',
                ),
              ],
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

      await _openConversation(tester, service);

      expect(find.text('Ticket #77 · In Progress'), findsOneWidget);
      expect(find.text('Patient question'), findsOneWidget);
      expect(find.text('Staff reply'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Clinic Staff'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('support-message-image-2')),
        findsOneWidget,
      );
      final expectedPatientTime = TimeOfDay.fromDateTime(
        DateTime.parse('2026-11-10T10:01:00Z').toLocal(),
      ).format(tester.element(find.text('Patient question')));
      expect(find.text(expectedPatientTime), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Patient question')).dy,
        lessThan(tester.getTopLeft(find.text('Staff reply')).dy),
      );
      expect(
        requests
            .where(
              (request) => request.url.path.endsWith('/tickets/77/messages'),
            )
            .map((request) => request.method),
        ['GET'],
      );

      final readRequest = requests.singleWhere(
        (request) =>
            request.method == 'PUT' &&
            request.url.path.endsWith('/tickets/77/messages/read'),
      );
      expect(readRequest.headers['Authorization'], 'Bearer test-token');
      expect(readRequest.body, isEmpty);
    },
  );

  testWidgets('shows an empty conversation and allows a permitted reply', (
    tester,
  ) async {
    final service = await _supportService((request) async {
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse();
      }
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'messages': <Object>[],
            'chatAvailable': true,
            'readOnly': false,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'updatedCount': 0}),
        200,
      );
    });

    await _openConversation(tester, service);

    expect(find.text('No messages yet.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('support-message-input')),
          )
          .enabled,
      isTrue,
    );
  });

  testWidgets('read-only and unavailable responses disable message sending', (
    tester,
  ) async {
    for (final scenario in [
      (
        name: 'read-only',
        chatAvailable: true,
        readOnly: true,
        notice: 'This conversation is read-only.',
      ),
      (
        name: 'unavailable',
        chatAvailable: false,
        readOnly: false,
        notice: 'Messaging is currently unavailable.',
      ),
    ]) {
      final service = await _supportService((request) async {
        if (request.url.path.endsWith('/my-tickets')) {
          return _ticketListResponse();
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'success': true,
              'messages': <Object>[],
              'chatAvailable': scenario.chatAvailable,
              'readOnly': scenario.readOnly,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'updatedCount': 0}),
          200,
        );
      });

      await _openConversation(tester, service);

      expect(find.text(scenario.notice), findsOneWidget, reason: scenario.name);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('support-message-input')),
            )
            .enabled,
        isFalse,
        reason: scenario.name,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('support-message-send')),
            )
            .onPressed,
        isNull,
        reason: scenario.name,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'keeps an open ticket disabled until its refreshed accepted status arrives',
    (tester) async {
      final refreshedTickets = Completer<http.Response>();
      var ticketListRequestCount = 0;
      final service = await _supportService((request) async {
        if (request.url.path.endsWith('/my-tickets')) {
          ticketListRequestCount++;
          if (ticketListRequestCount == 1) {
            return _ticketListResponse(status: 'open');
          }
          return refreshedTickets.future;
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'success': true,
              'messages': [
                _messageJson(text: 'Your support ticket has been accepted.'),
              ],
              'chatAvailable': true,
              'readOnly': false,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'updatedCount': 0}),
          200,
        );
      });

      await tester.pumpWidget(
        MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('support-ticket-77')));
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('support-message-input'));
      final sendFinder = find.byKey(const ValueKey('support-message-send'));
      expect(
        find.text('Your support ticket has been accepted.'),
        findsOneWidget,
      );
      expect(find.text('Checking the latest ticket status.'), findsOneWidget);
      expect(tester.widget<TextField>(inputFinder).enabled, isFalse);
      expect(tester.widget<IconButton>(sendFinder).onPressed, isNull);

      refreshedTickets.complete(_ticketListResponse(status: 'in_progress'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(inputFinder).enabled, isTrue);
      expect(tester.widget<IconButton>(sendFinder).onPressed, isNotNull);
    },
  );

  testWidgets('enables replies for refreshed in-progress and pending tickets', (
    tester,
  ) async {
    for (final status in ['in_progress', 'pending']) {
      var ticketListRequestCount = 0;
      final service = await _supportService((request) async {
        if (request.url.path.endsWith('/my-tickets')) {
          ticketListRequestCount++;
          return _ticketListResponse(
            status: ticketListRequestCount == 1 ? 'open' : status,
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'success': true,
              'messages': <Object>[],
              'chatAvailable': true,
              'readOnly': false,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'updatedCount': 0}),
          200,
        );
      });

      await _openConversation(tester, service);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('support-message-input')),
            )
            .enabled,
        isTrue,
        reason: status,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('support-message-send')),
            )
            .onPressed,
        isNotNull,
        reason: status,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('failed ticket status refresh keeps sending disabled', (
    tester,
  ) async {
    var ticketListRequestCount = 0;
    final service = await _supportService((request) async {
      if (request.url.path.endsWith('/my-tickets')) {
        ticketListRequestCount++;
        if (ticketListRequestCount == 1) {
          return _ticketListResponse(status: 'in_progress');
        }
        return http.Response('{}', 500);
      }
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'messages': <Object>[],
            'chatAvailable': true,
            'readOnly': false,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'updatedCount': 0}),
        200,
      );
    });

    await _openConversation(tester, service);

    expect(
      find.text('Could not refresh the ticket status. Messaging is disabled.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('support-message-input')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('support-message-send')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('terminal ticket statuses remain read-only after refresh', (
    tester,
  ) async {
    for (final status in ['closed', 'resolved', 'cancelled']) {
      var ticketListRequestCount = 0;
      final service = await _supportService((request) async {
        if (request.url.path.endsWith('/my-tickets')) {
          ticketListRequestCount++;
          return _ticketListResponse(
            status: ticketListRequestCount == 1 ? 'open' : status,
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'success': true,
              'messages': <Object>[],
              'chatAvailable': true,
              'readOnly': false,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'updatedCount': 0}),
          200,
        );
      });

      await _openConversation(tester, service);
      expect(find.text('This conversation is read-only.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('support-message-input')),
            )
            .enabled,
        isFalse,
        reason: status,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('support-message-send')),
            )
            .onPressed,
        isNull,
        reason: status,
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('enforces the Website message length limit', (tester) async {
    final service = await _supportService((request) async {
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse();
      }
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'messages': <Object>[],
            'chatAvailable': true,
            'readOnly': false,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'updatedCount': 0}),
        200,
      );
    });

    await _openConversation(tester, service);

    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('support-message-input')),
    );
    expect(input.maxLength, 2000);
    await tester.enterText(
      find.byKey(const ValueKey('support-message-input')),
      'm' * 2001,
    );
    await tester.pump();
    expect(input.controller!.text.length, 2000);
  });

  testWidgets('selects, previews, removes, and reselects an image', (
    tester,
  ) async {
    var pickerCalls = 0;
    await _openConversation(
      tester,
      await _supportService(_conversationHandler()),
      imagePicker: () async {
        pickerCalls++;
        return _validPng();
      },
    );

    final attachFinder = find.byKey(const ValueKey('support-message-attach'));
    await tester.tap(attachFinder);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('support-image-preview')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('support-image-remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('support-image-preview')), findsNothing);

    await tester.tap(attachFinder);
    await tester.pumpAndSettle();
    expect(pickerCalls, 2);
    expect(find.byKey(const ValueKey('support-image-preview')), findsOneWidget);
  });

  testWidgets('rejects unsupported image formats', (tester) async {
    await _openConversation(
      tester,
      await _supportService(_conversationHandler()),
      imagePicker: () async => XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'animation.gif',
        mimeType: 'image/gif',
      ),
    );

    await tester.tap(find.byKey(const ValueKey('support-message-attach')));
    await tester.pumpAndSettle();

    expect(find.text('Choose a JPEG, PNG, or WebP image.'), findsOneWidget);
    expect(find.byKey(const ValueKey('support-image-preview')), findsNothing);
  });

  testWidgets('rejects images larger than 10 MiB', (tester) async {
    await _openConversation(
      tester,
      await _supportService(_conversationHandler()),
      imagePicker: () async => XFile.fromData(
        Uint8List(_maxTestImageBytes + 1),
        name: 'large.jpg',
        mimeType: 'image/jpeg',
      ),
    );

    await tester.tap(find.byKey(const ValueKey('support-message-attach')));
    await tester.pumpAndSettle();

    expect(find.text('Images must be 10 MiB or smaller.'), findsOneWidget);
    expect(find.byKey(const ValueKey('support-image-preview')), findsNothing);
  });

  testWidgets('sends confirmed messages with the selected ticket and JWT', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final service = await _supportService((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse();
      }
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'messages': <Object>[],
            'chatAvailable': true,
            'readOnly': false,
          }),
          200,
        );
      }
      if (request.method == 'POST') {
        return http.Response(
          jsonEncode({
            'success': true,
            'chatMessage': _messageJson(
              id: 9,
              senderType: 'patient',
              senderPatientId: 'patient-7',
              text: 'A real reply',
              createdAt: '2026-11-10T10:03:00Z',
            ),
          }),
          201,
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'updatedCount': 0}),
        200,
      );
    });

    await _openConversation(tester, service);
    final inputFinder = find.byKey(const ValueKey('support-message-input'));
    await tester.enterText(inputFinder, '  A real reply  ');
    await tester.tap(find.byKey(const ValueKey('support-message-send')));
    await tester.pumpAndSettle();

    final sendRequest = requests.singleWhere(
      (request) => request.method == 'POST',
    );
    expect(sendRequest.url.path, '/api/patients/support/tickets/77/messages');
    final authorization = sendRequest.headers.entries
        .singleWhere((header) => header.key.toLowerCase() == 'authorization')
        .value;
    expect(authorization, startsWith('Bearer '));
    expect(authorization, endsWith('test-token'));
    expect(jsonDecode(sendRequest.body), {'message': 'A real reply'});
    expect(sendRequest.body, isNot(contains('patient_id')));
    expect(find.text('A real reply'), findsOneWidget);
    expect(tester.widget<TextField>(inputFinder).controller!.text, isEmpty);
    expect(
      requests.where(
        (request) =>
            request.method == 'PUT' &&
            request.url.path.endsWith('/tickets/77/messages/read'),
      ),
      hasLength(1),
    );
  });

  testWidgets('sends image-only messages and renders the returned image', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final service = await _supportService((request) async {
      if (request.method == 'POST') {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'success': true,
            'chatMessage': _messageJson(
              id: 21,
              senderType: 'patient',
              senderPatientId: 'patient-7',
              text: '',
              attachmentUrl: 'https://cdn.example.test/photo.png',
              attachmentName: 'photo.png',
              attachmentMimeType: 'image/png',
            ),
          }),
          201,
        );
      }
      return _conversationHandler()(request);
    });

    await _openConversation(
      tester,
      service,
      imagePicker: () async => _validPng(),
    );
    await tester.tap(find.byKey(const ValueKey('support-message-attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-message-send')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('support-message-send-error')),
      findsNothing,
    );
    expect(requests, hasLength(1));
    final authorization = requests.single.headers.entries
        .singleWhere((header) => header.key.toLowerCase() == 'authorization')
        .value;
    expect(authorization, startsWith('Bearer '));
    expect(authorization, endsWith('test-token'));
    expect(
      requests.single.headers['Content-Type'],
      startsWith('multipart/form-data; boundary='),
    );
    expect(
      _multipartRequestBody(requests.single),
      contains('name="attachment"; filename="support_image.png"'),
    );
    expect(
      _multipartRequestBody(requests.single),
      isNot(contains('name="message"')),
    );
    expect(find.byKey(const ValueKey('support-image-preview')), findsNothing);
    expect(
      find.byKey(const ValueKey('support-message-image-21')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('retains text and image after a failed upload for retry', (
    tester,
  ) async {
    final requests = <http.Request>[];
    var postCount = 0;
    final service = await _supportService((request) async {
      if (request.method == 'POST') {
        requests.add(request);
        postCount++;
        if (postCount == 1) {
          return http.Response(
            jsonEncode({'success': false, 'error': 'Upload failed'}),
            400,
          );
        }
        return http.Response(
          jsonEncode({
            'success': true,
            'chatMessage': _messageJson(
              id: 22,
              senderType: 'patient',
              senderPatientId: 'patient-7',
              text: 'Image details',
              attachmentUrl: 'https://cdn.example.test/photo.png',
              attachmentName: 'photo.png',
              attachmentMimeType: 'image/png',
            ),
          }),
          201,
        );
      }
      return _conversationHandler()(request);
    });

    await _openConversation(
      tester,
      service,
      imagePicker: () async => _validPng(),
    );
    final inputFinder = find.byKey(const ValueKey('support-message-input'));
    await tester.enterText(inputFinder, 'Image details');
    await tester.tap(find.byKey(const ValueKey('support-message-attach')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('support-message-send')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('support-message-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('support-image-preview')), findsOneWidget);
    expect(
      tester.widget<TextField>(inputFinder).controller!.text,
      'Image details',
    );
    expect(
      find.byKey(const ValueKey('support-message-send-error')),
      findsOneWidget,
    );
    final multipartBody = _multipartRequestBody(requests.first);
    expect(multipartBody, contains('name="message"'));
    expect(multipartBody, contains('Image details'));
    expect(
      multipartBody,
      contains('name="attachment"; filename="support_image.png"'),
    );

    await tester.tap(find.byKey(const ValueKey('support-message-send')));
    await tester.pumpAndSettle();

    expect(postCount, 2);
    expect(find.byKey(const ValueKey('support-image-preview')), findsNothing);
    expect(tester.widget<TextField>(inputFinder).controller!.text, isEmpty);
    expect(find.text('Image details'), findsOneWidget);
  });

  testWidgets('prevents duplicate attachment uploads while sending', (
    tester,
  ) async {
    final uploadResponse = Completer<http.Response>();
    var postCount = 0;
    final service = await _supportService((request) async {
      if (request.method == 'POST') {
        postCount++;
        return uploadResponse.future;
      }
      return _conversationHandler()(request);
    });

    await _openConversation(
      tester,
      service,
      imagePicker: () async => _validPng(),
    );
    await tester.tap(find.byKey(const ValueKey('support-message-attach')));
    await tester.pumpAndSettle();
    final sendFinder = find.byKey(const ValueKey('support-message-send'));
    await tester.tap(sendFinder);
    await tester.pump();

    expect(postCount, 1);
    expect(tester.widget<IconButton>(sendFinder).onPressed, isNull);
    expect(find.byKey(const ValueKey('support-image-preview')), findsOneWidget);

    uploadResponse.complete(
      http.Response(
        jsonEncode({
          'success': true,
          'chatMessage': _messageJson(
            id: 23,
            senderType: 'patient',
            senderPatientId: 'patient-7',
            text: '',
            attachmentUrl: 'https://cdn.example.test/photo.png',
            attachmentName: 'photo.png',
            attachmentMimeType: 'image/png',
          ),
        }),
        201,
      ),
    );
    await tester.pumpAndSettle();
    expect(postCount, 1);
  });

  testWidgets('empty messages do not send a request', (tester) async {
    var postCount = 0;
    final service = await _supportService((request) async {
      if (request.method == 'POST') postCount++;
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse();
      }
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'messages': <Object>[],
            'chatAvailable': true,
            'readOnly': false,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'updatedCount': 0}),
        200,
      );
    });

    await _openConversation(tester, service);
    final inputFinder = find.byKey(const ValueKey('support-message-input'));
    await tester.enterText(inputFinder, '   ');
    await tester.tap(find.byKey(const ValueKey('support-message-send')));
    await tester.pump();

    expect(postCount, 0);
  });

  testWidgets('prevents duplicate sends while the request is pending', (
    tester,
  ) async {
    final sendCompleter = Completer<http.Response>();
    var postCount = 0;
    final service = await _supportService((request) async {
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse();
      }
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'messages': <Object>[],
            'chatAvailable': true,
            'readOnly': false,
          }),
          200,
        );
      }
      if (request.method == 'POST') {
        postCount++;
        return sendCompleter.future;
      }
      return http.Response(
        jsonEncode({'success': true, 'updatedCount': 0}),
        200,
      );
    });

    await _openConversation(tester, service);
    await tester.enterText(
      find.byKey(const ValueKey('support-message-input')),
      'One message',
    );
    final sendFinder = find.byKey(const ValueKey('support-message-send'));
    await tester.tap(sendFinder);
    await tester.pump();
    expect(postCount, 1);
    expect(tester.widget<IconButton>(sendFinder).onPressed, isNull);

    sendCompleter.complete(
      http.Response(
        jsonEncode({
          'success': true,
          'chatMessage': _messageJson(
            id: 10,
            senderType: 'patient',
            senderPatientId: 'patient-7',
            text: 'One message',
            createdAt: '2026-11-10T10:03:00Z',
          ),
        }),
        201,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('One message'), findsOneWidget);
  });

  testWidgets('failed sends retain the typed message and show a safe error', (
    tester,
  ) async {
    final service = await _supportService((request) async {
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse();
      }
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'messages': <Object>[],
            'chatAvailable': true,
            'readOnly': false,
          }),
          200,
        );
      }
      if (request.method == 'POST') {
        return http.Response(
          jsonEncode({'success': false, 'error': 'internal database detail'}),
          400,
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'updatedCount': 0}),
        200,
      );
    });

    await _openConversation(tester, service);
    final inputFinder = find.byKey(const ValueKey('support-message-input'));
    await tester.enterText(inputFinder, 'Please keep this message');
    await tester.tap(find.byKey(const ValueKey('support-message-send')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(inputFinder).controller!.text,
      'Please keep this message',
    );
    expect(
      find.byKey(const ValueKey('support-message-send-error')),
      findsOneWidget,
    );
    expect(find.text('internal database detail'), findsNothing);
  });

  testWidgets('network send failures retain the message for retry', (
    tester,
  ) async {
    final service = await _supportService((request) async {
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse();
      }
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'messages': <Object>[],
            'chatAvailable': true,
            'readOnly': false,
          }),
          200,
        );
      }
      if (request.method == 'POST') {
        throw http.ClientException('internal socket detail');
      }
      return http.Response(
        jsonEncode({'success': true, 'updatedCount': 0}),
        200,
      );
    });

    await _openConversation(tester, service);
    final inputFinder = find.byKey(const ValueKey('support-message-input'));
    await tester.enterText(inputFinder, 'Network retry message');
    await tester.tap(find.byKey(const ValueKey('support-message-send')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(inputFinder).controller!.text,
      'Network retry message',
    );
    expect(
      find.text(
        'Unable to reach the clinic service. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('internal socket detail'), findsNothing);
  });

  testWidgets(
    'retries message loading and treats read receipt failure as safe',
    (tester) async {
      var messageRequestCount = 0;
      final service = await _supportService((request) async {
        if (request.url.path.endsWith('/my-tickets')) {
          return _ticketListResponse();
        }
        if (request.method == 'GET') {
          messageRequestCount++;
          if (messageRequestCount == 1) {
            return http.Response('{}', 500);
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'messages': <Object>[],
              'chatAvailable': false,
              'readOnly': false,
            }),
            200,
          );
        }
        return http.Response('{}', 500);
      });

      await _openConversation(tester, service);
      expect(
        find.byKey(const ValueKey('support-messages-error')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('support-messages-retry')));
      await tester.pumpAndSettle();

      expect(messageRequestCount, 2);
      expect(find.text('No messages yet.'), findsOneWidget);
      expect(find.text('Messaging is currently unavailable.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('does not update the conversation after it is disposed', (
    tester,
  ) async {
    final messagesCompleter = Completer<http.Response>();
    final service = await _supportService((request) async {
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse();
      }
      if (request.method == 'GET') return messagesCompleter.future;
      return http.Response(
        jsonEncode({'success': true, 'updatedCount': 0}),
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(home: SupportServiceScreen(supportCenterService: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-ticket-77')));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    messagesCompleter.complete(
      http.Response(
        jsonEncode({
          'success': true,
          'messages': [_messageJson()],
          'chatAvailable': true,
          'readOnly': false,
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openConversation(
  WidgetTester tester,
  SupportCenterService service, {
  Future<XFile?> Function()? imagePicker,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SupportServiceScreen(
        supportCenterService: service,
        imagePicker: imagePicker,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('support-ticket-77')));
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

http.Response _ticketListResponse({String status = 'in_progress'}) =>
    http.Response(
      jsonEncode({
        'success': true,
        'tickets': [
          {
            'ticket_id': 77,
            'patient_id': 'patient-7',
            'subject': 'Actual appointment request',
            'category': 'Appointment',
            'priority': 'Medium',
            'status': status,
            'created_at': '2026-11-10T10:00:00Z',
          },
        ],
      }),
      200,
    );

Map<String, dynamic> _messageJson({
  int id = 1,
  String ticketId = '77',
  String senderType = 'staff',
  String? senderPatientId,
  String senderName = 'Clinic Support',
  String text = 'Help is on the way.',
  String createdAt = '2026-11-10T10:01:00Z',
  String? attachmentUrl,
  String? attachmentName,
  String? attachmentMimeType,
}) => {
  'message_id': id,
  'ticket_id': ticketId,
  'sender_id': null,
  'sender_patient_id': senderPatientId,
  'sender_name': senderName,
  'sender_role': senderType,
  'sender_type': senderType,
  'message': text,
  'attachment_url': attachmentUrl,
  'attachment_name': attachmentName,
  'attachment_mime_type': attachmentMimeType,
  'is_read': false,
  'created_at': createdAt,
};

const int _maxTestImageBytes = 10 * 1024 * 1024;

XFile _validPng() => XFile.fromData(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lS8AAAAASUVORK5CYII=',
  ),
  name: 'photo.png',
  mimeType: 'image/png',
);

Future<http.Response> Function(http.Request) _conversationHandler() =>
    (request) async {
      if (request.url.path.endsWith('/my-tickets')) {
        return _ticketListResponse();
      }
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'success': true,
            'messages': <Object>[],
            'chatAvailable': true,
            'readOnly': false,
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({'success': true, 'updatedCount': 0}),
        200,
      );
    };

String _multipartRequestBody(http.Request request) =>
    utf8.decode(request.bodyBytes, allowMalformed: true);

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
