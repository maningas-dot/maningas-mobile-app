import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/edit_profile_screen.dart';
import 'package:optcare_app/philippine_address_helper.dart';
import 'package:optcare_app/main.dart' as app;
import 'package:ph_address_finder/ph_address_finder.dart';
import 'package:optcare_app/zip_code_lookup.dart';

const _ambiguousAddress =
    'Unit 205, 123 Main St, Zip Code: 4027, Province: Benguet, '
    'City/Municipality: Baguio City, Barangay: Poblacion';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    Directory.current = Directory(packageRoot.toFilePath());
    await AddressData.loadData();
    await Future.wait([
      AddressData.loadBarangayShard('86'),
      AddressData.loadBarangayShard('1'),
      AddressData.loadBarangayShard('2'),
      AddressData.loadBarangayShard('10'),
      AddressData.loadBarangayShard('41'),
      AddressData.loadBarangayShard('35'),
    ]);
  });

  tearDownAll(() {
    Directory.current = originalDirectory;
    AddressData.clearBarangayCache();
  });

  testWidgets('restores a uniquely matched active address path', (
    tester,
  ) async {
    const address =
        'Unit 205, Zip Code: 8000, Province: Davao Occidental, '
        'City/Municipality: Sta. Maria, Barangay: Poblacion';
    await _openEditProfile(tester, address);

    final provinceDropdown = _dropdown(tester, 'province');
    final cityDropdown = _dropdown(tester, 'city');
    final barangayDropdown = _dropdown(tester, 'barangay');
    expect(provinceDropdown.value, isNotNull);
    expect(cityDropdown.value, isNotNull);
    expect(barangayDropdown.value, isNotNull);
    expect(_selectedLabel(provinceDropdown).toLowerCase(), 'davao occidental');
    expect(_selectedLabel(cityDropdown).toLowerCase(), 'sta. maria');
    expect(_selectedLabel(barangayDropdown).toLowerCase(), 'poblacion');
    expect(_zipField(tester).controller!.text, '8000');
    for (final level in ['province', 'city', 'barangay']) {
      final optionLabels = _dropdown(
        tester,
        level,
      ).items!.map((item) => (item.child as Text).data!).toList();
      expect(
        optionLabels.where(
          (label) =>
              RegExp(r'\b(code|ID)\b', caseSensitive: false).hasMatch(label),
        ),
        isEmpty,
      );
    }
  });

  testWidgets('opening Edit Profile keeps the saved ZIP unchanged', (
    tester,
  ) async {
    await _openEditProfile(tester, _addressWithZip('3013'));

    expect(_zipField(tester).controller!.text, '3013');
    expect(find.textContaining('ZIP Code updated'), findsNothing);
  });

  testWidgets('changing Province alone does not invent a ZIP Code', (
    tester,
  ) async {
    await _openEditProfile(tester, _addressWithZip('3013'));

    await _selectOption(tester, 'province', 'Abra');

    expect(_zipField(tester).controller!.text, '3013');
    expect(
      find.text(
        'Select a city and barangay to check the ZIP Code for this location.',
      ),
      findsNothing,
    );
  });

  testWidgets('selecting a uniquely mapped locality updates ZIP Code', (
    tester,
  ) async {
    await _openEditProfile(tester, _addressWithZip('3013'));

    await _selectOption(tester, 'province', 'Abra');
    await _selectOption(tester, 'city', 'BANGUED');
    await _selectOption(tester, 'barangay', 'AGTANGAO');

    expect(_zipField(tester).controller!.text, '2800');
    expect(
      find.textContaining(
        "We couldn't find a unique ZIP Code for this location.",
      ),
      findsNothing,
    );
  });

  testWidgets('changing location resolves the supported Sta. Maria alias', (
    tester,
  ) async {
    await _openEditProfile(tester, _addressWithZip('3013'));

    await _selectOption(tester, 'province', 'Abra');
    await _selectOption(tester, 'city', 'BANGUED');
    await _selectOption(tester, 'barangay', 'SAN GREGORIO');
    expect(
      find.textContaining(
        "We couldn't find a unique ZIP Code for this location.",
      ),
      findsOneWidget,
    );

    await _selectOption(tester, 'province', 'Davao Occidental');
    await _selectOption(tester, 'city', 'STA. MARIA');
    await _selectOption(tester, 'barangay', 'POBLACION');

    expect(_zipField(tester).controller!.text, '8011');
    expect(
      find.textContaining(
        "We couldn't find a unique ZIP Code for this location.",
      ),
      findsNothing,
    );
  });

  testWidgets('a manually edited ZIP Code is not replaced by lookup', (
    tester,
  ) async {
    await _openEditProfile(tester, _addressWithZip('3013'));

    await tester.enterText(
      find.byKey(const ValueKey('edit-profile-zip')),
      '9999',
    );
    await _selectOption(tester, 'province', 'Abra');
    await _selectOption(tester, 'city', 'BANGUED');
    await _selectOption(tester, 'barangay', 'AGTANGAO');

    expect(_zipField(tester).controller!.text, '9999');
    expect(
      find.textContaining('manually entered ZIP Code was kept'),
      findsOneWidget,
    );
  });

  testWidgets('unmapped locality preserves ZIP and requests confirmation', (
    tester,
  ) async {
    await _openEditProfile(tester, _addressWithZip('3013'));

    await _selectOption(tester, 'province', 'Abra');
    await _selectOption(tester, 'city', 'BANGUED');
    await _selectOption(tester, 'barangay', 'SAN GREGORIO');

    expect(_zipField(tester).controller!.text, '3013');
    expect(
      find.textContaining(
        "We couldn't find a unique ZIP Code for this location.",
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('edit-profile-zip')),
      '9999',
    );
    await tester.pumpAndSettle();
    expect(_zipField(tester).controller!.text, '9999');
    expect(
      find.textContaining(
        "We couldn't find a unique ZIP Code for this location.",
      ),
      findsNothing,
    );
  });

  test('resolver rejects a slash-separated ambiguous ZIP value', () async {
    final result = await PhilippineZipCodeLookup.resolvePostalCode(
      province: 'Albay',
      municipality: 'Oas',
      barangay: 'Badbad',
    );

    expect(result, isNull);
  });

  testWidgets('preserves ambiguous and unmatched saved locations', (
    tester,
  ) async {
    await _openEditProfile(tester, _ambiguousAddress);

    expect(
      _field(tester, 'Street Address').controller!.text,
      'Unit 205, 123 Main St',
    );
    expect(_zipField(tester).controller!.text, '4027');
    expect(_manualField(tester, 'province').controller!.text, 'Benguet');
    expect(_manualField(tester, 'city').controller!.text, 'Baguio City');
    expect(_manualField(tester, 'barangay').controller!.text, 'Poblacion');
    expect(_dropdown(tester, 'province').value, isNull);
    expect(_provinceOptionLabels(tester), isNot(contains('Benguet')));
    expect(find.textContaining('kept'), findsWidgets);
  });

  testWidgets('keeps an unmatched saved province available for manual entry', (
    tester,
  ) async {
    await _openEditProfile(tester, 'Province: Not a real province');
    expect(
      _manualField(tester, 'province').controller!.text,
      'Not a real province',
    );
    expect(_dropdown(tester, 'province').value, isNull);
  });

  testWidgets('saves edited components in the existing structured format', (
    tester,
  ) async {
    String? savedAddress;
    Map<String, dynamic>? savedPayload;
    Map<String, dynamic>? returnedProfile;
    final requests = <http.Request>[];

    await http.runWithClient(
      () async {
        await _openEditProfile(
          tester,
          _ambiguousAddress,
          onResult: (result) => returnedProfile = result,
        );
        await tester.enterText(_fieldFinder('Street Address'), '123 Main St');
        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-unit')),
          'Apt 12',
        );
        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-zip')),
          '4028',
        );
        await tester.enterText(_manualFieldFinder('province'), 'Cavite');
        await tester.enterText(_manualFieldFinder('city'), 'Imus');
        await tester.enterText(_manualFieldFinder('barangay'), 'Anabu');

        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        requests.add(request);
        if (request.method == 'PUT') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          savedPayload = payload;
          savedAddress = payload['address'] as String;
          return http.Response('{"success":true}', 200);
        }
        return http.Response(
          jsonEncode({
            'patient_id': 'test-patient',
            'address': savedAddress,
            for (final key in const [
              'address_unit',
              'address_street',
              'address_barangay',
              'address_city_municipality',
              'address_province',
              'address_zip_code',
            ])
              key: savedPayload![key],
          }),
          200,
        );
      }),
    );

    const expectedAddress =
        'Apt 12, 123 Main St, Zip Code: 4028, Province: Cavite, '
        'City/Municipality: Imus, Barangay: Anabu';
    expect(savedAddress, expectedAddress);
    expect(savedPayload!['address_unit'], 'Apt 12');
    expect(savedPayload!['address_street'], '123 Main St');
    for (final key in const [
      'address_unit',
      'address_street',
      'address_barangay',
      'address_city_municipality',
      'address_province',
      'address_zip_code',
    ]) {
      expect(savedPayload![key], isA<String>());
      expect((savedPayload![key] as String).trim(), isNotEmpty);
    }
    expect(returnedProfile?['address'], savedAddress);
    expect(requests.map((request) => request.method), ['PUT', 'GET']);
    expect(requests.first.url.path, '/api/patients/test-patient');
    expect(requests.first.headers['content-type'], 'application/json');
    expect(requests.first.headers['accept'], 'application/json');
    expect(requests.last.url, requests.first.url);
  });

  testWidgets('diagnoses formatted GET address mismatch without logging it', (
    tester,
  ) async {
    var returnedFromEdit = false;
    var getRequested = false;
    String? submittedAddress;
    final diagnosticLogs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) diagnosticLogs.add(message);
    };

    try {
      await http.runWithClient(
        () async {
          await _openEditProfile(
            tester,
            _ambiguousAddress,
            onResult: (_) => returnedFromEdit = true,
          );
          await tester.enterText(_fieldFinder('Street Address'), '123 Main St');
          await tester.enterText(
            find.byKey(const ValueKey('edit-profile-unit')),
            'Apt 12',
          );
          await tester.enterText(
            find.byKey(const ValueKey('edit-profile-zip')),
            '4028',
          );
          await tester.enterText(_manualFieldFinder('province'), 'Cavite');
          await tester.enterText(_manualFieldFinder('city'), 'Imus');
          await tester.enterText(_manualFieldFinder('barangay'), 'Anabu');
          await tester.ensureVisible(find.text('Save'));
          await tester.tap(find.text('Save'));
          await tester.pump();
          await tester.pumpAndSettle();
        },
        () => MockClient((request) async {
          if (request.method == 'PUT') {
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            submittedAddress = payload['address'] as String;
            return http.Response('{"success":true}', 200);
          }
          getRequested = true;
          final formattedAddress = submittedAddress!.replaceFirst(
            ', Zip Code:',
            ' Zip Code:',
          );
          return http.Response(
            jsonEncode({
              'patient_id': 'test-patient',
              'address': formattedAddress,
              'address_unit': 'Apt 12',
              'address_street': '123 Main St',
              'address_barangay': 'Anabu',
              'address_city_municipality': 'Imus',
              'address_province': 'Cavite',
              'address_zip_code': '4028',
            }),
            200,
          );
        }),
      );
    } finally {
      debugPrint = previousDebugPrint;
    }

    expect(getRequested, isTrue);
    expect(returnedFromEdit, isFalse);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(
      find.text(
        'The server did not confirm the updated address. Please try again.',
      ),
      findsOneWidget,
    );
    final confirmationLog = diagnosticLogs.singleWhere(
      (message) => message.startsWith('EDIT PROFILE CONFIRMATION:'),
    );
    expect(confirmationLog, contains('addressMatches=false'));
    expect(
      confirmationLog,
      contains('addressMismatchClassification=formatting_only_candidate'),
    );
    expect(confirmationLog, contains('firstDiffIndex='));
    expect(
      confirmationLog,
      contains('submittedCharKind=punctuation-or-symbol'),
    );
    expect(confirmationLog, contains('returnedCharKind=whitespace'));
    expect(confirmationLog, contains('address_barangay: true'));
    expect(confirmationLog, contains('address_city_municipality: true'));
    expect(confirmationLog, contains('address_province: true'));
    expect(confirmationLog, contains('address_zip_code: true'));
    expect(confirmationLog, isNot(contains(submittedAddress!)));
  });

  testWidgets('classifies content mismatch and still rejects confirmation', (
    tester,
  ) async {
    var returnedFromEdit = false;
    String? submittedAddress;
    final diagnosticLogs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) diagnosticLogs.add(message);
    };

    try {
      await http.runWithClient(
        () async {
          await _openEditProfile(
            tester,
            _ambiguousAddress,
            onResult: (_) => returnedFromEdit = true,
          );
          await tester.enterText(_fieldFinder('Street Address'), '123 Main St');
          await tester.enterText(
            find.byKey(const ValueKey('edit-profile-unit')),
            'Apt 12',
          );
          await tester.enterText(
            find.byKey(const ValueKey('edit-profile-zip')),
            '4028',
          );
          await tester.enterText(_manualFieldFinder('province'), 'Cavite');
          await tester.enterText(_manualFieldFinder('city'), 'Imus');
          await tester.enterText(_manualFieldFinder('barangay'), 'Anabu');
          await tester.ensureVisible(find.text('Save'));
          await tester.tap(find.text('Save'));
          await tester.pump();
          await tester.pumpAndSettle();
        },
        () => MockClient((request) async {
          if (request.method == 'PUT') {
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            submittedAddress = payload['address'] as String;
            return http.Response('{"success":true}', 200);
          }
          final differentAddress = submittedAddress!.replaceFirst(
            '123 Main St',
            '456 Oak Ave',
          );
          return http.Response(
            jsonEncode({
              'patient_id': 'test-patient',
              'address': differentAddress,
              'address_unit': 'Apt 12',
              'address_street': '123 Main St',
              'address_barangay': 'Anabu',
              'address_city_municipality': 'Imus',
              'address_province': 'Cavite',
              'address_zip_code': '4028',
            }),
            200,
          );
        }),
      );
    } finally {
      debugPrint = previousDebugPrint;
    }

    expect(returnedFromEdit, isFalse);
    expect(
      find.text(
        'The server did not confirm the updated address. Please try again.',
      ),
      findsOneWidget,
    );
    final confirmationLog = diagnosticLogs.singleWhere(
      (message) => message.startsWith('EDIT PROFILE CONFIRMATION:'),
    );
    expect(confirmationLog, contains('addressMatches=false'));
    expect(
      confirmationLog,
      contains('addressMismatchClassification=content_mismatch'),
    );
    expect(confirmationLog, isNot(contains(submittedAddress!)));
    expect(confirmationLog, isNot(contains('456 Oak Ave')));
    expect(confirmationLog, isNot(contains('test-patient')));
  });

  testWidgets('does not confirm save when GET response omits address', (
    tester,
  ) async {
    var returnedFromEdit = false;

    await http.runWithClient(
      () async {
        await _openEditProfile(
          tester,
          _ambiguousAddress,
          onResult: (_) => returnedFromEdit = true,
        );
        await tester.enterText(_fieldFinder('Street Address'), '123 Main St');
        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-unit')),
          'Apt 12',
        );
        await tester.enterText(
          find.byKey(const ValueKey('edit-profile-zip')),
          '4028',
        );
        await tester.enterText(_manualFieldFinder('province'), 'Cavite');
        await tester.enterText(_manualFieldFinder('city'), 'Imus');
        await tester.enterText(_manualFieldFinder('barangay'), 'Anabu');
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        if (request.method == 'PUT') {
          return http.Response('{"success":true}', 200);
        }
        return http.Response('{"patient_id":"test-patient"}', 200);
      }),
    );

    expect(returnedFromEdit, isFalse);
    expect(
      find.text(
        'The server did not confirm the updated address. Please try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('does not confirm when a structured GET field mismatches', (
    tester,
  ) async {
    var returnedFromEdit = false;
    String? savedAddress;
    Map<String, dynamic>? savedPayload;

    await http.runWithClient(
      () async {
        await _openEditProfile(
          tester,
          _ambiguousAddress,
          onResult: (_) => returnedFromEdit = true,
        );
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        if (request.method == 'PUT') {
          savedPayload = jsonDecode(request.body) as Map<String, dynamic>;
          savedAddress = savedPayload!['address'] as String;
          return http.Response('{"success":true}', 200);
        }
        return http.Response(
          jsonEncode({
            'patient_id': 'test-patient',
            'address': savedAddress,
            for (final key in const [
              'address_unit',
              'address_street',
              'address_barangay',
              'address_city_municipality',
              'address_province',
              'address_zip_code',
            ])
              key: key == 'address_street'
                  ? 'Different Street'
                  : savedPayload![key],
          }),
          200,
        );
      }),
    );

    expect(returnedFromEdit, isFalse);
    expect(
      find.text(
        'The server did not confirm the updated address. Please try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('allows unrelated edits when all structured fields are known', (
    tester,
  ) async {
    Map<String, dynamic>? savedPayload;
    var returnedFromEdit = false;

    await http.runWithClient(
      () async {
        await _openEditProfile(
          tester,
          _ambiguousAddress,
          onResult: (_) => returnedFromEdit = true,
        );
        await tester.enterText(_fieldFinder('Email'), 'updated@example.com');
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        if (request.method == 'PUT') {
          savedPayload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"success":true}', 200);
        }
        return http.Response(
          jsonEncode({
            'patient_id': 'test-patient',
            'address': savedPayload!['address'],
            for (final key in const [
              'address_unit',
              'address_street',
              'address_barangay',
              'address_city_municipality',
              'address_province',
              'address_zip_code',
            ])
              key: savedPayload![key],
          }),
          200,
        );
      }),
    );

    expect(returnedFromEdit, isTrue);
    expect(savedPayload?['email'], 'updated@example.com');
  });

  testWidgets('does not return an updated profile when save fails', (
    tester,
  ) async {
    var returnedFromEdit = false;

    await http.runWithClient(
      () async {
        await _openEditProfile(
          tester,
          _addressWithZip('3013'),
          onResult: (_) => returnedFromEdit = true,
        );
        await tester.enterText(
          _fieldFinder('Street Address'),
          'Updated street address',
        );
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pumpAndSettle();
      },
      () => MockClient(
        (request) async => http.Response(
          '{"success":false,"message":"Unable to update profile"}',
          500,
        ),
      ),
    );

    expect(returnedFromEdit, isFalse);
    expect(find.text('Edit Profile'), findsOneWidget);
    expect(find.text('Unable to update profile'), findsOneWidget);
  });

  testWidgets('explicit parent selections reset dependent values', (
    tester,
  ) async {
    const address =
        'Unit 205, Zip Code: 8000, Province: Davao Occidental, '
        'City/Municipality: Sta. Maria, Barangay: Poblacion';
    await _openEditProfile(tester, address);

    final provinceDropdown = _dropdown(tester, 'province');
    provinceDropdown.onChanged!(_choiceValue(provinceDropdown, 'Batanes'));
    await tester.pumpAndSettle();

    expect(_manualField(tester, 'city').controller!.text, isEmpty);
    expect(_manualField(tester, 'barangay').controller!.text, isEmpty);

    final cityDropdown = _dropdown(tester, 'city');
    final firstCity = cityDropdown.items!
        .firstWhere((item) => item.value != null)
        .value!;
    cityDropdown.onChanged!(firstCity);
    await tester.pumpAndSettle();
    if (find
        .byKey(const ValueKey('edit-profile-barangay-dropdown'))
        .evaluate()
        .isNotEmpty) {
      final barangayDropdown = _dropdown(tester, 'barangay');
      barangayDropdown.onChanged!(
        barangayDropdown.items!.firstWhere((item) => item.value != null).value,
      );
      await tester.pumpAndSettle();
    } else {
      await tester.enterText(_manualFieldFinder('barangay'), 'Manual Barangay');
    }

    final changedCityDropdown = _dropdown(tester, 'city');
    final differentCity = changedCityDropdown.items!
        .firstWhere((item) => item.value != changedCityDropdown.value)
        .value!;
    changedCityDropdown.onChanged!(differentCity);
    await tester.pumpAndSettle();
    if (find
        .byKey(const ValueKey('edit-profile-barangay-manual'))
        .evaluate()
        .isNotEmpty) {
      expect(_manualField(tester, 'barangay').controller!.text, isEmpty);
    } else {
      expect(_dropdown(tester, 'barangay').value, isNull);
    }
  });

  testWidgets('late province loads cannot replace the latest selection', (
    tester,
  ) async {
    const address =
        'Province: Davao Occidental, City/Municipality: Sta. Maria, '
        'Barangay: Poblacion';
    await _openEditProfile(tester, address);

    final provinceDropdown = _dropdown(tester, 'province');
    provinceDropdown.onChanged!(_choiceValue(provinceDropdown, 'Batanes'));
    provinceDropdown.onChanged!(_choiceValue(provinceDropdown, 'Aklan'));
    await tester.pumpAndSettle();

    final latestProvince = _dropdown(tester, 'province');
    expect(latestProvince.value, _choiceValue(latestProvince, 'Aklan'));
    final cityOptions = _dropdown(
      tester,
      'city',
    ).items!.map((item) => (item.child as Text).data!).toList();
    expect(cityOptions, contains('Altavas'));
    expect(cityOptions, isNot(contains('Basco')));
    expect(
      cityOptions.where(
        (label) =>
            RegExp(r'\b(code|ID)\b', caseSensitive: false).hasMatch(label),
      ),
      isEmpty,
    );
  });

  testWidgets('equivalent province records produce one visible option', (
    tester,
  ) async {
    await _openEditProfile(tester, 'Province: Laguna');

    final labels = _provinceOptionLabels(tester);
    expect(
      labels.where((label) => label.toLowerCase() == 'laguna'),
      hasLength(1),
    );
    expect(
      labels.map((label) => label.toLowerCase()).toSet(),
      hasLength(labels.length),
    );
    expect(
      labels.where(
        (label) => RegExp(
          r'\b(code|ID|RegionNo)\b',
          caseSensitive: false,
        ).hasMatch(label),
      ),
      isEmpty,
    );
    expect(_dropdown(tester, 'province').value, isNotNull);
    expect(
      _selectedLabel(_dropdown(tester, 'province')).toLowerCase(),
      'laguna',
    );
  });

  testWidgets('distinct province identities are not silently merged', (
    tester,
  ) async {
    await _openEditProfile(tester, 'Province: Maguindanao');

    expect(_provinceOptionLabels(tester), isNot(contains('Maguindanao')));
    expect(_provinceOptionLabels(tester), isNot(contains('Benguet')));
    expect(_manualField(tester, 'province').controller!.text, 'Maguindanao');
    expect(_dropdown(tester, 'province').value, isNull);
  });

  testWidgets(
    'saving without address changes preserves the exact saved string',
    (tester) async {
      const original =
          'Apt 5,  Zip Code: 4027 , Province: Laguna, '
          'City/Municipality: Calamba, Barangay: Real';
      String? savedAddress;

      await http.runWithClient(
        () async {
          await _openEditProfile(tester, original);
          await tester.ensureVisible(find.text('Save'));
          await tester.tap(find.text('Save'));
          await tester.pump();
          await tester.pumpAndSettle();
        },
        () => MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          savedAddress = payload['address'] as String;
          return http.Response('{"success":true}', 200);
        }),
      );

      expect(savedAddress, original);
    },
  );

  testWidgets('does not initialize structured fields from a legacy address', (
    tester,
  ) async {
    const legacyAddress = 'Unit 4, Old Town Road, Laguna';
    await _openEditProfile(
      tester,
      legacyAddress,
      includeStructuredAddressFields: false,
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('edit-profile-unit')))
          .controller!
          .text,
      isEmpty,
    );
    expect(_field(tester, 'Street Address').controller!.text, isEmpty);
    expect(_zipField(tester).controller!.text, '');
    expect(_manualField(tester, 'province').controller!.text, '');
    expect(_manualField(tester, 'city').controller!.text, '');
    expect(_manualField(tester, 'barangay').controller!.text, '');
  });

  testWidgets(
    'login structured fields become unavailable after null profile GET and stay blank in Edit Profile',
    (tester) async {
      const legacyAddress = 'Unit 4, Old Town Road, Laguna';
      const keys = [
        'address_unit',
        'address_street',
        'address_barangay',
        'address_city_municipality',
        'address_province',
        'address_zip_code',
      ];
      final loginResponse = {
        'address': legacyAddress,
        for (final key in keys) key: 'login $key',
      };
      final loginProfile = {
        'patient_id': 'synthetic-patient',
        'address': loginResponse['address'],
        ...app.structuredAddressFieldsFromLoginResponse(loginResponse),
      };
      expect(
        keys.every((key) => loginProfile[key] == loginResponse[key]),
        isTrue,
      );

      final profileGetResponse = {for (final key in keys) key: null};
      final refreshedProfile = app.mergeProfileRefreshData(
        loginProfile,
        profileGetResponse,
      );
      expect(keys.every((key) => refreshedProfile[key] == null), isTrue);

      await _openEditProfile(
        tester,
        legacyAddress,
        profileData: refreshedProfile,
      );

      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('edit-profile-unit')))
            .controller!
            .text,
        isEmpty,
      );
      expect(_field(tester, 'Street Address').controller!.text, isEmpty);
      expect(_zipField(tester).controller!.text, isEmpty);
      for (final level in const ['province', 'city', 'barangay']) {
        final manualField = find.byKey(ValueKey('edit-profile-$level-manual'));
        expect(
          tester.widget<TextFormField>(manualField).controller!.text,
          isEmpty,
        );
      }
      expect(find.text(legacyAddress), findsOneWidget);
    },
  );

  testWidgets('blocks updates rather than clearing unresolved legacy fields', (
    tester,
  ) async {
    const legacyAddress = 'Unit 4, Old Town Road, Laguna';
    var requestCount = 0;
    await http.runWithClient(
      () async {
        await _openEditProfile(
          tester,
          legacyAddress,
          includeStructuredAddressFields: false,
        );
        expect(find.text(legacyAddress), findsOneWidget);
        await tester.enterText(_fieldFinder('Email'), 'updated@example.com');
        await tester.enterText(_fieldFinder('Contact number'), '5550100');
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        requestCount++;
        return http.Response('{"success":true}', 200);
      }),
    );

    expect(requestCount, 0);
    expect(
      find.text('Your saved address is still displayed below.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Its components are not available in the editable fields. Complete or restore them before saving profile changes; the app cannot reconstruct them automatically.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Email or contact changes cannot currently be saved separately while the structured address is incomplete.',
      ),
      findsOneWidget,
    );
    expect(find.text(legacyAddress), findsOneWidget);
  });

  testWidgets('no-unit address is not sent using an empty unit value', (
    tester,
  ) async {
    var requestCount = 0;
    await http.runWithClient(
      () async {
        await _openEditProfile(
          tester,
          '123 Main St, Zip Code: 4027, Province: Laguna, '
          'City/Municipality: Calamba, Barangay: Real',
          structuredAddressFields: {
            'address_unit': '',
            'address_street': '123 Main St',
            'address_barangay': 'Real',
            'address_city_municipality': 'Calamba',
            'address_province': 'Laguna',
            'address_zip_code': '4027',
          },
        );

        final unitField = tester.widget<TextField>(
          find.byKey(const ValueKey('edit-profile-unit')),
        );
        expect(unitField.controller!.text, isEmpty);
        expect(
          unitField.decoration!.labelText,
          'House / Unit / Lot / Block (if applicable)',
        );

        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        requestCount++;
        return http.Response('{"success":true}', 200);
      }),
    );

    expect(requestCount, 0);
    expect(
      find.textContaining(
        'the current API contract does not confirm a safe way to represent an address with no unit',
      ),
      findsOneWidget,
    );
  });

  testWidgets('incomplete structured legacy address is not sent or guessed', (
    tester,
  ) async {
    const original = 'Unit 4, Old Town Road, Laguna';
    var requestCount = 0;
    await http.runWithClient(
      () async {
        await _openEditProfile(
          tester,
          original,
          structuredAddressFields: {
            'address_unit': 'Unit 4',
            'address_street': 'Old Town Road',
            'address_barangay': '',
            'address_city_municipality': '',
            'address_province': '',
            'address_zip_code': '',
          },
        );

        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('edit-profile-unit')),
              )
              .controller!
              .text,
          'Unit 4',
        );
        expect(
          _field(tester, 'Street Address').controller!.text,
          'Old Town Road',
        );
        expect(_manualField(tester, 'province').controller!.text, isEmpty);

        await tester.enterText(_manualFieldFinder('province'), 'Laguna');
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pumpAndSettle();
      },
      () => MockClient((request) async {
        requestCount++;
        return http.Response('{"success":true}', 200);
      }),
    );

    expect(requestCount, 0);
    expect(
      find.textContaining(
        'This profile address cannot be saved safely yet because structured address details are missing.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('other profile changes cannot be saved separately'),
      findsOneWidget,
    );
  });
}

