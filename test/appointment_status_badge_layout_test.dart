import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/main.dart';

void main() {
  testWidgets(
    'appointment status badge aligns with title at narrow and wide widths',
    (tester) async {
      const patientId = 'x';
      const appointmentTitle = 'Fictional Optometry Visit';
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await http.runWithClient(
        () async {
          for (final width in [370.0, 400.0]) {
            for (final textScale in [1.0, 1.3]) {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = Size(width, 800);

              await tester.pumpWidget(
                MaterialApp(
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(textScale)),
                    child: child!,
                  ),
                  home: const DashboardScreen(
                    profileData: {'patient_id': patientId},
                  ),
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

              final titleFinder = find.text(appointmentTitle);
              final badgeTextFinder = find.text('CONFIRMED');
              expect(titleFinder, findsOneWidget);
              expect(badgeTextFinder, findsOneWidget);

              final badgeFinder = find
                  .ancestor(
                    of: badgeTextFinder,
                    matching: find.byType(Container),
                  )
                  .first;
              final cardFinder = find
                  .ancestor(of: titleFinder, matching: find.byType(Container))
                  .first;
              final cardLayoutFinder = find
                  .ancestor(
                    of: titleFinder,
                    matching: find.byType(LayoutBuilder),
                  )
                  .first;
              final titleRect = tester.getRect(titleFinder);
              final badgeRect = tester.getRect(badgeFinder);
              final cardRect = tester.getRect(cardFinder);
              final cardLayoutWidth = tester.getSize(cardLayoutFinder).width;

              expect(cardLayoutWidth < 340, width == 370.0);

              expect(
                badgeRect.top,
                closeTo(titleRect.top, 1),
                reason: 'width=$width, textScale=$textScale',
              );
              expect(
                badgeRect.left,
                greaterThanOrEqualTo(titleRect.right),
                reason: 'Badge should remain trailing beside the title.',
              );
              expect(
                badgeRect.right,
                closeTo(cardRect.right - 13, 1),
                reason: 'Badge should remain right-aligned within the card.',
              );
              final layoutException = tester.takeException();
              if (textScale == 1.3) {
                expect(
                  layoutException.toString(),
                  contains(
                    'A RenderFlex overflowed by 20 pixels on the bottom',
                  ),
                  reason:
                      'No appointment-card errors should add to the existing dashboard tile overflow.',
                );
              } else if (width == 370.0) {
                expect(
                  layoutException.toString(),
                  contains(
                    'A RenderFlex overflowed by 11 pixels on the bottom',
                  ),
                  reason:
                      'No appointment-card errors should add to the existing dashboard tile overflow.',
                );
              } else {
                expect(layoutException, isNull);
              }
            }
          }
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/appointments/patient/$patientId') {
            return http.Response(
              jsonEncode([
                {
                  'appointment_date': '2026-10-22',
                  'appointment_time': '10:00',
                  'appointment_status': 'Confirmed',
                  'provider': appointmentTitle,
                  'appointment_type': 'Eye examination',
                },
              ]),
              200,
            );
          }
          if (request.url.path == '/api/patients/$patientId') {
            return http.Response('{}', 200);
          }
          if (request.url.path == '/api/frames') {
            return http.Response('[]', 200);
          }
          return http.Response('[]', 200);
        }),
      );
    },
  );
}
