import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'services/patient_session_service.dart';

const _clinicUtcOffset = Duration(hours: 8);

class AppointmentServiceOption {
  const AppointmentServiceOption({
    required this.name,
    required this.durationMinutes,
    required this.legacyNames,
  });

  final String name;
  final int durationMinutes;
  final List<String> legacyNames;
}

class PartialClinicClosure {
  const PartialClinicClosure({required this.start, required this.end});

  final TimeOfDay start;
  final TimeOfDay end;
}

class AppointmentInterval {
  const AppointmentInterval({required this.start, required this.end});

  final TimeOfDay start;
  final TimeOfDay end;
}

List<AppointmentServiceOption> parseAppointmentServices(dynamic data) {
  if (data is! List) {
    throw const FormatException('Invalid appointment service response.');
  }

  final services = <AppointmentServiceOption>[];
  for (final item in data) {
    if (item is! Map) {
      throw const FormatException('Invalid appointment service record.');
    }
    final name = item['name']?.toString().trim() ?? '';
    final duration = item['duration_minutes'];
    final durationMinutes = duration is int
        ? duration
        : duration is String
        ? int.tryParse(duration.trim())
        : null;
    if (name.isEmpty || durationMinutes == null || durationMinutes <= 0) {
      throw const FormatException('Invalid appointment service record.');
    }

    final rawLegacyNames = item['legacy_names'];
    if (rawLegacyNames != null && rawLegacyNames is! List) {
      throw const FormatException('Invalid appointment service legacy names.');
    }
    final legacyNames = rawLegacyNames is List
        ? rawLegacyNames
              .whereType<Object>()
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    services.add(
      AppointmentServiceOption(
        name: name,
        durationMinutes: durationMinutes,
        legacyNames: legacyNames,
      ),
    );
  }
  return services;
}

TimeOfDay? parseClinicClosureTime(dynamic rawValue) {
  final raw = rawValue?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(raw);
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    return null;
  }
  return TimeOfDay(hour: hour, minute: minute);
}

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
    'completed',
  }.contains(normalized);
}