String _addressWithZip(String zip) =>
    'Unit 205, Zip Code: $zip, Province: Davao Occidental, '
    'City/Municipality: Sta. Maria, Barangay: Poblacion';

Future<void> _openEditProfile(
  WidgetTester tester,
  String address, {
  void Function(Map<String, dynamic>?)? onResult,
  Map<String, dynamic>? structuredAddressFields,
  bool includeStructuredAddressFields = true,
  Map<String, dynamic>? profileData,
}) async {
  final parsedAddress = parseStructuredAddress(address);
  final initialStructuredFields =
      structuredAddressFields ??
      <String, dynamic>{
        'address_unit': 'Unit 205',
        'address_street': parsedAddress['streetAddress']!.isEmpty
            ? '123 Main St'
            : parsedAddress['streetAddress'],
        'address_barangay': parsedAddress['barangay']!.isEmpty
            ? 'Poblacion'
            : parsedAddress['barangay'],
        'address_city_municipality': parsedAddress['city']!.isEmpty
            ? 'Baguio City'
            : parsedAddress['city'],
        'address_province': parsedAddress['province']!.isEmpty
            ? 'Benguet'
            : parsedAddress['province'],
        'address_zip_code': parsedAddress['zipCode']!.isEmpty
            ? '4027'
            : parsedAddress['zipCode'],
      };
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.of(context)
                  .push<Map<String, dynamic>>(
                    MaterialPageRoute<Map<String, dynamic>>(
                      builder: (_) => EditProfileScreen(
                        profile:
                            profileData ??
                            {
                              'patient_id': 'test-patient',
                              'first_name': 'Test',
                              'last_name': 'Patient',
                              'email': 'test@example.com',
                              'contact_number': '+639123456789',
                              'gender': 'Male',
                              'address': address,
                              if (includeStructuredAddressFields)
                                ...initialStructuredFields,
                            },
                      ),
                    ),
                  );
              onResult?.call(result);
            },
            child: const Text('Open Edit Profile'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open Edit Profile'));
  await tester.pumpAndSettle();
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final provinceDropdownFinder = find.descendant(
      of: find.byKey(const ValueKey('edit-profile-province-dropdown')),
      matching: find.byWidgetPredicate(
        (widget) => widget is DropdownButton<String>,
      ),
    );
    if (provinceDropdownFinder.evaluate().isNotEmpty &&
        tester
                .widget<DropdownButton<String>>(provinceDropdownFinder)
                .onChanged !=
            null) {
      break;
    }
  }
}

