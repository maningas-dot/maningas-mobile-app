import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/main.dart';
import 'package:optcare_app/transaction_history_screen.dart';

void main() {
  testWidgets(
    'Dashboard shortcut order and five bottom-navigation destinations work',
    (tester) async {
      const patientId = 'synthetic-patient-transaction-nav';
      var transactionRequests = 0;
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {};

      try {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              const MaterialApp(
                home: DashboardScreen(profileData: {'patient_id': patientId}),
              ),
            );
            await tester.pumpAndSettle();

            final dashboardCard = find.ancestor(
              of: find.text('Welcome back,'),
              matching: find.byType(DecoratedBox),
            );
            final initialAppBarBottom = tester
                .getBottomLeft(find.byType(AppBar))
                .dy;
            expect(
              tester.getTopLeft(dashboardCard).dy - initialAppBarBottom,
              closeTo(16, 1),
            );

            const expectedLabels = [
              'Book Appointment',
              'Explore Frames',
              'My Appointments',
              'Transaction History',
              'My Profile',
            ];
            final grid = find.byType(GridView).first;
            final shortcutOrder =
                expectedLabels
                    .map(
                      (label) => MapEntry(
                        label,
                        tester.getTopLeft(
                          find.descendant(of: grid, matching: find.text(label)),
                        ),
                      ),
                    )
                    .toList()
                  ..sort((a, b) {
                    final verticalOrder = a.value.dy.compareTo(b.value.dy);
                    return verticalOrder == 0
                        ? a.value.dx.compareTo(b.value.dx)
                        : verticalOrder;
                  });
            expect(
              shortcutOrder.map((entry) => entry.key).toList(),
              expectedLabels,
            );
            expect(
              tester
                  .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                  .items
                  .map((item) => item.label)
                  .toList(),
              [
                'Dashboard',
                'Explore Frames',
                'My Appointments',
                'Transaction History',
                'My Profile',
              ],
            );

            Future<void> tapDestination(String label) async {
              await tester.tap(
                find.descendant(
                  of: find.byType(BottomNavigationBar),
                  matching: find.text(label),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }

            Future<void> tapShortcut(String label) async {
              final shortcut = find.descendant(
                of: find.byType(GridView).first,
                matching: find.text(label),
              );
              final tapTarget = find
                  .ancestor(
                    of: shortcut,
                    matching: find.byType(GestureDetector),
                  )
                  .first;
              tester.widget<GestureDetector>(tapTarget).onTap!.call();
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }

            await tapShortcut('Book Appointment');
            expect(find.text('Appointment Scheduler'), findsOneWidget);
            await tester.pageBack();
            await tester.pumpAndSettle();

            await tapShortcut('Transaction History');
            await tester.pumpAndSettle();

            expect(find.text('Transaction History'), findsWidgets);
            expect(find.byType(BottomNavigationBar), findsOneWidget);
            expect(find.byType(Scaffold), findsOneWidget);
            expect(find.byType(AppBar), findsOneWidget);
            expect(find.text('Quick actions'), findsNothing);
            expect(find.text('Your transactions'), findsOneWidget);
            expect(
              find.text('Review your purchases and payment details.'),
              findsOneWidget,
            );
            final transactionHeader = find.ancestor(
              of: find.text('Your transactions'),
              matching: find.byType(DecoratedBox),
            ).last;
            final transactionAppBarBottom = tester
                .getBottomLeft(find.byType(AppBar))
                .dy;
            expect(
              tester.getTopLeft(transactionHeader).dy - transactionAppBarBottom,
              closeTo(16, 1),
            );
            expect(find.text('No transactions yet.'), findsOneWidget);
            expect(transactionRequests, 1);
            final tabs = find.byType(IndexedStack);
            final transactionPage = find.descendant(
              of: tabs,
              matching: find.byType(TransactionHistoryScreen),
            );
            expect(transactionPage, findsOneWidget);
            expect(tester.getSize(transactionPage), tester.getSize(tabs));
            expect(
              tester
                  .widget<TransactionHistoryScreen>(transactionPage)
                  .showScaffold,
              isFalse,
            );
            expect(
              tester
                  .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                  .currentIndex,
              3,
            );

            await tapDestination('Explore Frames');
            await tester.pumpAndSettle();
            expect(find.text('No transactions yet.'), findsNothing);
            expect(
              tester
                  .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                  .currentIndex,
              1,
            );
            await tapDestination('Transaction History');
            expect(find.text('No transactions yet.'), findsOneWidget);
            expect(transactionRequests, 1);

            await tapDestination('Dashboard');
            expect(
              tester
                  .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                  .currentIndex,
              0,
            );
            expect(find.text('Quick actions'), findsOneWidget);
            expect(find.text('Appointment Scheduler'), findsNothing);
            await tapDestination('Explore Frames');
            expect(
              tester
                  .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                  .currentIndex,
              1,
            );
            await tapDestination('My Appointments');
            expect(
              tester
                  .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                  .currentIndex,
              2,
            );

            final navHistoryLabel = find.descendant(
              of: find.byType(BottomNavigationBar),
              matching: find.text('Transaction History'),
            );
            expect(navHistoryLabel, findsOneWidget);
            await tester.tap(navHistoryLabel);
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expect(find.text('Transaction History'), findsWidgets);
            expect(find.byType(BottomNavigationBar), findsOneWidget);
            expect(find.byType(Scaffold), findsOneWidget);
            expect(find.byType(AppBar), findsOneWidget);
            expect(find.text('Your transactions'), findsOneWidget);
            expect(find.text('No transactions yet.'), findsOneWidget);
            expect(transactionRequests, 1);
            expect(
              tester
                  .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                  .currentIndex,
              3,
            );

            await tapDestination('My Profile');
            expect(
              tester
                  .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                  .currentIndex,
              4,
            );
            expect(find.text('Patient ID'), findsWidgets);
          },
          () => MockClient((request) async {
            if (request.method == 'GET' &&
                request.url.path == '/api/patients/$patientId/transactions') {
              transactionRequests++;
              return http.Response('[]', 200);
            }
            if (request.method == 'GET' &&
                request.url.path == '/api/patients/$patientId') {
              return http.Response('{}', 200);
            }
            return http.Response('[]', 200);
          }),
        );
      } finally {
        debugPrint = previousDebugPrint;
      }
    },
  );
}
