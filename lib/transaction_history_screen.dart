import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'currency_format.dart';
import 'services/patient_session_service.dart';

class TransactionHistoryScreen extends StatefulWidget {
  final String? patientId;
  final String? authenticatedPatientId;
  final PatientSessionService? sessionService;
  final bool showScaffold;

  const TransactionHistoryScreen({
    super.key,
    this.patientId,
    this.authenticatedPatientId,
    this.sessionService,
    this.showScaffold = true,
  });

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  static const int _transactionsPerPage = 10;

  bool _loading = true;
  bool _requestInFlight = false;
  bool _refreshing = false;
  String? _errorMessage;
  String? _refreshErrorMessage;
  List<_TransactionRecord> _records = [];
  int _currentPage = 1;
  int _totalPages = 0;
  int _lastRequestedPage = 1;
  bool _recoveryAttempted = false;

  @override
  void initState() {
    super.initState();
    _loadPage(1);
  }

  String get _requestedPatientId => (widget.patientId ?? '').trim();

  String get _authenticatedPatientId =>
      (widget.authenticatedPatientId ?? widget.patientId ?? '').trim();

  bool get _hasValidAuthenticatedIdentity {
    final requested = _requestedPatientId;
    final authenticated = _authenticatedPatientId;
    return requested.isNotEmpty &&
        authenticated.isNotEmpty &&
        requested == authenticated;
  }

  Future<void> _refreshCurrentPage() {
    if (_requestInFlight) return Future<void>.value();
    return _loadPage(
      _currentPage,
      isRecovery: false,
      isRefresh: true,
    );
  }

