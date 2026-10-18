import 'package:flutter_test/flutter_test.dart';
import 'package:optcare_app/edit_profile_screen.dart';
import 'package:optcare_app/philippine_address_helper.dart';

void main() {
  group('Philippine address helper', () {
    test(
      'buildStructuredAddress keeps the backend-friendly flat string format',
      () {
        final address = buildStructuredAddress(
          streetAddress: 'Unit 205, 123 Main St',
          zipCode: '4027',
          province: 'Laguna',
          city: 'Calamba',
          barangay: 'Real',
        );

        expect(
          address,
          'Unit 205, 123 Main St, Zip Code: 4027, Province: Laguna, City/Municipality: Calamba, Barangay: Real',
        );
      },
    );

    test('parseStructuredAddress extracts province city and barangay values', () {
      final parsed = parseStructuredAddress(
        'Unit 205, 123 Main St, Zip Code: 4027, Province: Laguna, City/Municipality: Calamba, Barangay: Real',
      );

      expect(parsed['streetAddress'], 'Unit 205, 123 Main St');
      expect(parsed['zipCode'], '4027');
      expect(parsed['province'], 'Laguna');
      expect(parsed['city'], 'Calamba');
      expect(parsed['barangay'], 'Real');
    });

    test(
      'buildStructuredAddress preserves all saved components after a street edit',
      () {
        final parsed = parseStructuredAddress(
          'Unit 205, 123 Main St, Zip Code: 4027, Province: Laguna, City/Municipality: Calamba, Barangay: Real',
        );

        final rebuilt = buildStructuredAddress(
          streetAddress: 'Unit 205, 123 Main St, Apt 12',
          zipCode: parsed['zipCode'],
          province: parsed['province'],
          city: parsed['city'],
          barangay: parsed['barangay'],
        );

        expect(
          rebuilt,
          'Unit 205, 123 Main St, Apt 12, Zip Code: 4027, Province: Laguna, City/Municipality: Calamba, Barangay: Real',
        );
      },
    );
  });

  test(
    'EditProfileScreen preserves saved address components when the street changes',
    () {
      final address = EditProfileScreen.buildStructuredAddressForSave(
        streetAddress: 'Unit 205, 123 Main St, Apt 12',
        zipCode: '4027',
        province: 'Laguna',
        city: 'Calamba',
        barangay: 'Real',
      );

      expect(
        address,
        'Unit 205, 123 Main St, Apt 12, Zip Code: 4027, Province: Laguna, City/Municipality: Calamba, Barangay: Real',
      );
    },
  );
}