Finder _fieldFinder(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Finder _formFieldFinder(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(TextFormField),
  );
}

Finder _manualFieldFinder(String level) =>
    find.byKey(ValueKey('edit-profile-$level-manual'));

TextField _field(WidgetTester tester, String label) {
  return tester.widget<TextField>(_fieldFinder(label));
}

TextFormField _formField(WidgetTester tester, String label) {
  return tester.widget<TextFormField>(_formFieldFinder(label));
}

TextFormField _zipField(WidgetTester tester) =>
    tester.widget(find.byKey(const ValueKey('edit-profile-zip')));

TextFormField _manualField(WidgetTester tester, String level) {
  return tester.widget<TextFormField>(_manualFieldFinder(level));
}

DropdownButton<String> _dropdown(WidgetTester tester, String level) {
  return tester.widget(
    find.descendant(
      of: find.byKey(ValueKey('edit-profile-$level-dropdown')),
      matching: find.byWidgetPredicate(
        (widget) => widget is DropdownButton<String>,
      ),
    ),
  );
}

String _choiceValue(DropdownButton<String> dropdown, String label) {
  return dropdown.items!
      .firstWhere(
        (item) =>
            (item.child as Text).data!.toLowerCase() == label.toLowerCase(),
      )
      .value!;
}

String _selectedLabel(DropdownButton<String> dropdown) {
  return (dropdown.items!
              .firstWhere((item) => item.value == dropdown.value)
              .child
          as Text)
      .data!;
}

