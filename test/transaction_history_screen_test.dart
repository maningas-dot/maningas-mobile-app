import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:optcare_app/transaction_history_screen.dart';

void main() {
  const patientId = 'synthetic-transaction-patient';

  testWidgets('shows purchased items, totals, and direct purchase label', (
    tester,
  ) async {
    await _pumpWithTransactions(tester, patientId, {
      'success': true,
      'transactions': [
        {
          'transaction_id': 42,
          'invoice_number': 'INV-42',
          'purpose_of_visit': 'Direct Purchase',
          'subtotal': 100,
          'vat_amount': 12,
          'total_amount': 112,
          'payment_status': 'Paid',
          'created_at': '2025-01-15T10:30:00.000Z',
          'items': [
            {'item_name': 'Classic frame', 'quantity': 2, 'unit_price': 50},
          ],
        },
      ],
    });

    expect(find.text('Direct Purchase'), findsOneWidget);
    expect(find.text('Ref: INV-42'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Jan 15, 2025'), findsOneWidget);
    expect(find.text('Classic frame × 2'), findsOneWidget);
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('VAT'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('₱100.00'), findsNWidgets(2));
    expect(find.text('₱12.00'), findsOneWidget);
    expect(find.text('₱112.00'), findsNWidgets(2));
  });

  testWidgets('accepts a top-level list and displays items summary as-is', (
    tester,
  ) async {
    await _pumpWithTransactions(tester, patientId, [
      {
        'transaction_id': 44,
        'purpose_of_visit': 'Direct Purchase',
        'total_amount': 250,
        'payment_status': 'Paid',
        'created_at': '2025-02-10T10:30:00.000Z',
        'items_summary': 'Classic frame (x2), Lens coating (x1)',
      },
    ]);

    expect(find.text('Direct Purchase'), findsOneWidget);
    expect(find.text('Ref: 44'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Feb 10, 2025'), findsOneWidget);
    expect(find.text('₱250.00'), findsNWidgets(2));
    expect(find.text('Classic frame (x2), Lens coating (x1)'), findsOneWidget);
    expect(find.text('Subtotal'), findsNothing);
    expect(find.text('VAT'), findsNothing);
    expect(find.text('Invoice'), findsNothing);
    expect(find.text('Payment'), findsNothing);
    expect(find.textContaining('unit_price'), findsNothing);
  });

  testWidgets(
    'groups thousands in transaction, item, subtotal, VAT, and total amounts',
    (tester) async {
      await _pumpWithTransactions(tester, patientId, {
        'success': true,
        'transactions': [
          {
            'transaction_id': 45,
            'purpose_of_visit': 'Direct Purchase',
            'amount': 1000000,
            'subtotal': '5000.00',
            'vat_amount': 600,
            'total_amount': 1000000,
            'payment_status': 'Paid',
            'items': [
              {'item_name': 'Item 1', 'quantity': 1, 'unit_price': 5600},
              {'item_name': 'Item 2', 'quantity': 2, 'unit_price': 2500},
              {'item_name': 'Item 3', 'quantity': 1, 'unit_price': 600},
              {'item_name': 'Item 4', 'quantity': 1, 'unit_price': 1000000},
            ],
          },
        ],
      });

      expect(find.text('₱5,600.00'), findsOneWidget);
      expect(find.text('₱5,000.00'), findsNWidgets(2));
      expect(find.text('₱600.00'), findsNWidgets(2));
      expect(find.text('₱1,000,000.00'), findsNWidgets(3));
    },
  );

  testWidgets(
    'does not substitute zero or fabricated details for missing values',
    (tester) async {
      await _pumpWithTransactions(tester, patientId, {
        'success': true,
        'transactions': [
          {
            'transaction_id': 43,
            'items': [
              {'item_name': 'Repair service'},
            ],
          },
        ],
      });

      expect(find.text('Transaction'), findsOneWidget);
      expect(find.text('Repair service'), findsOneWidget);
      expect(find.textContaining('×'), findsNothing);
      expect(find.text('Amount unavailable'), findsOneWidget);
      expect(find.text('Ref: 43'), findsOneWidget);
      expect(find.text('Paid'), findsNothing);
      expect(find.text('Payment'), findsNothing);
      expect(find.text('₱0.00'), findsNothing);
      expect(find.text('Subtotal'), findsNothing);
      expect(find.text('VAT'), findsNothing);
      expect(find.text('Total'), findsNothing);
    },
  );

  testWidgets('shows ten newest transactions per page with working controls', (
    tester,
  ) async {
    await _pumpWithTransactions(tester, patientId, {
      'transactions': _transactions(12),
    });

    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(_buttonIsEnabled(tester, 'transaction-previous-page'), isFalse);
    expect(_buttonIsEnabled(tester, 'transaction-next-page'), isTrue);
    expect(find.text('Ref: 12'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Ref: 3'), 300);
    expect(find.text('Ref: 3'), findsOneWidget);
    expect(find.text('Ref: 2'), findsNothing);
    expect(find.text('Ref: 1'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('transaction-next-page')));
    await tester.pumpAndSettle();

    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(_buttonIsEnabled(tester, 'transaction-previous-page'), isTrue);
    expect(_buttonIsEnabled(tester, 'transaction-next-page'), isFalse);
    expect(find.text('Ref: 2'), findsOneWidget);
    expect(find.text('Ref: 1'), findsOneWidget);
    expect(find.text('Ref: 3'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('transaction-previous-page')));
    await tester.pumpAndSettle();

    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.text('Ref: 12'), findsOneWidget);
    expect(find.text('Ref: 2'), findsNothing);
  });

  testWidgets('sorts newest first across page boundaries', (tester) async {
    final transactions = _transactions(12).reversed.toList();
    await _pumpWithTransactions(tester, patientId, {
      'transactions': transactions,
    });

    expect(find.text('Ref: 12'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Ref: 3'), 300);
    expect(find.text('Ref: 3'), findsOneWidget);
    expect(find.text('Ref: 2'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('transaction-next-page')));
    await tester.pumpAndSettle();
    expect(find.text('Ref: 2'), findsOneWidget);
    expect(find.text('Ref: 1'), findsOneWidget);
  });

  testWidgets('preserves input order for transactions with equal dates', (
    tester,
  ) async {
    _useTallViewport(tester);
    await _pumpWithTransactions(tester, patientId, {
      'transactions': [
        _transaction(51, '2025-03-01T10:00:00Z'),
        _transaction(52, '2025-03-01T10:00:00Z'),
        _transaction(53, '2025-03-01T10:00:00Z'),
      ],
    });

    _expectReferenceOrder(tester, [51, 52, 53]);
  });

  testWidgets('places missing and invalid dates last in stable order', (
    tester,
  ) async {
    _useTallViewport(tester);
    await _pumpWithTransactions(tester, patientId, {
      'transactions': [
        _transaction(61, 'not-a-date'),
        _transaction(62, '2025-03-01T10:00:00Z'),
        {'transaction_id': 63, 'title': 'Transaction 63'},
        _transaction(64, '2024-03-01T10:00:00Z'),
      ],
    });

    _expectReferenceOrder(tester, [62, 64, 61, 63]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a single disabled page for fewer than ten transactions', (
    tester,
  ) async {
    await _pumpWithTransactions(tester, patientId, {
      'transactions': _transactions(3),
    });

    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(_buttonIsEnabled(tester, 'transaction-previous-page'), isFalse);
    expect(_buttonIsEnabled(tester, 'transaction-next-page'), isFalse);
  });

  testWidgets('empty transaction response hides pagination controls', (
    tester,
  ) async {
    await _pumpWithTransactions(tester, patientId, {'transactions': []});

    expect(find.text('No transactions yet.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transaction-previous-page')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('transaction-next-page')), findsNothing);
    expect(
      find.byKey(const ValueKey('transaction-page-indicator')),
      findsNothing,
    );
  });
}

List<Map<String, dynamic>> _transactions(int count) {
  return List.generate(count, (index) {
    final id = index + 1;
    final date = DateTime.utc(2025, 1, 1).add(Duration(days: id));
    return _transaction(id, date.toIso8601String());
  });
}

Map<String, dynamic> _transaction(int id, String date) {
  return {
    'transaction_id': id,
    'title': 'Transaction $id',
    'amount': id * 100,
    'payment_status': 'Paid',
    'created_at': date,
  };
}

bool _buttonIsEnabled(WidgetTester tester, String key) {
  return tester.widget<TextButton>(find.byKey(ValueKey(key))).onPressed != null;
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _expectReferenceOrder(WidgetTester tester, List<int> transactionIds) {
  final topOffsets = transactionIds
      .map((id) => tester.getTopLeft(find.text('Ref: $id')).dy)
      .toList();
  for (var index = 1; index < topOffsets.length; index++) {
    expect(topOffsets[index - 1], lessThan(topOffsets[index]));
  }
}

Future<void> _pumpWithTransactions(
  WidgetTester tester,
  String patientId,
  Object payload,
) async {
  await http.runWithClient(
    () async {
      await tester.pumpWidget(
        MaterialApp(home: TransactionHistoryScreen(patientId: patientId)),
      );
      await tester.pumpAndSettle();
    },
    () => MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/patients/$patientId/transactions');
      return http.Response(jsonEncode(payload), 200);
    }),
  );
}
