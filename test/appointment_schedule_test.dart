import 'package:flutter_test/flutter_test.dart';
import 'package:optcare_app/appointment_scheduler.dart';
import 'package:optcare_app/constants.dart';
import 'package:optcare_app/main.dart';

void main() {
  test('Appointments are only available Monday to Saturday', () {
    expect(isClinicOpenDay(DateTime(2026, 10, 5)), isTrue);
    expect(isClinicOpenDay(DateTime(2026, 10, 10)), isTrue);
    expect(isClinicOpenDay(DateTime(2026, 10, 11)), isFalse);
  });

  test(
    'Closure dates are blocked even when they are otherwise weekday open days',
    () {
      final closedDates = {DateTime(2026, 10, 8), DateTime(2026, 10, 9)};

      expect(isClinicOpenDay(DateTime(2026, 10, 8)), isTrue);
      expect(isClinicClosedDate(DateTime(2026, 10, 8), closedDates), isTrue);
      expect(
        isDateSelectableForBooking(DateTime(2026, 10, 8), closedDates),
        isFalse,
      );
      expect(
        isDateSelectableForBooking(DateTime(2026, 10, 7), closedDates),
        isTrue,
      );
      expect(
        isDateSelectableForBooking(DateTime(2026, 10, 11), closedDates),
        isFalse,
      );
    },
  );

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
    expect(isValidPhilippineMobileNumber('+63 912345678'), isFalse);
    expect(isValidPhilippineMobileNumber('+63 91234567890'), isFalse);
    expect(isValidPhilippineMobileNumber('+63 9123abcd89'), isFalse);
    expect(
      normalizePhilippineMobileNumber('9123456789'),
      equals('+639123456789'),
    );
  });
}
