import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/appointment_scheduler.dart';
import 'package:optcare_app/constants.dart';
import 'package:optcare_app/main.dart';

void main() {
  test('clinic clock converts UTC to Philippine local time', () {
    expect(
      appointmentClinicLocalNow(utcNow: DateTime.utc(2026, 10, 21, 13, 52)),
      DateTime.utc(2026, 10, 21, 21, 52),
    );
    expect(
      appointmentClinicLocalNow(utcNow: DateTime.utc(2026, 10, 21, 16, 30)),
      DateTime.utc(2026, 10, 22, 0, 30),
    );
  });

  test('appointment slots are offered every half hour through 17:30', () {
    final slots = generateAppointmentTimeSlots();

    expect(slots, hasLength(20));
    expect(slots.first, const TimeOfDay(hour: 8, minute: 0));
    expect(slots.last, const TimeOfDay(hour: 17, minute: 30));
    for (var index = 1; index < slots.length; index++) {
      final previous = slots[index - 1].hour * 60 + slots[index - 1].minute;
      final current = slots[index].hour * 60 + slots[index].minute;
      expect(current - previous, 30);
    }
  });

  test('booking dates enforce local past and 365-day boundaries', () {
    final now = DateTime(2026, 10, 5, 12);

    expect(isDateWithinBookingWindow(DateTime(2026, 10, 4), now: now), isFalse);
    expect(isDateWithinBookingWindow(DateTime(2026, 10, 5), now: now), isTrue);
    expect(isDateWithinBookingWindow(DateTime(2027, 10, 5), now: now), isTrue);
    expect(isDateWithinBookingWindow(DateTime(2027, 10, 6), now: now), isFalse);
    expect(
      isDateSelectableForBooking(DateTime(2026, 10, 11), {}, now: now),
      isFalse,
    );
  });

  test('clinic closures disable dates and inclusive range endpoints', () {
    final now = DateTime(2026, 10, 5);
    final closures = parseClinicClosureDates([
      {'start_date': '2026-10-06', 'end_date': '2026-10-07'},
    ]);

    expect(
      isDateSelectableForBooking(DateTime(2026, 10, 6), closures, now: now),
      isFalse,
    );
    expect(
      isDateSelectableForBooking(DateTime(2026, 10, 7), closures, now: now),
      isFalse,
    );
    expect(
      isDateSelectableForBooking(DateTime(2026, 10, 8), closures, now: now),
      isTrue,
    );
  });

  test('today cutoff closes slots 20 minutes or less away', () {
    final today = DateTime(2026, 10, 5);

    expect(
      isAppointmentSlotWithinBookingCutoff(
        today,
        const TimeOfDay(hour: 8, minute: 0),
        now: DateTime(2026, 10, 5, 7, 40),
      ),
      isTrue,
    );
    expect(
      isAppointmentSlotWithinBookingCutoff(
        today,
        const TimeOfDay(hour: 8, minute: 0),
        now: DateTime(2026, 10, 5, 7, 39),
      ),
      isFalse,
    );
    expect(
      isAppointmentSlotWithinBookingCutoff(
        today.add(const Duration(days: 1)),
        const TimeOfDay(hour: 8, minute: 0),
        now: DateTime(2026, 10, 5, 7, 59),
      ),
      isFalse,
    );
  });

  test(
    'active and Requested appointments block while terminal states do not',
    () {
      for (final status in [' Requested ', 'Pending', 'Confirmed']) {
        expect(isAppointmentStatusBlocking(status), isTrue);
      }
      for (final status in [
        'cancelled',
        ' CANCELED ',
        'Rejected',
        ' DECLINED ',
      ]) {
        expect(isAppointmentStatusBlocking(status), isFalse);
      }
    },
  );

  test('a date is fully unavailable only when every slot is blocked', () {
    final date = DateTime(2026, 10, 6);
    final now = DateTime(2026, 10, 5, 12);
    final booked = {
      for (final time in generateAppointmentTimeSlots())
        appointmentSlotKey(date, time),
    };

    expect(isAppointmentDateFullyUnavailable(date, booked, now: now), isTrue);
    booked.remove(
      appointmentSlotKey(date, const TimeOfDay(hour: 17, minute: 30)),
    );
    expect(isAppointmentDateFullyUnavailable(date, booked, now: now), isFalse);
  });

  test(
    'today at 9:52 PM is unavailable and has no available afternoon slots',
    () {
      final today = DateTime(2026, 10, 21);
      final now = DateTime(2026, 10, 21, 21, 52);
      final booked = <String>{};

      expect(
        isAppointmentDateFullyUnavailable(today, booked, now: now),
        isTrue,
      );
      for (final time in [
        const TimeOfDay(hour: 15, minute: 0),
        const TimeOfDay(hour: 17, minute: 0),
        const TimeOfDay(hour: 17, minute: 30),
      ]) {
        expect(
          isAppointmentSlotAvailable(today, time, booked, now: now),
          isFalse,
        );
      }
    },
  );

  test(
    'at 5 PM the 20-minute cutoff is shared by slot and date availability',
    () {
      final today = DateTime(2026, 10, 21);
      final now = DateTime(2026, 10, 21, 17);
      final booked = <String>{};

      expect(
        isAppointmentSlotAvailable(
          today,
          const TimeOfDay(hour: 17, minute: 0),
          booked,
          now: now,
        ),
        isFalse,
      );

      expect(
        isAppointmentSlotAvailable(
          today,
          const TimeOfDay(hour: 17, minute: 30),
          booked,
          now: now,
        ),
        isTrue,
      );
      expect(
        isAppointmentDateFullyUnavailable(today, booked, now: now),
        isFalse,
      );
    },
  );

  test('at 4:50 PM the 5 PM slot is unavailable at the 20-minute cutoff', () {
    final today = DateTime(2026, 10, 21);
    expect(
      isAppointmentSlotAvailable(
        today,
        const TimeOfDay(hour: 17, minute: 0),
        {},
        now: DateTime(2026, 10, 21, 16, 50),
      ),
      isFalse,
    );
  });

  test('today stays selectable when one slot remains available', () {
    final today = DateTime(2026, 10, 21);
    final now = DateTime(2026, 10, 21, 16, 30);

    expect(isAppointmentDateFullyUnavailable(today, {}, now: now), isFalse);
    expect(
      isAppointmentSlotAvailable(
        today,
        const TimeOfDay(hour: 17, minute: 30),
        {},
        now: now,
      ),
      isTrue,
    );
  });

  test('reserved slots use the same date and submission availability rule', () {
    final date = DateTime(2026, 10, 21);
    const slot = TimeOfDay(hour: 17, minute: 30);
    final now = DateTime(2026, 10, 21, 16);
    final booked = {appointmentSlotKey(date, slot)};

    expect(isAppointmentSlotAvailable(date, slot, booked, now: now), isFalse);
    expect(isAppointmentDateFullyUnavailable(date, booked, now: now), isFalse);

    final allBooked = {
      for (final time in generateAppointmentTimeSlots())
        appointmentSlotKey(date, time),
    };
    expect(
      isAppointmentDateFullyUnavailable(date, allBooked, now: now),
      isTrue,
    );
  });

  test('Appointments are only available Monday to Saturday', () {
    expect(isClinicOpenDay(DateTime(2026, 10, 5)), isTrue);
    expect(isClinicOpenDay(DateTime(2026, 10, 10)), isTrue);
    expect(isClinicOpenDay(DateTime(2026, 10, 11)), isFalse);
  });

  test(
    'Closure dates are blocked even when they are otherwise weekday open days',
    () {
      final closedDates = {DateTime(2026, 10, 8), DateTime(2026, 10, 9)};
      final now = DateTime(2026, 10, 1);

      expect(isClinicOpenDay(DateTime(2026, 10, 8)), isTrue);
      expect(isClinicClosedDate(DateTime(2026, 10, 8), closedDates), isTrue);
      expect(
        isDateSelectableForBooking(
          DateTime(2026, 10, 8),
          closedDates,
          now: now,
        ),
        isFalse,
      );
      expect(
        isDateSelectableForBooking(
          DateTime(2026, 10, 7),
          closedDates,
          now: now,
        ),
        isTrue,
      );
      expect(
        isDateSelectableForBooking(
          DateTime(2026, 10, 11),
          closedDates,
          now: now,
        ),
        isFalse,
      );
    },
  );

  test('Closure parser accepts only the existing list response structure', () {
    expect(
      parseClinicClosureDates([
        {'closure_date': '2026-10-08'},
      ]),
      {DateTime(2026, 10, 8)},
    );
    expect(
      () => parseClinicClosureDates({
        'success': true,
        'data': [
          {'closure_date': '2026-10-08'},
        ],
      }),
      throwsFormatException,
    );
    final summary = clinicClosureResponseShape([
      {
        'unrecognized_date_key': 'synthetic-private-value',
        'private_field': 'another synthetic value',
      },
    ]);
    expect(summary, contains('jsonType=list'));
    expect(
      summary,
      contains('itemFieldNames=unrecognized_date_key,private_field'),
    );
    expect(summary, contains('supportedDateFieldCount=0'));
    expect(summary, isNot(contains('synthetic-private-value')));
    expect(summary, isNot(contains('another synthetic value')));
  });

  test('Closure parser expands verified date ranges inclusively', () {
    expect(
      parseClinicClosureDates([
        {'start_date': '2026-10-08', 'end_date': '2026-10-08'},
      ]),
      {DateTime(2026, 10, 8)},
    );
    expect(
      parseClinicClosureDates([
        {'start_date': '2026-10-05', 'end_date': '2026-10-06'},
      ]),
      {DateTime(2026, 10, 5), DateTime(2026, 10, 6)},
    );
    expect(
      parseClinicClosureDates([
        {'start_date': '2026-10-05', 'end_date': '2026-10-06'},
        {'start_date': '2026-10-08', 'end_date': '2026-10-09'},
      ]),
      {
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 6),
        DateTime(2026, 10, 8),
        DateTime(2026, 10, 9),
      },
    );
  });

  test('Closure reasons cover inclusive dates and deduplicate per date', () {
    final reasonsByDate = parseClinicClosureReasons([
      {
        'start_date': '2026-10-05',
        'end_date': '2026-10-07',
        'reason': 'Clinic maintenance',
      },
      {
        'start_date': '2026-10-06',
        'end_date': '2026-10-06',
        'reason': 'Clinic maintenance',
      },
      {
        'start_date': '2026-10-06',
        'end_date': '2026-10-06',
        'reason': 'Staff training',
      },
      {'start_date': '2026-10-08', 'end_date': '2026-10-08', 'reason': '  '},
    ]);

    expect(reasonsByDate[DateTime(2026, 10, 5)], {'Clinic maintenance'});
    expect(reasonsByDate[DateTime(2026, 10, 6)], {
      'Clinic maintenance',
      'Staff training',
    });
    expect(reasonsByDate[DateTime(2026, 10, 7)], {'Clinic maintenance'});
    expect(reasonsByDate[DateTime(2026, 10, 8)], {'No reason provided.'});
  });

  test('Ranges block their inclusive dates but not adjacent open dates', () {
    final now = DateTime(2026, 10, 1);
    final closedDates = parseClinicClosureDates([
      {'start_date': '2026-10-05', 'end_date': '2026-10-06'},
    ]);

    expect(
      isDateSelectableForBooking(DateTime(2026, 10, 3), closedDates, now: now),
      isTrue,
    );
    expect(
      isDateSelectableForBooking(DateTime(2026, 10, 5), closedDates, now: now),
      isFalse,
    );
    expect(
      isDateSelectableForBooking(DateTime(2026, 10, 6), closedDates, now: now),
      isFalse,
    );
    expect(
      isDateSelectableForBooking(DateTime(2026, 10, 7), closedDates, now: now),
      isTrue,
    );
  });

  test('Malformed closure ranges are rejected rather than treated as open', () {
    expect(
      () => parseClinicClosureDates([
        {'start_date': '2026-10-05'},
      ]),
      throwsFormatException,
    );
    expect(
      () => parseClinicClosureDates([
        {'start_date': '2026-02-30', 'end_date': '2026-03-01'},
      ]),
      throwsFormatException,
    );
    expect(
      () => parseClinicClosureDates([
        {'start_date': '2026-10-05T00:00:00Z', 'end_date': '2026-10-06'},
      ]),
      throwsFormatException,
    );
    expect(
      () => parseClinicClosureDates([
        {'start_date': '2026-10-06', 'end_date': '2026-10-05'},
      ]),
      throwsFormatException,
    );
  });

  test('Empty closure list is valid and malformed items are rejected', () {
    expect(parseClinicClosureDates([]), isEmpty);
    expect(() => parseClinicClosureDates([null]), throwsFormatException);
    expect(
      () => parseClinicClosureDates([
        {'closure_date': ''},
      ]),
      throwsFormatException,
    );
  });

  test(
    'Closure dates reject calendar overflow and preserve timestamp date',
    () {
      expect(
        () => parseClinicClosureDates([
          {'closure_date': '2026-02-30'},
        ]),
        throwsFormatException,
      );
      expect(
        parseClinicClosureDates([
          {'closure_date': '2026-10-08T23:30:00-05:00'},
        ]),
        {DateTime(2026, 10, 8)},
      );
      expect(
        () => parseClinicClosureDates([
          {'closure_date': 'not-a-date'},
        ]),
        throwsFormatException,
      );
    },
  );

  test('Booking submission requires verified closures and an open date', () {
    final closure = DateTime(2026, 10, 8);
    final openDay = DateTime(2026, 10, 7);
    final now = DateTime(2026, 10, 1);

    expect(
      canSubmitAppointmentOnDate(
        closure,
        {closure},
        closuresVerified: true,
        now: now,
      ),
      isFalse,
    );
    expect(
      canSubmitAppointmentOnDate(
        openDay,
        {},
        closuresVerified: false,
        now: now,
      ),
      isFalse,
    );
    expect(
      canSubmitAppointmentOnDate(openDay, {}, closuresVerified: true, now: now),
      isTrue,
    );
    expect(
      canSubmitAppointmentOnDate(
        DateTime(2026, 10, 11),
        {},
        closuresVerified: true,
        now: now,
      ),
      isFalse,
    );
  });

  testWidgets('API closure is labeled CLOSED and is not selectable', (
    tester,
  ) async {
    final closedDate = nextClinicOpenDate(DateTime.now());
    http.Request? closureRequest;
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        closureRequest = request;
        return _jsonResponse(200, [
          {
            'id': 1,
            'start_date': _formatDate(closedDate),
            'end_date': _formatDate(closedDate),
            'reason': 'synthetic reason',
            'created_by': 1,
            'created_at': '2026-01-01T00:00:00Z',
          },
        ]);
      }
      if (request.url.path == '/api/appointments') {
        return _jsonResponse(200, []);
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked path.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(closureRequest?.method, 'GET');
    expect(closureRequest?.url, Uri.parse('$apiBaseUrl/api/clinic-closures'));
    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(calendar.selectableDayPredicate!(closedDate), isFalse);
    expect(
      calendar.selectableDayPredicate!(
        nextClinicOpenDate(closedDate.add(const Duration(days: 1))),
      ),
      isTrue,
    );

    calendar.onDisplayedMonthChanged?.call(closedDate);
    await tester.pump();
    expect(
      find.byKey(ValueKey('clinic-closure-${_formatDate(closedDate)}')),
      findsOneWidget,
    );
    expect(find.textContaining('CLOSED'), findsOneWidget);

    final selectedDateText = find.textContaining('Selected:');
    final selectedDateBefore = tester.widget<Text>(selectedDateText).data;
    calendar.onDateChanged(closedDate);
    await tester.pump();
    expect(tester.widget<Text>(selectedDateText).data, selectedDateBefore);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('shows deduplicated reasons for every date in a closure range', (
    tester,
  ) async {
    final startDate = nextClinicOpenDate(DateTime.now());
    final endDate = startDate.add(const Duration(days: 2));
    var closureRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        closureRequests++;
        return _jsonResponse(200, [
          {
            'start_date': _formatDate(startDate),
            'end_date': _formatDate(endDate),
            'reason': 'Clinic maintenance',
          },
          {
            'start_date': _formatDate(startDate.add(const Duration(days: 1))),
            'end_date': _formatDate(startDate.add(const Duration(days: 1))),
            'reason': 'Clinic maintenance',
          },
          {
            'start_date': _formatDate(startDate.add(const Duration(days: 1))),
            'end_date': _formatDate(startDate.add(const Duration(days: 1))),
            'reason': 'Staff training',
          },
        ]);
      }
      if (request.url.path == '/api/appointments') {
        return _jsonResponse(200, []);
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked path.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(closureRequests, 1);
    for (
      var date = startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      expect(
        find.byKey(ValueKey('clinic-closure-${_formatDate(date)}')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey(
            'clinic-closure-reason-${_formatDate(date)}-Clinic maintenance',
          ),
        ),
        findsOneWidget,
      );
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(calendar.selectableDayPredicate!(date), isFalse);
      expect(
        canSubmitAppointmentOnDate(
          date,
          parseClinicClosureDates([
            {
              'start_date': _formatDate(startDate),
              'end_date': _formatDate(endDate),
            },
          ]),
          closuresVerified: true,
        ),
        isFalse,
      );
    }
    expect(
      find.byKey(
        ValueKey(
          'clinic-closure-reason-${_formatDate(startDate.add(const Duration(days: 1)))}-Staff training',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Reason: Clinic maintenance'), findsNWidgets(3));

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('shows fallback when closure reasons are missing or blank', (
    tester,
  ) async {
    final startDate = nextClinicOpenDate(DateTime.now());
    final blankReasonDate = startDate.add(const Duration(days: 1));
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(200, [
          {
            'start_date': _formatDate(startDate),
            'end_date': _formatDate(startDate),
          },
          {
            'start_date': _formatDate(blankReasonDate),
            'end_date': _formatDate(blankReasonDate),
            'reason': '   ',
          },
        ]);
      }
      if (request.url.path == '/api/appointments') {
        return _jsonResponse(200, []);
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked path.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(
        ValueKey(
          'clinic-closure-reason-${_formatDate(startDate)}-No reason provided.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey(
          'clinic-closure-reason-${_formatDate(blankReasonDate)}-No reason provided.',
        ),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('closure added before submit is rechecked and blocks POST', (
    tester,
  ) async {
    final selectedDate = nextClinicOpenDate(
      DateTime.now().add(const Duration(days: 2)),
    );
    var closureFetches = 0;
    var appointmentPosts = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        closureFetches++;
        return _jsonResponse(
          200,
          closureFetches == 1
              ? []
              : [
                  {
                    'id': 1,
                    'start_date': _formatDate(selectedDate),
                    'end_date': _formatDate(selectedDate),
                    'reason': 'synthetic reason',
                    'created_by': 1,
                    'created_at': '2026-01-01T00:00:00Z',
                  },
                ],
        );
      }
      if (request.url.path == '/api/appointments' && request.method == 'GET') {
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/appointments' && request.method == 'POST') {
        appointmentPosts++;
        return _jsonResponse(201, {'success': true});
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked request.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    calendar.onDateChanged(selectedDate);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Confirm Appointment'));
    await tester.tap(find.text('Confirm Appointment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(closureFetches, greaterThanOrEqualTo(2));
    expect(appointmentPosts, 0);
    expect(
      find.text(
        'This date is unavailable for booking. Please choose another day.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('clinic closure API failure blocks selection and submission', (
    tester,
  ) async {
    var appointmentPosts = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(503, {'error': 'Unavailable.'});
      }
      if (request.url.path == '/api/appointments' && request.method == 'GET') {
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/appointments' && request.method == 'POST') {
        appointmentPosts++;
        return _jsonResponse(201, {'success': true});
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked request.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('clinic-closure-load-error')),
      findsOneWidget,
    );
    expect(find.text('8:00 AM'), findsNothing);
    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(
      calendar.selectableDayPredicate!(
        nextClinicOpenDate(DateTime.now().add(const Duration(days: 2))),
      ),
      isFalse,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Confirm Appointment'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Confirm Appointment'), warnIfMissed: false);
    await tester.pump();
    expect(appointmentPosts, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('unexpected closure response shape fails closed', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(200, {
          'success': true,
          'data': [
            {'closure_date': _formatDate(DateTime.now())},
          ],
        });
      }
      if (request.url.path == '/api/appointments') {
        return _jsonResponse(200, []);
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked request.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('clinic-closure-load-error')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Confirm Appointment'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('8:00 AM'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('failed appointment availability shows retry and no slots', (
    tester,
  ) async {
    var availabilityRequests = 0;
    final now = DateTime(2026, 10, 5, 7);
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/appointments') {
        availabilityRequests++;
        return availabilityRequests == 1
            ? _jsonResponse(503, {'error': 'Unavailable.'})
            : _jsonResponse(200, []);
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked request.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
          nowProvider: () => now,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Unable to load available appointment times.'),
      findsOneWidget,
    );
    expect(find.text('8:00 AM'), findsNothing);
    expect(
      find.byKey(const ValueKey('retry-appointment-availability')),
      findsOneWidget,
    );

    final retryButton = find.byKey(
      const ValueKey('retry-appointment-availability'),
    );
    await tester.ensureVisible(retryButton);
    await tester.tap(retryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(availabilityRequests, 2);
    expect(find.text('8:00 AM'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('resuming after clinic hours recalculates date and slot states', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 21, 16);
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/appointments') {
        return _jsonResponse(200, []);
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked request.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
          nowProvider: () => now,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    final today = DateTime(2026, 10, 21);
    expect(calendar.selectableDayPredicate!(today), isTrue);
    expect(find.text('Available'), findsWidgets);

    now = DateTime(2026, 10, 21, 21, 52);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    final resumedCalendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(resumedCalendar.selectableDayPredicate!(today), isFalse);
    expect(find.text('3:00 PM'), findsOneWidget);
    expect(find.text('Booking Closed'), findsNWidgets(20));
    expect(find.text('Available'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('at 9:52 PM today is disabled and no slot is available', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 21, 21, 52);
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/appointments') {
        return _jsonResponse(200, []);
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked request.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
          nowProvider: () => now,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    final today = DateTime(2026, 10, 21);
    expect(calendar.selectableDayPredicate!(today), isFalse);
    expect(calendar.initialDate, isNull);

    final semantics = tester.ensureSemantics();
    final dateFinder = find.bySemanticsLabel(RegExp('October 21, 2026'));
    expect(dateFinder, findsOneWidget);
    final dateSemantics = tester.getSemantics(dateFinder);
    expect(
      dateSemantics.flagsCollection.isEnabled.toString(),
      'Tristate.isFalse',
    );
    expect(
      dateSemantics.flagsCollection.isSelected.toString(),
      isNot('Tristate.isTrue'),
    );

    for (final label in [
      '3:00 PM',
      '3:30 PM',
      '4:00 PM',
      '4:30 PM',
      '5:00 PM',
      '5:30 PM',
    ]) {
      final slot = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(slot.onPressed, isNull, reason: '$label must be unavailable');
    }
    expect(find.text('Booking Closed'), findsNWidgets(20));
    expect(find.text('Available'), findsNothing);

    await tester.ensureVisible(find.text('Confirm Appointment'));
    await tester.tap(find.text('Confirm Appointment'));
    await tester.pump();
    expect(
      find.text('Please select an available appointment time.'),
      findsOneWidget,
    );

    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('a fully reserved date is disabled by the rendered calendar', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 21, 8);
    final fullyReservedDate = DateTime(2026, 10, 22);
    final appointments = [
      for (final time in generateAppointmentTimeSlots())
        {
          'appointment_date': _formatDate(fullyReservedDate),
          'appointment_time':
              '${time.hour.toString().padLeft(2, '0')}:'
              '${time.minute.toString().padLeft(2, '0')}:00',
          'appointment_status': 'Requested',
        },
    ];
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/appointments') {
        return _jsonResponse(200, appointments);
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked request.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
          nowProvider: () => now,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(calendar.selectableDayPredicate!(fullyReservedDate), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets(
    'submission rejects a selected slot after clinic-local time advances',
    (tester) async {
      var now = DateTime(2026, 10, 21, 16, 30);
      var appointmentPosts = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/clinic-closures') {
          return _jsonResponse(200, []);
        }
        if (request.url.path == '/api/appointments' &&
            request.method == 'GET') {
          return _jsonResponse(200, []);
        }
        if (request.url.path == '/api/appointments' &&
            request.method == 'POST') {
          appointmentPosts++;
          return _jsonResponse(201, {'success': true});
        }
        return _jsonResponse(500, {'error': 'Unexpected mocked request.'});
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AppointmentSchedulerScreen(
            patientId: 'synthetic-patient',
            onScheduled: () async {},
            client: client,
            nowProvider: () => now,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      calendar.onDateChanged(DateTime(2026, 10, 21));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final lastSlot = find.text('5:30 PM');
      await tester.ensureVisible(lastSlot);
      await tester.tap(lastSlot);
      await tester.pump();
      await tester.ensureVisible(find.text('Confirm Appointment'));

      now = DateTime(2026, 10, 21, 21, 52);
      await tester.tap(find.text('Confirm Appointment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(appointmentPosts, 0);
      expect(
        find.text(
          'That appointment time is no longer available. Please choose another time.',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );

  testWidgets('submission refresh blocks a slot newly occupied by Requested', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 5, 7);
    final selectedDate = DateTime(2026, 10, 6);
    var availabilityRequests = 0;
    var appointmentPosts = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/appointments' && request.method == 'GET') {
        availabilityRequests++;
        return _jsonResponse(
          200,
          availabilityRequests >= 3
              ? [
                  {
                    'appointment_date': _formatDate(selectedDate),
                    'appointment_time': '08:00:00',
                    'appointment_status': ' Requested ',
                  },
                ]
              : [],
        );
      }
      if (request.url.path == '/api/appointments' && request.method == 'POST') {
        appointmentPosts++;
        return _jsonResponse(201, {'success': true});
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked request.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
          nowProvider: () => now,
        ),
      ),
    );
    await _prepareAppointmentSubmission(tester, selectedDate);
    await tester.ensureVisible(find.text('Confirm Appointment'));
    await tester.tap(find.text('Confirm Appointment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(availabilityRequests, greaterThanOrEqualTo(3));
    expect(appointmentPosts, 0);
    expect(
      find.text(
        'That appointment slot is already reserved. Please choose another time.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('HTTP 409 shows conflict and refreshes availability', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 5, 7);
    final selectedDate = DateTime(2026, 10, 6);
    var availabilityRequests = 0;
    var appointmentPosts = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/appointments' && request.method == 'GET') {
        availabilityRequests++;
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/appointments' && request.method == 'POST') {
        appointmentPosts++;
        return _jsonResponse(409, {'error': 'The slot was taken.'});
      }
      return _jsonResponse(500, {'error': 'Unexpected mocked request.'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          onScheduled: () async {},
          client: client,
          nowProvider: () => now,
        ),
      ),
    );
    await _prepareAppointmentSubmission(tester, selectedDate);
    await tester.ensureVisible(find.text('Confirm Appointment'));
    await tester.tap(find.text('Confirm Appointment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(appointmentPosts, 1);
    expect(availabilityRequests, greaterThanOrEqualTo(4));
    expect(find.text('The slot was taken.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  test('Date of birth must be within the 1926 to 2016 registration range', () {
    expect(isValidDateOfBirth(DateTime(1926, 1, 1)), isTrue);
    expect(isValidDateOfBirth(DateTime(2016, 12, 31)), isTrue);
    expect(isValidDateOfBirth(DateTime(1925, 12, 31)), isFalse);
    expect(isValidDateOfBirth(DateTime(2017, 1, 1)), isFalse);
  });

  test('Philippine mobile numbers must use +63 and exactly 10 digits', () {
    expect(isValidPhilippineMobileNumber('+63 9123456789'), isTrue);
    expect(isValidPhilippineMobileNumber('+639123456789'), isTrue);
    expect(isValidPhilippineMobileNumber('9123456789'), isTrue);
    expect(isValidPhilippineMobileNumber('09123456789'), isTrue);
    expect(isValidPhilippineMobileNumber('+63 912345678'), isFalse);
    expect(isValidPhilippineMobileNumber('+63 91234567890'), isFalse);
    expect(isValidPhilippineMobileNumber('+63 9123abcd89'), isFalse);
    expect(
      normalizePhilippineMobileNumber('09123456789'),
      equals('+639123456789'),
    );
    expect(
      normalizePhilippineMobileNumber('9123456789'),
      equals('+639123456789'),
    );
  });
}

Future<void> _prepareAppointmentSubmission(
  WidgetTester tester,
  DateTime selectedDate,
) async {
  final calendar = tester.widget<CalendarDatePicker>(
    find.byType(CalendarDatePicker),
  );
  calendar.onDateChanged(selectedDate);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  final firstSlot = find.text('8:00 AM');
  await tester.ensureVisible(firstSlot);
  await tester.tap(firstSlot);
  await tester.pump();
  final visitType = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(visitType);
  await tester.tap(visitType);
  await tester.pump();
  await tester.tap(find.text('Eye Examination').last);
  await tester.pump();
}

http.Response _jsonResponse(int statusCode, Object body) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

String _formatDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
