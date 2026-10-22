import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/notification_screen.dart';

void main() {
  const patientId = 'synthetic-notification-patient';
  const token = 'synthetic-notification-jwt';

  tearDown(() async {
    await notificationsController.clear();
  });

  testWidgets('shows loading then empty state', (tester) async {
    final response = Completer<http.Response>();

    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NotificationScreen(patientId: patientId, token: token),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      response.complete(http.Response('[]', 200));
      await tester.pumpAndSettle();

      expect(find.text('No notifications yet.'), findsOneWidget);
    }, () => MockClient((_) => response.future));
  });

  testWidgets('shows API errors and offers retry', (tester) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(
            home: NotificationScreen(patientId: patientId, token: token),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Notifications are temporarily unavailable.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
      },
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'Notifications are temporarily unavailable.'}),
          503,
        ),
      ),
    );
  });

  testWidgets('loads and marks a notification as read with session token', (
    tester,
  ) async {
    final requests = <http.Request>[];

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(
            home: NotificationScreen(patientId: patientId, token: token),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Fictional appointment reminder'), findsOneWidget);
        expect(find.byIcon(Icons.circle), findsOneWidget);
        await tester.tap(find.text('Fictional appointment reminder'));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.circle), findsNothing);
        expect(requests, hasLength(2));
        expect(requests.first.method, 'GET');
        expect(requests.last.method, 'PATCH');
        for (final request in requests) {
          expect(request.headers['Authorization'], contains(token));
        }
      },
      () => MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode([
              {
                'notification_id': 'demo-notification-1',
                'title': 'Fictional appointment reminder',
                'body': 'This is a test notification.',
                'created_at': '2026-10-22T09:00:00Z',
                'is_read': false,
                'type': 'appointment',
              },
            ]),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
  });
}
