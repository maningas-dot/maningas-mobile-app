// Production backend (Render) is the default so a plain
// `flutter build apk --release` always ships pointing to the live API.
// For local XAMPP testing, override with:
//   flutter run --dart-define=API_BASE_URL=http://10.0.2.2/optcare_api
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://gonzalesvisionclinic.onrender.com',
);

String _stripPhilippineCountryCode(String digits) {
  String result = digits.trim();

  if (result.startsWith('+63')) {
    result = result.substring(3);
  } else if (result.startsWith('63')) {
    result = result.substring(2);
  }

  if (result.length > 11 && result.startsWith('0')) {
    result = result.substring(1);
  }

  return result;
}

bool isValidPhilippineMobileNumber(String? rawValue) {
  final value = (rawValue ?? '').trim();

  if (value.isEmpty) {
    return false;
  }

  final compact = value.replaceAll(RegExp(r'[\s\-()]+'), '');
  String digits = compact.replaceAll(RegExp(r'[^0-9]'), '');

  if (digits.isEmpty) {
    return false;
  }

  digits = _stripPhilippineCountryCode(digits);

  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }

  return digits.length == 10;
}

String normalizePhilippineMobileNumber(String? rawValue) {
  final value = (rawValue ?? '').trim();

  if (value.isEmpty) {
    return '';
  }

  final compact = value.replaceAll(RegExp(r'[\s\-()]+'), '');
  String digits = compact.replaceAll(RegExp(r'[^0-9]'), '');

  if (digits.isEmpty) {
    return '';
  }

  digits = _stripPhilippineCountryCode(digits);

  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }

  if (digits.length != 10) {
    return '';
  }

  return '+63$digits';
}
