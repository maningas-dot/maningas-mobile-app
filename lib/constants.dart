// Production backend (Render) is the default so a plain
// `flutter build apk --release` always ships pointing to the live API.
// For local XAMPP testing, override with:
//   flutter run --dart-define=API_BASE_URL=http://10.0.2.2/optcare_api
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://gonzalesvisionclinic.onrender.com',
);

bool isValidPhilippineMobileNumber(String? rawValue) {
  final value = (rawValue ?? '').trim();

  if (value.isEmpty) {
    return false;
  }

  final compact = value.replaceAll(RegExp(r'[\s\-()]+'), '');

  String digits = compact;

  if (digits.startsWith('+63')) {
    digits = digits.substring(3);
  } else if (digits.startsWith('63')) {
    digits = digits.substring(2);
  }

  digits = digits.replaceAll(RegExp(r'[^0-9]'), '');

  return digits.length == 10;
}

String normalizePhilippineMobileNumber(String? rawValue) {
  final value = (rawValue ?? '').trim();

  if (value.isEmpty) {
    return '';
  }

  final compact = value.replaceAll(RegExp(r'[\s\-()]+'), '');

  String digits = compact;

  if (digits.startsWith('+63')) {
    digits = digits.substring(3);
  } else if (digits.startsWith('63')) {
    digits = digits.substring(2);
  }

  digits = digits.replaceAll(RegExp(r'[^0-9]'), '');

  return '+63$digits';
}
