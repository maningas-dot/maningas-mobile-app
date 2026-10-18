import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optcare_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpAddress(WidgetTester tester, String address) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfileAddressDisplay(address: address)),
      ),
    );
  }

  testWidgets('displays each available structured address component', (
    tester,
  ) async {
    await pumpAddress(
      tester,
      'Unit 205, 123 Main St, Zip Code: 4027, Province: Laguna, '
      'City/Municipality: Calamba, Barangay: Real',
    );

    expect(find.text('Street Address'), findsOneWidget);
    expect(find.text('Unit 205, 123 Main St'), findsOneWidget);
    expect(find.text('ZIP Code'), findsOneWidget);
    expect(find.text('4027'), findsOneWidget);
    expect(find.text('Province'), findsOneWidget);
    expect(find.text('Laguna'), findsOneWidget);
    expect(find.text('City/Municipality'), findsOneWidget);
    expect(find.text('Calamba'), findsOneWidget);
    expect(find.text('Barangay'), findsOneWidget);
    expect(find.text('Real'), findsOneWidget);
    expect(find.text('Address'), findsNothing);
  });

  testWidgets('omits Street Address when no street was saved', (tester) async {
    await pumpAddress(
      tester,
      'Zip Code: 4027, Province: Laguna, '
      'City/Municipality: Calamba, Barangay: Real',
    );

    expect(find.text('Street Address'), findsNothing);
    expect(find.text('ZIP Code'), findsOneWidget);
    expect(find.text('Barangay'), findsOneWidget);
  });

  testWidgets('shows the existing empty-address placeholder', (tester) async {
    await pumpAddress(tester, '');

    expect(find.text('Address'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
  });

  testWidgets('preserves a legacy unstructured address verbatim', (
    tester,
  ) async {
    const legacyAddress = 'Unit 4, Old Town Road, Laguna';
    await pumpAddress(tester, legacyAddress);

    expect(find.text('Address'), findsOneWidget);
    expect(find.text(legacyAddress), findsOneWidget);
    expect(find.text('Province'), findsNothing);
    expect(find.text('City/Municipality'), findsNothing);
    expect(find.text('Barangay'), findsNothing);
  });

  testWidgets(
    'displays all six structured address values without reformatting',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAddressDisplay(
              address: 'Ignored flat address',
              structuredAddress: const {
                'address_unit': '  Unit 9  ',
                'address_street': '123 Test Street',
                'address_barangay': 'Poblacion',
                'address_city_municipality': 'Test City',
                'address_province': 'Test Province',
                'address_zip_code': '0123',
              },
            ),
          ),
        ),
      );

      for (final label in const [
        'Unit',
        'Street',
        'Barangay',
        'City/Municipality',
        'Province',
        'ZIP Code',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      for (final value in const [
        '  Unit 9  ',
        '123 Test Street',
        'Poblacion',
        'Test City',
        'Test Province',
        '0123',
      ]) {
        expect(find.text(value), findsOneWidget);
      }
      expect(find.text('Ignored flat address'), findsNothing);
    },
  );

  test(
    'maps top-level structured profile fields from each supported wrapper',
    () {
      const patient = {
        'patient_id': 'synthetic-patient',
        'address_unit': 'Unit 1',
        'address_street': '1 Test Street',
        'address_barangay': 'Sample Barangay',
        'address_city_municipality': 'Sample City',
        'address_province': 'Sample Province',
        'address_zip_code': '1234',
      };

      for (final response in [
        patient,
        {'patient': patient},
        {'data': patient},
      ]) {
        final mapped = patientProfileFromResponse(response);
        for (final key in const [
          'address_unit',
          'address_street',
          'address_barangay',
          'address_city_municipality',
          'address_province',
          'address_zip_code',
        ]) {
          expect(mapped[key], patient[key]);
        }
        expect(mapped['patient_id'], 'synthetic-patient');
      }
    },
  );

  test('uses nested structured address fields only as a fallback', () {
    final mapped = patientProfileFromResponse({
      'address_unit': 'Top-level unit',
      'address': {
        'unit': 'Nested unit',
        'street': 'Nested street',
        'barangay': 'Nested barangay',
        'city_municipality': 'Nested city',
        'province': 'Nested province',
        'zip_code': '9876',
      },
    });

    expect(mapped['address_unit'], 'Top-level unit');
    expect(mapped['address_street'], 'Nested street');
    expect(mapped['address_barangay'], 'Nested barangay');
    expect(mapped['address_city_municipality'], 'Nested city');
    expect(mapped['address_province'], 'Nested province');
    expect(mapped['address_zip_code'], '9876');

    final patientAddress = patientProfileFromResponse({
      'patient_address': {
        'address_unit': 'Patient unit',
        'address_street': 'Patient street',
        'address_barangay': 'Patient barangay',
        'address_city_municipality': 'Patient city',
        'address_province': 'Patient province',
        'address_zip_code': '6789',
      },
    });
    expect(patientAddress['address_unit'], 'Patient unit');
    expect(patientAddress['address_street'], 'Patient street');
    expect(patientAddress['address_barangay'], 'Patient barangay');
    expect(patientAddress['address_city_municipality'], 'Patient city');
    expect(patientAddress['address_province'], 'Patient province');
    expect(patientAddress['address_zip_code'], '6789');
  });

  testWidgets('null, missing, and whitespace-only values show Not provided', (
    tester,
  ) async {
    final mapped = patientProfileFromResponse({
      'address_unit': null,
      'address_street': ' \t ',
      'address_barangay': '',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileAddressDisplay(address: '', structuredAddress: mapped),
        ),
      ),
    );

    expect(find.text('Not provided'), findsNWidgets(6));
    expect(find.text('-'), findsNothing);
  });
}
