import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/appointment_scheduler.dart';
import 'package:optcare_app/main.dart';

void main() {
  testWidgets('separates and sorts upcoming and past appointments', (
    tester,
  ) async {
    final now = DateTime.now();
    final futureLater = now
        .add(const Duration(days: 5))
        .toIso8601String()
        .split('T')
        .first;
    final futureSoon = now
        .add(const Duration(days: 2))
        .toIso8601String()
        .split('T')
        .first;
    final pastRecent = now
        .subtract(const Duration(days: 2))
        .toIso8601String()
        .split('T')
        .first;
    final pastOlder = now
        .subtract(const Duration(days: 5))
        .toIso8601String()
        .split('T')
        .first;
    final appointments = [
      _withCreatedAt(
        _appointment('Past older', pastOlder, '10:00'),
        now.subtract(const Duration(hours: 1)),
      ),
      _withCreatedAt(
        _appointment('Upcoming later', futureLater, '09:00'),
        now.subtract(const Duration(minutes: 1)),
      ),
      _withCreatedAt(
        _appointment('Past recent', pastRecent, '16:00'),
        now.subtract(const Duration(hours: 2)),
      ),
      _withCreatedAt(
        _appointment('Upcoming soon 11 AM', futureSoon, '11:00'),
        now.subtract(const Duration(minutes: 3)),
      ),
      _withCreatedAt(
        _appointment('Upcoming soon 9 AM', futureSoon, '09:00'),
        now.subtract(const Duration(minutes: 4)),
      ),
    ];

    await _withDashboard(tester, (_) async {
      expect(find.text('Upcoming Appointments'), findsOneWidget);
      expect(find.text('Past Appointments'), findsOneWidget);

      final positions = [
        tester.getTopLeft(find.text('Upcoming later')).dy,
        tester.getTopLeft(find.text('Upcoming soon 11 AM')).dy,
        tester.getTopLeft(find.text('Upcoming soon 9 AM')).dy,
        tester.getTopLeft(find.text('Past recent')).dy,
        tester.getTopLeft(find.text('Past older')).dy,
      ];
      expect(positions, orderedEquals(positions.toList()..sort()));
    }, (_) async => _jsonResponse(200, appointments));
  });

  testWidgets('sorts by scheduled date and time instead of created_at', (
    tester,
  ) async {
    var november30Evening = _appointment(
      'Nov 30 Evening',
      '2026-11-30',
      '16:00',
    );
    november30Evening = _withCreatedAt(november30Evening, DateTime(2026, 1, 1));
    var november30Cancelled = _appointment(
      'Nov 30 Cancelled',
      '2026-11-30',
      '12:00',
    );
    november30Cancelled = {
      ..._withCreatedAt(november30Cancelled, DateTime(2026, 12, 1)),
      'appointment_status': 'Cancelled',
    };
    var november30Morning = _appointment(
      'Nov 30 Morning',
      '2026-11-30',
      '09:00',
    );
    november30Morning = _withCreatedAt(
      november30Morning,
      DateTime(2026, 10, 1),
    );
    final november25 = _withCreatedAt(
      _appointment('Nov 25', '2026-11-25', '10:00'),
      DateTime(2026, 11, 30),
    );
    final november24 = _withCreatedAt(
      _appointment('Nov 24', '2026-11-24', '10:00'),
      DateTime(2027, 1, 1),
    );

    await _withDashboard(
      tester,
      (_) async {
        final positions = [
          tester.getTopLeft(find.text('Nov 30 Evening')).dy,
          tester.getTopLeft(find.text('Nov 30 Cancelled')).dy,
          tester.getTopLeft(find.text('Nov 30 Morning')).dy,
          tester.getTopLeft(find.text('Nov 25')).dy,
          tester.getTopLeft(find.text('Nov 24')).dy,
        ];
        expect(positions, orderedEquals(positions.toList()..sort()));
        expect(find.text('CANCELLED'), findsOneWidget);
      },
      (_) async => _jsonResponse(200, [
        november24,
        november30Morning,
        november25,
        november30Evening,
        november30Cancelled,
      ]),
    );
  });

  testWidgets('six appointments appear together on page one', (tester) async {
    await _withDashboard(tester, (_) async {
      expect(find.text('Page 1 of 1'), findsNothing);
      for (var index = 1; index <= 6; index++) {
        expect(find.text('Appointment $index'), findsOneWidget);
      }
    }, (_) async => _jsonResponse(200, _appointments(6)));
  });

  testWidgets('invalid appointment dates are placed safely after valid dates', (
    tester,
  ) async {
    await _withDashboard(
      tester,
      (_) async {
        expect(find.text('Valid Later'), findsOneWidget);
        expect(find.text('Invalid Date'), findsOneWidget);
        final validPosition = tester.getTopLeft(find.text('Valid Later')).dy;
        final invalidPosition = tester.getTopLeft(find.text('Invalid Date')).dy;
        expect(validPosition, lessThan(invalidPosition));
      },
      (_) async => _jsonResponse(200, [
        _appointment('Invalid Date', 'invalid', '10:00'),
        _appointment('Valid Later', '2026-11-30', '16:00'),
      ]),
    );
  });

  testWidgets('deduplicates repeated appointment IDs after refresh', (
    tester,
  ) async {
    final duplicate = _appointment('Unique appointment', '2026-10-22', '11:00');
    duplicate['appointment_id'] = 'dup-1';
    await _withDashboard(
      tester,
      (_) async {
        expect(find.text('Unique appointment'), findsOneWidget);
      },
      (_) async => _jsonResponse(200, [
        duplicate,
        {...duplicate},
      ]),
    );
  });

  testWidgets('missing creation timestamps sort by scheduled date', (
    tester,
  ) async {
    final futureSoon = DateTime.now()
        .add(const Duration(days: 1))
        .toIso8601String()
        .split('T')
        .first;
    final futureLater = DateTime.now()
        .add(const Duration(days: 5))
        .toIso8601String()
        .split('T')
        .first;
    await _withDashboard(
      tester,
      (_) async {
        final first = tester.getTopLeft(find.text('First returned')).dy;
        final second = tester.getTopLeft(find.text('Second returned')).dy;
        expect(second, lessThan(first));
      },
      (_) async => _jsonResponse(200, [
        _appointment('First returned', futureSoon, '09:00'),
        _appointment('Second returned', futureLater, '09:00'),
      ]),
    );
  });

  testWidgets(
    'shows ten appointments on page one and the next ten on page two',
    (tester) async {
      final appointments = _appointments(23);

      await _withDashboard(tester, (_) async {
        expect(find.text('Page 1 of 3'), findsOneWidget);
        for (var index = 1; index <= 10; index++) {
          expect(find.text('Appointment $index'), findsOneWidget);
        }
        expect(find.text('Appointment 11'), findsNothing);

        await tester.ensureVisible(
          find.byKey(const ValueKey('appointments-next-page')),
        );
        await tester.tap(find.byKey(const ValueKey('appointments-next-page')));
        await tester.pumpAndSettle();

        expect(find.text('Page 2 of 3'), findsOneWidget);
        for (var index = 11; index <= 20; index++) {
          expect(find.text('Appointment $index'), findsOneWidget);
        }
        expect(find.text('Appointment 1'), findsNothing);
        expect(find.text('Appointment 21'), findsNothing);
      }, (_) async => _jsonResponse(200, appointments));
    },
  );

  testWidgets('last page shows only the remaining appointments', (
    tester,
  ) async {
    await _withDashboard(tester, (_) async {
      for (var page = 0; page < 2; page++) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('appointments-next-page')),
        );
        await tester.tap(find.byKey(const ValueKey('appointments-next-page')));
        await tester.pumpAndSettle();
      }

      expect(find.text('Page 3 of 3'), findsOneWidget);
      for (final index in [21, 22, 23]) {
        expect(find.text('Appointment $index'), findsOneWidget);
      }
      expect(find.text('Appointment 4'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('appointments-next-page')),
            )
            .onPressed,
        isNull,
      );
    }, (_) async => _jsonResponse(200, _appointments(23)));
  });

  testWidgets('cancelled future appointment remains upcoming', (tester) async {
    final futureDate = DateTime.now()
        .add(const Duration(days: 3))
        .toIso8601String()
        .split('T')
        .first;
    await _withDashboard(
      tester,
      (_) async {
        expect(find.text('Upcoming Appointments'), findsOneWidget);
        expect(find.text('Cancelled Future'), findsOneWidget);
        expect(find.text('CANCELLED'), findsOneWidget);
      },
      (_) async => _jsonResponse(200, [
        {
          ..._appointment('Cancelled Future', futureDate, '10:00'),
          'appointment_status': 'Cancelled',
        },
      ]),
    );
  });

  testWidgets('pagination controls navigate and disable at page boundaries', (
    tester,
  ) async {
    await _withDashboard(tester, (_) async {
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('appointments-previous-page')),
            )
            .onPressed,
        isNull,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('appointments-next-page')),
      );
      await tester.tap(find.byKey(const ValueKey('appointments-next-page')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('appointments-previous-page')),
      );
      await tester.tap(
        find.byKey(const ValueKey('appointments-previous-page')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 3'), findsOneWidget);
    }, (_) async => _jsonResponse(200, _appointments(23)));
  });

  testWidgets('hides pagination when there is only one page', (tester) async {
    await _withDashboard(tester, (_) async {
      expect(
        find.byKey(const ValueKey('appointments-page-indicator')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('appointments-next-page')),
        findsNothing,
      );
      expect(find.text('CONFIRMED'), findsOneWidget);
    }, (_) async => _jsonResponse(200, _appointments(1)));
  });

  testWidgets('uses a graceful purpose fallback when the API value is empty', (
    tester,
  ) async {
    await _withDashboard(
      tester,
      (_) async {
        expect(find.text('SERVICE / PURPOSE: Clinic visit'), findsOneWidget);
        expect(find.textContaining('Provider:'), findsNothing);
        expect(find.textContaining('Type:'), findsNothing);
      },
      (_) async {
        return _jsonResponse(200, [
          {
            ..._appointment('Appointment title', '2026-10-22', '10:00'),
            'purpose_of_visit': ' ',
          },
        ]);
      },
    );
  });

  testWidgets('shows cancellation only for eligible future appointments', (
    tester,
  ) async {
    final today = DateTime.now();
    final appointments = [
      for (final status in [' Requested ', 'Pending', 'CONFIRMED'])
        _futureAppointment(status, status: status),
      for (final status in [
        'Cancelled',
        'Rejected',
        'Approved',
        'Scheduled',
        'Accepted',
      ])
        _futureAppointment(status, status: status),
      {
        ..._futureAppointment('past'),
        'appointment_date': today
            .subtract(const Duration(days: 1))
            .toIso8601String()
            .split('T')
            .first,
      },
    ];

    await _withDashboard(tester, (_) async {
      for (final id in [' Requested ', 'Pending', 'CONFIRMED']) {
        expect(find.byKey(ValueKey('appointment-cancel-$id')), findsOneWidget);
      }
      for (final id in [
        'Cancelled',
        'Rejected',
        'Approved',
        'Scheduled',
        'Accepted',
        'past',
      ]) {
        expect(find.byKey(ValueKey('appointment-cancel-$id')), findsNothing);
      }
    }, (_) async => _jsonResponse(200, appointments));
  });

  testWidgets('dismissing cancellation confirmation sends no request', (
    tester,
  ) async {
    var cancellationRequests = 0;
    await _withDashboard(
      tester,
      (_) async {
        final action = find.byKey(const ValueKey('appointment-cancel-42'));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('This action cannot be undone.'),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('appointment-cancel-dismiss-42')),
        );
        await tester.pumpAndSettle();
        expect(cancellationRequests, 0);
        expect(find.text('CONFIRMED'), findsOneWidget);
      },
      (_) async => _jsonResponse(200, [_futureAppointment('42')]),
      otherRequestHandler: (request) async {
        if (request.method == 'PATCH') cancellationRequests++;
        return _defaultDashboardResponse(request);
      },
    );
  });

  testWidgets(
    'confirmation sends the verified request and refreshes list and availability',
    (tester) async {
      var cancelled = false;
      var appointmentListFetches = 0;
      http.Request? cancellationRequest;
      final appointment = _futureAppointment('42');
      await _withDashboard(
        tester,
        (_) async {
          final action = find.byKey(const ValueKey('appointment-cancel-42'));
          await tester.ensureVisible(action);
          await tester.tap(action);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('appointment-cancel-confirm-42')),
          );
          await tester.pumpAndSettle();

          expect(cancellationRequest, isNotNull);
          expect(cancellationRequest!.method, 'PATCH');
          expect(
            cancellationRequest!.url.path,
            '/api/appointments/patient/42/cancel',
          );
          expect(
            cancellationRequest!.headers['content-type'],
            'application/json',
          );
          expect(cancellationRequest!.headers['accept'], 'application/json');
          expect(jsonDecode(cancellationRequest!.body), {
            'patient_id': 'patient-test',
          });
          expect(appointmentListFetches, 2);
          expect(find.text('CANCELLED'), findsOneWidget);
          expect(find.text('Appointment cancelled.'), findsOneWidget);
          expect(
            isAppointmentStatusBlocking(
              cancelled ? 'Cancelled' : appointment['appointment_status'],
            ),
            isFalse,
          );
        },
        (_) async {
          appointmentListFetches++;
          return _jsonResponse(200, [
            cancelled
                ? {...appointment, 'appointment_status': 'Cancelled'}
                : appointment,
          ]);
        },
        otherRequestHandler: (request) async {
          if (request.method == 'PATCH') {
            cancellationRequest = request;
            cancelled = true;
            return _jsonResponse(200, {
              'success': true,
              'appointment_status': 'Cancelled',
              'booking_slot_released': true,
            });
          }
          return _defaultDashboardResponse(request);
        },
      );
    },
  );

  for (final (statusCode, expectedMessage) in [
    (400, 'The cancellation request was invalid.'),
    (404, 'This appointment could not be found'),
    (409, 'This appointment can no longer be cancelled.'),
    (500, 'The clinic could not cancel this appointment.'),
  ]) {
    testWidgets('cancellation HTTP $statusCode does not change status', (
      tester,
    ) async {
      var appointmentListFetches = 0;
      await _withDashboard(
        tester,
        (_) async {
          final action = find.byKey(const ValueKey('appointment-cancel-42'));
          await tester.ensureVisible(action);
          await tester.tap(action);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('appointment-cancel-confirm-42')),
          );
          await tester.pumpAndSettle();

          expect(find.text('PENDING'), findsOneWidget);
          expect(find.textContaining(expectedMessage), findsOneWidget);
          expect(appointmentListFetches, 1);
        },
        (_) async {
          appointmentListFetches++;
          return _jsonResponse(200, [
            _futureAppointment('42', status: 'Requested'),
          ]);
        },
        otherRequestHandler: (request) async {
          if (request.method == 'PATCH') {
            return _jsonResponse(statusCode, {'error': 'Server response'});
          }
          return _defaultDashboardResponse(request);
        },
      );
    });
  }

  testWidgets('duplicate cancellation requests are prevented', (tester) async {
    final cancellationResponse = Completer<http.Response>();
    var cancellationRequests = 0;
    await _withDashboard(
      tester,
      (_) async {
        final action = find.byKey(const ValueKey('appointment-cancel-42'));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('appointment-cancel-confirm-42')),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(cancellationRequests, 1);
        final actionButton = tester.widget<TextButton>(
          find.byKey(const ValueKey('appointment-cancel-42')),
        );
        expect(actionButton.onPressed, isNull);

        cancellationResponse.complete(
          _jsonResponse(200, {
            'success': true,
            'appointment_status': 'Cancelled',
            'booking_slot_released': true,
          }),
        );
        await tester.pumpAndSettle();
        expect(cancellationRequests, 1);
      },
      (_) async => _jsonResponse(200, [_futureAppointment('42')]),
      otherRequestHandler: (request) async {
        if (request.method == 'PATCH') {
          cancellationRequests++;
          return cancellationResponse.future;
        }
        if (request.method == 'GET' &&
            request.url.path == '/api/appointments') {
          return _jsonResponse(200, []);
        }
        return _defaultDashboardResponse(request);
      },
    );
  });

  testWidgets(
    'cancellation refresh preserves sorting and ten-item pagination',
    (tester) async {
      var cancelled = false;
      final appointments = List.generate(
        11,
        (index) => _futureAppointment('$index', daysFromNow: 11 - index),
      );
      await _withDashboard(
        tester,
        (_) async {
          expect(find.text('Page 1 of 2'), findsOneWidget);
          expect(find.text('Appointment 0'), findsOneWidget);

          final action = find.byKey(const ValueKey('appointment-cancel-0'));
          await tester.ensureVisible(action);
          await tester.tap(action);
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('appointment-cancel-confirm-0')),
          );
          await tester.pumpAndSettle();

          expect(find.text('Page 1 of 2'), findsOneWidget);
          for (var index = 1; index <= 9; index++) {
            expect(find.text('Appointment $index'), findsOneWidget);
          }
          expect(find.text('CANCELLED'), findsOneWidget);
        },
        (_) async => _jsonResponse(
          200,
          appointments.map((appointment) {
            return cancelled && appointment['appointment_id'] == '0'
                ? {...appointment, 'appointment_status': 'Cancelled'}
                : appointment;
          }).toList(),
        ),
        otherRequestHandler: (request) async {
          if (request.method == 'PATCH') {
            cancelled = true;
            return _jsonResponse(200, {
              'success': true,
              'appointment_status': 'Cancelled',
              'booking_slot_released': true,
            });
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/appointments') {
            return _jsonResponse(200, [
              {...appointments.last, 'appointment_status': 'Cancelled'},
            ]);
          }
          return _defaultDashboardResponse(request);
        },
      );
    },
  );

  testWidgets('refresh sorts updated results and resets to page one', (
    tester,
  ) async {
    var fetchCount = 0;
    await _withDashboard(
      tester,
      (_) async {
        await tester.ensureVisible(
          find.byKey(const ValueKey('appointments-next-page')),
        );
        await tester.tap(find.byKey(const ValueKey('appointments-next-page')));
        await tester.pumpAndSettle();
        expect(find.text('Page 2 of 3'), findsOneWidget);

        final refreshIndicator = find.ancestor(
          of: find.byKey(const ValueKey('appointments-page-indicator')),
          matching: find.byType(RefreshIndicator),
        );
        final refresh = tester
            .state<RefreshIndicatorState>(refreshIndicator)
            .show();
        await tester.pumpAndSettle();
        await refresh;

        expect(find.text('Page 1 of 1'), findsNothing);
        expect(find.text('Refreshed newest'), findsOneWidget);
        expect(find.text('Refreshed older'), findsOneWidget);
        expect(fetchCount, 2);
        expect(find.text('Page 1 of 1'), findsNothing);
      },
      (_) async {
        fetchCount++;
        return _jsonResponse(
          200,
          fetchCount == 1
              ? _appointments(21)
              : [
                  _appointment('Refreshed older', '2026-10-20', '09:00'),
                  _appointment('Refreshed newest', '2026-10-22', '11:00'),
                ],
        );
      },
    );
  });

  testWidgets(
    'secure availability block prevents scheduling and exposes no POST',
    (tester) async {
      var scheduled = false;
      var appointmentFetchCount = 0;
      await _withDashboard(
        tester,
        (_) async {
          await tester.ensureVisible(
            find.byKey(const ValueKey('appointments-next-page')),
          );
          await tester.tap(
            find.byKey(const ValueKey('appointments-next-page')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Page 2 of 2'), findsOneWidget);

          await tester.ensureVisible(find.text('Schedule New Appointment'));
          await tester.tap(find.text('Schedule New Appointment'));
          await tester.pumpAndSettle();
          final calendar = tester.widget<CalendarDatePicker>(
            find.byType(CalendarDatePicker),
          );
          final selectedDate = nextClinicOpenDate(
            DateTime.now().add(const Duration(days: 1)),
          );
          calendar.onDateChanged(selectedDate);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            find.text(
              'Secure patient appointment availability is unavailable. '
              'Booking is temporarily disabled until secure backend availability is provided.',
            ),
            findsOneWidget,
          );
          expect(find.text('8:00 AM'), findsNothing);
          expect(scheduled, isFalse);
        },
        (request) async {
          if (request.url.path == '/api/appointments/patient/patient-test') {
            appointmentFetchCount++;
            return _jsonResponse(
              200,
              scheduled
                  ? [
                      ..._appointments(11, year: 2020),
                      _appointment(
                        'Eye Examination',
                        DateTime.now().toIso8601String().split('T').first,
                        '23:59',
                      ),
                    ]
                  : _appointments(11, year: 2020),
            );
          }
          return _defaultDashboardResponse(request);
        },
        otherRequestHandler: (request) async {
          if (request.url.path == '/api/appointments/services') {
            return _jsonResponse(200, [
              {
                'name': 'Eye Examination',
                'duration_minutes': 60,
                'legacy_names': ['Eye Examination'],
              },
            ]);
          }
          if (request.url.path == '/api/appointments' &&
              request.method == 'GET') {
            return _jsonResponse(200, []);
          }
          if (request.url.path == '/api/appointments' &&
              request.method == 'POST') {
            scheduled = true;
            return _jsonResponse(201, {'success': true});
          }
          if (request.url.path == '/api/clinic-closures') {
            return _jsonResponse(200, []);
          }
          return _defaultDashboardResponse(request);
        },
      );
      expect(appointmentFetchCount, greaterThanOrEqualTo(1));
    },
  );
}

