import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/edit_profile_screen.dart';
import 'package:optcare_app/main.dart' as app;
import 'package:ph_address_finder/ph_address_finder.dart';

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

  testWidgets(
    'Dashboard maps synthetic profile response into Profile and Edit Profile',
    (tester) async {
      const patientId = 'synthetic-profile-mapping-id';
      const flatAddress =
          'Unit 7, 99 Test Road, Zip Code: 4027, Province: Benguet, '
          'City/Municipality: Baguio City, Barangay: Poblacion';
      const patientResponse = {
        'patient_id': patientId,
        'name': 'Casey Sample Patient',
        'contact': '0000000000',
        'email': 'synthetic@example.invalid',
        'address': flatAddress,
        'address_unit': 'Unit 7',
        'address_street': '99 Test Road',
        'address_barangay': 'Poblacion',
        'address_city_municipality': 'Baguio City',
        'address_province': 'Benguet',
        'address_zip_code': '4027',
      };
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {};

      try {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              const MaterialApp(
                home: app.DashboardScreen(
                  profileData: {'patient_id': patientId},
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('My Profile').last);
            await tester.pumpAndSettle();

            expect(find.text('Casey Sample Patient'), findsOneWidget);
            expect(find.text('0000000000'), findsOneWidget);
            expect(find.text('Unit'), findsOneWidget);
            expect(find.text('Unit 7'), findsOneWidget);
            expect(find.text('Street'), findsOneWidget);
            expect(find.text('99 Test Road'), findsOneWidget);
            expect(find.text('4027'), findsOneWidget);
            expect(find.text('Benguet'), findsOneWidget);
            expect(find.text('Baguio City'), findsOneWidget);
            expect(find.text('Poblacion'), findsOneWidget);

            await tester.ensureVisible(find.text('Edit Profile'));
            await tester.tap(find.text('Edit Profile'));
            await tester.pumpAndSettle();
            for (var attempt = 0; attempt < 20; attempt++) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await tester.pump();
              final provinceField = find.byKey(
                const ValueKey('edit-profile-province-manual'),
              );
              if (provinceField.evaluate().isNotEmpty) break;
            }

            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('edit-profile-unit')),
                  )
                  .controller!
                  .text,
              'Unit 7',
            );
            expect(
              tester
                  .widget<TextField>(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is TextField &&
                          widget.decoration?.labelText == 'Street Address',
                    ),
                  )
                  .controller!
                  .text,
              '99 Test Road',
            );
            expect(
              tester
                  .widget<TextFormField>(
                    find.byKey(const ValueKey('edit-profile-zip')),
                  )
                  .controller!
                  .text,
              '4027',
            );
            for (final entry in const {
              'province': 'Benguet',
              'city': 'Baguio City',
              'barangay': 'Poblacion',
            }.entries) {
              expect(
                tester
                    .widget<TextFormField>(
                      find.byKey(ValueKey('edit-profile-${entry.key}-manual')),
                    )
                    .controller!
                    .text,
                entry.value,
              );
            }
          },
          () => MockClient((request) async {
            if (request.method == 'GET' &&
                request.url.path == '/api/patients/$patientId') {
              return http.Response(jsonEncode(patientResponse), 200);
            }
            return http.Response('[]', 200);
          }),
        );
      } finally {
        debugPrint = previousDebugPrint;
      }
    },
  );

  testWidgets(
    'profile shows loading and an error without losing existing details',
    (tester) async {
      const patientId = 'synthetic-profile-loading-id';
      final profileResponse = Completer<http.Response>();
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {};

      try {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              const MaterialApp(
                home: app.DashboardScreen(
                  profileData: {
                    'patient_id': patientId,
                    'first_name': 'Taylor',
                    'last_name': 'Example',
                    'email': 'synthetic@example.invalid',
                    'contact_number': '0000000000',
                    'address': 'Legacy profile address',
                  },
                ),
              ),
            );
            await tester.tap(find.text('My Profile').last);
            await tester.pump();

            expect(
              find.byKey(const ValueKey('profile-loading')),
              findsOneWidget,
            );

            profileResponse.complete(
              http.Response('{"error":"synthetic failure"}', 503),
            );
            await tester.pumpAndSettle();

            expect(find.byKey(const ValueKey('profile-loading')), findsNothing);
            expect(
              find.byKey(const ValueKey('profile-load-error')),
              findsOneWidget,
            );
            expect(
              find.text('Unable to load profile. Please try again.'),
              findsOneWidget,
            );
            expect(find.text('Taylor Example'), findsOneWidget);
            expect(find.text('synthetic@example.invalid'), findsNWidgets(2));
            expect(find.text('0000000000'), findsOneWidget);
          },
          () => MockClient((request) async {
            if (request.method == 'GET' &&
                request.url.path == '/api/patients/$patientId') {
              return profileResponse.future;
            }
            return http.Response('[]', 200);
          }),
        );
      } finally {
        debugPrint = previousDebugPrint;
      }
    },
  );

  testWidgets(
    'Dashboard keeps GET-confirmed address when a pre-save refresh completes later',
    (tester) async {
      const patientId = 'synthetic-patient-id';
      const oldAddress =
          'Unit 205, 123 Main St, Zip Code: 4027, Province: Benguet, '
          'City/Municipality: Baguio City, Barangay: Poblacion';
      const updatedStreet = '456 Synthetic Street';
      const updatedAddress =
          'Unit 205, 456 Synthetic Street, Zip Code: 4027, Province: Benguet, '
          'City/Municipality: Baguio City, Barangay: Poblacion';

      final staleRefreshStarted = Completer<void>();
      final staleRefreshResponse = Completer<http.Response>();
      var patientGetCount = 0;
      Map<String, dynamic>? putPayload;

      final previousDebugPrint = debugPrint;
      final diagnosticLogs = <String>[];
      debugPrint = (message, {wrapWidth}) {
        if (message != null) diagnosticLogs.add(message);
      };

      try {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                home: app.DashboardScreen(
                  profileData: {
                    'patient_id': patientId,
                    'first_name': 'Synthetic',
                    'last_name': 'Patient',
                    'name': 'Synthetic Patient',
                    'email': 'synthetic@example.invalid',
                    'contact_number': '0000000000',
                    'gender': 'Male',
                    'address': oldAddress,
                    'address_unit': 'Unit 205',
                    'address_street': '123 Main St',
                    'address_barangay': 'Poblacion',
                    'address_city_municipality': 'Baguio City',
                    'address_province': 'Benguet',
                    'address_zip_code': '4027',
                  },
                ),
              ),
            );
            await tester.pump();

            for (
              var attempt = 0;
              attempt < 20 && !staleRefreshStarted.isCompleted;
              attempt++
            ) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await tester.pump();
            }
            expect(staleRefreshStarted.isCompleted, isTrue);

            await tester.tap(find.text('My Profile').last);
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Edit Profile'));
            await tester.tap(find.text('Edit Profile'));
            await tester.pumpAndSettle();

            final streetField = find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText == 'Street Address',
            );
            await tester.ensureVisible(streetField);
            await tester.enterText(streetField, updatedStreet);
            await tester.ensureVisible(find.text('Save'));
            await tester.tap(find.text('Save'));
            await tester.pump();
            await tester.pumpAndSettle();

            expect(putPayload, isNotNull);
            final stateMatchLog = diagnosticLogs.singleWhere(
              (message) => message.startsWith('PROFILE ADDRESS STATE:'),
            );
            expect(
              stateMatchLog,
              'PROFILE ADDRESS STATE: matchesConfirmedResponse=true',
            );
            expect(stateMatchLog, isNot(contains(oldAddress)));
            expect(stateMatchLog, isNot(contains(updatedAddress)));
            final confirmationLog = diagnosticLogs.singleWhere(
              (message) => message.startsWith('EDIT PROFILE CONFIRMATION:'),
            );
            expect(confirmationLog, contains('addressMatches=true'));
            expect(confirmationLog, contains('patientIdMatches=true'));
            expect(confirmationLog, contains('address_unit: true'));
            expect(confirmationLog, contains('address_street: true'));
            expect(confirmationLog, contains('address_barangay: true'));
            expect(
              confirmationLog,
              contains('address_city_municipality: true'),
            );
            expect(confirmationLog, contains('address_province: true'));
            expect(confirmationLog, contains('address_zip_code: true'));
            expect(
              find.byWidgetPredicate(
                (widget) =>
                    widget is app.ProfileAddressDisplay &&
                    widget.address == updatedAddress,
              ),
              findsOneWidget,
            );
            expect(find.text(oldAddress), findsNothing);

            staleRefreshResponse.complete(
              http.Response(
                jsonEncode({
                  'patient_id': patientId,
                  'name': 'Synthetic Patient',
                  'address': oldAddress,
                  'address_unit': 'Unit 205',
                  'address_street': '123 Main St',
                  'address_barangay': 'Poblacion',
                  'address_city_municipality': 'Baguio City',
                  'address_province': 'Benguet',
                  'address_zip_code': '4027',
                }),
                200,
              ),
            );
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();

            expect(
              find.byWidgetPredicate(
                (widget) =>
                    widget is app.ProfileAddressDisplay &&
                    widget.address == updatedAddress,
              ),
              findsOneWidget,
            );
            expect(find.text(oldAddress), findsNothing);
          },
          () => MockClient((request) async {
            if (request.method == 'PUT') {
              putPayload = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response('{"success":true}', 200);
            }

            if (request.url.path == '/api/patients/$patientId') {
              patientGetCount++;
              if (patientGetCount == 1) {
                staleRefreshStarted.complete();
                return staleRefreshResponse.future;
              }
              return http.Response(
                jsonEncode({
                  'patient_id': patientId,
                  'name': 'Synthetic Patient',
                  'address': putPayload!['address'],
                  for (final key in const [
                    'address_unit',
                    'address_street',
                    'address_barangay',
                    'address_city_municipality',
                    'address_province',
                    'address_zip_code',
                  ])
                    key: putPayload![key],
                }),
                200,
              );
            }

            return http.Response('[]', 200);
          }),
        );
      } finally {
        debugPrint = previousDebugPrint;
      }

      expect(patientGetCount, 2);
      expect(putPayload?['address'], updatedAddress);
    },
  );
}
