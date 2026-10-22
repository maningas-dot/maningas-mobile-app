import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';

const _clinicUtcOffset = Duration(hours: 8);

DateTime appointmentClinicLocalNow({DateTime? now, DateTime? utcNow}) {
  final clinicTime =
      now ?? (utcNow ?? DateTime.now().toUtc()).add(_clinicUtcOffset);
  return DateTime.utc(
    clinicTime.year,
    clinicTime.month,
    clinicTime.day,
    clinicTime.hour,
    clinicTime.minute,
    clinicTime.second,
    clinicTime.millisecond,
    clinicTime.microsecond,
  );
}

List<TimeOfDay> generateAppointmentTimeSlots() {
  const firstMinute = 8 * 60;
  const lastMinute = 17 * 60 + 30;
  return [
    for (var minute = firstMinute; minute <= lastMinute; minute += 30)
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
  ];
}

bool isAppointmentStatusBlocking(dynamic status) {
  final normalized = status?.toString().trim().toLowerCase() ?? '';
  return !const {
    'cancelled',
    'canceled',
    'rejected',
    'declined',
  }.contains(normalized);
}

String appointmentSlotKey(DateTime date, TimeOfDay time) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')} '
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

bool isAppointmentSlotWithinBookingCutoff(
  DateTime date,
  TimeOfDay time, {
  DateTime? now,
}) {
  final localNow = appointmentClinicLocalNow(now: now);
  if (date.year != localNow.year ||
      date.month != localNow.month ||
      date.day != localNow.day) {
    return false;
  }

  final appointmentDateTime = DateTime.utc(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  return appointmentDateTime.difference(localNow) <=
      const Duration(minutes: 20);
}

bool isAppointmentDateFullyUnavailable(
  DateTime date,
  Set<String> bookedSlots, {
  Set<DateTime> closedDates = const {},
  bool availabilityVerified = true,
  DateTime? now,
}) {
  return !availabilityVerified ||
      !isDateSelectableForBooking(date, closedDates, now: now) ||
      generateAppointmentTimeSlots().every(
        (time) => !isAppointmentSlotAvailable(
          date,
          time,
          bookedSlots,
          closedDates: closedDates,
          availabilityVerified: availabilityVerified,
          now: now,
        ),
      );
}

bool isAppointmentSlotAvailable(
  DateTime date,
  TimeOfDay time,
  Set<String> bookedSlots, {
  Set<DateTime> closedDates = const {},
  bool availabilityVerified = true,
  DateTime? now,
}) {
  return availabilityVerified &&
      isDateSelectableForBooking(date, closedDates, now: now) &&
      !isAppointmentSlotWithinBookingCutoff(date, time, now: now) &&
      !bookedSlots.contains(appointmentSlotKey(date, time));
}

bool isClinicOpenDay(DateTime date) {
  final weekday = date.weekday;

  return weekday >= DateTime.monday && weekday <= DateTime.saturday;
}

DateTime nextClinicOpenDate(DateTime date) {
  var nextDate = DateTime(date.year, date.month, date.day);

  while (!isClinicOpenDay(nextDate)) {
    nextDate = nextDate.add(const Duration(days: 1));
  }

  return nextDate;
}

bool isClinicClosedDate(DateTime date, Set<DateTime> closedDates) {
  final normalized = DateTime(date.year, date.month, date.day);

  return closedDates.any(
    (closedDate) =>
        closedDate.year == normalized.year &&
        closedDate.month == normalized.month &&
        closedDate.day == normalized.day,
  );
}

bool isDateWithinBookingWindow(DateTime date, {DateTime? now}) {
  final localNow = appointmentClinicLocalNow(now: now);
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final normalized = DateTime(date.year, date.month, date.day);
  final lastBookableDate = today.add(const Duration(days: 365));
  return !normalized.isBefore(today) && !normalized.isAfter(lastBookableDate);
}

bool isDateSelectableForBooking(
  DateTime date,
  Set<DateTime> closedDates, {
  DateTime? now,
}) {
  final normalized = DateTime(date.year, date.month, date.day);

  return isDateWithinBookingWindow(normalized, now: now) &&
      isClinicOpenDay(normalized) &&
      !isClinicClosedDate(normalized, closedDates);
}

bool canSubmitAppointmentOnDate(
  DateTime date,
  Set<DateTime> closedDates, {
  required bool closuresVerified,
  DateTime? now,
}) {
  return closuresVerified &&
      isDateSelectableForBooking(date, closedDates, now: now);
}

DateTime nextAvailableClinicDate(
  DateTime date,
  Set<DateTime> closedDates, {
  DateTime? now,
}) {
  var nextDate = DateTime(date.year, date.month, date.day);

  final localNow = appointmentClinicLocalNow(now: now);
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final lastBookableDate = today.add(const Duration(days: 365));
  while (nextDate.isBefore(lastBookableDate) ||
      nextDate.isAtSameMomentAs(lastBookableDate)) {
    if (isDateSelectableForBooking(nextDate, closedDates, now: localNow)) {
      return nextDate;
    }
    nextDate = nextDate.add(const Duration(days: 1));
  }

  return DateTime(date.year, date.month, date.day);
}

Set<DateTime> parseClinicClosureDates(dynamic data) {
  final closureDates = <DateTime>{};

  if (data is! List) {
    throw const FormatException('Invalid clinic closure response.');
  }

  for (final item in data) {
    if (item is String) {
      final date = _parseClinicClosureDate(item);
      if (date == null) {
        throw const FormatException('Invalid clinic closure date.');
      }
      closureDates.add(date);
      continue;
    }

    if (item is! Map) {
      throw const FormatException('Invalid clinic closure date.');
    }

    if (item.containsKey('start_date') || item.containsKey('end_date')) {
      final startDate = _parseClinicClosureDateOnly(
        item['start_date']?.toString() ?? '',
      );
      final endDate = _parseClinicClosureDateOnly(
        item['end_date']?.toString() ?? '',
      );
      if (startDate == null || endDate == null || startDate.isAfter(endDate)) {
        throw const FormatException('Invalid clinic closure date range.');
      }

      for (
        var date = startDate;
        !date.isAfter(endDate);
        date = date.add(const Duration(days: 1))
      ) {
        closureDates.add(date);
      }
      continue;
    }

    const legacyDateKeys = [
      'closure_date',
      'date',
      'closed_date',
      'closed_on',
      'holiday_date',
      'clinic_date',
    ];
    final legacyDateKey = legacyDateKeys.firstWhere(
      item.containsKey,
      orElse: () => '',
    );
    final date = _parseClinicClosureDate(
      legacyDateKey.isEmpty ? '' : item[legacyDateKey]?.toString() ?? '',
    );
    if (date == null) {
      throw const FormatException('Invalid clinic closure date.');
    }
    closureDates.add(date);
  }

  return closureDates;
}

Map<DateTime, Set<String>> parseClinicClosureReasons(dynamic data) {
  final closedDates = parseClinicClosureDates(data);
  final reasonsByDate = {for (final date in closedDates) date: <String>{}};

  void addReason(Iterable<DateTime> dates, dynamic rawReason) {
    final reason = rawReason is String ? rawReason.trim() : '';
    final displayReason = reason.isEmpty ? 'No reason provided.' : reason;
    for (final date in dates) {
      reasonsByDate[date]!.add(displayReason);
    }
  }

  for (final item in data as List) {
    if (item is String) {
      final date = _parseClinicClosureDate(item)!;
      addReason([date], null);
      continue;
    }

    final record = item as Map;
    if (record.containsKey('start_date') || record.containsKey('end_date')) {
      final startDate = _parseClinicClosureDateOnly(
        record['start_date']?.toString() ?? '',
      )!;
      final endDate = _parseClinicClosureDateOnly(
        record['end_date']?.toString() ?? '',
      )!;
      final dates = <DateTime>[];
      for (
        var date = startDate;
        !date.isAfter(endDate);
        date = date.add(const Duration(days: 1))
      ) {
        dates.add(date);
      }
      addReason(dates, record['reason']);
      continue;
    }

    const legacyDateKeys = [
      'closure_date',
      'date',
      'closed_date',
      'closed_on',
      'holiday_date',
      'clinic_date',
    ];
    final dateKey = legacyDateKeys.firstWhere(
      record.containsKey,
      orElse: () => '',
    );
    final date = _parseClinicClosureDate(
      dateKey.isEmpty ? '' : record[dateKey]?.toString() ?? '',
    )!;
    addReason([date], record['reason']);
  }

  return reasonsByDate;
}

DateTime? _parseClinicClosureDate(String rawDate) {
  final normalizedRaw = rawDate.trim();
  final dateMatch = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})',
  ).firstMatch(normalizedRaw);
  if (dateMatch == null) return null;

  final isDateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(normalizedRaw);
  final isIsoTimestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})?$',
  ).hasMatch(normalizedRaw);
  if (!isDateOnly && !isIsoTimestamp) return null;
  if (!isDateOnly && DateTime.tryParse(normalizedRaw) == null) return null;

  final year = int.parse(dateMatch.group(1)!);
  final month = int.parse(dateMatch.group(2)!);
  final day = int.parse(dateMatch.group(3)!);
  final normalized = DateTime(year, month, day);
  if (normalized.year != year ||
      normalized.month != month ||
      normalized.day != day) {
    return null;
  }
  return normalized;
}