bool isAppointmentCancellationEligible(dynamic appointment, {DateTime? now}) {
  if (appointment is! Map) return false;

  final status =
      (appointment['appointment_status'] ?? appointment['status'])
          ?.toString()
          .trim()
          .toLowerCase() ??
      '';
  if (!const {'requested', 'pending', 'confirmed'}.contains(status)) {
    return false;
  }

  final rawDate = appointment['appointment_date']?.toString().trim() ?? '';
  final rawTime = appointment['appointment_time']?.toString().trim() ?? '';
  if (rawDate.isEmpty || rawTime.isEmpty) return false;

  final appointmentDateTime = DateTime.tryParse(
    '${rawDate.split('T').first}T${rawTime.split('T').last}',
  );
  return appointmentDateTime != null &&
      appointmentDateTime.isAfter(now ?? DateTime.now());
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

int _timeOfDayMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

bool appointmentIntervalOverlaps({
  required TimeOfDay slotStart,
  required int slotDurationMinutes,
  required TimeOfDay intervalStart,
  required int intervalDurationMinutes,
}) {
  final slotStartMinutes = _timeOfDayMinutes(slotStart);
  final slotEndMinutes = slotStartMinutes + slotDurationMinutes;
  final intervalStartMinutes = _timeOfDayMinutes(intervalStart);
  final intervalEndMinutes = intervalStartMinutes + intervalDurationMinutes;
  return slotStartMinutes < intervalEndMinutes &&
      slotEndMinutes >= intervalStartMinutes;
}

bool appointmentSlotFitsClinicHours(TimeOfDay start, int durationMinutes) {
  final endMinutes = _timeOfDayMinutes(start) + durationMinutes;
  return endMinutes <= 18 * 60;
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
      if (item['start_time'] != null && item['end_time'] != null) {
        continue;
      }
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
      if (record['start_time'] != null && record['end_time'] != null) {
        final startDate = _parseClinicClosureDateOnly(
          record['start_date']?.toString() ?? '',
        );
        final endDate = _parseClinicClosureDateOnly(
          record['end_date']?.toString() ?? '',
        );
        if (startDate != null && endDate != null) {
          final rawReason =
              record['reason'] ??
              record['closure_reason'] ??
              record['description'];
          final reason = rawReason is String && rawReason.trim().isNotEmpty
              ? rawReason.trim()
              : 'No reason provided.';
          for (
            var date = startDate;
            !date.isAfter(endDate);
            date = date.add(const Duration(days: 1))
          ) {
            reasonsByDate.putIfAbsent(date, () => <String>{}).add(reason);
          }
        }
        continue;
      }
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
      addReason(
        dates,
        record['reason'] ?? record['closure_reason'] ?? record['description'],
      );
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
    addReason([
      date,
    ], record['reason'] ?? record['closure_reason'] ?? record['description']);
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

Map<DateTime, List<PartialClinicClosure>> parsePartialClinicClosures(
  dynamic data,
) {
  if (data is! List) {
    throw const FormatException('Invalid clinic closure response.');
  }

  final result = <DateTime, List<PartialClinicClosure>>{};
  for (final item in data) {
    if (item is! Map) continue;
    final startDate = _parseClinicClosureDateOnly(
      item['start_date']?.toString() ?? '',
    );
    final endDate = _parseClinicClosureDateOnly(
      item['end_date']?.toString() ?? '',
    );
    final rawStartTime = item['start_time'];
    final rawEndTime = item['end_time'];
    if (startDate == null ||
        endDate == null ||
        rawStartTime == null ||
        rawEndTime == null) {
      continue;
    }

    final startTime = parseClinicClosureTime(rawStartTime);
    final endTime = parseClinicClosureTime(rawEndTime);
    if (startTime == null ||
        endTime == null ||
        _timeOfDayMinutes(endTime) <= _timeOfDayMinutes(startTime)) {
      continue;
    }

    for (
      var date = startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))
    ) {
      result
          .putIfAbsent(date, () => [])
          .add(PartialClinicClosure(start: startTime, end: endTime));
    }
  }
  return result;
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
  final String? authenticatedPatientId;
  final PatientSessionService? sessionService;
  final Future<void> Function() onScheduled;
  final http.Client? client;
  final DateTime Function()? nowProvider;

  const AppointmentSchedulerScreen({
    super.key,
    required this.patientId,
    this.authenticatedPatientId,
    this.sessionService,
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
  late final PatientSessionService? _sessionService = widget.sessionService;
  late final bool _ownsClient = widget.client == null;
  late DateTime _selectedDate;
  late DateTime _visibleMonth;

  TimeOfDay? _selectedTime;

  String? _selectedVisitType;
  List<AppointmentServiceOption> _serviceOptions = const [];
  bool _loadingServices = true;
  String? _serviceLoadError;

  AppointmentServiceOption? get _selectedService {
    final selected = (_selectedVisitType ?? '').trim();
    if (selected.isEmpty) return null;
    for (final service in _serviceOptions) {
      if (service.name == selected) return service;
      if (service.legacyNames.any(
        (legacyName) => legacyName.toLowerCase() == selected.toLowerCase(),
      )) {
        return service;
      }
    }
    return null;
  }

  int? _durationForAppointmentPurpose(String purpose) {
    final normalized = purpose.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final service in _serviceOptions) {
      if (service.name.toLowerCase() == normalized) {
        return service.durationMinutes;
      }
      if (service.legacyNames.any(
        (legacyName) => legacyName.toLowerCase() == normalized,
      )) {
        return service.durationMinutes;
      }
    }
    return null;
  }

  bool _loadingAvailability = false;
  bool _refreshingAvailability = false;
  bool _availabilityVerified = false;
  bool _isSubmitting = false;
  bool _availabilityRequestInFlight = false;
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
  Map<DateTime, List<PartialClinicClosure>> _partialClosuresByDate = {};
  Map<DateTime, List<AppointmentInterval>> _appointmentIntervalsByDate = {};
  int _serviceRequestGeneration = 0;
  int _availabilityRequestGeneration = 0;

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

  String _formatEndTime(TimeOfDay start, int durationMinutes) {
    final totalMinutes = start.hour * 60 + start.minute + durationMinutes;
    final hour = (totalMinutes ~/ 60) % 24;
    final minute = totalMinutes % 60;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  String _formatTime(TimeOfDay time) => time.format(context);

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

  /*
  ============================================================
  CHECK IF SLOT IS ALREADY BOOKED
  ============================================================
  */

  bool _isSlotBooked(TimeOfDay time) {
    return _bookedSlots.contains(appointmentSlotKey(_selectedDate, time));
  }

  bool _isSlotAvailableForSelectedService(TimeOfDay time) {
    final service = _selectedService;
    if (service == null) return false;
    if (!appointmentSlotFitsClinicHours(time, service.durationMinutes)) {
      return false;
    }
    if (!isAppointmentSlotAvailable(
      _selectedDate,
      time,
      _bookedSlots,
      closedDates: _closedDates,
      availabilityVerified: _availabilityVerified && _closuresVerified,
      now: _now(),
    )) {
      return false;
    }

    final partialClosures =
        _partialClosuresByDate[_selectedDate] ?? const <PartialClinicClosure>[];
    for (final closure in partialClosures) {
      if (appointmentIntervalOverlaps(
        slotStart: time,
        slotDurationMinutes: service.durationMinutes,
        intervalStart: closure.start,
        intervalDurationMinutes:
            _timeOfDayMinutes(closure.end) - _timeOfDayMinutes(closure.start),
      )) {
        return false;
      }
    }
    final appointmentIntervals =
        _appointmentIntervalsByDate[_selectedDate] ??
        const <AppointmentInterval>[];
    for (final appointment in appointmentIntervals) {
      if (appointmentIntervalOverlaps(
        slotStart: time,
        slotDurationMinutes: service.durationMinutes,
        intervalStart: appointment.start,
        intervalDurationMinutes:
            _timeOfDayMinutes(appointment.end) -
            _timeOfDayMinutes(appointment.start),
      )) {
        return false;
      }
    }
    return true;
  }

  void _isolateUnsafeAvailability() {
    if (!mounted) return;
    ++_availabilityRequestGeneration;
    setState(() {
      _refreshingAvailability = false;
      _loadingAvailability = false;
      _availabilityRequestInFlight = false;
      _availabilityVerified = false;
      _bookedSlots.clear();
      _selectedTime = null;
      _availabilityError =
          'Secure patient appointment availability is unavailable. '
          'Booking is temporarily disabled until secure backend availability is provided.';
    });
  }

  Future<void> _loadServices() async {
    if (!mounted) return;
    final generation = ++_serviceRequestGeneration;
    setState(() {
      _loadingServices = true;
      _serviceLoadError = null;
    });
    try {
      final uri = Uri.parse('$apiBaseUrl/api/appointments/services');
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 404) {
        if (!mounted || generation != _serviceRequestGeneration) return;
        setState(() {
          _serviceOptions = const [];
          _selectedVisitType = null;
          _selectedTime = null;
          _serviceLoadError =
              'No appointment services are currently available.';
          _loadingServices = false;
        });
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to load appointment services.');
      }
      final decoded = jsonDecode(response.body);
      final services = parseAppointmentServices(decoded);
      if (!mounted || generation != _serviceRequestGeneration) return;
      setState(() {
        _serviceOptions = services;
        _loadingServices = false;
        if (_selectedVisitType != null &&
            !services.any((service) => service.name == _selectedVisitType)) {
          _selectedVisitType = null;
          _selectedTime = null;
        }
      });
    } catch (_) {
      if (!mounted || generation != _serviceRequestGeneration) return;
      setState(() {
        _serviceOptions = const [];
        _serviceLoadError =
            'Unable to load appointment services. Please try again.';
        _loadingServices = false;
      });
    }
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
    await _loadPatientAvailability();
  }

  Future<void> _loadPatientAvailability() async {
    if (!mounted) return;
    if (_availabilityRequestInFlight) return;
    final generation = ++_availabilityRequestGeneration;

    final patientId = widget.patientId?.toString().trim() ?? '';
    final authenticatedPatientId = (widget.authenticatedPatientId ?? '').trim();
    final token = _sessionService?.token?.trim() ?? '';
    if (patientId.isEmpty ||
        authenticatedPatientId.isEmpty ||
        patientId != authenticatedPatientId ||
        token.isEmpty) {
      _isolateUnsafeAvailability();
      return;
    }

    setState(() {
      _loadingAvailability = true;
      _availabilityError = null;
      _availabilityVerified = false;
      _availabilityRequestInFlight = true;
    });

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/api/appointments/patient/${Uri.encodeComponent(patientId)}',
      );
      final response = await _client
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted || generation != _availabilityRequestGeneration) return;
      if (response.statusCode == 401 || response.statusCode == 403) {
        setState(() {
          _loadingAvailability = false;
          _availabilityRequestInFlight = false;
          _availabilityVerified = false;
          _availabilityError =
              'Your sign-in session is no longer valid. Please sign in again.';
          _appointmentIntervalsByDate = {};
          _bookedSlots.clear();
          _selectedTime = null;
        });
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to load patient appointment availability.');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException(
          'Invalid patient appointment availability response.',
        );
      }

      final bookedSlots = <String>{};
      final intervals = <DateTime, List<AppointmentInterval>>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final status = (item['appointment_status'] ?? item['status'])
            ?.toString()
            .trim()
            .toLowerCase();
        if (!isAppointmentStatusBlocking(status)) continue;

        final rawDate =
            (item['appointment_date'] ?? item['date'])?.toString().trim() ?? '';
        final rawTime =
            (item['appointment_time'] ?? item['time'])?.toString().trim() ?? '';
        final appointmentDate = _parseClinicClosureDate(
          rawDate.split('T').first,
        );
        final startTime = parseClinicClosureTime(rawTime);
        if (appointmentDate == null || startTime == null) continue;

        final purpose =
            (item['purpose_of_visit'] ??
                    item['purpose'] ??
                    item['appointment_type'])
                ?.toString()
                .trim() ??
            '';
        var durationMinutes = _durationForAppointmentPurpose(purpose);

        final rawEndTime =
            (item['appointment_end_time'] ??
                    item['end_time'] ??
                    item['appointment_end'])
                ?.toString()
                .trim();
        final storedEnd = parseClinicClosureTime(rawEndTime);
        if (storedEnd != null &&
            _timeOfDayMinutes(storedEnd) > _timeOfDayMinutes(startTime)) {
          durationMinutes =
              _timeOfDayMinutes(storedEnd) - _timeOfDayMinutes(startTime);
        }
        durationMinutes ??= 30;

        final endMinutes = _timeOfDayMinutes(startTime) + durationMinutes;
        final endTime = TimeOfDay(
          hour: (endMinutes ~/ 60) % 24,
          minute: endMinutes % 60,
        );
        bookedSlots.add(appointmentSlotKey(appointmentDate, startTime));
        intervals
            .putIfAbsent(appointmentDate, () => [])
            .add(AppointmentInterval(start: startTime, end: endTime));
      }

      setState(() {
        _bookedSlots
          ..clear()
          ..addAll(bookedSlots);
        _appointmentIntervalsByDate = intervals;
        _loadingAvailability = false;
        _availabilityRequestInFlight = false;
        _refreshingAvailability = false;
        _availabilityVerified = true;
        _availabilityError = null;
        _calendarAvailabilityRevision++;
      });
    } on TimeoutException {
      if (!mounted || generation != _availabilityRequestGeneration) return;
      setState(() {
        _loadingAvailability = false;
        _availabilityRequestInFlight = false;
        _availabilityVerified = false;
        _availabilityError =
            'The appointment availability request timed out. Please try again.';
        _selectedTime = null;
      });
    } on http.ClientException {
      if (!mounted || generation != _availabilityRequestGeneration) return;
      setState(() {
        _loadingAvailability = false;
        _availabilityRequestInFlight = false;
        _availabilityVerified = false;
        _availabilityError =
            'Unable to reach the clinic service. Check your connection.';
        _selectedTime = null;
      });
    } catch (_) {
      if (!mounted || generation != _availabilityRequestGeneration) return;
      setState(() {
        _loadingAvailability = false;
        _availabilityRequestInFlight = false;
        _availabilityVerified = false;
        _availabilityError = 'Unable to load patient appointment availability.';
        _selectedTime = null;
      });
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

    if (_loadingAvailability || _refreshingAvailability) {
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
      late final Map<DateTime, List<PartialClinicClosure>> partialClosures;
      try {
        nextClosedDates = parseClinicClosureDates(decoded);
        nextClosureReasons = parseClinicClosureReasons(decoded);
        partialClosures = parsePartialClinicClosures(decoded);
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
        _partialClosuresByDate = partialClosures;
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
        _partialClosuresByDate = {};
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

    _loadServices();
    _loadClosedDates();
    _loadPatientAvailability();

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

  Future<String?> _authenticatedPatientIdFromSession() async {
    final token = _sessionService?.token?.trim();
    if (token == null || token.isEmpty) return null;
    final response = await _client
        .get(
          Uri.parse('$apiBaseUrl/api/patients/auth/me'),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final patient = map['patient'] is Map
          ? Map<String, dynamic>.from(map['patient'] as Map)
          : map['data'] is Map
          ? Map<String, dynamic>.from(map['data'] as Map)
          : map;
      final id = (patient['patient_id'] ?? patient['user_id'] ?? patient['id'])
          ?.toString()
          .trim();
      return id?.isNotEmpty == true ? id : null;
    }
    return null;
  }

  Future<void> _submitAppointment({
    required DateTime selectedDate,
    required TimeOfDay selectedTime,
    required String patientId,
    required String authenticatedPatientId,
    required AppointmentServiceOption service,
  }) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final serverPatientId = await _authenticatedPatientIdFromSession();
      if (!mounted) return;
      if (serverPatientId == null ||
          serverPatientId != patientId ||
          serverPatientId != authenticatedPatientId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your patient account could not be verified. Please sign in again.',
            ),
          ),
        );
        return;
      }

      await _loadPatientAvailability();
      if (!mounted) return;
      if (!_availabilityVerified || _availabilityError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _availabilityError ??
                  'Appointment availability could not be verified.',
            ),
          ),
        );
        return;
      }

      if (!_isSlotAvailableForSelectedService(selectedTime) ||
          !appointmentSlotFitsClinicHours(
            selectedTime,
            service.durationMinutes,
          )) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That appointment time is no longer available. Please choose another time.',
            ),
          ),
        );
        await _loadPatientAvailability();
        return;
      }

      final token = _sessionService?.token?.trim();
      if (token == null || token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in again to book an appointment.'),
          ),
        );
        return;
      }

      final appointmentDate =
          '${selectedDate.year.toString().padLeft(4, '0')}-'
          '${selectedDate.month.toString().padLeft(2, '0')}-'
          '${selectedDate.day.toString().padLeft(2, '0')}';
      final appointmentTime =
          '${selectedTime.hour.toString().padLeft(2, '0')}:'
          '${selectedTime.minute.toString().padLeft(2, '0')}:00';

      final response = await _client
          .post(
            Uri.parse('$apiBaseUrl/api/appointments'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'patient_id': serverPatientId,
              'appointment_date': appointmentDate,
              'appointment_time': appointmentTime,
              'purpose_of_visit': service.name,
              'appointment_status': 'Requested',
              'appointment_source': 'mobile',
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } on FormatException {
        data = {};
      }

      if (response.statusCode == 201 ||
          (response.statusCode == 200 && data['success'] == true)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointment request sent successfully!'),
          ),
        );
        setState(() {
          _selectedVisitType = null;
          _selectedTime = null;
        });
        await widget.onScheduled();
        await _loadPatientAvailability();
        return;
      }

      if (response.statusCode == 409) {
        await _loadPatientAvailability();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['error']?.toString() ??
                  data['message']?.toString() ??
                  'This time slot was just reserved. Please select another time.',
            ),
          ),
        );
        setState(() => _selectedTime = null);
        return;
      }

      String message;
      switch (response.statusCode) {
        case 400:
          message =
              data['error']?.toString() ??
              data['message']?.toString() ??
              'Please review the appointment details and try again.';
          break;
        case 401:
        case 403:
          message =
              'Your sign-in session is no longer valid. Please sign in again.';
          break;
        case 500:
          message =
              'The clinic could not create the appointment. Please try again.';
          break;
        default:
          message =
              data['error']?.toString() ??
              data['message']?.toString() ??
              'The appointment could not be submitted. Please try again.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The request timed out. Please try again.'),
        ),
      );
    } on http.ClientException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to reach the clinic service. Check your connection.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The appointment could not be submitted. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

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

    final authenticatedPatientId = (widget.authenticatedPatientId ?? patientId)
        .trim();
    if (authenticatedPatientId != patientId ||
        _sessionService?.token?.trim().isNotEmpty != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Secure patient appointment booking is unavailable. '
            'Please sign in again with a verified patient account.',
          ),
        ),
      );
      return;
    }

    final service = _selectedService;
    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a valid appointment service.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm appointment request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${_formatDate(selectedDateForSubmission)}'),
            const SizedBox(height: 6),
            Text(
              'Time: ${selectedTimeForSubmission.format(context)} '
              '– ${_formatEndTime(selectedTimeForSubmission, service.durationMinutes)}',
            ),
            const SizedBox(height: 6),
            Text('Purpose: ${service.name}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Review details'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Book appointment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _submitAppointment(
      selectedDate: selectedDateForSubmission,
      selectedTime: selectedTimeForSubmission,
      patientId: patientId,
      authenticatedPatientId: authenticatedPatientId,
      service: service,
    );
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
            else ...[
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
              ..._partialClosuresInVisibleMonth().map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${MaterialLocalizations.of(context).formatShortDate(entry.$1)} • PARTIAL CLOSURE',
                        key: ValueKey(
                          'partial-clinic-closure-${_formatDate(entry.$1)}',
                        ),
                        style: const TextStyle(
                          color: Color(0xFFB3261E),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      for (final closure in entry.$2)
                        Text(
                          '${_formatTime(closure.start)}–${_formatTime(closure.end)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      for (final reason
                          in _closureReasonsByDate[entry.$1] ??
                              const {'No reason provided.'})
                        Text(
                          'Reason: $reason',
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

  List<(DateTime, List<PartialClinicClosure>)>
  _partialClosuresInVisibleMonth() {
    final entries =
        _partialClosuresByDate.entries
            .where(
              (entry) =>
                  entry.key.year == _visibleMonth.year &&
                  entry.key.month == _visibleMonth.month,
            )
            .map((entry) => (entry.key, entry.value))
            .toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    return entries;
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

            if (_selectedTime != null && _selectedService != null) ...[
              const SizedBox(height: 8),
              Text(
                'Selected time: ${_selectedTime!.format(context)} '
                '– ${_formatEndTime(_selectedTime!, _selectedService!.durationMinutes)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F76FF),
                ),
              ),
            ],

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

                  final available = _isSlotAvailableForSelectedService(time);
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
                              if (!_isSlotAvailableForSelectedService(time)) {
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

            if (_loadingServices)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else if (_serviceLoadError != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _serviceLoadError!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                  TextButton(
                    onPressed: _loadServices,
                    child: const Text('Retry'),
                  ),
                ],
              )
            else if (_serviceOptions.isEmpty)
              const Text(
                'No appointment services are currently available.',
                style: TextStyle(color: Colors.black54),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedVisitType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Purpose of Visit',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.assignment_outlined),
                ),
                hint: const Text('Select purpose of visit'),
                selectedItemBuilder: (context) => _serviceOptions
                    .map(
                      (service) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${service.name} — ${service.durationMinutes} min',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                items: _serviceOptions
                    .map(
                      (service) => DropdownMenuItem<String>(
                        value: service.name,
                        child: Text(
                          '${service.name} — ${service.durationMinutes} min',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedVisitType = value;
                    _selectedTime = null;
                  });
                  _calendarAvailabilityRevision++;
                  setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAppointmentTerms() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final maxHeight = MediaQuery.sizeOf(dialogContext).height * 0.85;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Appointment Terms & Conditions',
                          style: TextStyle(
                            color: Color(0xFF172B4D),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('appointment-terms-close-icon'),
                        tooltip: 'Close Appointment Terms & Conditions',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('appointment-terms-scroll'),
                    padding: const EdgeInsets.all(20),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '1. Select an available date from today through the '
                          'next 12 months. Past dates, Sundays, and clinic '
                          'closure dates cannot be booked.',
                        ),
                        SizedBox(height: 14),
                        Text(
                          '2. Choose an available time slot. Slots are offered '
                          'in 30-minute intervals from 8:00 AM to 5:30 PM. '
                          'Availability can change; if a slot is taken before '
                          'your request is submitted, select another available '
                          'time.',
                        ),
                        SizedBox(height: 14),
                        Text(
                          '3. Choose the purpose that best matches your visit: '
                          'Eye Examination, Follow-up, Frame / Eyewear, Contact '
                          'Lens. Review the selected date, time, and purpose '
                          'before submitting.',
                        ),
                        SizedBox(height: 14),
                        Text(
                          '4. Submitting creates an appointment request, not a '
                          'confirmed appointment. The clinic must approve the '
                          'request before it is confirmed.',
                        ),
                        SizedBox(height: 14),
                        Text(
                          '5. You can cancel an eligible upcoming appointment '
                          'from My Appointments. Cancellation cannot be undone. '
                          'To request a different time, cancel the existing '
                          'appointment if eligible, then submit a new request '
                          'for an available slot.',
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const ValueKey('appointment-terms-close'),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppointmentTermsLink() {
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        key: const ValueKey('appointment-terms-link'),
        onPressed: _showAppointmentTerms,
        icon: const Icon(Icons.info_outline, size: 18),
        label: const Text('View Appointment Terms & Conditions'),
        style: TextButton.styleFrom(foregroundColor: const Color(0xFF0F76FF)),
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
        onPressed:
            _isSubmitting ||
                !_closuresVerified ||
                _loadingServices ||
                _serviceOptions.isEmpty ||
                _selectedService == null ||
                !_availabilityVerified
            ? null
            : _createAppointment,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F76FF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: _isSubmitting
            ? const Text(
                'Booking...',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              )
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

              const SizedBox(height: 8),

              _buildAppointmentTermsLink(),

              const SizedBox(height: 16),

              _buildActionButton(),
            ],
          ),
        ),
      ),
    );
  }
}
