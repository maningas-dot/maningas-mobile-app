import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';

class TransactionHistoryScreen extends StatefulWidget {
  final String? patientId;
  final bool showScaffold;

  const TransactionHistoryScreen({
    super.key,
    this.patientId,
    this.showScaffold = true,
  });

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  bool _loading = true;
  String? _errorMessage;
  List<_TransactionRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    final patientId = (widget.patientId ?? '').trim();

    if (patientId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Patient information is unavailable.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/api/patients/${Uri.encodeComponent(patientId)}/transactions',
      );

      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final rawList = decoded is List
            ? decoded
            : decoded is Map
            ? decoded['transactions'] ??
                  decoded['data'] ??
                  decoded['items'] ??
                  []
            : const [];
        final list = rawList is List ? rawList : const <dynamic>[];

        setState(() {
          _records = list
              .whereType<Map<String, dynamic>>()
              .map(_TransactionRecord.fromJson)
              .toList();
          _loading = false;
          _errorMessage = null;
        });
        return;
      }

      final decoded = jsonDecode(response.body);
      final message = decoded is Map
          ? (decoded['message']?.toString() ??
                decoded['error']?.toString() ??
                'Unable to load transactions.')
          : 'Unable to load transactions.';

      setState(() {
        _loading = false;
        _errorMessage = message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Unable to connect to the server.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildPageContent();

    if (!widget.showScaffold) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        backgroundColor: const Color(0xFF0F76FF),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _buildPageContent() {
    return ColoredBox(
      color: const Color(0xFFF2F6FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F76FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Color(0xFF0F76FF),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your transactions',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Review your purchases and payment details.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),
                  )
                : _records.isEmpty
                ? const Center(
                    child: Text(
                      'No transactions yet.',
                      style: TextStyle(color: Colors.black54, fontSize: 15),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _buildTransactionCard(_records[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(_TransactionRecord record) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: record.statusColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: record.statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (record.subtitle != null)
                      Text(
                        record.subtitle!,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    if (record.referenceLabel != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        record.referenceLabel!,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          record.dateLabel,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    record.amountLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF0F76FF),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (record.status != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: record.statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        record.status!,
                        style: TextStyle(
                          color: record.statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (record.hasDetails) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            Text(
              'Items',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            if (record.items.isNotEmpty)
              ...record.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (item.lineAmountLabel != null)
                        Text(
                          item.lineAmountLabel!,
                          style: const TextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
              )
            else if (record.itemsSummary != null)
              Text(record.itemsSummary!, style: const TextStyle(fontSize: 12))
            else
              const Text(
                'No item details available.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            const SizedBox(height: 8),
            if (record.subtotalLabel != null)
              _summaryRow('Subtotal', record.subtotalLabel!),
            if (record.vatLabel != null) _summaryRow('VAT', record.vatLabel!),
            if (record.totalAmountLabel != null)
              _summaryRow('Total', record.totalAmountLabel!, isTotal: true),
          ],
        ],
      ),
    );
  }
}

class _TransactionRecord {
  final String title;
  final String? subtitle;
  final String? referenceLabel;
  final String dateLabel;
  final String amountLabel;
  final String? totalAmountLabel;
  final String? subtotalLabel;
  final String? vatLabel;
  final List<_TransactionItemRecord> items;
  final String? itemsSummary;
  final String? status;
  final Color statusColor;

  bool get hasDetails =>
      items.isNotEmpty ||
      itemsSummary != null ||
      subtotalLabel != null ||
      vatLabel != null ||
      totalAmountLabel != null;

  const _TransactionRecord({
    required this.title,
    required this.subtitle,
    required this.referenceLabel,
    required this.dateLabel,
    required this.amountLabel,
    required this.totalAmountLabel,
    required this.subtotalLabel,
    required this.vatLabel,
    required this.items,
    required this.itemsSummary,
    required this.status,
    required this.statusColor,
  });

  factory _TransactionRecord.fromJson(Map<String, dynamic> json) {
    final statusLabel = _firstNonEmpty([
      json['status'],
      json['payment_status'],
      json['transaction_status'],
    ]);
    final normalized = statusLabel?.toLowerCase() ?? '';
    final color = normalized == 'pending'
        ? Colors.orange
        : normalized == 'failed' || normalized == 'cancelled'
        ? Colors.red
        : const Color(0xFF0F76FF);

    final title =
        _firstNonEmpty([
          json['purpose_of_visit'],
          json['title'],
          json['description'],
          json['product'],
          json['service'],
          json['item_name'],
        ]) ??
        'Transaction';

    final subtitle = _firstNonEmpty([
      json['subtitle'],
      json['category'],
      json['type'],
      json['payment_method'],
    ]);

    final reference = _firstNonEmpty([
      json['invoice_number'],
      json['transaction_id'],
    ]);

    final rawAmount =
        json['amount'] ??
        json['total_amount'] ??
        json['payment_amount'] ??
        json['transaction_amount'] ??
        json['value'];

    final totalAmountLabel = _formatAmount(rawAmount);
    final subtotalLabel = _formatAmount(json['subtotal']);
    final vatLabel = _formatAmount(json['vat_amount']);
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(_TransactionItemRecord.fromJson)
              .toList()
        : <_TransactionItemRecord>[];
    final itemsSummary = _firstNonEmpty([json['items_summary']]);

    final rawDate =
        json['created_at']?.toString() ??
        json['date']?.toString() ??
        json['transaction_date']?.toString() ??
        json['paid_at']?.toString() ??
        json['datetime']?.toString() ??
        '';

    final dateLabel = rawDate.isEmpty ? 'Recently' : _formatDateLabel(rawDate);

    return _TransactionRecord(
      title: title,
      subtitle: subtitle,
      referenceLabel: reference == null ? null : 'Ref: $reference',
      dateLabel: dateLabel,
      amountLabel: totalAmountLabel ?? 'Amount unavailable',
      totalAmountLabel: totalAmountLabel,
      subtotalLabel: subtotalLabel,
      vatLabel: vatLabel,
      items: items,
      itemsSummary: items.isEmpty ? itemsSummary : null,
      status: statusLabel == null ? null : _titleCase(statusLabel),
      statusColor: color,
    );
  }

  static String? _formatAmount(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    if (rawValue is num) {
      if (!rawValue.isFinite) return null;
      return '₱${rawValue.toStringAsFixed(2)}';
    }

    final trimmed = rawValue.toString().trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final numeric = double.tryParse(trimmed.replaceAll(',', ''));
    if (numeric != null && numeric.isFinite) {
      return '₱${numeric.toStringAsFixed(2)}';
    }

    return null;
  }

  static String? _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static String _formatDateLabel(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) {
      return rawDate;
    }

    final local = parsed.toLocal();
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${monthNames[local.month - 1]} ${local.day}, ${local.year}';
  }

  static String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value
        .split(RegExp(r'\s+'))
        .map(
          (part) => part.isEmpty
              ? part
              : part[0].toUpperCase() + part.substring(1).toLowerCase(),
        )
        .join(' ');
  }
}

class _TransactionItemRecord {
  final String label;
  final String? lineAmountLabel;

  const _TransactionItemRecord({
    required this.label,
    required this.lineAmountLabel,
  });

  factory _TransactionItemRecord.fromJson(Map<String, dynamic> json) {
    final name = _TransactionRecord._firstNonEmpty([json['item_name']]);
    final quantity = _formatQuantity(json['quantity']);
    final label = [
      name ?? 'Item name unavailable',
      if (quantity != null) '× $quantity',
    ].join(' ');

    final quantityValue = _parseNumber(json['quantity']);
    final unitPrice = _parseNumber(json['unit_price']);
    final lineAmount = quantityValue != null && unitPrice != null
        ? _TransactionRecord._formatAmount(quantityValue * unitPrice)
        : null;

    return _TransactionItemRecord(label: label, lineAmountLabel: lineAmount);
  }

  static String? _formatQuantity(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static double? _parseNumber(dynamic value) {
    if (value is num) {
      return value.isFinite ? value.toDouble() : null;
    }
    if (value == null) return null;
    final parsed = double.tryParse(value.toString().trim().replaceAll(',', ''));
    return parsed != null && parsed.isFinite ? parsed : null;
  }
}

Widget _summaryRow(String label, String value, {bool isTotal = false}) {
  final style = TextStyle(
    fontSize: isTotal ? 13 : 12,
    fontWeight: isTotal ? FontWeight.w700 : FontWeight.normal,
  );

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    ),
  );
}
