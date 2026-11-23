import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/services/patient_session_service.dart';
import 'package:optcare_app/transaction_history_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Transaction history authentication and loading', () {
    testWidgets(
      'attaches bearer token and requests page 1 with correct patient ID',
      (tester) async {
        http.Request? captured;
        final sessionService = await _loggedInSessionService();

        await _runWithClient(
          tester,
          sessionService: sessionService,
          patientId: 'patient-1',
          authenticatedPatientId: 'patient-1',
          client: MockClient((request) async {
            captured = request;
            return _paginatedResponse(
              records: [_record(1, date: '2026-04-10')],
            );
          }),
        );

        expect(captured, isNotNull);
        expect(captured!.method, 'GET');
        expect(captured!.url.path, '/api/patients/patient-1/transactions');
        expect(captured!.url.queryParameters['page'], '1');
        expect(captured!.url.queryParameters['limit'], '10');
        expect(captured!.headers['authorization'], 'Bearer test-token');
        expect(captured!.headers['accept'], 'application/json');
      },
    );

    testWidgets('missing token prevents the protected request', (tester) async {
      var requestCount = 0;
      final sessionService = PatientSessionService(
        tokenStorage: _MemoryTokenStorage(),
      );

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          requestCount += 1;
          return _paginatedResponse(records: const []);
        }),
      );

      expect(requestCount, 0);
      expect(
        find.text('Please sign in to your patient account first.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-page-indicator')),
        findsNothing,
      );
    });

    testWidgets('mismatched patient identity prevents the protected request', (
      tester,
    ) async {
      var requestCount = 0;
      final sessionService = await _loggedInSessionService();

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-2',
        client: MockClient((request) async {
          requestCount += 1;
          return _paginatedResponse(records: const []);
        }),
      );

      expect(requestCount, 0);
      expect(
        find.text(
          'Unable to confirm your account for transaction history. Please sign in again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      '401 displays an authentication error without clearing valid session',
      (tester) async {
        final sessionService = await _loggedInSessionService();

        await _runWithClient(
          tester,
          sessionService: sessionService,
          patientId: 'patient-1',
          authenticatedPatientId: 'patient-1',
          client: MockClient((request) async {
            return http.Response(jsonEncode({'message': 'Unauthorized'}), 401);
          }),
        );

        expect(
          find.text(
            'Your session is no longer valid. Please sign in again to view transactions.',
          ),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(sessionService.token, 'test-token');
      },
    );

    testWidgets(
      '403 displays an authorization error without clearing valid session',
      (tester) async {
        final sessionService = await _loggedInSessionService();

        await _runWithClient(
          tester,
          sessionService: sessionService,
          patientId: 'patient-1',
          authenticatedPatientId: 'patient-1',
          client: MockClient((request) async {
            return http.Response(jsonEncode({'message': 'Forbidden'}), 403);
          }),
        );

        expect(
          find.text(
            'Your session is no longer valid. Please sign in again to view transactions.',
          ),
          findsOneWidget,
        );
        expect(sessionService.token, 'test-token');
      },
    );

    testWidgets(
      'network failures show retryable error and do not clear valid session',
      (tester) async {
        final sessionService = await _loggedInSessionService();

        await _runWithClient(
          tester,
          sessionService: sessionService,
          patientId: 'patient-1',
          authenticatedPatientId: 'patient-1',
          client: MockClient((request) async {
            throw http.ClientException('network down');
          }),
        );

        expect(find.text('Unable to connect to the server.'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(sessionService.token, 'test-token');
      },
    );
  });

  group('Transaction history display and server pagination', () {
    testWidgets('shows refresh icon in standalone AppBar', (tester) async {
      final sessionService = await _loggedInSessionService();

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          return _paginatedResponse(records: const []);
        }),
      );

      expect(
        find.byKey(const ValueKey('transaction-refresh')),
        findsOneWidget,
      );
    });

    testWidgets('shows refresh icon in embedded mode', (tester) async {
      final sessionService = await _loggedInSessionService();

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: TransactionHistoryScreen(
              patientId: 'patient-1',
              authenticatedPatientId: 'patient-1',
              sessionService: sessionService,
              showScaffold: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('transaction-refresh')),
          findsOneWidget,
        );
      }, () => MockClient((request) async {
        return _paginatedResponse(records: const []);
      }));
    });

    testWidgets(
      'shows proof section only for valid primary or fallback Cloudinary URLs',
      (tester) async {
        final sessionService = await _loggedInSessionService();

        await _runWithClient(
          tester,
          sessionService: sessionService,
          patientId: 'patient-1',
          authenticatedPatientId: 'patient-1',
          client: MockClient((request) async {
            return _paginatedResponse(
              records: [
                {
                  ..._record(1, date: '2026-04-01'),
                  'discount_id_proof_url':
                      'https://res.cloudinary.com/demo/image/upload/primary.png',
                },
                {
                  ..._record(2, date: '2026-04-02'),
                  'discount_id_proof_url': ' ',
                  'id_proof_url':
                      'https://res.cloudinary.com/demo/image/upload/fallback.png',
                },
                {
                  ..._record(3, date: '2026-04-03'),
                  'discount_id_proof_url': null,
                },
                {
                  ..._record(4, date: '2026-04-04'),
                  'discount_id_proof_url':
                      'http://res.cloudinary.com/demo/image/upload/insecure.png',
                },
                {
                  ..._record(5, date: '2026-04-05'),
                  'discount_id_proof_url':
                      'https://example.com/image/upload/unsupported.png',
                },
              ],
            );
          }),
        );

        expect(
          find.byKey(const ValueKey('transaction-proof-section')),
          findsNWidgets(2),
        );
        expect(
          find.byKey(const ValueKey('transaction-proof-thumbnail')),
          findsNWidgets(2),
        );

        await tester.tap(
          find.byKey(const ValueKey('transaction-proof-thumbnail')).first,
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('transaction-proof-dialog')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('transaction-proof-preview')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('transaction-proof-close')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('transaction-proof-dialog')),
          findsNothing,
        );
      },
    );

    testWidgets('shows unavailable state when proof image fails to load', (
      tester,
    ) async {
      final sessionService = await _loggedInSessionService();

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          return _paginatedResponse(
            records: [
              {
                ..._record(6, date: '2026-04-06'),
                'discount_id_proof_url':
                    'https://res.cloudinary.com/demo/image/upload/broken.png',
              },
            ],
          );
        }),
      );

      await tester.pumpAndSettle();
      expect(find.text('ID picture unavailable'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey('transaction-proof-thumbnail')),
      );
      await tester.pumpAndSettle();
      expect(find.text('ID picture unavailable'), findsWidgets);
    });

    testWidgets('renders transaction details and formatted monetary values', (
      tester,
    ) async {
      final sessionService = await _loggedInSessionService();

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          return _paginatedResponse(
            records: [
              {
                'title': 'Eyeglasses Purchase',
                'invoice_number': 'INV-001',
                'status': 'paid',
                'created_at': '2026-04-10T09:30:00.000Z',
                'items_summary': 'Aviator frame and lens package',
                'items': [
                  {
                    'item_name': 'Aviator Frame',
                    'quantity': 1,
                    'unit_price': 1500,
                  },
                  {
                    'item_name': 'Lens Package',
                    'quantity': 1,
                    'unit_price': 500,
                  },
                ],
                'subtotal': 2000,
                'vat_amount': 240,
                'amount': 2240,
              },
            ],
          );
        }),
      );

      expect(find.text('Eyeglasses Purchase'), findsOneWidget);
      expect(find.text('Ref: INV-001'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Aviator frame and lens package'), findsNothing);
      expect(find.text('Aviator Frame × 1'), findsOneWidget);
      expect(find.text('₱1,500.00'), findsWidgets);
      expect(find.text('Lens Package × 1'), findsOneWidget);
      expect(find.text('₱500.00'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('₱2,000.00'), findsOneWidget);
      expect(find.text('VAT'), findsOneWidget);
      expect(find.text('₱240.00'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('₱2,240.00'), findsNWidgets(2));
    });

    testWidgets(
      'shows backend discount name percent subtotal VAT and post-discount total',
      (tester) async {
        final sessionService = await _loggedInSessionService();

        await _runWithClient(
          tester,
          sessionService: sessionService,
          patientId: 'patient-1',
          authenticatedPatientId: 'patient-1',
          client: MockClient((request) async {
            return _paginatedResponse(
              records: [
                {
                  'title': 'Discounted Purchase',
                  'subtotal': 4999,
                  'discount_name': 'Senior/PWD',
                  'discount_percent': 20,
                  'discount_amount': '999.80',
                  'vat_amount': 479.90,
                  'total_amount': 4479.10,
                  'amount': 999999,
                },
              ],
            );
          }),
        );

        expect(find.text('Subtotal'), findsOneWidget);
        expect(find.text('₱4,999.00'), findsOneWidget);
        expect(find.text('Senior/PWD (20%)'), findsOneWidget);
        expect(find.text('₱-999.80'), findsOneWidget);
        expect(find.text('VAT'), findsOneWidget);
        expect(find.text('₱479.90'), findsOneWidget);
        expect(find.text('Total'), findsOneWidget);
        expect(find.text('₱4,479.10'), findsWidgets);
        expect(find.text('₱999,999.00'), findsNothing);
      },
    );

    testWidgets('uses generic Discount label when discount name is missing', (
      tester,
    ) async {
      final sessionService = await _loggedInSessionService();

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          return _paginatedResponse(
            records: [
              {
                'title': 'Generic Discount',
                'subtotal': 1000,
                'discount_amount': 100,
                'vat_amount': 108,
                'total_amount': 1008,
              },
            ],
          );
        }),
      );

      expect(find.text('Discount'), findsOneWidget);
      expect(find.text('₱-100.00'), findsOneWidget);
    });

    testWidgets('hides discount row for missing null zero or invalid amounts', (
      tester,
    ) async {
      final sessionService = await _loggedInSessionService();

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          return _paginatedResponse(
            records: [
              {'title': 'Missing', 'subtotal': 1000},
              {'title': 'Null', 'discount_amount': null},
              {'title': 'Zero', 'discount_amount': 0},
              {'title': 'Negative', 'discount_amount': -50},
              {'title': 'Invalid', 'discount_amount': 'not-a-number'},
            ],
          );
        }),
      );

      expect(find.text('Discount'), findsNothing);
    });

    testWidgets('prefers valid image_url and preserves item details', (tester) async {
      final sessionService = await _loggedInSessionService();

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: TransactionHistoryScreen(
              patientId: 'patient-1',
              authenticatedPatientId: 'patient-1',
              sessionService: sessionService,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.byKey(
            const ValueKey(
              'transaction-item-image:https://images.example.test/frame-primary.jpg',
            ),
          ),
          findsOneWidget,
        );
        expect(find.text('Aviator Frame × 1'), findsOneWidget);
        expect(find.text('₱1,500.00'), findsWidgets);
      }, () => MockClient((request) async {
        return _paginatedResponse(
          records: [
            {
              'title': 'Eyeglasses Purchase',
              'amount': 1500,
              'items': [
                {
                  'item_name': 'Aviator Frame',
                  'quantity': 1,
                  'unit_price': 1500,
                  'image_url':
                      'https://images.example.test/frame-primary.jpg',
                  'image_2d_url':
                      'https://images.example.test/frame-fallback.jpg',
                },
              ],
            },
          ],
        );
      }));
    });

    testWidgets('falls back to image_2d_url for missing or invalid primary', (
      tester,
    ) async {
      final sessionService = await _loggedInSessionService();

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: TransactionHistoryScreen(
              patientId: 'patient-1',
              authenticatedPatientId: 'patient-1',
              sessionService: sessionService,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.byKey(
            const ValueKey(
              'transaction-item-image:https://images.example.test/frame-2d.jpg',
            ),
          ),
          findsNWidgets(2),
        );
      }, () => MockClient((request) async {
        return _paginatedResponse(
          records: [
            {
              'title': 'Eyeglasses Purchase',
              'items': [
                {
                  'item_name': 'Frame Without Primary',
                  'quantity': 1,
                  'unit_price': 1000,
                  'image_2d_url':
                      'https://images.example.test/frame-2d.jpg',
                },
                {
                  'item_name': 'Frame With Invalid Primary',
                  'quantity': 1,
                  'unit_price': 1200,
                  'image_url': 'ftp://images.example.test/frame.jpg',
                  'image_2d_url':
                      'https://images.example.test/frame-2d.jpg',
                },
              ],
            },
          ],
        );
      }));
    });

    testWidgets('shows item placeholders for missing or invalid image URLs', (
      tester,
    ) async {
      final sessionService = await _loggedInSessionService();

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          return _paginatedResponse(
            records: [
              {
                'title': 'Eyeglasses Purchase',
                'items': [
                  {
                    'item_name': 'Frame Without Images',
                    'quantity': 1,
                    'unit_price': 1000,
                  },
                  {
                    'item_name': 'Frame With Invalid Images',
                    'quantity': 2,
                    'unit_price': 750,
                    'image_url': 'javascript:alert(1)',
                    'image_2d_url': 'not a url',
                  },
                ],
              },
            ],
          );
        }),
      );

      expect(
        find.byKey(const ValueKey('transaction-item-placeholder')),
        findsNWidgets(2),
      );
      expect(find.text('Frame Without Images × 1'), findsOneWidget);
      expect(find.text('Frame With Invalid Images × 2'), findsOneWidget);
      expect(find.text('₱1,000.00'), findsWidgets);
      expect(find.text('₱1,500.00'), findsWidgets);
    });

    testWidgets('item image loading failure shows placeholder without breaking card', (
      tester,
    ) async {
      final sessionService = await _loggedInSessionService();

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          return _paginatedResponse(
            records: [
              {
                'title': 'Eyeglasses Purchase',
                'amount': 1500,
                'items': [
                  {
                    'item_name': 'Broken Image Frame',
                    'quantity': 1,
                    'unit_price': 1500,
                    'image_url':
                        'https://images.example.test/broken-frame.jpg',
                  },
                ],
              },
            ],
          );
        }),
      );

      expect(find.text('Broken Image Frame × 1'), findsOneWidget);
      expect(find.text('₱1,500.00'), findsWidgets);
      expect(
        find.byKey(const ValueKey('transaction-item-placeholder')),
        findsOneWidget,
      );
    });

    testWidgets('manual refresh success replaces records and preserves page', (
      tester,
    ) async {
      final sessionService = await _loggedInSessionService();
      final requestedPages = <String>[];

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          final page = request.url.queryParameters['page'] ?? '1';
          requestedPages.add(page);
          return _paginatedResponse(
            records: [
              {
                'title': requestedPages.length == 1
                    ? 'Initial Transaction'
                    : 'Refreshed Transaction',
                'subtotal': 4999,
                'discount_name': 'Senior/PWD',
                'discount_percent': 20,
                'discount_amount': 999.80,
                'vat_amount': 479.90,
                'total_amount': 4479.10,
              },
            ],
            page: 1,
            totalPages: 1,
            total: 1,
          );
        }),
        afterLoad: () async {
          expect(find.text('Initial Transaction'), findsOneWidget);
          final refreshButton = tester.widget<IconButton>(
            find.byKey(const ValueKey('transaction-refresh')),
          );
          expect(refreshButton.onPressed, isNotNull);
          refreshButton.onPressed!.call();
          await tester.pumpAndSettle();

          expect(requestedPages, ['1', '1']);
          expect(find.text('Refreshed Transaction'), findsOneWidget);
          expect(find.text('Senior/PWD (20%)'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('transaction-refresh-error')),
            findsNothing,
          );
        },
      );
    });

    testWidgets('manual refresh failure preserves records discount and item data', (
      tester,
    ) async {
      final sessionService = await _loggedInSessionService();
      var requestCount = 0;

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          requestCount++;
          if (requestCount > 1) {
            throw http.ClientException('offline');
          }
          return _paginatedResponse(
            records: [
              {
                'title': 'Preserved Transaction',
                'subtotal': 4999,
                'discount_name': 'Senior/PWD',
                'discount_percent': 20,
                'discount_amount': 999.80,
                'vat_amount': 479.90,
                'total_amount': 4479.10,
                'items': [
                  {
                    'item_name': 'Preserved Frame',
                    'quantity': 1,
                    'unit_price': 4999,
                    'image_url':
                        'https://images.example.test/preserved-frame.jpg',
                  },
                ],
              },
            ],
            page: 1,
            totalPages: 1,
            total: 1,
          );
        }),
        afterLoad: () async {
          expect(find.text('Preserved Transaction'), findsOneWidget);
          expect(find.text('Preserved Frame × 1'), findsOneWidget);
          expect(find.text('Senior/PWD (20%)'), findsOneWidget);

          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('transaction-refresh')),
              )
              .onPressed!
              .call();
          await tester.pumpAndSettle();

          expect(find.text('Preserved Transaction'), findsOneWidget);
          expect(find.text('Preserved Frame × 1'), findsOneWidget);
          expect(find.text('Senior/PWD (20%)'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('transaction-refresh-error')),
            findsOneWidget,
          );
        },
      );
    });

    testWidgets('overlapping refresh requests are prevented', (tester) async {
      final sessionService = await _loggedInSessionService();
      final refreshCompleter = Completer<http.Response>();
      var requestCount = 0;

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          requestCount++;
          if (requestCount == 1) {
            return _paginatedResponse(
              records: [_record(1, date: '2026-04-01')],
              page: 1,
              totalPages: 1,
              total: 1,
            );
          }
          return refreshCompleter.future;
        }),
        afterLoad: () async {
          final firstRefreshButton = tester.widget<IconButton>(
            find.byKey(const ValueKey('transaction-refresh')),
          );
          firstRefreshButton.onPressed!.call();
          await tester.pump();
          final overlappingRefreshButton = tester.widget<IconButton>(
            find.byKey(const ValueKey('transaction-refresh')),
          );
          overlappingRefreshButton.onPressed?.call();
          await tester.pump();

          expect(requestCount, 2);

          refreshCompleter.complete(
            _paginatedResponse(
              records: [_record(2, date: '2026-04-02')],
              page: 1,
              totalPages: 1,
              total: 1,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Transaction 2'), findsOneWidget);
        },
      );
    });

    testWidgets('refresh preserves the currently selected page', (tester) async {
      final sessionService = await _loggedInSessionService();
      final requestedPages = <String>[];

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          final page = request.url.queryParameters['page'] ?? '1';
          requestedPages.add(page);
          if (page == '2') {
            return _paginatedResponse(
              records: [_record(2, date: '2026-04-02')],
              page: 2,
              totalPages: 2,
              total: 11,
            );
          }
          return _paginatedResponse(
            records: [_record(11, date: '2026-04-11')],
            page: 1,
            totalPages: 2,
            total: 11,
          );
        }),
        afterLoad: () async {
          await tester.tap(
            find.byKey(const ValueKey('transaction-next-page')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Page 2 of 2'), findsOneWidget);

          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('transaction-refresh')),
              )
              .onPressed!
              .call();
          await tester.pumpAndSettle();

          expect(requestedPages.last, '2');
          expect(find.text('Page 2 of 2'), findsOneWidget);
        },
      );
    });

    for (final scenario in [
      (
        name: 'transaction_status Pending Void takes precedence over payment',
        record: {
          'title': 'Pending void purchase',
          'transaction_status': 'Pending Void',
          'payment_status': 'Paid',
        },
        expectedStatus: 'Pending Void',
        expectedPaymentStatus: 'Paid',
      ),
      (
        name: 'transaction_status Voided takes precedence over payment',
        record: {
          'title': 'Voided purchase',
          'transaction_status': 'Voided',
          'payment_status': 'Paid',
        },
        expectedStatus: 'Voided',
        expectedPaymentStatus: null,
      ),
      (
        name: 'transaction_status Completed takes precedence over payment',
        record: {
          'title': 'Completed purchase',
          'transaction_status': 'Completed',
          'payment_status': 'Paid',
        },
        expectedStatus: 'Completed',
        expectedPaymentStatus: 'Paid',
      ),
      (
        name: 'generic status is used when transaction_status is missing',
        record: {
          'title': 'Generic status purchase',
          'status': 'Cancelled',
          'payment_status': 'Paid',
        },
        expectedStatus: 'Cancelled',
        expectedPaymentStatus: 'Paid',
      ),
      (
        name: 'payment status is used when transaction and generic status are missing',
        record: {
          'title': 'Payment status purchase',
          'payment_status': 'Paid',
        },
        expectedStatus: 'Paid',
        expectedPaymentStatus: null,
      ),
    ]) {
      testWidgets(scenario.name, (tester) async {
        final sessionService = await _loggedInSessionService();

        await _runWithClient(
          tester,
          sessionService: sessionService,
          patientId: 'patient-1',
          authenticatedPatientId: 'patient-1',
          client: MockClient((request) async {
            return _paginatedResponse(records: [scenario.record]);
          }),
        );

        expect(find.text(scenario.expectedStatus), findsOneWidget);
        if (scenario.expectedPaymentStatus != null) {
          expect(find.text(scenario.expectedPaymentStatus!), findsOneWidget);
        }
      });
    }

    testWidgets(
      'parses paginated envelope and shows correct controls for first page',
      (tester) async {
        final sessionService = await _loggedInSessionService();

        await _runWithClient(
          tester,
          sessionService: sessionService,
          patientId: 'patient-1',
          authenticatedPatientId: 'patient-1',
          client: MockClient((request) async {
            return _paginatedResponse(
              records: [_record(11, date: '2026-04-11')],
              page: 1,
              totalPages: 2,
              total: 11,
            );
          }),
        );

        expect(find.text('Transaction 11'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('transaction-page-indicator')),
          findsOneWidget,
        );
        expect(find.text('Page 1 of 2'), findsOneWidget);
        expect(_isPreviousPageDisabled(tester), isTrue);
        expect(_isNextPageDisabled(tester), isFalse);
      },
    );

    testWidgets('Next and Previous request the correct server pages', (
      tester,
    ) async {
      final pages = <String>[];
      final sessionService = await _loggedInSessionService();

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          final page = request.url.queryParameters['page'] ?? '1';
          pages.add(page);
          if (page == '2') {
            return _paginatedResponse(
              records: [_record(1, date: '2026-04-01')],
              page: 2,
              totalPages: 2,
              total: 11,
            );
          }
          return _paginatedResponse(
            records: [_record(11, date: '2026-04-11')],
            page: 1,
            totalPages: 2,
            total: 11,
          );
        }),
        afterLoad: () async {
          expect(pages, ['1']);
          expect(find.text('Transaction 11'), findsOneWidget);
          expect(_isNextPageDisabled(tester), isFalse);

          await tester.tap(find.byKey(const ValueKey('transaction-next-page')));
          await tester.pump();
          await tester.pumpAndSettle();

          expect(pages, ['1', '2']);
          expect(find.text('Page 2 of 2'), findsOneWidget);
          expect(find.text('Transaction 1'), findsOneWidget);
          expect(_isPreviousPageDisabled(tester), isFalse);
          expect(_isNextPageDisabled(tester), isTrue);

          await tester.tap(
            find.byKey(const ValueKey('transaction-previous-page')),
          );
          await tester.pump();
          await tester.pumpAndSettle();

          expect(pages, ['1', '2', '1']);
          expect(find.text('Page 1 of 2'), findsOneWidget);
          expect(find.text('Transaction 11'), findsOneWidget);
        },
      );
    });

    testWidgets('shows empty state for genuinely empty transaction history', (
      tester,
    ) async {
      final sessionService = await _loggedInSessionService();

      await _runWithClient(
        tester,
        sessionService: sessionService,
        patientId: 'patient-1',
        authenticatedPatientId: 'patient-1',
        client: MockClient((request) async {
          return _paginatedResponse(
            records: const [],
            page: 1,
            totalPages: 0,
            total: 0,
          );
        }),
      );

      expect(find.text('No transactions yet.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transaction-page-indicator')),
        findsNothing,
      );
    });

    testWidgets(
      'shows safe error when pagination metadata is missing or invalid',
      (tester) async {
        final sessionService = await _loggedInSessionService();

        await _runWithClient(
          tester,
          sessionService: sessionService,
          patientId: 'patient-1',
          authenticatedPatientId: 'patient-1',
          client: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'success': true,
                'transactions': [_record(1, date: '2026-04-01')],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        expect(
          find.text('Unable to load transactions. Please try again later.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Transaction 1'), findsNothing);
      },
    );
  });

  group('Transaction history retry and page recovery', () {
    testWidgets(
      'retries the appropriate page request and prevents duplicate retries',
      (tester) async {
        final pages = <String>[];
        final completer = Completer<http.Response>();
        final sessionService = await _loggedInSessionService();

        await _runWithClient(
          tester,
          sessionService: sessionService,
          patientId: 'patient-1',
          authenticatedPatientId: 'patient-1',
          client: MockClient((request) async {
            final page = request.url.queryParameters['page'] ?? '1';
            pages.add(page);
            if (pages.length == 1) {
              throw http.ClientException('temporary');
            }
            if (pages.length == 2) {
              return completer.future;
            }
            return _paginatedResponse(
              records: [_record(1, date: '2026-04-01')],
              page: 1,
              totalPages: 1,
              total: 1,
            );
          }),
          afterLoad: () async {
            expect(
              find.text('Unable to connect to the server.'),
              findsOneWidget,
            );
            expect(find.text('Retry'), findsOneWidget);
            final initialRetryButton = tester.widget<ElevatedButton>(
              find.ancestor(
                of: find.text('Retry'),
                matching: find.byType(ElevatedButton),
              ),
            );
            expect(initialRetryButton.onPressed, isNotNull);

            await tester.tap(find.text('Retry'));
            await tester.pump();
            await tester.pump();

            expect(pages, ['1', '1']);
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            expect(find.text('Retry'), findsNothing);

            completer.complete(
              _paginatedResponse(
                records: [_record(1, date: '2026-04-01')],
                page: 1,
                totalPages: 1,
                total: 1,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Transaction 1'), findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsNothing);
          },
        );
      },
    );

    testWidgets(
      'recovers to last valid page when requested page exceeds total pages',
      (tester) async {
        final pages = <String>[];
        var requestedNext = false;
        final sessionService = await _loggedInSessionService();

        await _runWithClient(
          tester,
          sessionService: sessionService,
          patientId: 'patient-1',
          authenticatedPatientId: 'patient-1',
          client: MockClient((request) async {
            final page = request.url.queryParameters['page'] ?? '1';
            pages.add(page);
            if (!requestedNext && page == '1') {
              return _paginatedResponse(
                records: [_record(11, date: '2026-04-11')],
                page: 1,
                totalPages: 2,
                total: 11,
              );
            }
            if (page == '2') {
              return _paginatedResponse(
                records: const [],
                page: 2,
                totalPages: 1,
                total: 5,
              );
            }
            if (page == '1' && requestedNext) {
              return _paginatedResponse(
                records: [_record(5, date: '2026-04-05')],
                page: 1,
                totalPages: 1,
                total: 5,
              );
            }
            return _paginatedResponse(
              records: [_record(5, date: '2026-04-05')],
              page: 1,
              totalPages: 1,
              total: 5,
            );
          }),
          afterLoad: () async {
            requestedNext = true;
            expect(_isNextPageDisabled(tester), isFalse);
            await tester.tap(
              find.byKey(const ValueKey('transaction-next-page')),
            );
            await tester.pump();
            await tester.pumpAndSettle();

            expect(pages, containsAllInOrder(['1', '2', '1']));
            expect(pages.last, '1');
            expect(find.text('Page 1 of 1'), findsOneWidget);
            expect(find.text('Transaction 5'), findsOneWidget);
            expect(
              pages.where((page) => page == '2').length,
              1,
              reason: 'invalid page should not be retried in a loop',
            );
          },
        );
      },
    );
  });
}

Future<void> _runWithClient(
  WidgetTester tester, {
  required PatientSessionService sessionService,
  required String? patientId,
  required String? authenticatedPatientId,
  required MockClient client,
  Future<void> Function()? afterLoad,
}) {
  return http.runWithClient(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: TransactionHistoryScreen(
          patientId: patientId,
          authenticatedPatientId: authenticatedPatientId,
          sessionService: sessionService,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (afterLoad != null) {
      await afterLoad();
    }
  }, () => client);
}

Future<PatientSessionService> _loggedInSessionService() async {
  final service = PatientSessionService(
    tokenStorage: _MemoryTokenStorage(),
    client: MockClient((request) async {
      if (request.url.path.endsWith('/api/patients/login')) {
        return http.Response(
          jsonEncode({
            'token': 'test-token',
            'patient': {'patient_id': 'patient-1'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    }),
  );

  await service.login(
    email: 'user@example.com',
    password: 'password',
    rememberMe: false,
  );
  return service;
}

class _MemoryTokenStorage implements PatientTokenStorage {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async {
    _token = token;
  }

  @override
  Future<void> deleteToken() async {
    _token = null;
  }
}

http.Response _paginatedResponse({
  required List<dynamic> records,
  int page = 1,
  int limit = 10,
  int? total,
  int? totalPages,
}) {
  final resolvedTotal = total ?? records.length;
  final resolvedTotalPages =
      totalPages ??
      (resolvedTotal == 0 ? 0 : ((resolvedTotal - 1) ~/ limit) + 1);

  return http.Response(
    jsonEncode({
      'success': true,
      'transactions': records,
      'pagination': {
        'page': page,
        'limit': limit,
        'total': resolvedTotal,
        'totalPages': resolvedTotalPages,
      },
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _record(int index, {required String date}) {
  return {
    'title': 'Transaction $index',
    'invoice_number': 'INV-$index',
    'status': 'paid',
    'created_at': date,
    'amount': index * 100,
  };
}

bool _isPreviousPageDisabled(WidgetTester tester) {
  final button = tester.widget<TextButton>(
    find.byKey(const ValueKey('transaction-previous-page')),
  );
  return button.onPressed == null;
}

bool _isNextPageDisabled(WidgetTester tester) {
  final button = tester.widget<TextButton>(
    find.byKey(const ValueKey('transaction-next-page')),
  );
  return button.onPressed == null;
}
