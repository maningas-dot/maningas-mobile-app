import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/main.dart';

void main() {
  group('Philippine peso frame price formatting', () {
    test('uses thousands separators, two decimals, and rounding', () {
      expect(formatPhilippinePeso(1500), '₱1,500.00');
      expect(formatPhilippinePeso(12000), '₱12,000.00');
      expect(formatPhilippinePeso(125000.5), '₱125,000.50');
      expect(formatPhilippinePeso(1.999), '₱2.00');
      expect(formatPhilippinePeso(0), '₱0.00');
    });

    test('parses numeric JSON values and ungrouped numeric strings', () {
      final numeric = FrameModel.fromJson({
        'frame_id': 1,
        'name': 'Numeric Price',
        'price': 12000,
        'stock': 3,
      });
      final string = FrameModel.fromJson({
        'frame_id': 2,
        'name': 'String Price',
        'price': '125000.5',
        'stock': 2,
      });

      expect(numeric.price, 12000);
      expect(string.price, 125000.5);
      expect([numeric, string]..sort((a, b) => a.price!.compareTo(b.price!)), [
        numeric,
        string,
      ]);
      expect(numeric.price! + string.price!, 137000.5);
    });

    test('does not invent a zero price for missing or invalid values', () {
      expect(parseFramePrice(null), isNull);
      expect(parseFramePrice(''), isNull);
      expect(parseFramePrice('₱1,234.50'), isNull);
      expect(parseFramePrice('invalid'), isNull);
      expect(parseFramePrice(double.nan), isNull);
      expect(formatPhilippinePeso(null), 'Price unavailable');

      final missingPrice = FrameModel.fromJson({
        'frame_id': 3,
        'name': 'Missing Price',
      });
      final invalidPrice = FrameModel.fromJson({
        'frame_id': 4,
        'name': 'Invalid Price',
        'price': '₱1,234.50',
      });
      expect(missingPrice.price, isNull);
      expect(invalidPrice.price, isNull);
    });
  });

  testWidgets('frames catalog uses paginated server controls', (tester) async {
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {};
    final requests = <Uri>[];

    try {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: DashboardScreen(profileData: {})),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Explore Frames').last);
          await tester.pumpAndSettle();

          expect(requests, isNotEmpty);
          expect(requests.last.path, '/api/frames/page');
          expect(requests.last.queryParameters['page'], '1');
          expect(requests.last.queryParameters['limit'], '10');
          expect(requests.last.queryParameters['sort'], 'newest');
          expect(requests.last.queryParameters['availability'], 'all');

          await tester.enterText(find.byType(TextField), '  Ray  ');
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();

          expect(requests.last.queryParameters['search'], 'Ray');
          expect(requests.last.queryParameters['page'], '1');

          await tester.tap(find.text('Sunglasses').last);
          await tester.pumpAndSettle();
          expect(requests.last.queryParameters['category'], 'Sunglasses');
          expect(requests.last.queryParameters['page'], '1');
        },
        () => MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/frames/page') {
            requests.add(request.url);
            return http.Response(
              jsonEncode({
                'items': [],
                'categories': ['Sunglasses'],
                'pagination': {
                  'page': 1,
                  'limit': 10,
                  'total': 0,
                  'totalPages': 0,
                },
              }),
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/appointments') {
            return http.Response('[]', 200);
          }
          return http.Response('[]', 200);
        }),
      );
    } finally {
      debugPrint = previousDebugPrint;
    }
  });

  testWidgets(
    'older search response cannot overwrite a newer debounced search',
    (tester) async {
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {};
      final oldResponse = Completer<http.Response>();

      try {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              const MaterialApp(home: DashboardScreen(profileData: {})),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Explore Frames').last);
            await tester.pumpAndSettle();

            await tester.enterText(find.byType(TextField), 'A');
            await tester.pump(const Duration(milliseconds: 300));
            await tester.enterText(find.byType(TextField), 'Latest');
            await tester.pump(const Duration(milliseconds: 100));
            oldResponse.complete(
              http.Response(
                jsonEncode({
                  'items': [
                    {'frame_id': 1, 'name': 'Older Frame', 'stock_quantity': 3},
                  ],
                  'categories': [],
                  'pagination': {
                    'page': 1,
                    'limit': 10,
                    'total': 1,
                    'totalPages': 1,
                  },
                }),
                200,
              ),
            );
            await tester.pump(const Duration(milliseconds: 250));
            await tester.pumpAndSettle();

            expect(find.text('Latest Frame'), findsOneWidget);
            expect(find.text('Older Frame'), findsNothing);
          },
          () => MockClient((request) async {
            if (request.url.path == '/api/frames/page') {
              final search = request.url.queryParameters['search'] ?? '';
              if (search.isEmpty) {
                return http.Response(
                  jsonEncode({
                    'items': [
                      {
                        'frame_id': 0,
                        'name': 'Initial Frame',
                        'stock_quantity': 3,
                      },
                    ],
                    'categories': [],
                    'pagination': {
                      'page': 1,
                      'limit': 10,
                      'total': 1,
                      'totalPages': 1,
                    },
                  }),
                  200,
                );
              }
              if (search == 'A') {
                return oldResponse.future;
              }
              return http.Response(
                jsonEncode({
                  'items': [
                    {
                      'frame_id': 2,
                      'name': 'Latest Frame',
                      'stock_quantity': 3,
                    },
                  ],
                  'categories': [],
                  'pagination': {
                    'page': 1,
                    'limit': 10,
                    'total': 1,
                    'totalPages': 1,
                  },
                }),
                200,
              );
            }
            if (request.url.path == '/api/appointments') {
              return http.Response('[]', 200);
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
    'zero-total page normalizes to one and recovers without looping',
    (tester) async {
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {};
      var pageOneRequests = 0;
      var pageTwoRequests = 0;

      try {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              const MaterialApp(home: DashboardScreen(profileData: {})),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Explore Frames').last);
            await tester.pumpAndSettle();

            await tester.tap(find.byTooltip('Next'));
            await tester.pumpAndSettle();

            expect(pageOneRequests, 2);
            expect(pageTwoRequests, 1);
            expect(find.text('No frames currently available'), findsOneWidget);
          },
          () => MockClient((request) async {
            if (request.url.path == '/api/frames/page') {
              final page = int.parse(
                request.url.queryParameters['page'] ?? '1',
              );
              if (page == 1 && pageOneRequests == 0) {
                pageOneRequests++;
                return http.Response(
                  jsonEncode({
                    'items': [
                      {
                        'frame_id': 10,
                        'name': 'Recovered Frame',
                        'stock_quantity': 3,
                      },
                    ],
                    'categories': [],
                    'pagination': {
                      'page': 1,
                      'limit': 10,
                      'total': 11,
                      'totalPages': 2,
                    },
                  }),
                  200,
                );
              }
              if (page == 1) {
                pageOneRequests++;
                return http.Response(
                  jsonEncode({
                    'items': [],
                    'categories': [],
                    'pagination': {
                      'page': 1,
                      'limit': 10,
                      'total': 0,
                      'totalPages': 0,
                    },
                  }),
                  200,
                );
              }
              pageTwoRequests++;
              return http.Response(
                jsonEncode({
                  'items': [],
                  'categories': [],
                  'pagination': {
                    'page': 2,
                    'limit': 10,
                    'total': 0,
                    'totalPages': 0,
                  },
                }),
                200,
              );
            }
            if (request.url.path == '/api/appointments') {
              return http.Response('[]', 200);
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
    'pagination controls are disabled while loading and rapid taps remain guarded',
    (tester) async {
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {};
      final pageTwoResponse = Completer<http.Response>();
      var pageTwoRequests = 0;

      try {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              const MaterialApp(home: DashboardScreen(profileData: {})),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Explore Frames').last);
            await tester.pumpAndSettle();

            await tester.tap(find.byTooltip('Next'));
            await tester.pump();

            expect(pageTwoRequests, 1);
            final previousButton = tester.widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.chevron_left),
                matching: find.byType(IconButton),
              ),
            );
            final nextButton = tester.widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.chevron_right),
                matching: find.byType(IconButton),
              ),
            );
            expect(previousButton.onPressed, isNull);
            expect(nextButton.onPressed, isNull);

            await tester.tap(find.byTooltip('Next'));
            await tester.pump();
            expect(pageTwoRequests, 1);

            pageTwoResponse.complete(
              http.Response(
                jsonEncode({
                  'items': [
                    {'frame_id': 11, 'name': 'Frame 11', 'stock_quantity': 3},
                  ],
                  'categories': [],
                  'pagination': {
                    'page': 2,
                    'limit': 10,
                    'total': 11,
                    'totalPages': 2,
                  },
                }),
                200,
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Page 2 of 2'), findsOneWidget);
            expect(
              tester
                  .widget<IconButton>(
                    find.ancestor(
                      of: find.byIcon(Icons.chevron_right),
                      matching: find.byType(IconButton),
                    ),
                  )
                  .onPressed,
              isNull,
            );
          },
          () => MockClient((request) async {
            if (request.url.path == '/api/frames/page') {
              final page = int.parse(
                request.url.queryParameters['page'] ?? '1',
              );
              if (page == 1) {
                return http.Response(
                  jsonEncode({
                    'items': [
                      {'frame_id': 10, 'name': 'Frame 10', 'stock_quantity': 3},
                    ],
                    'categories': [],
                    'pagination': {
                      'page': 1,
                      'limit': 10,
                      'total': 11,
                      'totalPages': 2,
                    },
                  }),
                  200,
                );
              }
              pageTwoRequests++;
              return pageTwoResponse.future;
            }
            if (request.url.path == '/api/appointments') {
              return http.Response('[]', 200);
            }
            return http.Response('[]', 200);
          }),
        );
      } finally {
        debugPrint = previousDebugPrint;
      }
    },
  );

  testWidgets('invalid returned pagination limit shows recoverable error', (
    tester,
  ) async {
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {};

    try {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: DashboardScreen(profileData: {})),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Explore Frames').last);
          await tester.pumpAndSettle();
          expect(find.text('Unable to load frames'), findsOneWidget);
          expect(
            find.text('Please check your connection and try again.'),
            findsOneWidget,
          );
          expect(find.text('Retry'), findsOneWidget);
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/frames/page') {
            return http.Response(
              jsonEncode({
                'items': [],
                'categories': [],
                'pagination': {
                  'page': 1,
                  'limit': 20,
                  'total': 0,
                  'totalPages': 0,
                },
              }),
              200,
            );
          }
          if (request.url.path == '/api/appointments') {
            return http.Response('[]', 200);
          }
          return http.Response('[]', 200);
        }),
      );
    } finally {
      debugPrint = previousDebugPrint;
    }
  });

  testWidgets('missing returned pagination limit shows recoverable error', (
    tester,
  ) async {
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {};

    try {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: DashboardScreen(profileData: {})),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Explore Frames').last);
          await tester.pumpAndSettle();
          expect(find.text('Unable to load frames'), findsOneWidget);
          expect(
            find.text('Please check your connection and try again.'),
            findsOneWidget,
          );
          expect(find.text('Retry'), findsOneWidget);
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/frames/page') {
            return http.Response(
              jsonEncode({
                'items': [],
                'categories': [],
                'pagination': {'page': 1, 'total': 0, 'totalPages': 0},
              }),
              200,
            );
          }
          if (request.url.path == '/api/appointments') {
            return http.Response('[]', 200);
          }
          return http.Response('[]', 200);
        }),
      );
    } finally {
      debugPrint = previousDebugPrint;
    }
  });

  testWidgets('catalog card and frame details use the same formatted price', (
    tester,
  ) async {
    const frame = {
      'frame_id': 22,
      'name': 'Synthetic Test Frame',
      'brand': 'Example Brand',
      'price': 125000.5,
      'stock_quantity': 4,
    };
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {};

    try {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: DashboardScreen(profileData: {})),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Explore Frames').last);
          await tester.pumpAndSettle();

          expect(find.text('₱125,000.50'), findsOneWidget);

          await tester.tap(find.text('Synthetic Test Frame'));
          await tester.pumpAndSettle();
          expect(find.text('₱125,000.50'), findsNWidgets(2));
        },
        () => MockClient((request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/frames/page') {
            return http.Response(
              jsonEncode({
                'items': [frame],
                'categories': [],
                'pagination': {
                  'page': int.parse(request.url.queryParameters['page'] ?? '1'),
                  'limit': 10,
                  'total': 1,
                  'totalPages': 1,
                },
              }),
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/appointments') {
            return http.Response('[]', 200);
          }
          return http.Response('[]', 200);
        }),
      );
    } finally {
      debugPrint = previousDebugPrint;
    }
  });
}