DateTime? _parseClinicClosureDateOnly(String rawDate) {
  final normalizedRaw = rawDate.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(normalizedRaw)) return null;
  return _parseClinicClosureDate(normalizedRaw);
}

String clinicClosureResponseShape(dynamic data) {
  String typeOf(Object? value) {
    if (value == null) return 'null';
    if (value is List) return 'list';
    if (value is Map) return 'object';
    if (value is String) return 'string';
    if (value is num) return 'number';
    if (value is bool) return 'boolean';
    return 'other';
  }

  const dateKeys = [
    'start_date',
    'end_date',
    'closure_date',
    'date',
    'closed_date',
    'closed_on',
    'holiday_date',
    'clinic_date',
  ];

  if (data is List) {
    var supportedDateFields = 0;
    var parseableDates = 0;
    final itemFieldNames = <String>{};
    for (final item in data) {
      if (item is String) {
        if (_parseClinicClosureDate(item.trim()) != null) parseableDates++;
      } else if (item is Map) {
        for (final key in item.keys) {
          if (itemFieldNames.length >= 12) break;
          itemFieldNames.add(_safeFieldName(key));
        }
        if (item.containsKey('start_date') || item.containsKey('end_date')) {
          if (item.containsKey('start_date') && item.containsKey('end_date')) {
            supportedDateFields++;
            final startDate = _parseClinicClosureDateOnly(
              item['start_date']?.toString() ?? '',
            );
            final endDate = _parseClinicClosureDateOnly(
              item['end_date']?.toString() ?? '',
            );
            if (startDate != null &&
                endDate != null &&
                !startDate.isAfter(endDate)) {
              parseableDates++;
            }
          }
        } else {
          final key = dateKeys.firstWhere(
            (key) =>
                key != 'start_date' && key != 'end_date' && item[key] != null,
            orElse: () => '',
          );
          if (key.isEmpty) continue;
          supportedDateFields++;
          final rawDate = item[key]?.toString().trim() ?? '';
          if (rawDate.isNotEmpty && _parseClinicClosureDate(rawDate) != null) {
            parseableDates++;
          }
        }
      }
    }
    return 'jsonType=list itemCount=${data.length} '
        'itemFieldNames=${itemFieldNames.isEmpty ? 'none' : itemFieldNames.join(',')} '
        'supportedDateFieldCount=$supportedDateFields '
        'parseableDateCount=$parseableDates';
  }

  if (data is Map) {
    final fieldNames = data.keys.take(12).map(_safeFieldName).join(',');
    return 'jsonType=object '
        'fieldNames=${fieldNames.isEmpty ? 'none' : fieldNames}';
  }

  return 'jsonType=${typeOf(data)}';
}