Future<void> _withDashboard(
  WidgetTester tester,
  Future<void> Function(WidgetTester) body,
  Future<http.Response> Function(http.Request) appointmentHandler, {
  Future<http.Response> Function(http.Request)? otherRequestHandler,
}) async {
  final previousErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    // Keep an unrelated dashboard summary-tile layout error out of these
    // tests while continuing to report every other Flutter error.
    if (message.contains('Incorrect use of ParentDataWidget') &&
        message.contains('_SummaryTile')) {
      return;
    }
    if (previousErrorHandler == null) {
      FlutterError.presentError(details);
    } else {
      previousErrorHandler(details);
    }
  };
  addTearDown(() => FlutterError.onError = previousErrorHandler);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2200);

  await http.runWithClient(
    () async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DashboardScreen(profileData: {'patient_id': 'patient-test'}),
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
      await body(tester);
    },
    () => MockClient((request) async {
      if (request.url.path == '/api/appointments/patient/patient-test') {
        return appointmentHandler(request);
      }
      if (otherRequestHandler != null) {
        return otherRequestHandler(request);
      }
      return _defaultDashboardResponse(request);
    }),
  );
}

Future<http.Response> _defaultDashboardResponse(http.Request request) async {
  if (request.url.path == '/api/patients/patient-test') {
    return _jsonResponse(200, {});
  }
  if (request.url.path == '/api/frames/page') {
    return _jsonResponse(200, {
      'items': [],
      'categories': [],
      'pagination': {'page': 1, 'limit': 10, 'total': 0, 'totalPages': 0},
    });
  }
  return _jsonResponse(200, []);
}

