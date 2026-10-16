import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';

class TransactionHistoryScreen extends StatefulWidget {
  final String? patientId;

  const TransactionHistoryScreen({super.key, this.patientId});

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
        final rawList = decoded is Map
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        backgroundColor: const Color(0xFF0F76FF),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
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
                padding: const EdgeInsets.all(16),
                itemCount: _records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final record = _records[index];

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
                    child: Row(
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
                              Text(
                                record.subtitle,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
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
                                record.status,
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
                  );
                },
              ),
      ),
    );
  }
}

class _TransactionRecord {
  final String title;
  final String subtitle;
  final String dateLabel;
  final String amountLabel;
  final String status;
  final Color statusColor;

  const _TransactionRecord({
    required this.title,
    required this.subtitle,
    required this.dateLabel,
    required this.amountLabel,
    required this.status,
    required this.statusColor,
  });

  factory _TransactionRecord.fromJson(Map<String, dynamic> json) {
    final rawStatus =
        json['status']?.toString() ??
        json['payment_status']?.toString() ??
        json['transaction_status']?.toString() ??
        'Paid';
    final statusLabel = rawStatus.isEmpty ? 'Paid' : rawStatus;
    final normalized = statusLabel.toLowerCase();
    final color = normalized == 'pending'
        ? Colors.orange
        : normalized == 'failed' || normalized == 'cancelled'
        ? Colors.red
        : const Color(0xFF0F76FF);

    final title =
        json['title']?.toString() ??
        json['description']?.toString() ??
        json['product']?.toString() ??
        json['service']?.toString() ??
        json['item_name']?.toString() ??
        'Transaction';

    final subtitle =
        json['subtitle']?.toString() ??
        json['category']?.toString() ??
        json['type']?.toString() ??
        json['payment_method']?.toString() ??
        'Payment';

    final rawAmount =
        json['amount'] ??
        json['total_amount'] ??
        json['payment_amount'] ??
        json['transaction_amount'] ??
        json['value'];

    final amountLabel = _formatAmount(rawAmount);

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
      dateLabel: dateLabel,
      amountLabel: amountLabel,
      status: _titleCase(statusLabel),
      statusColor: color,
    );
  }

  static String _formatAmount(dynamic rawValue) {
    if (rawValue == null) {
      return '₱0.00';
    }

    if (rawValue is num) {
      return '₱${rawValue.toStringAsFixed(2)}';
    }

    final trimmed = rawValue.toString().trim();
    if (trimmed.isEmpty) {
      return '₱0.00';
    }

    final numeric = double.tryParse(trimmed.replaceAll(',', ''));
    if (numeric != null) {
      return '₱${numeric.toStringAsFixed(2)}';
    }

    return trimmed;
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
