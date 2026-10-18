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