List<Map<String, dynamic>> _appointments(int count, {int year = 2026}) =>
    List.generate(count, (index) {
      final scheduledDay = count - index;
      final appointment = _appointment(
        'Appointment ${index + 1}',
        DateTime(year, 12, scheduledDay).toIso8601String().split('T').first,
        '10:00',
      );
      appointment['created_at'] = DateTime.now()
          .subtract(Duration(days: count - index))
          .toIso8601String();
      return appointment;
    });

Map<String, dynamic> _withCreatedAt(
  Map<String, dynamic> appointment,
  DateTime createdAt,
) => {...appointment, 'created_at': createdAt.toIso8601String()};

Map<String, dynamic> _futureAppointment(
  String id, {
  String status = 'Confirmed',
  int daysFromNow = 2,
}) {
  final date = DateTime.now()
      .add(Duration(days: daysFromNow))
      .toIso8601String()
      .split('T')
      .first;
  return {
    ..._appointment('Appointment $id', date, '23:59'),
    'appointment_id': id,
    'appointment_status': status,
  };
}

Map<String, dynamic> _appointment(String name, String date, String time) => {
  'appointment_date': date,
  'appointment_time': time,
  'appointment_status': 'Confirmed',
  'provider': name,
  'appointment_type': 'Eye examination',
  'purpose_of_visit': 'Eye Examination',
};

http.Response _jsonResponse(int statusCode, Object body) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
