import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ph_address_finder/ph_address_finder.dart';

void main() {
  late Directory originalDirectory;

  setUpAll(() async {
    originalDirectory = Directory.current;

    final packageConfigFile = File('.dart_tool/package_config.json');
    final packageConfig =
        jsonDecode(await packageConfigFile.readAsString())
            as Map<String, dynamic>;
    final packages = packageConfig['packages'] as List<dynamic>;
    final package = packages.cast<Map<String, dynamic>>().firstWhere(
      (entry) => entry['name'] == 'ph_address_finder',
    );
    final packageRoot = Uri.parse(
      packageConfigFile.absolute.uri.toString(),
    ).resolve(package['rootUri'] as String);

    // AddressData intentionally uses package-local files when FLUTTER_TEST is
    // set, so run the real service against the installed package data.
    Directory.current = Directory(packageRoot.toFilePath());
    await AddressData.loadData();
  });

  tearDownAll(() {
    Directory.current = originalDirectory;
    AddressData.clearBarangayCache();
  });

  Future<Map<String, dynamic>> province({
    required String regionNo,
    required String name,
    String? provinceCode,
  }) async {
    final provinces = await PcicAddressService.getProvinces(regionNo: regionNo);
    return provinces.firstWhere(
      (record) =>
          record['provinceName'].toString().toLowerCase() ==
              name.toLowerCase() &&
          (provinceCode == null || record['provinceCode'] == provinceCode),
    );
  }

  Future<List<Map<String, dynamic>>> municipalitiesFor(
    Map<String, dynamic> selectedProvince,
  ) {
    return PcicAddressService.getMunicipalities(
      regionNo: selectedProvince['regionNo'].toString(),
      provinceCode: selectedProvince['provinceCode'].toString(),
      provinceId: selectedProvince['provinceId'].toString(),
    );
  }

  Future<List<Map<String, dynamic>>> barangaysFor({
    required Map<String, dynamic> selectedProvince,
    required Map<String, dynamic> selectedMunicipality,
  }) {
    return PcicAddressService.getBarangays(
      regionNo: selectedProvince['regionNo'].toString(),
      provinceCode: selectedProvince['provinceCode'].toString(),
      municipalityCode: selectedMunicipality['municipalityCode'].toString(),
      provinceId: selectedProvince['provinceId'].toString(),
      municipalityId: selectedMunicipality['municipalityId'].toString(),
    );
  }

  void expectMunicipalityContext(
    List<Map<String, dynamic>> municipalities,
    Map<String, dynamic> selectedProvince,
  ) {
    expect(municipalities, isNotEmpty);
    for (final municipality in municipalities) {
      expect(municipality['regionNo'], selectedProvince['regionNo']);
      expect(municipality['provinceId'], selectedProvince['provinceId']);
      expect(municipality['provinceCode'], selectedProvince['provinceCode']);
      expect(
        municipality['provinceName'].toString().toLowerCase(),
        selectedProvince['provinceName'].toString().toLowerCase(),
      );
      expect(municipality['municipalityId'], isNotEmpty);
    }
  }

  void expectBarangayContext(
    List<Map<String, dynamic>> barangays,
    Map<String, dynamic> selectedProvince,
    Map<String, dynamic> selectedMunicipality,
  ) {
    expect(barangays, isNotEmpty);
    for (final barangay in barangays) {
      expect(barangay['regionNo'], selectedProvince['regionNo']);
      expect(barangay['provinceId'], selectedProvince['provinceId']);
      expect(barangay['provinceCode'], selectedProvince['provinceCode']);
      expect(
        barangay['municipalityId'],
        selectedMunicipality['municipalityId'],
      );
      expect(
        barangay['municipalityCode'],
        selectedMunicipality['municipalityCode'],
      );
      expect(barangay['barangayId'], isNotEmpty);
      expect(
        barangay['provinceName'].toString().toLowerCase(),
        selectedProvince['provinceName'].toString().toLowerCase(),
      );
      expect(
        barangay['municipalityName'].toString().toLowerCase(),
        selectedMunicipality['municipalityName'].toString().toLowerCase(),
      );
    }
  }

  test(
    'region numbers and options are returned by the installed service',
    () async {
      final regions = await PcicAddressService.getRegionNumbers();
      final regionNumbers = regions
          .map((region) => region['regionNo'].toString())
          .toSet();

      expect(regions, isNotEmpty);
      expect(regionNumbers, containsAll(['1', '2', '11', '12']));

      final rawRegionNumbers = (AddressData.provinces ?? const [])
          .map((record) => record['RegionNo'].toString().trim())
          .where((regionNo) => regionNo.isNotEmpty && regionNo != 'NULL')
          .toSet();
      expect(regionNumbers, rawRegionNumbers);

      final sameLabelOptions = <String, List<Map<String, dynamic>>>{};
      for (final region in regions) {
        final options = await PcicAddressService.getRegionOptions(
          regionNo: region['regionNo'].toString(),
        );
        expect(options, isNotEmpty);
        expect(
          options.map((option) => option['regionOption']).toSet(),
          containsAll(
            (region['regionOptions'] as List<dynamic>).cast<String>(),
          ),
        );

        for (final option in options) {
          final provinces = await PcicAddressService.getProvinces(
            regionNo: region['regionNo'].toString(),
            regionOption: option['regionOption'].toString(),
          );
          for (final province in provinces) {
            final key = [
              region['regionNo'],
              option['regionOption'],
              province['provinceName'].toString().toLowerCase(),
            ].join('|');
            sameLabelOptions.putIfAbsent(key, () => []).add(province);
          }
        }
      }

      expect(
        sameLabelOptions['1|1|maguindanao']!
            .map((record) => record['provinceId'])
            .toSet(),
        containsAll(['81', '82']),
      );
      expect(
        sameLabelOptions['1|1|sultan kudarat']!
            .map((record) => record['provinceId'])
            .toSet(),
        containsAll(['75', '76']),
      );
      expect(
        sameLabelOptions['11|11|davao occidental']!
            .map((record) => record['provinceId'])
            .toSet(),
        containsAll(['1035', '1038']),
      );
    },
  );

  test('Quezon City and Abra remain distinct province contexts', () async {
    final quezonCity = await province(
      regionNo: '1',
      name: 'QUEZON CITY',
      provinceCode: '1',
    );
    final abra = await province(regionNo: '1', name: 'ABRA', provinceCode: '1');

    expect(quezonCity['provinceId'], '1');
    expect(abra['provinceId'], '2');

    final quezonMunicipalities = await municipalitiesFor(quezonCity);
    final abraMunicipalities = await municipalitiesFor(abra);
    expectMunicipalityContext(quezonMunicipalities, quezonCity);
    expectMunicipalityContext(abraMunicipalities, abra);
    expect(quezonMunicipalities.map((item) => item['municipalityName']), [
      'QUEZON CITY',
    ]);
    final quezonCityMunicipality = quezonMunicipalities.single;
    expect(quezonCityMunicipality['municipalityId'], '1710');
    expect(
      abraMunicipalities.map((item) => item['municipalityName']),
      contains('BANGUED'),
    );
    expect(
      abraMunicipalities.map((item) => item['municipalityName']),
      isNot(contains('QUEZON CITY')),
    );

    final quezonCityBarangays = await barangaysFor(
      selectedProvince: quezonCity,
      selectedMunicipality: quezonCityMunicipality,
    );
    expectBarangayContext(
      quezonCityBarangays,
      quezonCity,
      quezonCityMunicipality,
    );

    final bangued = abraMunicipalities.firstWhere(
      (item) => item['municipalityName'] == 'BANGUED',
    );
    expect(bangued['municipalityId'], '2');
    final barangays = await barangaysFor(
      selectedProvince: abra,
      selectedMunicipality: bangued,
    );
    expectBarangayContext(barangays, abra, bangued);
    expect(barangays.map((item) => item['barangayName']), contains('AGTANGAO'));
  });

  test(
    'Benguet is distinguishable from the inactive Baguio City record',
    () async {
      final benguet = await province(
        regionNo: '2',
        name: 'Benguet',
        provinceCode: '8',
      );
      final benguetMunicipalities = await municipalitiesFor(benguet);
      expectMunicipalityContext(benguetMunicipalities, benguet);
      expect(
        benguetMunicipalities.map((item) => item['municipalityName']),
        contains('Baguio City'),
      );
      final benguetBaguio = benguetMunicipalities.firstWhere(
        (item) => item['municipalityName'] == 'Baguio City',
      );
      expect(benguetBaguio['municipalityId'], '1914');

      final baguioCityRecord = (AddressData.provinces ?? const [])
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (record) =>
                record['RegionNo'].toString() == '1' &&
                record['ProvinceID'].toString() == '79',
          );
      expect(baguioCityRecord['provinceName'], 'BAGUIO CITY');
      expect(baguioCityRecord['provinceCode'], '8');
      expect(baguioCityRecord['isActive'], '0');

      final baguioCityOption = (await PcicAddressService.getProvinces(
        regionNo: '1',
      )).firstWhere((record) => record['provinceId'] == '79');
      expect(baguioCityOption['provinceName'], 'BAGUIO CITY');
      expect(baguioCityOption['provinceCode'], '8');
      expect(baguioCityOption.containsKey('isActive'), isFalse);
      final baguioCityMunicipalities = await municipalitiesFor(
        baguioCityOption,
      );
      expect(baguioCityMunicipalities, hasLength(1));
      expect(baguioCityMunicipalities.single['provinceId'], '79');
      expect(baguioCityMunicipalities.single['provinceName'], 'Benguet');
      expect(
        baguioCityMunicipalities.single['municipalityName'],
        'BAGUIO CITY',
      );

      final barangays = await barangaysFor(
        selectedProvince: benguet,
        selectedMunicipality: benguetBaguio,
      );
      expectBarangayContext(barangays, benguet, benguetBaguio);
    },
  );

  test(
    'Davao Occidental exposes both source records without active filtering',
    () async {
      final rawRecords = (AddressData.provinces ?? const [])
          .cast<Map<String, dynamic>>()
          .where(
            (record) =>
                record['RegionNo'].toString() == '11' &&
                record['provinceName'].toString().toLowerCase() ==
                    'davao occidental',
          )
          .toList();
      expect(rawRecords, hasLength(2));
      expect(rawRecords.map((record) => record['ProvinceID']).toSet(), {
        '1035',
        '1038',
      });

      final returnedRecords = await PcicAddressService.getProvinces(
        regionNo: '11',
      );
      final davaoRecords = returnedRecords
          .where(
            (record) =>
                record['provinceName'].toString().toLowerCase() ==
                'davao occidental',
          )
          .toList();
      expect(davaoRecords, hasLength(2));
      expect(davaoRecords.map((record) => record['provinceId']).toSet(), {
        '1035',
        '1038',
      });
      expect(
        davaoRecords.every((record) => !record.containsKey('isActive')),
        isTrue,
      );

      final activeRecord = davaoRecords.firstWhere(
        (record) => record['provinceId'] == '1035',
      );
      final inactiveRecord = davaoRecords.firstWhere(
        (record) => record['provinceId'] == '1038',
      );
      expect(
        rawRecords.firstWhere(
          (record) => record['ProvinceID'] == '1035',
        )['isActive'],
        '1',
      );
      expect(
        rawRecords.firstWhere(
          (record) => record['ProvinceID'] == '1038',
        )['isActive'],
        '0',
      );

      final activeMunicipalities = await municipalitiesFor(activeRecord);
      expectMunicipalityContext(activeMunicipalities, activeRecord);
      expect(activeMunicipalities, hasLength(5));
      expect(await municipalitiesFor(inactiveRecord), isEmpty);
    },
  );

  test(
    'Maguindanao Province IDs and municipality parents remain distinct',
    () async {
      final first = await province(
        regionNo: '1',
        name: 'Maguindanao',
        provinceCode: '81',
      );
      final second = await province(
        regionNo: '1',
        name: 'Maguindanao',
        provinceCode: '83',
      );
      expect(first['provinceId'], '81');
      expect(second['provinceId'], '82');

      final firstMunicipalities = await municipalitiesFor(first);
      final secondMunicipalities = await municipalitiesFor(second);
      expectMunicipalityContext(firstMunicipalities, first);
      expectMunicipalityContext(secondMunicipalities, second);
      expect(firstMunicipalities, hasLength(37));
      expect(secondMunicipalities, hasLength(37));
      expect(
        firstMunicipalities.every((item) => item['provinceId'] == '81'),
        isTrue,
      );
      expect(
        secondMunicipalities.every((item) => item['provinceId'] == '82'),
        isTrue,
      );

      final firstBuluan = firstMunicipalities.firstWhere(
        (item) => item['municipalityName'].toString().toLowerCase() == 'buluan',
      );
      final secondBuluan = secondMunicipalities.firstWhere(
        (item) => item['municipalityName'].toString().toLowerCase() == 'buluan',
      );
      expect(firstBuluan['municipalityId'], '1606');
      expect(secondBuluan['municipalityId'], '1643');
      expect(
        firstBuluan['municipalityId'],
        isNot(secondBuluan['municipalityId']),
      );
      final firstBarangays = await barangaysFor(
        selectedProvince: first,
        selectedMunicipality: firstBuluan,
      );
      final secondBarangays = await barangaysFor(
        selectedProvince: second,
        selectedMunicipality: secondBuluan,
      );
      expectBarangayContext(firstBarangays, first, firstBuluan);
      expectBarangayContext(secondBarangays, second, secondBuluan);
    },
  );

  test(
    'Sultan Kudarat Province IDs and municipality parents remain distinct',
    () async {
      final first = await province(
        regionNo: '1',
        name: 'Sultan Kudarat',
        provinceCode: '76',
      );
      final second = await province(
        regionNo: '1',
        name: 'Sultan Kudarat',
        provinceCode: '77',
      );
      expect(first['provinceId'], '75');
      expect(second['provinceId'], '76');

      final firstMunicipalities = await municipalitiesFor(first);
      final secondMunicipalities = await municipalitiesFor(second);
      expectMunicipalityContext(firstMunicipalities, first);
      expectMunicipalityContext(secondMunicipalities, second);
      expect(firstMunicipalities, hasLength(12));
      expect(secondMunicipalities, hasLength(12));
      expect(
        firstMunicipalities.every((item) => item['provinceId'] == '75'),
        isTrue,
      );
      expect(
        secondMunicipalities.every((item) => item['provinceId'] == '76'),
        isTrue,
      );

      final firstIsulan = firstMunicipalities.firstWhere(
        (item) => item['municipalityName'].toString().toLowerCase() == 'isulan',
      );
      final secondIsulan = secondMunicipalities.firstWhere(
        (item) => item['municipalityName'].toString().toLowerCase() == 'isulan',
      );
      expect(firstIsulan['municipalityId'], '1488');
      expect(secondIsulan['municipalityId'], '1500');
      expect(
        firstIsulan['municipalityId'],
        isNot(secondIsulan['municipalityId']),
      );

      final firstBarangays = await barangaysFor(
        selectedProvince: first,
        selectedMunicipality: firstIsulan,
      );
      final secondBarangays = await barangaysFor(
        selectedProvince: second,
        selectedMunicipality: secondIsulan,
      );
      expectBarangayContext(firstBarangays, first, firstIsulan);
      expectBarangayContext(secondBarangays, second, secondIsulan);
    },
  );
}
