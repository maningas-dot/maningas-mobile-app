import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optcare_app/main.dart' as app;
import 'package:optcare_app/philippine_address_helper.dart';
import 'package:optcare_app/zip_code_lookup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('long Barangay labels fit the dropdown on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longBarangayName =
        'ZONE 7 POB. (BALILING) WITH AN ADDITIONAL LONG AREA DESCRIPTION';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: 'long',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Barangay *'),
                items: [
                  DropdownMenuItem(
                    value: 'long',
                    child: const Text(
                      longBarangayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final selectedName = tester.widget<Text>(find.text(longBarangayName));
    expect(selectedName.maxLines, 1);
    expect(selectedName.overflow, TextOverflow.ellipsis);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(longBarangayName), findsNWidgets(2));
    final visibleNames = tester.widgetList<Text>(find.text(longBarangayName));
    expect(
      visibleNames.every(
        (text) => text.maxLines == 1 && text.overflow == TextOverflow.ellipsis,
      ),
      isTrue,
    );
    await tester.tap(find.text(longBarangayName).last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  test(
    'Address dropdown options are deduplicated by stable code identifiers',
    () {
      final items = [
        {'provinceCode': '1', 'provinceName': 'Cebu'},
        {'provinceCode': '1', 'provinceName': 'Cebu'},
        {'provinceCode': '2', 'provinceName': 'Metro Manila'},
      ];

      final deduplicated = deduplicateAddressOptions(
        items,
        codeKey: 'provinceCode',
        nameKey: 'provinceName',
      );

      expect(deduplicated.length, 2);
      expect(deduplicated.map((item) => item['provinceCode']).toList(), [
        '1',
        '2',
      ]);
    },
  );

  test('Invalid selected dropdown values resolve to null safely', () {
    final items = [
      {'municipalityCode': '101', 'municipalityName': 'Bacoor'},
      {'municipalityCode': '102', 'municipalityName': 'Imus'},
    ];

    expect(
      resolveSelectedDropdownValue(
        currentValue: '999',
        items: items,
        codeKey: 'municipalityCode',
        nameKey: 'municipalityName',
      ),
      isNull,
    );

    expect(
      resolveSelectedDropdownValue(
        currentValue: '102',
        items: items,
        codeKey: 'municipalityCode',
        nameKey: 'municipalityName',
      ),
      '102',
    );

    expect(
      resolveSelectedDropdownValue(
        currentValue: '  imus  ',
        items: items,
        codeKey: 'municipalityCode',
        nameKey: 'municipalityName',
      ),
      '102',
    );
  });

  test('Address values are normalized case-insensitively when parsing', () {
    final parsed = parseStructuredAddress(
      'unit 205, 123 Main St, zip code: 4027, province: laguna, city/municipality: calamba, barangay: real',
    );

    expect(parsed['streetAddress'], 'unit 205, 123 Main St');
    expect(parsed['zipCode'], '4027');
    expect(parsed['province'], 'laguna');
    expect(parsed['city'], 'calamba');
    expect(parsed['barangay'], 'real');
  });

  test(
    'Dependent address selections reset when the parent selection changes',
    () {
      final cities = [
        {'municipalityCode': '1', 'municipalityName': 'Bacoor'},
        {'municipalityCode': '2', 'municipalityName': 'Imus'},
      ];

      final barangays = [
        {'barangayCode': '10', 'barangayName': 'Sambong'},
        {'barangayCode': '11', 'barangayName': 'Anabu'},
      ];

      expect(
        resolveSelectedDropdownValue(
          currentValue: '2',
          items: cities,
          codeKey: 'municipalityCode',
          nameKey: 'municipalityName',
        ),
        '2',
      );

      expect(
        resolveSelectedDropdownValue(
          currentValue: '999',
          items: barangays,
          codeKey: 'barangayCode',
          nameKey: 'barangayName',
        ),
        isNull,
      );
    },
  );

  test('Verified ZIP code resolves by province city and barangay', () async {
    final zipCode = await PhilippineZipCodeLookup.resolvePostalCode(
      province: 'Abra',
      municipality: 'Bangued',
      barangay: 'Agtangao',
    );

    expect(zipCode, '2800');
  });

  test('Bulacan Sta Maria Poblacion resolves its dataset ZIP code', () async {
    final zipCode = await PhilippineZipCodeLookup.resolvePostalCode(
      province: 'Bulacan',
      municipality: 'Sta Maria',
      barangay: 'POBLACION',
    );

    expect(zipCode, '3022');
  });

  test('Verified address aliases resolve to their dataset ZIP codes', () async {
    final cases = [
      ('Nueva Vizcaya', 'Sta. Fe', 'POBLACION', '3705'),
      ('Nueva Vizcaya', 'Vilaverde', 'POBLACION', '3710'),
      ('Nueva Vizcaya', 'Alfonso CastaÃ±eda', 'ABUYO', '3714'),
      ('Nueva Vizcaya', 'Bagabag', 'QUIRINO (POB.)', '3711'),
      ('Nueva Vizcaya', 'Solano', 'OSME¥A', '3709'),
      ('Nueva Vizcaya', 'Solano', 'OSMEÑA', '3709'),
      ('Nueva Vizcaya', 'Vilaverde', 'NEGBITIN', '3710'),
      ('Cagayan', 'Sta. Ana', 'BATU-PARADA', '3514'),
      ('Abra', 'Bangued', 'COSILI EAST (PROPER)', '2800'),
    ];

    for (final (province, municipality, barangay, expectedZip) in cases) {
      final zipCode = await PhilippineZipCodeLookup.resolvePostalCode(
        province: province,
        municipality: municipality,
        barangay: barangay,
      );

      expect(
        zipCode,
        expectedZip,
        reason: '$province / $municipality / $barangay',
      );
    }
  });

  test(
    'Default-selected barangay resolves after province and city defaults load',
    () async {
      final incompleteZip = await PhilippineZipCodeLookup.resolvePostalCode(
        province: 'Abra',
        municipality: 'Bangued',
        barangay: '',
      );
      final defaultSelectionZip =
          await PhilippineZipCodeLookup.resolvePostalCode(
            province: 'Abra',
            municipality: 'Bangued',
            barangay: 'Agtangao',
          );

      expect(incompleteZip, isNull);
      expect(defaultSelectionZip, '2800');
    },
  );

  test('Location without an exact dataset mapping keeps ZIP blank', () async {
    final zipCode = await PhilippineZipCodeLookup.resolvePostalCode(
      province: 'Abra',
      municipality: 'Bangued',
      barangay: 'San Gregorio',
    );

    expect(zipCode, isNull);
  });

  test('Nueva Vizcaya Bagabag Tapaya remains unresolved', () async {
    final zipCode = await PhilippineZipCodeLookup.resolvePostalCode(
      province: 'Nueva Vizcaya',
      municipality: 'Bagabag',
      barangay: 'TAPAYA',
    );

    expect(zipCode, isNull);
  });

  test('Ambiguous slash-separated ZIP values are rejected', () async {
    final zipCode = await PhilippineZipCodeLookup.resolvePostalCode(
      province: 'Albay',
      municipality: 'Oas',
      barangay: 'Badbad',
    );

    expect(zipCode, isNull);
  });

  test(
    'Changing the selected location resolves its new verified ZIP',
    () async {
      final firstZip = await PhilippineZipCodeLookup.resolvePostalCode(
        province: 'Abra',
        municipality: 'Bangued',
        barangay: 'Agtangao',
      );

      final secondZip = await PhilippineZipCodeLookup.resolvePostalCode(
        province: 'Abra',
        municipality: 'Boliney',
        barangay: 'Amti',
      );

      expect(firstZip, '2800');
      expect(secondZip, '2815');
    },
  );

  test('Manual ZIP entry is preserved when no verified mapping exists', () {
    final preserved = PhilippineZipCodeLookup.preserveManualZipEntry(
      currentZip: '1234',
      verifiedZip: '3022',
    );

    expect(preserved, '1234');
  });

  test('Stale barangay request does not match the current selection', () {
    expect(
      app.addressSelectionMatchesRequest(
        requestedProvinceCode: '16',
        requestedMunicipalityCode: '4',
        selectedProvinceCode: '16',
        selectedMunicipalityCode: '13',
      ),
      isFalse,
    );
    expect(
      app.addressSelectionMatchesRequest(
        requestedProvinceCode: '16',
        requestedMunicipalityCode: '13',
        selectedProvinceCode: '16',
        selectedMunicipalityCode: '13',
      ),
      isTrue,
    );
  });
}