List<String> _provinceOptionLabels(WidgetTester tester) {
  return _dropdown(
    tester,
    'province',
  ).items!.map((item) => (item.child as Text).data!).toList();
}

Future<void> _selectOption(
  WidgetTester tester,
  String level,
  String label,
) async {
  final dropdown = _dropdown(tester, level);
  final key = _choiceValue(dropdown, label);
  final onChanged = dropdown.onChanged;
  expect(onChanged, isNotNull, reason: '$level dropdown should be enabled');
  onChanged!(key);
  await tester.pumpAndSettle();

  final nextLevel = switch (level) {
    'province' => 'city',
    'city' => 'barangay',
    _ => null,
  };
  if (nextLevel == null) {
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (find
              .text('ZIP Code updated for this location.')
              .evaluate()
              .isNotEmpty ||
          find
              .textContaining(
                "We couldn't find a unique ZIP Code for this location.",
              )
              .evaluate()
              .isNotEmpty) {
        break;
      }
    }
    return;
  }

  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final nextDropdown = find.descendant(
      of: find.byKey(ValueKey('edit-profile-$nextLevel-dropdown')),
      matching: find.byWidgetPredicate(
        (widget) => widget is DropdownButton<String>,
      ),
    );
    if (nextDropdown.evaluate().isNotEmpty &&
        tester.widget<DropdownButton<String>>(nextDropdown).onChanged != null) {
      break;
    }
  }
}
