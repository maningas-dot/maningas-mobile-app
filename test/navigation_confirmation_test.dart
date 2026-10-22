import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/main.dart';
import 'package:optcare_app/notification_screen.dart';
import 'package:optcare_app/services/patient_session_service.dart';

void main() {
  const patientId = 'synthetic-confirmation-patient';

  testWidgets('system Back No keeps the current tab and session active', (
    tester,
  ) async {
    await notificationsController.clear();
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DashboardScreen(profileData: {'patient_id': patientId}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('My Appointments'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to exit?'), findsOneWidget);
      expect(find.text('Do you want to close the app?'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);

      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        2,
      );
      expect(find.text('My Appointments'), findsWidgets);
    }, () => MockClient(_mockResponse(patientId)));
  });

  testWidgets('system Back Yes requests platform app exit without logout', (
    tester,
  ) async {
    await notificationsController.clear();
    final platformCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DashboardScreen(profileData: {'patient_id': patientId}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(platformCalls, contains('SystemNavigator.pop'));
      expect(find.text('Are you sure you want to exit?'), findsNothing);
      expect(find.text('Login'), findsNothing);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
    }, () => MockClient(_mockResponse(patientId)));
  });

  testWidgets(
    'logout cancellation stays authenticated and confirmation logs out',
    (tester) async {
      await notificationsController.clear();
      final tokenStorage = _MemoryTokenStorage();
      final sessionClient = MockClient(
        (_) async => http.Response(
          jsonEncode({'token': 'synthetic-jwt', 'patient_id': patientId}),
          200,
        ),
      );
      final sessionService = PatientSessionService(
        client: sessionClient,
        tokenStorage: tokenStorage,
        baseUrl: 'https://api.example.test',
      );
      await sessionService.login(
        email: 'patient@example.test',
        password: 'synthetic-password',
        rememberMe: false,
      );
      var markReadRequests = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: DashboardScreen(
                profileData: const {'patient_id': patientId},
                sessionService: sessionService,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await notificationsController.markAllAsRead();
          expect(markReadRequests, 1);

          await tester.tap(
            find.descendant(
              of: find.byType(BottomNavigationBar),
              matching: find.text('My Appointments'),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Logout'));
          await tester.pumpAndSettle();

          expect(
            find.text('Are you sure you want to log out?'),
            findsOneWidget,
          );
          expect(
            find.text('You will need to log in again to access your account.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(BottomNavigationBar), findsOneWidget);
          expect(
            tester
                .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                .currentIndex,
            2,
          );
          expect(find.text('My Appointments'), findsWidgets);

          await tester.tap(find.byTooltip('Logout'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Yes, Log Out'));
          await tester.pumpAndSettle();

          expect(find.byType(BottomNavigationBar), findsNothing);
          expect(find.text('Login'), findsOneWidget);
          expect(tokenStorage.value, isNull);
          markReadRequests = 0;
          await notificationsController.markAllAsRead();
          expect(markReadRequests, 0);
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/read-all')) {
            expect(request.headers['Authorization'], contains('synthetic-jwt'));
            markReadRequests++;
            return http.Response('{}', 200);
          }
          return _mockResponse(patientId)(request);
        }),
      );
      sessionService.close();
      sessionClient.close();
    },
  );
}

Future<http.Response> Function(http.Request) _mockResponse(String patientId) {
  return (request) async {
    if (request.url.path == '/api/patients/$patientId') {
      return http.Response('{}', 200);
    }
    return http.Response('[]', 200);
  };
}

class _MemoryTokenStorage implements PatientTokenStorage {
  String? value;

  @override
  Future<void> deleteToken() async {
    value = null;
  }

  @override
  Future<String?> readToken() async => value;

  @override
  Future<void> writeToken(String token) async {
    value = token;
  }
}
