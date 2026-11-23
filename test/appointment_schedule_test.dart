import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/appointment_scheduler.dart';
import 'package:optcare_app/constants.dart';
import 'package:optcare_app/main.dart';
import 'package:optcare_app/services/patient_session_service.dart';

void main() {
  testWidgets(
    'service catalog loads and confirmation cannot open without secure availability',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var globalGetCount = 0;
      var bookingPostCount = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/clinic-closures') {
          return _jsonResponse(200, []);
        }
        if (request.url.path == '/api/appointments/services') {
          return _jsonResponse(200, [
            {
              'name': 'Comprehensive Eye Check Up',
              'duration_minutes': 60,
              'legacy_names': ['Eye Examination'],
            },
            {
              'name': 'Follow-up Checkup',
              'duration_minutes': 30,
              'legacy_names': ['Follow-up'],
            },
          ]);
        }
        if (request.url.path == '/api/appointments') {
          if (request.method == 'GET') globalGetCount++;
          if (request.method == 'POST') bookingPostCount++;
        }
        return _jsonResponse(500, {'error': 'Unsafe endpoint'});
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AppointmentSchedulerScreen(
            patientId: 'synthetic-patient',
            onScheduled: () async {},
            client: client,
            nowProvider: () => DateTime(2026, 10, 5, 7),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Comprehensive Eye Check Up'), findsNothing);
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('Comprehensive Eye Check Up — 60 min'), findsOneWidget);
      expect(find.text('Follow-up Checkup — 30 min'), findsOneWidget);
      expect(globalGetCount, 0);
      expect(bookingPostCount, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );

  testWidgets('successful booking sends authenticated payload and refreshes', (
    tester,
  ) async {
    http.Request? bookingRequest;
    var availabilityRequests = 0;
    var scheduledRefreshes = 0;
    final session = await _authenticatedAppointmentSession();
    final client = MockClient((request) async {
      if (request.url.path == '/api/appointments/services') {
        return _jsonResponse(200, [
          {
            'name': 'Comprehensive Eye Check Up',
            'duration_minutes': 60,
            'legacy_names': ['Eye Examination'],
          },
        ]);
      }
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/patients/auth/me') {
        return _jsonResponse(200, {
          'success': true,
          'patient': {'patient_id': 'synthetic-patient'},
        });
      }
      if (request.url.path == '/api/appointments/patient/synthetic-patient') {
        availabilityRequests++;
        return _jsonResponse(200, []);
      }
      if (request.method == 'POST' && request.url.path == '/api/appointments') {
        bookingRequest = request;
        return _jsonResponse(201, {'success': true});
      }
      return _jsonResponse(500, {'error': 'Unexpected request'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          authenticatedPatientId: 'synthetic-patient',
          sessionService: session,
          onScheduled: () async {
            scheduledRefreshes++;
          },
          client: client,
          nowProvider: () => DateTime(2026, 10, 5, 7),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final dropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comprehensive Eye Check Up — 60 min').last);
    await tester.pumpAndSettle();

    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    calendar.onDateChanged(DateTime(2026, 10, 6));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    await tester.ensureVisible(find.text('8:00 AM'));
    await tester.tap(find.text('8:00 AM'));
    await tester.pump();

    await tester.ensureVisible(find.text('Confirm Appointment'));
    await tester.tap(find.text('Confirm Appointment'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm appointment request?'), findsOneWidget);
    await tester.tap(find.text('Book appointment'));
    await tester.pumpAndSettle();

    expect(bookingRequest, isNotNull);
    expect(bookingRequest!.headers['authorization'], 'Bearer test-token');
    expect(bookingRequest!.method, 'POST');
    expect(bookingRequest!.url.path, '/api/appointments');
    expect(jsonDecode(bookingRequest!.body), {
      'patient_id': 'synthetic-patient',
      'appointment_date': '2026-10-06',
      'appointment_time': '08:00:00',
      'purpose_of_visit': 'Comprehensive Eye Check Up',
      'appointment_status': 'Requested',
      'appointment_source': 'mobile',
    });
    expect(scheduledRefreshes, 1);
    expect(availabilityRequests, greaterThanOrEqualTo(1));
    expect(find.text('Appointment request sent successfully!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets(
    'duplicate booking submission is prevented while POST is pending',
    (tester) async {
      final postCompleter = Completer<http.Response>();
      var bookingPosts = 0;
      final session = await _authenticatedAppointmentSession();
      final client = MockClient((request) async {
        if (request.url.path == '/api/appointments/services') {
          return _jsonResponse(200, [
            {
              'name': 'Comprehensive Eye Check Up',
              'duration_minutes': 60,
              'legacy_names': ['Eye Examination'],
            },
          ]);
        }
        if (request.url.path == '/api/clinic-closures') {
          return _jsonResponse(200, []);
        }
        if (request.url.path == '/api/patients/auth/me') {
          return _jsonResponse(200, {
            'success': true,
            'patient': {'patient_id': 'synthetic-patient'},
          });
        }
        if (request.url.path == '/api/appointments/patient/synthetic-patient') {
          return _jsonResponse(200, []);
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/appointments') {
          bookingPosts++;
          return postCompleter.future;
        }
        return _jsonResponse(500, {'error': 'Unexpected request'});
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AppointmentSchedulerScreen(
            patientId: 'synthetic-patient',
            authenticatedPatientId: 'synthetic-patient',
            sessionService: session,
            onScheduled: () async {},
            client: client,
            nowProvider: () => DateTime(2026, 10, 5, 7),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprehensive Eye Check Up — 60 min').last);
      await tester.pumpAndSettle();
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      calendar.onDateChanged(DateTime(2026, 10, 6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.ensureVisible(find.text('8:00 AM'));
      await tester.tap(find.text('8:00 AM'));
      await tester.pump();
      await tester.ensureVisible(find.text('Confirm Appointment'));
      await tester.tap(find.text('Confirm Appointment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book appointment'));
      await tester.pump();

      expect(bookingPosts, 1);
      expect(find.text('Booking...'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 50));
      expect(bookingPosts, 1);

      postCompleter.complete(_jsonResponse(201, {'success': true}));
      await tester.pumpAndSettle();
      expect(
        find.text('Appointment request sent successfully!'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );

  testWidgets('409 booking conflict refreshes availability and clears time', (
    tester,
  ) async {
    var bookingPosts = 0;
    var availabilityRequests = 0;
    final session = await _authenticatedAppointmentSession();
    final client = MockClient((request) async {
      if (request.url.path == '/api/appointments/services') {
        return _jsonResponse(200, [
          {
            'name': 'Comprehensive Eye Check Up',
            'duration_minutes': 60,
            'legacy_names': ['Eye Examination'],
          },
        ]);
      }
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/patients/auth/me') {
        return _jsonResponse(200, {
          'success': true,
          'patient': {'patient_id': 'synthetic-patient'},
        });
      }
      if (request.url.path == '/api/appointments/patient/synthetic-patient') {
        availabilityRequests++;
        return _jsonResponse(200, []);
      }
      if (request.method == 'POST' && request.url.path == '/api/appointments') {
        bookingPosts++;
        return _jsonResponse(409, {'error': 'The slot was taken.'});
      }
      return _jsonResponse(500, {'error': 'Unexpected request'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          authenticatedPatientId: 'synthetic-patient',
          sessionService: session,
          onScheduled: () async {},
          client: client,
          nowProvider: () => DateTime(2026, 10, 5, 7),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final dropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comprehensive Eye Check Up — 60 min').last);
    await tester.pumpAndSettle();

    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    calendar.onDateChanged(DateTime(2026, 10, 6));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.ensureVisible(find.text('8:00 AM'));
    await tester.tap(find.text('8:00 AM'));
    await tester.pump();

    await tester.ensureVisible(find.text('Confirm Appointment'));
    await tester.tap(find.text('Confirm Appointment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book appointment'));
    await tester.pumpAndSettle();

    expect(bookingPosts, 1);
    expect(availabilityRequests, greaterThanOrEqualTo(2));
    expect(find.text('The slot was taken.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets(
    'authenticated patient availability request uses bearer and matching patient ID',
    (tester) async {
      http.Request? availabilityRequest;
      var bookingPostCount = 0;
      final session = await _authenticatedAppointmentSession();
      final client = MockClient((request) async {
        if (request.url.path == '/api/appointments/services') {
          return _jsonResponse(200, [
            {
              'name': 'Comprehensive Eye Check Up',
              'duration_minutes': 60,
              'legacy_names': ['Eye Examination'],
            },
          ]);
        }
        if (request.url.path == '/api/clinic-closures') {
          return _jsonResponse(200, []);
        }
        if (request.url.path == '/api/appointments/patient/synthetic-patient') {
          availabilityRequest = request;
          return _jsonResponse(200, [
            {
              'appointment_date': '2026-10-06',
              'appointment_time': '09:00:00',
              'purpose_of_visit': 'Eye Examination',
              'appointment_status': 'Confirmed',
            },
          ]);
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/appointments') {
          bookingPostCount++;
        }
        return _jsonResponse(500, {'error': 'Unexpected request'});
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AppointmentSchedulerScreen(
            patientId: 'synthetic-patient',
            authenticatedPatientId: 'synthetic-patient',
            sessionService: session,
            onScheduled: () async {},
            client: client,
            nowProvider: () => DateTime(2026, 10, 5, 7),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(availabilityRequest, isNotNull);
      expect(availabilityRequest!.method, 'GET');
      expect(
        availabilityRequest!.headers['authorization'],
        'Bearer test-token',
      );
      expect(bookingPostCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );

  testWidgets('expired availability session shows sign-in retry blocker', (
    tester,
  ) async {
    final session = await _authenticatedAppointmentSession();
    final client = MockClient((request) async {
      if (request.url.path == '/api/appointments/services') {
        return _jsonResponse(200, [
          {
            'name': 'Eye Examination',
            'duration_minutes': 60,
            'legacy_names': ['Eye Examination'],
          },
        ]);
      }
      if (request.url.path == '/api/clinic-closures') {
        return _jsonResponse(200, []);
      }
      if (request.url.path == '/api/appointments/patient/synthetic-patient') {
        return _jsonResponse(401, {'message': 'Unauthorized'});
      }
      return _jsonResponse(500, {'error': 'Unexpected request'});
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppointmentSchedulerScreen(
          patientId: 'synthetic-patient',
          authenticatedPatientId: 'synthetic-patient',
          sessionService: session,
          onScheduled: () async {},
          client: client,
          nowProvider: () => DateTime(2026, 10, 5, 7),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.textContaining('Your sign-in session is no longer valid'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });
  test(
    'appointment service catalog parses names durations and legacy names',
    () {
      final services = parseAppointmentServices([
        {
          'name': 'Comprehensive Eye Check Up',
          'duration_minutes': 60,
          'legacy_names': ['Eye Examination'],
        },
      ]);
      expect(services, hasLength(1));
      expect(services.single.name, 'Comprehensive Eye Check Up');
      expect(services.single.durationMinutes, 60);
      expect(services.single.legacyNames, ['Eye Examination']);
    },
  );

  test('appointment service catalog rejects invalid durations', () {
    expect(
      () => parseAppointmentServices([
        {
          'name': 'Invalid Service',
          'duration_minutes': 0,
          'legacy_names': <Object>[],
        },
      ]),
      throwsFormatException,
    );
    expect(
      () => parseAppointmentServices([
        {
          'name': 'Invalid Service',
          'duration_minutes': 30.5,
          'legacy_names': <Object>[],
        },
      ]),
      throwsFormatException,
    );
  });

  test('partial closure overlap uses closure boundary semantics', () {
    expect(
      appointmentIntervalOverlaps(
        slotStart: const TimeOfDay(hour: 9, minute: 0),
        slotDurationMinutes: 60,
        intervalStart: const TimeOfDay(hour: 10, minute: 0),
        intervalDurationMinutes: 60,
      ),
      isTrue,
    );
    expect(
      appointmentIntervalOverlaps(
        slotStart: const TimeOfDay(hour: 9, minute: 30),
        slotDurationMinutes: 60,
        intervalStart: const TimeOfDay(hour: 10, minute: 0),
        intervalDurationMinutes: 60,
      ),
      isTrue,
    );
  });

  test('appointment end time must not exceed 6 PM', () {
    expect(
      appointmentSlotFitsClinicHours(const TimeOfDay(hour: 17, minute: 30), 30),
      isTrue,
    );
    expect(
      appointmentSlotFitsClinicHours(const TimeOfDay(hour: 17, minute: 30), 60),
      isFalse,
    );
  });
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

  test('partial closure records preserve date and time intervals', () {
    final partial = parsePartialClinicClosures([
      {
        'start_date': '2026-10-06',
        'end_date': '2026-10-06',
        'start_time': '12:00',
        'end_time': '14:00',
      },
    ]);
    final closures = partial[DateTime(2026, 10, 6)]!;
    expect(closures, hasLength(1));
    expect(closures.single.start, const TimeOfDay(hour: 12, minute: 0));
    expect(closures.single.end, const TimeOfDay(hour: 14, minute: 0));
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
        'Completed',
      ]) {
        expect(isAppointmentStatusBlocking(status), isFalse);
      }
    },
  );

  test('cancellation eligibility requires a future supported appointment', () {
    final now = DateTime(2026, 11, 12, 9);
    for (final status in [' Requested ', 'Pending', 'CONFIRMED']) {
      expect(
        isAppointmentCancellationEligible({
          'appointment_status': status,
          'appointment_date': '2026-11-12',
          'appointment_time': '09:01:00',
        }, now: now),
        isTrue,
      );
    }

    for (final status in [
      'Cancelled',
      'Rejected',
      'Approved',
      'Scheduled',
      'Accepted',
      'Other',
    ]) {
      expect(
        isAppointmentCancellationEligible({
          'appointment_status': status,
          'appointment_date': '2026-11-12',
          'appointment_time': '10:00:00',
        }, now: now),
        isFalse,
      );
    }

    expect(
      isAppointmentCancellationEligible({
        'appointment_status': 'Confirmed',
        'appointment_date': '2026-11-12',
        'appointment_time': '09:00:00',
      }, now: now),
      isFalse,
    );
    expect(
      isAppointmentCancellationEligible({
        'appointment_status': 'Pending',
        'appointment_date': '2026-11-11',
        'appointment_time': '10:00:00',
      }, now: now),
      isFalse,
    );
    expect(
      isAppointmentCancellationEligible({
        'appointment_status': 'Pending',
        'appointment_date': 'invalid',
        'appointment_time': '10:00',
      }, now: now),
      isFalse,
    );
  });

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
      isFalse,
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

  testWidgets(
    'appointment terms link opens all five terms and closing preserves selections',
    (tester) async {
      final now = DateTime(2026, 10, 5, 7);
      final client = MockClient((request) async {
        if (request.url.path == '/api/clinic-closures') {
          return _jsonResponse(200, []);
        }
        if (request.url.path == '/api/appointments/services') {
          return _jsonResponse(200, [
            {
              'name': 'Eye Examination',
              'duration_minutes': 60,
              'legacy_names': ['Eye Examination'],
            },
          ]);
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
      final selectedDateText = find.textContaining('Selected:');
      final dateBeforeDialog = tester.widget<Text>(selectedDateText).data;
      final termsLink = find.byKey(const ValueKey('appointment-terms-link'));
      await tester.ensureVisible(termsLink);
      await tester.tap(termsLink);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Appointment Terms & Conditions'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('appointment-terms-scroll')),
        findsOneWidget,
      );
      for (final term in [
        '1. Select an available date from today through the next 12 months. '
            'Past dates, Sundays, and clinic closure dates cannot be booked.',
        '2. Choose an available time slot. Slots are offered in 30-minute '
            'intervals from 8:00 AM to 5:30 PM. Availability can change; if a '
            'slot is taken before your request is submitted, select another '
            'available time.',
        '3. Choose the purpose that best matches your visit: Eye Examination, '
            'Follow-up, Frame / Eyewear, Contact Lens. Review the selected date, '
            'time, and purpose before submitting.',
        '4. Submitting creates an appointment request, not a confirmed '
            'appointment. The clinic must approve the request before it is '
            'confirmed.',
        '5. You can cancel an eligible upcoming appointment from My '
            'Appointments. Cancellation cannot be undone. To request a '
            'different time, cancel the existing appointment if eligible, then '
            'submit a new request for an available slot.',
      ]) {
        expect(find.text(term), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey('appointment-terms-close')));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(tester.widget<Text>(selectedDateText).data, dateBeforeDialog);
      expect(find.text('8:00 AM'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );

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

  testWidgets('closure changes remain fail-closed and POST stays blocked', (
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

    expect(closureFetches, greaterThanOrEqualTo(1));
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

  testWidgets(
    'secure availability blocker is shown and no global request occurs',
    (tester) async {
      var globalAvailabilityRequests = 0;
      var bookingPosts = 0;
      final now = DateTime(2026, 10, 5, 7);
      final client = MockClient((request) async {
        if (request.url.path == '/api/clinic-closures') {
          return _jsonResponse(200, []);
        }
        if (request.url.path == '/api/appointments/services') {
          return _jsonResponse(200, [
            {
              'name': 'Comprehensive Eye Check Up',
              'duration_minutes': 60,
              'legacy_names': ['Eye Examination'],
            },
          ]);
        }
        if (request.url.path == '/api/appointments') {
          if (request.method == 'GET') globalAvailabilityRequests++;
          if (request.method == 'POST') bookingPosts++;
          return _jsonResponse(500, {
            'error': 'Unsafe endpoint must not be called',
          });
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
        find.textContaining(
          'Secure patient appointment availability is unavailable',
        ),
        findsOneWidget,
      );
      expect(find.text('8:00 AM'), findsNothing);
      expect(globalAvailabilityRequests, 0);
      expect(bookingPosts, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );

  testWidgets(
    'resuming after clinic hours recalculates date safeguards securely',
    (tester) async {
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
      expect(calendar.selectableDayPredicate!(today), isFalse);
      expect(
        find.textContaining(
          'Secure patient appointment availability is unavailable',
        ),
        findsOneWidget,
      );
      expect(find.text('Available'), findsNothing);

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
      expect(find.text('3:00 PM'), findsNothing);
      expect(find.text('Booking Closed'), findsNothing);
      expect(find.text('Available'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );

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

    expect(find.text('3:00 PM'), findsNothing);
    expect(find.text('Booking Closed'), findsNothing);
    expect(find.text('Available'), findsNothing);
    expect(
      find.textContaining(
        'Secure patient appointment availability is unavailable',
      ),
      findsOneWidget,
    );

    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('fully reserved mock is never fetched as patient availability', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 21, 8);
    final fullyReservedDate = DateTime(2026, 10, 22);
    var globalAvailabilityRequests = 0;
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
        globalAvailabilityRequests++;
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
    expect(globalAvailabilityRequests, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets(
    'clinic-local cutoff remains client-side without unsafe submission',
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
      now = DateTime(2026, 10, 21, 21, 52);
      expect(appointmentPosts, 0);
      expect(
        find.textContaining(
          'Secure patient appointment availability is unavailable',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );

  testWidgets('Requested mock never triggers unsafe availability or booking', (
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
    await tester.pump(const Duration(milliseconds: 100));
    expect(availabilityRequests, 0);
    expect(appointmentPosts, 0);
    expect(
      find.textContaining(
        'Secure patient appointment availability is unavailable',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
  });

  testWidgets('HTTP 409 conflict path is not used without secure booking', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 5, 7);
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
    await tester.pump(const Duration(milliseconds: 100));
    expect(appointmentPosts, 0);
    expect(availabilityRequests, 0);
    expect(
      find.textContaining(
        'Secure patient appointment availability is unavailable',
      ),
      findsOneWidget,
    );

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

Future<PatientSessionService> _authenticatedAppointmentSession() async {
  final session = PatientSessionService(
    tokenStorage: _AppointmentMemoryTokenStorage(),
    client: MockClient((request) async {
      return _jsonResponse(200, {
        'token': 'test-token',
        'patient': {'patient_id': 'synthetic-patient'},
      });
    }),
  );
  await session.login(
    email: 'patient@example.test',
    password: 'password',
    rememberMe: false,
  );
  return session;
}

class _AppointmentMemoryTokenStorage implements PatientTokenStorage {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async {
    _token = token;
  }

  @override
  Future<void> deleteToken() async {
    _token = null;
  }
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
