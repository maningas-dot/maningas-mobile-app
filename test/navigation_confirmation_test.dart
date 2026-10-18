import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/main.dart';

void main() {
  const patientId = 'synthetic-confirmation-patient';

  testWidgets('system Back No keeps the current tab and session active', (
    tester,
  ) async {
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
        await tester.tap(find.byTooltip('Logout'));
        await tester.pumpAndSettle();

        expect(find.text('Are you sure you want to log out?'), findsOneWidget);
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
      }, () => MockClient(_mockResponse(patientId)));
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
