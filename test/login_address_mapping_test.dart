import 'package:flutter_test/flutter_test.dart';
import 'package:optcare_app/main.dart';

void main() {
  group('structured address fields from login response', () {
    test('copies structured fields when present', () {
      final result = structuredAddressFieldsFromLoginResponse({
        'address_unit': 'Unit A',
        'address_street': 'Example Street',
        'address_barangay': 'Sample Barangay',
        'address_city_municipality': 'Sample City',
        'address_province': 'Sample Province',
        'address_zip_code': '1234',
      });

      expect(result, {
        'address_unit': 'Unit A',
        'address_street': 'Example Street',
        'address_barangay': 'Sample Barangay',
        'address_city_municipality': 'Sample City',
        'address_province': 'Sample Province',
        'address_zip_code': '1234',
      });
    });

    test('does not fabricate fields from flat address or missing keys', () {
      final result = structuredAddressFieldsFromLoginResponse({
        'address': 'An opaque legacy address',
        'address_unit': null,
        'address_street': '   ',
      });

      expect(result, {'address_unit': null, 'address_street': '   '});
      expect(result.containsKey('address_barangay'), isFalse);
      expect(result.containsKey('address_city_municipality'), isFalse);
      expect(result.containsKey('address_province'), isFalse);
      expect(result.containsKey('address_zip_code'), isFalse);
    });
  });

  group('name fields from login response', () {
    test('preserves separately supplied name fields', () {
      final result = nameFieldsFromLoginResponse({
        'first_name': 'Synthetic First',
        'middle_name': 'Synthetic Middle',
        'last_name': 'Synthetic Last',
      });

      expect(result, {
        'first_name': 'Synthetic First',
        'middle_name': 'Synthetic Middle',
        'last_name': 'Synthetic Last',
      });
    });

    test('splits a combined name when separate fields are absent', () {
      final result = nameFieldsFromLoginResponse({
        'name': 'Synthetic First Synthetic Middle Synthetic Last',
      });

      expect(result, {
        'first_name': 'Synthetic',
        'last_name': 'First Synthetic Middle Synthetic Last',
      });
      expect(result.containsKey('middle_name'), isFalse);
    });

    test('uses combined name only for separately missing components', () {
      final result = nameFieldsFromLoginResponse({
        'name': 'Combined First Combined Last',
        'first_name': 'Explicit First',
        'middle_name': 'Explicit Middle',
      });

      expect(result, {
        'first_name': 'Explicit First',
        'middle_name': 'Explicit Middle',
        'last_name': 'First Combined Last',
      });
    });
  });

  test('profile GET null structured fields replace login values', () {
    const keys = [
      'address_unit',
      'address_street',
      'address_barangay',
      'address_city_municipality',
      'address_province',
      'address_zip_code',
    ];
    final loginProfile = {for (final key in keys) key: 'login $key'};
    final profileGetResponse = {for (final key in keys) key: null};

    final merged = mergeProfileRefreshData(loginProfile, profileGetResponse);

    for (final key in keys) {
      expect(merged.containsKey(key), isTrue);
      expect(merged[key], isNull);
    }
  });
}