  Future<void> _loadPage(
    int page, {
    bool isRecovery = false,
    bool isRefresh = false,
  }) async {
    if (_requestInFlight) return;

    final patientId = _requestedPatientId;
    if (patientId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Patient information is unavailable.';
        _records = [];
        _currentPage = 1;
        _totalPages = 0;
      });
      return;
    }

    if (!_hasValidAuthenticatedIdentity) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage =
            'Unable to confirm your account for transaction history. Please sign in again.';
        _records = [];
        _currentPage = 1;
        _totalPages = 0;
      });
      return;
    }

    final token = widget.sessionService?.token?.trim();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Please sign in to your patient account first.';
        _records = [];
        _currentPage = 1;
        _totalPages = 0;
      });
      return;
    }

    final safePage = page < 1 ? 1 : page;

    _requestInFlight = true;
    _lastRequestedPage = safePage;
    if (!isRecovery) {
      _recoveryAttempted = false;
    }

    if (mounted) {
      setState(() {
        _refreshing = isRefresh;
        if (isRefresh) {
          _refreshErrorMessage = null;
        } else {
          _loading = true;
          _errorMessage = null;
        }
      });
    }

    try {
      final uri =
          Uri.parse(
            '$apiBaseUrl/api/patients/${Uri.encodeComponent(patientId)}/transactions',
          ).replace(
            queryParameters: {
              'page': safePage.toString(),
              'limit': _transactionsPerPage.toString(),
            },
          );

      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final handled = await _handleSuccessResponse(
          response.body,
          requestedPage: safePage,
          isRefresh: isRefresh,
        );
        if (!handled) {
          if (mounted) {
            setState(() {
              if (isRefresh) {
                _refreshing = false;
                _refreshErrorMessage =
                    'Unable to refresh transactions. Your existing records are unchanged.';
              } else {
                _loading = false;
                _errorMessage =
                    'Unable to load transactions. Please try again later.';
                _records = [];
                _currentPage = 1;
                _totalPages = 0;
              }
              _requestInFlight = false;
            });
          } else {
            _requestInFlight = false;
          }
        }
        return;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        if (mounted) {
          setState(() {
            if (isRefresh) {
              _refreshing = false;
              _refreshErrorMessage =
                  'Unable to refresh transactions. Your existing records are unchanged.';
            } else {
              _loading = false;
              _errorMessage =
                  'Your session is no longer valid. Please sign in again to view transactions.';
              _records = [];
              _currentPage = 1;
              _totalPages = 0;
            }
            _requestInFlight = false;
          });
        } else {
          _requestInFlight = false;
        }
        return;
      }

      String message = 'Unable to load transactions.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          message =
              (decoded['message']?.toString() ??
                      decoded['error']?.toString() ??
                      message)
                  .trim();
          if (message.isEmpty) message = 'Unable to load transactions.';
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          if (isRefresh) {
            _refreshing = false;
            _refreshErrorMessage =
                'Unable to refresh transactions. Your existing records are unchanged.';
          } else {
            _loading = false;
            _errorMessage = message;
            _records = [];
            _currentPage = 1;
            _totalPages = 0;
          }
          _requestInFlight = false;
        });
      } else {
        _requestInFlight = false;
      }
    } catch (_) {
      if (!mounted) {
        _requestInFlight = false;
        return;
      }
      setState(() {
        if (isRefresh) {
          _refreshing = false;
          _refreshErrorMessage =
              'Unable to refresh transactions. Your existing records are unchanged.';
        } else {
          _loading = false;
          _errorMessage = 'Unable to connect to the server.';
          _records = [];
          _currentPage = 1;
          _totalPages = 0;
        }
        _requestInFlight = false;
      });
    } finally {
      if (_requestInFlight) {
        if (mounted) {
          setState(() {
            _requestInFlight = false;
          });
        } else {
          _requestInFlight = false;
        }
      }
    }
  }

  Future<bool> _handleSuccessResponse(
    String body, {
    required int requestedPage,
    bool isRefresh = false,
  }) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return false;
    }

    if (decoded is! Map) return false;

    final pagination = _parsePagination(decoded['pagination']);
    final rawTransactions = decoded['transactions'];
    final transactions = rawTransactions is List ? rawTransactions : null;

    if (pagination == null || transactions == null) {
      return false;
    }

    final page = pagination.page;
    final totalPages = pagination.totalPages;
    final total = pagination.total;
    final records = transactions
        .whereType<Map<String, dynamic>>()
        .map(_TransactionRecord.fromJson)
        .toList();

    if (total == 0 || totalPages == 0) {
      if (!mounted) {
        _requestInFlight = false;
        return true;
      }
      setState(() {
        _records = [];
        _currentPage = 1;
        _totalPages = 0;

        _loading = false;
        _refreshing = false;
        _errorMessage = null;
        _refreshErrorMessage = null;
        _requestInFlight = false;
      });
      return true;
    }

    final lastValidPage = totalPages < 1 ? 1 : totalPages;
    final pageIsOutOfRange = page < 1 || page > lastValidPage;
    final emptyPageWithRemaining = records.isEmpty && total > 0;

    if ((pageIsOutOfRange || emptyPageWithRemaining) && requestedPage > 1) {
      if (_recoveryAttempted) {
        return false;
      }
      _recoveryAttempted = true;
      _requestInFlight = false;
      await _loadPage(
        lastValidPage,
        isRecovery: true,
        isRefresh: isRefresh,
      );
      return true;
    }

    if (pageIsOutOfRange || (records.isEmpty && total > 0)) {
      return false;
    }

    if (!mounted) {
      _requestInFlight = false;
      return true;
    }
    setState(() {
      _records = records;
      _currentPage = page;
      _totalPages = lastValidPage;

      _loading = false;
      _refreshing = false;
      _errorMessage = null;
      _refreshErrorMessage = null;
      _requestInFlight = false;
    });
    return true;
  }

  _TransactionPagination? _parsePagination(dynamic rawPagination) {
    if (rawPagination is! Map) return null;

    int? parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.isFinite ? value.toInt() : null;
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    final page = parseInt(rawPagination['page']);
    final limit = parseInt(rawPagination['limit']);
    final total = parseInt(rawPagination['total']);
    final totalPages = parseInt(rawPagination['totalPages']);

    if (page == null ||
        limit == null ||
        total == null ||
        totalPages == null ||
        limit <= 0 ||
        total < 0 ||
        totalPages < 0) {
      return null;
    }

    return _TransactionPagination(
      page: page,
      limit: limit,
      total: total,
      totalPages: totalPages,
    );
  }

  void _retry() {
    if (_requestInFlight) return;
    final page = _lastRequestedPage < 1 ? 1 : _lastRequestedPage;
    _loadPage(page);
  }

  Future<void> _showProofPreview(String proofUrl) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          key: const ValueKey('transaction-proof-dialog'),
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: SizedBox(
            width: 420,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      key: const ValueKey('transaction-proof-close'),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          proofUrl,
                          key: const ValueKey('transaction-proof-preview'),
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const ColoredBox(
                              color: Color(0xFFEAF2FF),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) =>
                              const ColoredBox(
                                color: Color(0xFFEAF2FF),
                                child: Center(
                                  child: Text(
                                    'ID picture unavailable',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
        actions: [
          IconButton(
            key: const ValueKey('transaction-refresh'),
            tooltip: 'Refresh',
            onPressed: _requestInFlight
                ? null
                : () => unawaited(_refreshCurrentPage()),
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
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
                if (!widget.showScaffold) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    key: const ValueKey('transaction-refresh'),
                    tooltip: 'Refresh',
                    onPressed: _requestInFlight
                        ? null
                        : () => unawaited(_refreshCurrentPage()),
                    icon: _refreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ],
            ),
          ),
          if (_refreshErrorMessage != null)
            Container(
              key: const ValueKey('transaction-refresh-error'),
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD699)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Color(0xFF9A6700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _refreshErrorMessage!,
                      style: const TextStyle(
                        color: Color(0xFF7A5200),
                        fontSize: 12,
                      ),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _requestInFlight ? null : _retry,
                            child: const Text('Retry'),
                          ),
                        ],
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
                    key: ValueKey(_currentPage),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _buildTransactionCard(_records[index]);
                    },
                  ),
          ),
          if (!_loading &&
              _errorMessage == null &&
              _records.isNotEmpty &&
              _totalPages > 0)
            _buildPaginationControls(),
        ],
      ),
    );
  }

  Widget _buildPaginationControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Page $_currentPage of $_totalPages',
            key: const ValueKey('transaction-page-indicator'),
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('transaction-previous-page'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: (!_requestInFlight && _currentPage > 1)
                        ? () => _loadPage(_currentPage - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Previous'),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('transaction-next-page'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: (!_requestInFlight && _currentPage < _totalPages)
                        ? () => _loadPage(_currentPage + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Next'),
                    iconAlignment: IconAlignment.end,
                  ),
                ),
              ),
            ],
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
                  Icons.receipt_long,
                  color: record.statusColor,
                  size: 22,
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
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
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
                  if (record.paymentStatus != null &&
                      record.paymentStatus != record.status &&
                      record.status?.toLowerCase() != 'voided')
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        record.paymentStatus!,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
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
                      _TransactionItemThumbnail(imageUrl: item.imageUrl),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
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
            if (record.discountLabel != null &&
                record.discountAmountLabel != null)
              _summaryRow(
                record.discountLabel!,
                record.discountAmountLabel!,
              ),
            if (record.vatLabel != null) _summaryRow('VAT', record.vatLabel!),
            if (record.totalAmountLabel != null)
              _summaryRow('Total', record.totalAmountLabel!, isTotal: true),
          ],
          if (record.proofUrl != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1),
            ),
            const Text(
              'SENIOR/PWD ID PROOF',
              key: ValueKey('transaction-proof-section'),
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                key: const ValueKey('transaction-proof-thumbnail'),
                onTap: () => _showProofPreview(record.proofUrl!),
                borderRadius: BorderRadius.circular(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 96,
                    height: 72,
                    child: Image.network(
                      record.proofUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const ColoredBox(
                          color: Color(0xFFEAF2FF),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(
                            color: Color(0xFFEAF2FF),
                            child: Center(
                              child: Text(
                                'ID picture unavailable',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransactionPagination {
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  const _TransactionPagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });
}

String? _validTransactionItemImageUrl(dynamic rawUrl) {
  final value = rawUrl?.toString().trim();
  if (value == null || value.isEmpty) return null;

  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return value;
}

bool _isValidSeniorPwdProofUrl(String? rawUrl) {
  final value = rawUrl?.trim();
  if (value == null || value.isEmpty) return false;

  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort) {
    return false;
  }

  final host = uri.host.toLowerCase();
  return host == 'cloudinary.com' || host.endsWith('.cloudinary.com');
}

String? _proofUrlFromJson(Map<String, dynamic> json) {
  final primary = json['discount_id_proof_url']?.toString().trim();
  if (_isValidSeniorPwdProofUrl(primary)) return primary;

  final fallback = json['id_proof_url']?.toString().trim();
  if (_isValidSeniorPwdProofUrl(fallback)) return fallback;
  return null;
}

class _TransactionRecord {
  final String title;
  final String? subtitle;
  final String? referenceLabel;
  final String? proofUrl;
  final DateTime? transactionDate;
  final String dateLabel;
  final String amountLabel;
  final String? totalAmountLabel;
  final String? subtotalLabel;
  final String? vatLabel;
  final String? discountLabel;
  final String? discountAmountLabel;
  final List<_TransactionItemRecord> items;
  final String? itemsSummary;
  final String? status;
  final String? paymentStatus;
  final Color statusColor;

  bool get hasDetails =>
      items.isNotEmpty ||
      itemsSummary != null ||
      subtotalLabel != null ||
      discountAmountLabel != null ||
      vatLabel != null ||
      totalAmountLabel != null;

  const _TransactionRecord({
    required this.title,
    required this.subtitle,
    required this.referenceLabel,
    required this.proofUrl,
    required this.transactionDate,
    required this.dateLabel,
    required this.amountLabel,
    required this.totalAmountLabel,
    required this.subtotalLabel,
    required this.vatLabel,
    required this.discountLabel,
    required this.discountAmountLabel,
    required this.items,
    required this.itemsSummary,
    required this.status,
    required this.paymentStatus,
    required this.statusColor,
  });

  factory _TransactionRecord.fromJson(Map<String, dynamic> json) {
    final transactionStatus = json['transaction_status']?.toString().trim();
    final genericStatus = json['status']?.toString().trim();
    final paymentStatus = json['payment_status']?.toString().trim();
    final statusLabel = _firstNonEmpty([
      transactionStatus,
      genericStatus,
      paymentStatus,
    ]);
    final normalized = statusLabel
            ?.toLowerCase()
            .replaceAll('_', ' ')
            .replaceAll('-', ' ')
            .trim() ??
        '';
    final color = normalized == 'pending' ||
            normalized == 'pending void'
        ? Colors.orange
        : normalized == 'failed' ||
              normalized == 'cancelled' ||
              normalized == 'voided'
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
        json['total_amount'] ??
        json['amount'] ??
        json['payment_amount'] ??
        json['transaction_amount'] ??
        json['value'];

    final totalAmountLabel = _formatAmount(rawAmount);
    final subtotalLabel = _formatAmount(json['subtotal']);
    final vatLabel = _formatAmount(json['vat_amount']);
    final discountAmount = _parsePositiveAmount(json['discount_amount']);
    final discountName =
        json['discount_name']?.toString().trim();
    final discountPercent = _parsePositiveAmount(json['discount_percent']);
    final discountLabel = discountAmount == null
        ? null
        : [
            discountName == null || discountName.isEmpty
                ? 'Discount'
                : discountName,
            if (discountPercent != null)
              '(${_formatPercent(discountPercent)}%)',
          ].join(' ');
    final discountAmountLabel = discountAmount == null
        ? null
        : _formatAmount(-discountAmount);
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(_TransactionItemRecord.fromJson)
              .toList()
        : <_TransactionItemRecord>[];
    final itemsSummary = _firstNonEmpty([json['items_summary']]);
    final proofUrl = _proofUrlFromJson(json);

    final rawDate =
        json['created_at']?.toString() ??
        json['date']?.toString() ??
        json['transaction_date']?.toString() ??
        json['paid_at']?.toString() ??
        json['datetime']?.toString() ??
        '';

    final transactionDate = DateTime.tryParse(rawDate);
    final dateLabel = rawDate.isEmpty ? 'Recently' : _formatDateLabel(rawDate);

    return _TransactionRecord(
      title: title,
      subtitle: subtitle,
      referenceLabel: reference == null ? null : 'Ref: $reference',
      proofUrl: proofUrl,
      transactionDate: transactionDate,
      dateLabel: dateLabel,
      amountLabel: totalAmountLabel ?? 'Amount unavailable',
      totalAmountLabel: totalAmountLabel,
      subtotalLabel: subtotalLabel,
      vatLabel: vatLabel,
      discountLabel: discountLabel,
      discountAmountLabel: discountAmountLabel,
      items: items,
      itemsSummary: items.isEmpty ? itemsSummary : null,
      status: statusLabel == null ? null : _titleCase(statusLabel),
      paymentStatus: paymentStatus == null ? null : _titleCase(paymentStatus),
      statusColor: color,
    );
  }

  static double? _parsePositiveAmount(dynamic rawValue) {
    if (rawValue == null) return null;

    final value = rawValue is num
        ? rawValue.toDouble()
        : double.tryParse(rawValue.toString().trim().replaceAll(',', ''));
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  static String _formatPercent(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String? _formatAmount(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    if (rawValue is num) {
      if (!rawValue.isFinite) return null;
      return formatPhilippinePeso(rawValue.toDouble());
    }

    final trimmed = rawValue.toString().trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final numeric = double.tryParse(trimmed.replaceAll(',', ''));
    if (numeric != null && numeric.isFinite) {
      return formatPhilippinePeso(numeric);
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

class _TransactionItemThumbnail extends StatelessWidget {
  final String? imageUrl;

  const _TransactionItemThumbnail({required this.imageUrl});

  Widget _placeholder({Key? key}) {
    return Container(
      key: key,
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 22,
        color: Color(0xFF8091A8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) {
      return _placeholder(
        key: const ValueKey('transaction-item-placeholder'),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 52,
        height: 52,
        child: Image.network(
          imageUrl!,
          key: ValueKey('transaction-item-image:$imageUrl'),
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: 52,
              height: 52,
              color: const Color(0xFFEAF2FF),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => _placeholder(
            key: const ValueKey('transaction-item-placeholder'),
          ),
        ),
      ),
    );
  }
}

class _TransactionItemRecord {
  final String label;
  final String? lineAmountLabel;
  final String? imageUrl;

  const _TransactionItemRecord({
    required this.label,
    required this.lineAmountLabel,
    required this.imageUrl,
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
    final primaryImageUrl = _validTransactionItemImageUrl(
      json['image_url'],
    );
    final fallbackImageUrl = _validTransactionItemImageUrl(
      json['image_2d_url'],
    );

    return _TransactionItemRecord(
      label: label,
      lineAmountLabel: lineAmount,
      imageUrl: primaryImageUrl ?? fallbackImageUrl,
    );
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