String _safeFieldName(Object? key) {
  final name = key.toString();
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '?');
  return safe.length > 64 ? safe.substring(0, 64) : safe;
}

class AppointmentSchedulerScreen extends StatefulWidget {
  final dynamic patientId;
  final Future<void> Function() onScheduled;
  final http.Client? client;
  final DateTime Function()? nowProvider;

  const AppointmentSchedulerScreen({
    super.key,
    required this.patientId,
    required this.onScheduled,
    this.client,
    this.nowProvider,
  });

  @override
  State<AppointmentSchedulerScreen> createState() =>
      _AppointmentSchedulerScreenState();
}

class _AppointmentSchedulerScreenState extends State<AppointmentSchedulerScreen>
    with WidgetsBindingObserver {
  late final http.Client _client = widget.client ?? http.Client();
  late final bool _ownsClient = widget.client == null;
  late DateTime _selectedDate;
  late DateTime _visibleMonth;

  TimeOfDay? _selectedTime;

  String? _selectedVisitType;

  final List<String> _visitTypeOptions = [
    'Eye Examination',
    'Follow Up',
    'Frame / Eyewear',
    'Contact Lens',
  ];

  bool _creatingAppointment = false;
  bool _loadingAvailability = false;
  bool _refreshingAvailability = false;
  bool _availabilityVerified = false;
  Completer<void>? _availabilityLoadCompleter;
  int _calendarAvailabilityRevision = 0;

  String? _availabilityError;
  String? _closureError;
  bool _closuresVerified = false;
  bool _loadingClosures = true;

  Timer? _availabilityRefreshTimer;

  /*
  ============================================================
  CLINIC OPERATING TIME SLOTS
  8:00 AM - 5:30 PM
  Every 30 minutes
  ============================================================
  */

  final List<TimeOfDay> _operatingTimeSlots = generateAppointmentTimeSlots();

  /*
  ============================================================
  BOOKED SLOTS
  Example:
  2026-10-01 12:30
  ============================================================
  */

  final Set<String> _bookedSlots = {};

  final Set<DateTime> _closedDates = {};
  Map<DateTime, Set<String>> _closureReasonsByDate = {};

  /*
  ============================================================
  DATE HELPERS
  ============================================================
  */

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _timeKey(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  String _toMysqlTime(TimeOfDay time) {
    return '${_timeKey(time)}:00';
  }

  DateTime _now() => appointmentClinicLocalNow(now: widget.nowProvider?.call());

  /*
  ============================================================
  20-MINUTE BOOKING CUTOFF

  A slot becomes unavailable when there are
  20 minutes or less remaining before the appointment.

  Example:

  4:09 PM -> 4:30 PM = AVAILABLE
  4:10 PM -> 4:30 PM = BOOKING CLOSED
  4:11 PM -> 4:30 PM = BOOKING CLOSED

  Future dates are not affected by this cutoff.
  ============================================================
  */

  bool _isPastTime(TimeOfDay time) {
    return isAppointmentSlotWithinBookingCutoff(
      _selectedDate,
      time,
      now: _now(),
    );
  }

  /*
  ============================================================
  CHECK IF SLOT IS ALREADY BOOKED
  ============================================================
  */

  bool _isSlotBooked(TimeOfDay time) {
    return _bookedSlots.contains(appointmentSlotKey(_selectedDate, time));
  }

  /*
  ============================================================
  LOAD BOOKED APPOINTMENT SLOTS

  showLoading = true
  Used when the user changes the date or first opens the page.

  showLoading = false
  Used by the 10-second background refresh so the UI
  does not constantly show a loading spinner.
  ============================================================
  */

  Future<void> _loadBookedSlots({
    bool showLoading = true,
    bool forceRefresh = false,
  }) async {
    if (!mounted) return;

    if (_refreshingAvailability) {
      if (forceRefresh) {
        await _availabilityLoadCompleter?.future;
        if (!mounted) return;
        return _loadBookedSlots(showLoading: showLoading, forceRefresh: true);
      }
      return;
    }

    _refreshingAvailability = true;
    _availabilityLoadCompleter = Completer<void>();

    final currentSelectedTime = _selectedTime;

    if (showLoading) {
      setState(() {
        _loadingAvailability = true;
        _availabilityError = null;
        _availabilityVerified = false;
        _bookedSlots.clear();
      });
    }

    try {
      final uri = Uri.parse('$apiBaseUrl/api/appointments');

      debugPrint('APPOINTMENT AVAILABILITY REQUEST: $uri');

      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'APPOINTMENT AVAILABILITY STATUS: '
        '${response.statusCode}',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to load appointment availability.');
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! List) {
        throw Exception('Invalid appointment data received from server.');
      }

      final booked = <String>{};

      for (final item in decoded) {
        if (item is! Map) continue;

        if (!isAppointmentStatusBlocking(item['appointment_status'])) {
          continue;
        }

        final rawDate = item['appointment_date']?.toString().trim() ?? '';
        final rawTime = item['appointment_time']?.toString().trim() ?? '';
        final appointmentDate = rawDate.split('T').first;
        final timeMatch = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(rawTime);
        if (timeMatch == null) continue;
        final hour = int.tryParse(timeMatch.group(1)!);
        final minute = int.tryParse(timeMatch.group(2)!);
        if (hour == null ||
            minute == null ||
            hour < 0 ||
            hour > 23 ||
            minute < 0 ||
            minute > 59) {
          continue;
        }
        final appointmentTime =
            '${hour.toString().padLeft(2, '0')}:'
            '${minute.toString().padLeft(2, '0')}';
        if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(appointmentDate)) {
          booked.add('$appointmentDate $appointmentTime');
        }
      }

      if (!mounted) return;

      setState(() {
        _bookedSlots
          ..clear()
          ..addAll(booked);
        _calendarAvailabilityRevision++;
        _availabilityVerified = true;
        _availabilityError = null;

        /*
        Keep the currently selected time if it is
        still available.

        Remove it only if:
        - another booking took the slot, or
        - the 20-minute cutoff has been reached.
        */

        if (currentSelectedTime != null) {
          final selectedSlotBooked = _isSlotBooked(currentSelectedTime);

          final selectedSlotClosed = _isPastTime(currentSelectedTime);

          if (selectedSlotBooked || selectedSlotClosed) {
            _selectedTime = null;
          } else {
            _selectedTime = currentSelectedTime;
          }
        }
      });

      debugPrint('BOOKED SLOTS: $_bookedSlots');
    } catch (e, st) {
      debugPrint('APPOINTMENT AVAILABILITY ERROR: $e');

      debugPrint('APPOINTMENT AVAILABILITY STACK: $st');

      if (!mounted) return;

      setState(() {
        _calendarAvailabilityRevision++;
        _availabilityVerified = false;
        _bookedSlots.clear();
        _selectedTime = null;
        _availabilityError = 'Unable to load available appointment times.';
      });
    } finally {
      _refreshingAvailability = false;
      final loadCompleter = _availabilityLoadCompleter;
      _availabilityLoadCompleter = null;
      if (loadCompleter != null && !loadCompleter.isCompleted) {
        loadCompleter.complete();
      }

      if (mounted) {
        setState(() {
          _loadingAvailability = false;
        });
      }
    }
  }

  /*
  ============================================================
  BACKGROUND AVAILABILITY REFRESH

  Refreshes every 10 seconds without clearing the
  selected appointment time.
  ============================================================
  */

  Future<void> _refreshAvailability() async {
    if (!mounted) return;

    if (_loadingAvailability ||
        _refreshingAvailability ||
        _creatingAppointment) {
      return;
    }

    await _loadBookedSlots(showLoading: false);
    await _loadClosedDates();
  }

  String _safeContentType(String? contentType) {
    if (contentType == null) return 'unknown';
    return contentType.split(';').first.trim().toLowerCase();
  }

  Future<void> _loadClosedDates() async {
    if (!mounted) return;
    final dateBeforeRefresh = _selectedDate;
    final timeBeforeRefresh = _selectedTime;
    var responseStatusCode = 0;
    var responseContentType = 'unknown';
    var responseShape = 'unparsed';
    var failureReason = 'request_error';

    setState(() {
      _loadingClosures = true;
      _closuresVerified = false;
      _closureError = null;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/api/clinic-closures');

      debugPrint(
        'CLINIC CLOSURE REQUEST: '
        'scheme=${uri.scheme} host=${uri.host} path=${uri.path}',
      );

      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      responseStatusCode = response.statusCode;
      responseContentType = _safeContentType(response.headers['content-type']);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        failureReason = 'http_status';
        throw Exception('Failed to load clinic closure dates.');
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        responseShape = 'invalidJson';
        failureReason = 'json_decode';
        rethrow;
      }
      responseShape = clinicClosureResponseShape(decoded);
      late final Set<DateTime> nextClosedDates;
      late final Map<DateTime, Set<String>> nextClosureReasons;
      try {
        nextClosedDates = parseClinicClosureDates(decoded);
        nextClosureReasons = parseClinicClosureReasons(decoded);
      } on FormatException {
        failureReason = 'unsupported_json_shape_or_date';
        rethrow;
      }

      debugPrint(
        'CLINIC CLOSURE RESPONSE: status=$responseStatusCode '
        'contentType=$responseContentType $responseShape '
        'verification=success dateCount=${nextClosedDates.length}',
      );

      if (!mounted) return;

      setState(() {
        _closedDates.clear();
        _closedDates.addAll(nextClosedDates);
        _calendarAvailabilityRevision++;
        _closureReasonsByDate = nextClosureReasons;
        _closuresVerified = true;
        _closureError = null;

        if (!isDateSelectableForBooking(
          _selectedDate,
          _closedDates,
          now: _now(),
        )) {
          _selectedDate = nextAvailableClinicDate(
            _selectedDate,
            _closedDates,
            now: _now(),
          );
        }
        if (_selectedDate != dateBeforeRefresh) {
          _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
        }

        _selectedTime = _selectedDate == dateBeforeRefresh
            ? timeBeforeRefresh
            : null;
      });
    } catch (e) {
      debugPrint(
        'CLINIC CLOSURE FAILURE: status=$responseStatusCode '
        'contentType=$responseContentType response=$responseShape '
        'reason=$failureReason errorType=${e.runtimeType} '
        'verification=failed',
      );
      if (!mounted) return;

      setState(() {
        _calendarAvailabilityRevision++;
        _closedDates.clear();
        _closureReasonsByDate = {};
        _closuresVerified = false;
        _closureError = 'Unable to verify clinic closure dates. Try again.';
        _selectedTime = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingClosures = false;
        });
      }
    }
  }

  /*
  ============================================================
  INITIAL LOAD
  ============================================================
  */

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final now = _now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _visibleMonth = DateTime(now.year, now.month);
    if (!isDateSelectableForBooking(_selectedDate, _closedDates, now: _now())) {
      _selectedDate = nextAvailableClinicDate(
        _selectedDate,
        _closedDates,
        now: _now(),
      );
    }

    _loadClosedDates();
    _loadBookedSlots();

    /*
    Refresh appointment availability every 10 seconds.
    */

    _availabilityRefreshTimer = Timer.periodic(const Duration(seconds: 10), (
      _,
    ) {
      _refreshAvailability();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAfterResume();
    }
  }

  Future<void> _refreshAfterResume() async {
    if (!mounted) return;
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    if (_selectedDate.year != today.year ||
        _selectedDate.month != today.month ||
        _selectedDate.day != today.day) {
      setState(() {
        _calendarAvailabilityRevision++;
        _selectedDate = today;
        _visibleMonth = DateTime(today.year, today.month);
        _selectedTime = null;
      });
    } else {
      setState(() {
        _calendarAvailabilityRevision++;
      });
    }
    await _loadClosedDates();
    if (!mounted) return;
    await _loadBookedSlots(forceRefresh: true);
  }

  /*
  ============================================================
  CREATE APPOINTMENT
  ============================================================
  */

  Future<void> _createAppointment() async {
    final appointmentType = (_selectedVisitType ?? '').trim();
    final requestedDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    if (!_closuresVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Clinic closure dates could not be verified. Please try again.',
          ),
        ),
      );
      return;
    }

    await _loadClosedDates();
    if (!mounted) return;
    if (!canSubmitAppointmentOnDate(
      requestedDate,
      _closedDates,
      closuresVerified: _closuresVerified,
      now: _now(),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This date is unavailable for booking. Please choose another day.',
          ),
        ),
      );

      return;
    }

    /*
    ------------------------------------------------------------
    MAKE SURE TIME WAS SELECTED
    ------------------------------------------------------------
    */

    if (_selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an available appointment time.'),
        ),
      );

      return;
    }

    final selectedDateForSubmission = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final selectedTimeForSubmission = _selectedTime!;
    if (!_operatingTimeSlots.any(
      (time) =>
          time.hour == selectedTimeForSubmission.hour &&
          time.minute == selectedTimeForSubmission.minute,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an available appointment time.'),
        ),
      );
      return;
    }

    await _loadBookedSlots(forceRefresh: true);
    if (!mounted) return;
    if (!_availabilityVerified || _availabilityError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Appointment availability could not be verified. Please retry.',
          ),
        ),
      );
      return;
    }
    final submissionNow = _now();
    if (!isAppointmentSlotAvailable(
      selectedDateForSubmission,
      selectedTimeForSubmission,
      _bookedSlots,
      closedDates: _closedDates,
      availabilityVerified: _availabilityVerified && _closuresVerified,
      now: submissionNow,
    )) {
      final slotIsReserved = _bookedSlots.contains(
        appointmentSlotKey(
          selectedDateForSubmission,
          selectedTimeForSubmission,
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            slotIsReserved
                ? 'That appointment slot is already reserved. '
                      'Please choose another time.'
                : 'That appointment time is no longer available. '
                      'Please choose another time.',
          ),
        ),
      );
      await _loadBookedSlots();
      return;
    }
    final selectionChanged =
        selectedDateForSubmission !=
            DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
            ) ||
        _selectedTime?.hour != selectedTimeForSubmission.hour ||
        _selectedTime?.minute != selectedTimeForSubmission.minute;
    if (selectionChanged ||
        !canSubmitAppointmentOnDate(
          selectedDateForSubmission,
          _closedDates,
          closuresVerified: _closuresVerified,
          now: _now(),
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The selected appointment is no longer available. Please select it again.',
          ),
        ),
      );
      return;
    }

    /*
    ------------------------------------------------------------
    VALIDATE APPOINTMENT TYPE
    ------------------------------------------------------------
    */

    if (appointmentType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the appointment type.')),
      );

      return;
    }

    /*
    ------------------------------------------------------------
    VALIDATE PATIENT ID
    ------------------------------------------------------------
    */

    final patientId = widget.patientId?.toString().trim();

    if (patientId == null || patientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Patient ID is missing. Please log in again.'),
        ),
      );

      return;
    }

    setState(() {
      _creatingAppointment = true;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/api/appointments');

      final appointmentDate = _formatDate(selectedDateForSubmission);

      final appointmentTime = _toMysqlTime(selectedTimeForSubmission);

      /*
      The provider has been removed.

      The appointment type is now sent directly
      as the purpose of visit.
      */

      final purposeOfVisit = appointmentType;

      debugPrint('APPOINTMENT REQUEST URL: $uri');

      debugPrint(
        'APPOINTMENT REQUEST DATA: '
        'patient_id=$patientId, '
        'date=$appointmentDate, '
        'time=$appointmentTime, '
        'purpose=$purposeOfVisit',
      );

      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'patient_id': patientId,
              'appointment_date': appointmentDate,
              'appointment_time': appointmentTime,
              'purpose_of_visit': purposeOfVisit,

              /*
              Appointment requests from the mobile
              application enter the admin queue
              as Requested.
              */
              'appointment_status': 'Requested',
            }),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'APPOINTMENT REQUEST STATUS: '
        '${response.statusCode}',
      );

      debugPrint(
        'APPOINTMENT REQUEST RESPONSE: '
        '${response.body}',
      );

      final body = response.body.trim();

      Map<String, dynamic> data = {};

      if (body.isNotEmpty) {
        try {
          final decoded = jsonDecode(body);

          if (decoded is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (_) {
          debugPrint(
            'APPOINTMENT REQUEST: '
            'Invalid JSON response.',
          );
        }
      }

      if (!mounted) return;

      /*
      ----------------------------------------------------------
      SUCCESS
      ----------------------------------------------------------
      */

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointment request sent successfully!'),
          ),
        );

        _selectedVisitType = null;

        setState(() {
          _selectedTime = null;
        });

        /*
        Immediately refresh availability so the
        newly requested slot becomes unavailable.
        */

        await _loadBookedSlots();

        await widget.onScheduled();
      }
      /*
      ----------------------------------------------------------
      SLOT ALREADY RESERVED
      ----------------------------------------------------------
      */
      else if (response.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['error']?.toString() ??
                  'This time slot is already reserved.',
            ),
          ),
        );

        await _loadBookedSlots();
      }
      /*
      ----------------------------------------------------------
      BAD REQUEST
      ----------------------------------------------------------
      */
      else if (response.statusCode == 400) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['error']?.toString() ??
                  'Please provide all required appointment details.',
            ),
          ),
        );
      }
      /*
      ----------------------------------------------------------
      OTHER SERVER ERROR
      ----------------------------------------------------------
      */
      else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['error']?.toString() ??
                  data['message']?.toString() ??
                  'Could not send appointment request.',
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('APPOINTMENT REQUEST EXCEPTION: $e');

      debugPrint('APPOINTMENT REQUEST STACK: $st');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to send appointment request: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _creatingAppointment = false;
        });
      }
    }
  }

  /*
  ============================================================
  DISPOSE
  ============================================================
  */

  @override
  void dispose() {
    _availabilityRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsClient) _client.close();

    super.dispose();
  }

  /*
  ============================================================
  HEADER
  ============================================================
  */

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F76FF), Color(0xFF409CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.calendar_today, color: Colors.white, size: 32),

          const SizedBox(height: 16),

          const Text(
            'Select Appointment Date',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Selected: '
            '${_selectedDate.day}/'
            '${_selectedDate.month}/'
            '${_selectedDate.year}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  /*
  ============================================================
  CALENDAR
  ============================================================
  */

  Widget _buildCalendarCard() {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDateIsSelectable = !isAppointmentDateFullyUnavailable(
      _selectedDate,
      _bookedSlots,
      closedDates: _closedDates,
      availabilityVerified: _availabilityVerified && _closuresVerified,
      now: now,
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CalendarDatePicker(
              key: ValueKey(
                'appointment-calendar-${_formatDate(_selectedDate)}-'
                '${now.hour}:${now.minute}-$_calendarAvailabilityRevision',
              ),
              initialDate: selectedDateIsSelectable ? _selectedDate : null,
              firstDate: today,
              lastDate: today.add(const Duration(days: 365)),
              currentDate: today,
              onDisplayedMonthChanged: (date) {
                setState(() {
                  _visibleMonth = DateTime(date.year, date.month);
                });
              },
              selectableDayPredicate: (date) {
                final normalizedDate = DateTime(
                  date.year,
                  date.month,
                  date.day,
                );

                return !isAppointmentDateFullyUnavailable(
                  normalizedDate,
                  _bookedSlots,
                  closedDates: _closedDates,
                  availabilityVerified:
                      _availabilityVerified && _closuresVerified,
                  now: now,
                );
              },
              onDateChanged: (date) async {
                final normalizedDate = DateTime(
                  date.year,
                  date.month,
                  date.day,
                );

                if (!_closuresVerified ||
                    !_availabilityVerified ||
                    isAppointmentDateFullyUnavailable(
                      normalizedDate,
                      _bookedSlots,
                      closedDates: _closedDates,
                      availabilityVerified:
                          _availabilityVerified && _closuresVerified,
                      now: _now(),
                    )) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'This date is unavailable for booking. Please choose another day.',
                      ),
                    ),
                  );

                  return;
                }

                setState(() {
                  _selectedDate = normalizedDate;
                  _selectedTime = null;
                });

                await _loadBookedSlots();
              },
            ),
            if (_loadingClosures)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Verifying clinic closure dates...'),
              )
            else if (_closureError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    Text(
                      _closureError!,
                      key: const ValueKey('clinic-closure-load-error'),
                      style: TextStyle(color: Colors.red.shade700),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      key: const ValueKey('retry-clinic-closures'),
                      onPressed: _loadClosedDates,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else
              ..._closedDatesInVisibleMonth().map(
                (date) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${MaterialLocalizations.of(context).formatShortDate(date)} • CLOSED',
                        key: ValueKey('clinic-closure-${_formatDate(date)}'),
                        style: const TextStyle(
                          color: Color(0xFFB3261E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      for (final reason
                          in _closureReasonsByDate[date] ??
                              const {'No reason provided.'})
                        Text(
                          'Reason: $reason',
                          key: ValueKey(
                            'clinic-closure-reason-${_formatDate(date)}-$reason',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<DateTime> _closedDatesInVisibleMonth() {
    final dates =
        _closedDates
            .where(
              (date) =>
                  date.year == _visibleMonth.year &&
                  date.month == _visibleMonth.month,
            )
            .toList()
          ..sort((a, b) => a.compareTo(b));
    return dates;
  }

  /*
  ============================================================
  TIME SLOT CARD
  ============================================================
  */

  Widget _buildTimeCard() {
    final now = _now();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select appointment time',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            const Text(
              'Open: Monday - Saturday',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 4),

            const Text(
              'Closed on Sunday • Clinic hours: 8:00 AM - 5:30 PM',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),

            const SizedBox(height: 16),

            if (_loadingClosures)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_closureError != null || !_closuresVerified)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _closureError ??
                          'Clinic closure dates could not be verified. Appointment times are unavailable.',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('retry-clinic-closures-times'),
                      onPressed: _loadClosedDates,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (isClinicClosedDate(_selectedDate, _closedDates))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'CLOSED — No appointment times are available on this date.',
                  key: ValueKey('clinic-closed-no-times'),
                  style: TextStyle(
                    color: Color(0xFFB3261E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (_loadingAvailability)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_availabilityError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _availabilityError!,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('retry-appointment-availability'),
                      onPressed: _loadBookedSlots,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _operatingTimeSlots.map((time) {
                  final booked = _isSlotBooked(time);

                  final available = isAppointmentSlotAvailable(
                    _selectedDate,
                    time,
                    _bookedSlots,
                    closedDates: _closedDates,
                    availabilityVerified:
                        _availabilityVerified && _closuresVerified,
                    now: now,
                  );
                  final past = isAppointmentSlotWithinBookingCutoff(
                    _selectedDate,
                    time,
                    now: now,
                  );
                  final disabled = !available;

                  final selected =
                      _selectedTime != null &&
                      _selectedTime!.hour == time.hour &&
                      _selectedTime!.minute == time.minute;

                  return SizedBox(
                    width: 105,
                    child: OutlinedButton(
                      onPressed: disabled
                          ? null
                          : () {
                              if (!isAppointmentSlotAvailable(
                                _selectedDate,
                                time,
                                _bookedSlots,
                                closedDates: _closedDates,
                                availabilityVerified:
                                    _availabilityVerified && _closuresVerified,
                                now: _now(),
                              )) {
                                setState(() {
                                  _selectedTime = null;
                                });
                                return;
                              }
                              setState(() {
                                _selectedTime = time;
                              });
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),

                        backgroundColor: selected
                            ? const Color(0xFF0F76FF)
                            : booked
                            ? Colors.red.shade50
                            : disabled
                            ? Colors.grey.shade100
                            : Colors.white,

                        foregroundColor: selected
                            ? Colors.white
                            : booked
                            ? Colors.red.shade700
                            : disabled
                            ? Colors.grey
                            : const Color(0xFF0F76FF),

                        side: BorderSide(
                          color: selected
                              ? const Color(0xFF0F76FF)
                              : booked
                              ? Colors.red.shade200
                              : disabled
                              ? Colors.grey.shade300
                              : const Color(0xFF0F76FF),
                        ),

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            time.format(context),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),

                          if (booked)
                            const Text(
                              'Reserved',
                              style: TextStyle(fontSize: 10),
                            )
                          else if (past || (!available && !booked))
                            const Text(
                              'Booking Closed',
                              style: TextStyle(fontSize: 10),
                            )
                          else
                            const Text(
                              'Available',
                              style: TextStyle(fontSize: 10),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  /*
  ============================================================
  APPOINTMENT INPUT CARD

  Provider has been completely removed.
  ============================================================
  */

  Widget _buildInputCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Appointment Details',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              initialValue: _selectedVisitType,
              decoration: const InputDecoration(
                labelText: 'Purpose of Visit',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.assignment_outlined),
              ),
              hint: const Text('Select purpose of visit'),
              items: _visitTypeOptions
                  .map(
                    (option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(option),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedVisitType = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /*
  ============================================================
  CONFIRM BUTTON
  ============================================================
  */

  Widget _buildActionButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _creatingAppointment || !_closuresVerified
            ? null
            : _createAppointment,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F76FF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: _creatingAppointment
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text(
                'Confirm Appointment',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  /*
  ============================================================
  BUILD
  ============================================================
  */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointment Scheduler'),
        backgroundColor: const Color(0xFF0F76FF),
        elevation: 0,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),

              const SizedBox(height: 20),

              _buildCalendarCard(),

              const SizedBox(height: 16),

              _buildTimeCard(),

              const SizedBox(height: 16),

              _buildInputCard(),

              const SizedBox(height: 24),

              _buildActionButton(),
            ],
          ),
        ),
      ),
    );
  }
}
