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
          await tester.tap(find.text('Frames').last);
          await tester.pumpAndSettle();

          expect(find.text('₱125,000.50'), findsOneWidget);

          await tester.tap(find.text('Synthetic Test Frame'));
          await tester.pumpAndSettle();
          expect(find.text('₱125,000.50'), findsNWidgets(2));
        },
        () => MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/api/frames') {
            return http.Response(jsonEncode([frame]), 200);
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
