import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'models/support_ticket.dart';
import 'services/patient_session_service.dart';
import 'services/support_center_service.dart';

const Color _previewBlue = Color(0xFF0F76FF);
const Color _previewBackground = Color(0xFFF4F7FB);
const int _maxSupportImageBytes = 10 * 1024 * 1024;
const Set<String> _supportImageMimeTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
};

void main() {
  runApp(const SupportServicePreviewApp());
}

class SupportServicePreviewApp extends StatelessWidget {
  const SupportServicePreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Support Service Preview',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _previewBlue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: _previewBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: _previewBlue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _previewBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _previewBlue, width: 1.5),
          ),
        ),
      ),
      home: const SupportServiceScreen(),
    );
  }
}

class SupportServiceScreen extends StatefulWidget {
  const SupportServiceScreen({
    super.key,
    this.sessionService,
    this.supportCenterService,
    this.imagePicker,
  });

  final PatientSessionService? sessionService;
  final SupportCenterService? supportCenterService;
  final Future<XFile?> Function()? imagePicker;

  @override
  State<SupportServiceScreen> createState() => _SupportServiceScreenState();
}

class _SupportServiceScreenState extends State<SupportServiceScreen> {
  late final SupportCenterService _supportCenterService =
      widget.supportCenterService ??
      SupportCenterService(sessionService: widget.sessionService);
  late final bool _ownsSupportCenterService =
      widget.supportCenterService == null;

  List<SupportTicket> _tickets = const [];
  bool _isLoading = false;
  bool _isCancelling = false;
  String? _errorMessage;
  Future<void>? _ticketLoadFuture;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  @override
  void dispose() {
    if (_ownsSupportCenterService) {
      _supportCenterService.close();
    }
    super.dispose();
  }

  Future<void> _loadTickets({bool refreshAfterCurrent = false}) {
    final activeLoad = _ticketLoadFuture;
    if (activeLoad != null) {
      return refreshAfterCurrent
          ? activeLoad.then((_) => _loadTickets())
          : activeLoad;
    }

    final load = _fetchTickets();
    _ticketLoadFuture = load;
    return load.whenComplete(() {
      if (identical(_ticketLoadFuture, load)) {
        _ticketLoadFuture = null;
      }
    });
  }

  Future<void> _fetchTickets() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tickets = await _supportCenterService.getMyTickets();
      if (!mounted) return;
      setState(() {
        _tickets = _patientHistoryTickets(tickets);
        _isLoading = false;
      });
    } on SupportServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'support inbox',
          context: ErrorDescription('while loading patient support tickets'),
        ),
      );
      setState(() {
        _errorMessage =
            'We could not load your support requests. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openNewTicket(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final createdTicket = await Navigator.of(context).push<SupportTicket>(
      MaterialPageRoute<SupportTicket>(
        builder: (_) =>
            NewTicketScreen(supportCenterService: _supportCenterService),
      ),
    );
    if (createdTicket == null || !mounted) return;

    scaffoldMessenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Your support ticket was submitted.')),
      );
    await _loadTickets(refreshAfterCurrent: true);
    if (!mounted ||
        _tickets.any((ticket) => ticket.ticketId == createdTicket.ticketId)) {
      return;
    }
    setState(() {
      _tickets = [createdTicket, ..._tickets];
    });
  }

  Future<void> _openConversation(
    BuildContext context,
    SupportTicket ticket,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _TicketConversationScreen(
          ticket: ticket,
          supportCenterService: _supportCenterService,
          imagePicker: widget.imagePicker,
        ),
      ),
    );
    if (mounted) await _loadTickets(refreshAfterCurrent: true);
  }

  bool _canCancelTicket(SupportTicket ticket) =>
      (ticket.status ?? '').trim().toLowerCase() == 'open';

  SupportTicket _withTicketStatus(SupportTicket ticket, String status) =>
      SupportTicket(
        ticketId: ticket.ticketId,
        patientId: ticket.patientId,
        subject: ticket.subject,
        category: ticket.category,
        priority: ticket.priority,
        status: status,
        resolution: ticket.resolution,
        createdAt: ticket.createdAt,
        updatedAt: ticket.updatedAt,
      );

  Future<void> _cancelTicket(BuildContext context, SupportTicket ticket) async {
    if (_isCancelling || !_canCancelTicket(ticket)) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: const Text('Cancel Support Ticket?'),
        content: Text(
          'Are you sure you want to cancel "${ticket.subject ?? 'this ticket'}"? '
          'The conversation will become read-only, but its history will remain.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('support-ticket-cancel-dismiss'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Ticket'),
          ),
          FilledButton(
            key: const ValueKey('support-ticket-cancel-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel Ticket'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isCancelling) return;

    setState(() {
      _isCancelling = true;
      _errorMessage = null;
    });

    try {
      final latestTickets = await _supportCenterService.getMyTickets();
      if (!mounted) return;
      setState(() {
        _tickets = _patientHistoryTickets(latestTickets);
      });

      SupportTicket? latestTicket;
      for (final latest in latestTickets) {
        if (latest.ticketId == ticket.ticketId) {
          latestTicket = latest;
          break;
        }
      }
      if (latestTicket == null || !_canCancelTicket(latestTicket)) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'This ticket is no longer eligible for cancellation.',
              ),
            ),
          );
        return;
      }

      await _supportCenterService.cancelTicket(latestTicket.ticketId);
      if (!mounted) return;
      setState(() {
        _tickets = [
          for (final current in _tickets)
            if (current.ticketId != latestTicket!.ticketId) current,
        ];
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Support ticket cancelled.')),
        );
    } on SupportServiceException catch (error) {
      if (!mounted) return;
      final message = switch (error.kind) {
        SupportServiceFailureKind.missingAuthentication =>
          'Please sign in to cancel this support ticket.',
        SupportServiceFailureKind.unauthorized =>
          'Your login session has expired. Please sign in again.',
        SupportServiceFailureKind.forbidden =>
          'This account cannot cancel the support ticket.',
        SupportServiceFailureKind.network =>
          'Unable to reach the clinic service. Check your connection and try again.',
        SupportServiceFailureKind.timeout =>
          'The request timed out. Please try again.',
        SupportServiceFailureKind.requestRejected =>
          'The clinic could not cancel this ticket. It may no longer be eligible.',
        SupportServiceFailureKind.http ||
        SupportServiceFailureKind.server ||
        SupportServiceFailureKind.invalidResponse =>
          'The support ticket could not be cancelled right now. Please try again.',
      };
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'support inbox',
          context: ErrorDescription('while cancelling a support ticket'),
        ),
      );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'The support ticket could not be cancelled. Please try again.',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isCancelling = false;
        });
      }
    }
  }

  List<SupportTicket> _patientHistoryTickets(List<SupportTicket> tickets) =>
      tickets
          .where((ticket) => !ticket.isPatientCancelled)
          .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support Service')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How can we help?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'View your support requests or create a new ticket.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openNewTicket(context),
                      icon: const Icon(Icons.add),
                      label: const Text('New Ticket'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _previewBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Ticket history',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const _LoadingTicketsCard()
            else if (_errorMessage != null) ...[
              _TicketLoadErrorCard(
                message: _errorMessage!,
                onRetry: _loadTickets,
              ),
              ..._tickets.map(
                (ticket) => _TicketCard(
                  ticket: ticket,
                  onTap: () => _openConversation(context, ticket),
                  onCancel: () => _cancelTicket(context, ticket),
                  isCancelling: _isCancelling,
                ),
              ),
            ] else if (_tickets.isEmpty)
              const _EmptyTicketsCard()
            else
              ..._tickets.map(
                (ticket) => _TicketCard(
                  ticket: ticket,
                  onTap: () => _openConversation(context, ticket),
                  onCancel: () => _cancelTicket(context, ticket),
                  isCancelling: _isCancelling,
                ),
              ),
            const SizedBox(height: 8),
            const _PreviewNotice(
              text: 'Ticket history is loaded from your patient account.',
            ),
          ],
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final SupportTicket ticket;
  final VoidCallback onTap;
  final VoidCallback onCancel;
  final bool isCancelling;

  const _TicketCard({
    required this.ticket,
    required this.onTap,
    required this.onCancel,
    required this.isCancelling,
  });

  @override
  Widget build(BuildContext context) {
    final status = _ticketStatusLabel(ticket.status);
    final normalizedStatus = (ticket.status ?? '').trim().toLowerCase();
    final canCancel = normalizedStatus == 'open';
    final isOpen = const {
      'open',
      'in progress',
      'in_progress',
      'pending',
    }.contains(normalizedStatus);
    final category = ticket.category?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: ValueKey('support-ticket-${ticket.ticketId}'),
          margin: const EdgeInsets.only(bottom: 0),
          elevation: 2,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _previewBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _categoryIcon(category),
                      color: _previewBlue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.subject?.trim().isNotEmpty == true
                              ? ticket.subject!
                              : 'Support request',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          category?.isNotEmpty == true ? category! : 'Support',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _StatusPill(status: status, isOpen: isOpen),
                            Text(
                              _formatTicketDate(ticket.createdAt),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
        ),
        if (canCancel)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: ValueKey('support-ticket-cancel-${ticket.ticketId}'),
              onPressed: isCancelling ? null : onCancel,
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              icon: isCancelling
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cancel_outlined),
              label: Text(isCancelling ? 'Cancelling...' : 'Cancel Ticket'),
            ),
          )
        else
          const SizedBox(height: 12),
      ],
    );
  }
}

String _ticketStatusLabel(String? status) {
  final value = status?.trim();
  if (value == null || value.isEmpty) return 'Unknown';
  return value
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}

IconData _categoryIcon(String? category) {
  final normalized = (category ?? '').toLowerCase();
  if (normalized.contains('appointment')) return Icons.calendar_month_outlined;
  if (normalized.contains('product') || normalized.contains('frame')) {
    return Icons.visibility_outlined;
  }
  return Icons.support_agent_outlined;
}

String _formatTicketDate(DateTime? date) {
  if (date == null) return 'Date unavailable';
  const months = [
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
  final localDate = date.toLocal();
  return '${months[localDate.month - 1]} ${localDate.day}, ${localDate.year}';
}

class _StatusPill extends StatelessWidget {
  final String status;
  final bool isOpen;

  const _StatusPill({required this.status, required this.isOpen});

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? _previewBlue : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _LoadingTicketsCard extends StatelessWidget {
  const _LoadingTicketsCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: CircularProgressIndicator(
            key: ValueKey('support-tickets-loading'),
            color: _previewBlue,
          ),
        ),
      ),
    );
  }
}

class _TicketLoadErrorCard extends StatelessWidget {
  const _TicketLoadErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: Colors.grey.shade600,
              size: 36,
            ),
            const SizedBox(height: 10),
            const Text(
              'Could not load tickets',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const ValueKey('support-tickets-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _previewBlue,
                side: const BorderSide(color: _previewBlue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTicketsCard extends StatelessWidget {
  const _EmptyTicketsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, color: Colors.grey.shade500, size: 38),
            const SizedBox(height: 10),
            const Text(
              'No tickets yet',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 5),
            Text(
              'Your support requests will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class NewTicketScreen extends StatefulWidget {
  const NewTicketScreen({super.key, this.supportCenterService});

  final SupportCenterService? supportCenterService;

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  static const List<String> _categories = [
    'Appointment',
    'Billing / Payment',
    'Patient Account',
    'Eyewear / Frames',
    'Website / Technical Issue',
    'General Inquiry',
    'Other',
  ];
  static const List<String> _priorities = ['Low', 'Medium', 'High', 'Urgent'];

  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  late final SupportCenterService _supportCenterService =
      widget.supportCenterService ?? SupportCenterService();
  late final bool _ownsSupportCenterService =
      widget.supportCenterService == null;
  String? _category;
  String _priority = 'Medium';
  bool _isSubmitting = false;
  String? _submissionError;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    if (_ownsSupportCenterService) {
      _supportCenterService.close();
    }
    super.dispose();
  }

  String _submissionErrorMessage(SupportServiceException error) {
    return switch (error.kind) {
      SupportServiceFailureKind.missingAuthentication =>
        'Please sign in to your patient account before submitting a ticket.',
      SupportServiceFailureKind.unauthorized =>
        'Your login session has expired. Please sign in again.',
      SupportServiceFailureKind.forbidden =>
        'Your account cannot submit a support ticket.',
      SupportServiceFailureKind.network =>
        'Unable to reach the clinic service. Check your connection and try again.',
      SupportServiceFailureKind.timeout =>
        'The request timed out. Please try again.',
      SupportServiceFailureKind.requestRejected =>
        'The clinic could not accept this ticket. Review the details and try again.',
      SupportServiceFailureKind.http ||
      SupportServiceFailureKind.server ||
      SupportServiceFailureKind.invalidResponse =>
        'The ticket could not be submitted right now. Please try again.',
    };
  }

  Future<void> _submit() async {
    if (_isSubmitting || !(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _submissionError = null;
    });

    try {
      final ticket = await _supportCenterService.createTicket(
        category: _category!,
        subject: _subjectController.text.trim(),
        description: _messageController.text.trim(),
        priority: _priority,
      );
      if (!mounted) return;
      Navigator.of(context).pop(ticket);
    } on SupportServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _submissionError = _submissionErrorMessage(error);
        _isSubmitting = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'support ticket submission',
        ),
      );
      setState(() {
        _submissionError =
            'The ticket could not be submitted right now. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Ticket')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const Text(
                'Tell us what you need help with.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Your request will be sent to clinic staff when you submit.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (_submissionError case final error?)
                Container(
                  key: const ValueKey('support-ticket-submit-error'),
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    error,
                    style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                  ),
                ),
              TextFormField(
                controller: _subjectController,
                enabled: !_isSubmitting,
                maxLength: 160,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  hintText: 'Briefly describe your question',
                  counterText: '',
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Please enter a subject'
                    : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: _isSubmitting
                    ? null
                    : (value) => setState(() => _category = value),
                validator: (value) =>
                    value == null ? 'Please choose a category' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: _priorities
                    .map(
                      (priority) => DropdownMenuItem(
                        value: priority,
                        child: Text(priority),
                      ),
                    )
                    .toList(),
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        if (value != null) setState(() => _priority = value);
                      },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _messageController,
                enabled: !_isSubmitting,
                maxLength: 4000,
                minLines: 5,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  labelText: 'Description',
                  hintText: 'Add details about the issue',
                  counterText: '',
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Please describe your issue'
                    : null,
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const ValueKey('support-ticket-submit'),
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          key: ValueKey('support-ticket-submit-loading'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _previewBlue,
                    side: const BorderSide(color: _previewBlue),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(height: 8),
              const _PreviewNotice(
                text: 'Your request will be sent securely to the clinic.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketConversationScreen extends StatefulWidget {
  const _TicketConversationScreen({
    required this.ticket,
    required this.supportCenterService,
    required this.imagePicker,
  });

  final SupportTicket ticket;
  final SupportCenterService supportCenterService;
  final Future<XFile?> Function()? imagePicker;

  @override
  State<_TicketConversationScreen> createState() =>
      _TicketConversationScreenState();
}

class _TicketConversationScreenState extends State<_TicketConversationScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late SupportTicket _ticket = widget.ticket;
  List<SupportMessage> _messages = const [];
  bool _isLoading = false;
  bool _isSending = false;
  bool _isRefreshingTicketStatus = true;
  bool _ticketStatusRefreshed = false;
  bool _readReceiptAttempted = false;
  bool? _chatAvailable;
  bool? _readOnly;
  String? _loadError;
  String? _sendError;
  _SelectedSupportImage? _selectedImage;

  @override
  void initState() {
    super.initState();
    _refreshTicketStatus();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _safeErrorMessage(
    SupportServiceException error, {
    bool sending = false,
  }) {
    return switch (error.kind) {
      SupportServiceFailureKind.missingAuthentication =>
        sending
            ? 'Please sign in to send a message.'
            : 'Please sign in to view this conversation.',
      SupportServiceFailureKind.unauthorized =>
        'Your login session has expired. Please sign in again.',
      SupportServiceFailureKind.forbidden =>
        'This account cannot access the conversation.',
      SupportServiceFailureKind.network =>
        'Unable to reach the clinic service. Check your connection and try again.',
      SupportServiceFailureKind.timeout =>
        'The request timed out. Please try again.',
      SupportServiceFailureKind.requestRejected =>
        sending
            ? 'The clinic could not accept your message. Please try again.'
            : 'The clinic could not load this conversation. Please try again.',
      SupportServiceFailureKind.http ||
      SupportServiceFailureKind.server ||
      SupportServiceFailureKind.invalidResponse =>
        sending
            ? 'Your message could not be sent right now. Please try again.'
            : 'The conversation could not be loaded right now. Please try again.',
    };
  }

  Future<void> _refreshTicketStatus() async {
    try {
      final tickets = await widget.supportCenterService.getMyTickets();
      if (!mounted) return;
      SupportTicket? latestTicket;
      for (final ticket in tickets) {
        if (ticket.ticketId == _ticket.ticketId) {
          latestTicket = ticket;
          break;
        }
      }
      setState(() {
        _isRefreshingTicketStatus = false;
        if (latestTicket != null) {
          _ticket = latestTicket;
          _ticketStatusRefreshed = true;
        }
      });
    } on SupportServiceException catch (error) {
      if (!mounted) return;
      debugPrint('Unable to refresh support ticket status: ${error.kind.name}');
      setState(() {
        _isRefreshingTicketStatus = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'support conversation',
          context: ErrorDescription(
            'while refreshing the selected support ticket status',
          ),
        ),
      );
      setState(() {
        _isRefreshingTicketStatus = false;
      });
    }
  }

  Future<void> _loadMessages() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final result = await widget.supportCenterService.getMessages(
        _ticket.ticketId,
      );
      if (!mounted) return;
      if (result.messages.any(
        (message) => message.ticketId != _ticket.ticketId,
      )) {
        throw const FormatException(
          'The clinic service returned messages for another ticket.',
        );
      }
      setState(() {
        _messages = _orderedMessages(result.messages);
        _chatAvailable = result.chatAvailable;
        _readOnly = result.readOnly;
        _isLoading = false;
      });
      _scrollToLatest();

      if (!_readReceiptAttempted) {
        _readReceiptAttempted = true;
        try {
          await widget.supportCenterService.markMessagesRead(_ticket.ticketId);
        } on SupportServiceException catch (error) {
          debugPrint(
            'Unable to mark support messages as read: ${error.kind.name}',
          );
        } catch (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'support conversation',
              context: ErrorDescription(
                'while marking support messages as read',
              ),
            ),
          );
        }
      }
    } on SupportServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _safeErrorMessage(error);
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'support conversation',
          context: ErrorDescription('while loading support messages'),
        ),
      );
      setState(() {
        _loadError = 'The conversation could not be loaded. Please try again.';
        _isLoading = false;
      });
    }
  }

  bool get _isReadOnlyConversation {
    final status = (_ticket.status ?? '').trim().toLowerCase();
    return _readOnly == true ||
        status == 'resolved' ||
        status == 'closed' ||
        status == 'cancelled';
  }

  bool get _canSendMessage {
    final status = (_ticket.status ?? '').trim().toLowerCase().replaceAll(
      '_',
      ' ',
    );
    final acceptedStatus = status == 'in progress' || status == 'pending';
    return _ticketStatusRefreshed &&
        !_isRefreshingTicketStatus &&
        !_isLoading &&
        !_isSending &&
        _chatAvailable == true &&
        !_isReadOnlyConversation &&
        acceptedStatus;
  }

  String? get _conversationNotice {
    if (_isReadOnlyConversation) return 'This conversation is read-only.';
    if (_chatAvailable == false) return 'Messaging is currently unavailable.';
    if (_isRefreshingTicketStatus) return 'Checking the latest ticket status.';
    if (!_ticketStatusRefreshed) {
      return 'Could not refresh the ticket status. Messaging is disabled.';
    }
    final status = (_ticket.status ?? '').trim().toLowerCase().replaceAll(
      '_',
      ' ',
    );
    if (status == 'open') {
      return 'Waiting for clinic staff to accept your ticket.';
    }
    if (!_canSendMessage && !_isLoading && _loadError == null) {
      return 'Messaging is currently unavailable.';
    }
    return null;
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    if (!_canSendMessage || _isSending) return;
    final text = _messageController.text.trim();
    final selectedImage = _selectedImage;
    if (text.isEmpty && selectedImage == null) return;

    setState(() {
      _isSending = true;
      _sendError = null;
    });

    try {
      final sentMessage = await widget.supportCenterService.sendMessage(
        ticketId: _ticket.ticketId,
        message: text,
        attachmentBytes: selectedImage?.bytes,
        attachmentName: selectedImage?.name,
        attachmentMimeType: selectedImage?.mimeType,
      );
      if (!mounted) return;
      setState(() {
        if (!_messages.any(
          (message) => message.messageId == sentMessage.messageId,
        )) {
          _messages = [..._messages, sentMessage];
          _messages = _orderedMessages(_messages);
        }
        _messageController.clear();
        _selectedImage = null;
        _isSending = false;
      });
      _scrollToLatest();
    } on SupportServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _sendError = _safeErrorMessage(error, sending: true);
        _isSending = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'support conversation',
          context: ErrorDescription('while sending a support message'),
        ),
      );
      setState(() {
        _sendError = 'Your message could not be sent. Please try again.';
        _isSending = false;
      });
    }
  }

  Future<void> _selectImage() async {
    if (!_canSendMessage || _isSending) return;
    setState(() => _sendError = null);

    try {
      final image = widget.imagePicker != null
          ? await widget.imagePicker!()
          : await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;

      final mimeType = _imageMimeType(image);
      if (mimeType == null) {
        setState(() {
          _sendError = 'Choose a JPEG, PNG, or WebP image.';
        });
        return;
      }

      final bytes = await image.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        setState(() => _sendError = 'The selected image is empty.');
        return;
      }
      if (bytes.length > _maxSupportImageBytes) {
        setState(() {
          _sendError = 'Images must be 10 MiB or smaller.';
        });
        return;
      }

      setState(() {
        _selectedImage = _SelectedSupportImage(
          name: image.name.trim().isEmpty
              ? 'support_image.${_extensionForMimeType(mimeType)}'
              : image.name,
          mimeType: mimeType,
          bytes: bytes,
        );
        _sendError = null;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'support conversation',
          context: ErrorDescription('while selecting a support image'),
        ),
      );
      setState(() {
        _sendError = 'The image could not be selected. Please try again.';
      });
    }
  }

  String? _imageMimeType(XFile image) {
    final mimeType = image.mimeType?.toLowerCase();
    final extension = image.name.split('.').last.toLowerCase();
    final extensionMimeType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (mimeType == null ||
        mimeType.isEmpty ||
        mimeType == 'application/octet-stream') {
      return extensionMimeType;
    }
    return _supportImageMimeTypes.contains(mimeType) ? mimeType : null;
  }

  String _extensionForMimeType(String mimeType) => switch (mimeType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => throw StateError('Unsupported support image MIME type: $mimeType'),
  };

  List<SupportMessage> _orderedMessages(List<SupportMessage> messages) {
    final indexedMessages = messages.indexed.toList()
      ..sort((left, right) {
        final leftAt = left.$2.createdAt;
        final rightAt = right.$2.createdAt;
        if (leftAt == null && rightAt != null) return -1;
        if (leftAt != null && rightAt == null) return 1;
        if (leftAt == null || rightAt == null) {
          return left.$1.compareTo(right.$1);
        }
        final chronology = leftAt.compareTo(rightAt);
        return chronology != 0 ? chronology : left.$1.compareTo(right.$1);
      });
    return indexedMessages.map((entry) => entry.$2).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to Support Service',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _ticket.subject?.trim().isNotEmpty == true
                  ? _ticket.subject!
                  : 'Support request',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'Ticket #${_ticket.ticketId} · '
              '${_ticketStatusLabel(_ticket.status)}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_conversationNotice case final notice?)
              Container(
                key: const ValueKey('support-conversation-notice'),
                width: double.infinity,
                color: _previewBlue.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  notice,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        key: ValueKey('support-messages-loading'),
                        color: _previewBlue,
                      ),
                    )
                  : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _loadError!,
                              key: const ValueKey('support-messages-error'),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              key: const ValueKey('support-messages-retry'),
                              onPressed: _loadMessages,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try again'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _previewBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet.',
                        key: const ValueKey('support-messages-empty'),
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      key: const ValueKey('support-messages-list'),
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) => _MessageBubble(
                        message: _messages[index],
                        patientId: _ticket.patientId,
                      ),
                    ),
            ),
            if (_sendError case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Text(
                  error,
                  key: const ValueKey('support-message-send-error'),
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ),
            if (_selectedImage case final image?)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        image.bytes,
                        key: const ValueKey('support-image-preview'),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(
                              width: 56,
                              height: 56,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        image.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('support-image-remove'),
                      tooltip: 'Remove image',
                      onPressed: _isSending
                          ? null
                          : () => setState(() => _selectedImage = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      key: const ValueKey('support-message-attach'),
                      tooltip: 'Attach image',
                      onPressed: _canSendMessage ? _selectImage : null,
                      icon: const Icon(Icons.image_outlined),
                    ),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('support-message-input'),
                        controller: _messageController,
                        enabled: _canSendMessage,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Type your message...',
                          counterText: '',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: _canSendMessage
                            ? (_) => _sendMessage()
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: const ValueKey('support-message-send'),
                      tooltip: _isSending ? 'Sending message' : 'Send message',
                      onPressed: _canSendMessage ? _sendMessage : null,
                      style: IconButton.styleFrom(
                        backgroundColor: _previewBlue,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final SupportMessage message;
  final String? patientId;

  const _MessageBubble({required this.message, required this.patientId});

  @override
  Widget build(BuildContext context) {
    final isUser =
        message.senderType?.toLowerCase() == 'patient' &&
        message.senderPatientId != null &&
        message.senderPatientId == patientId;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final background = isUser ? _previewBlue : Colors.white;
    final foreground = isUser ? Colors.white : Colors.black87;
    final timestamp = message.createdAt;
    final senderLabel = isUser
        ? 'You'
        : message.senderName?.trim().isNotEmpty == true
        ? message.senderName!
        : 'Clinic Support';

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(17),
              topRight: const Radius.circular(17),
              bottomLeft: Radius.circular(isUser ? 17 : 5),
              bottomRight: Radius.circular(isUser ? 5 : 17),
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                senderLabel,
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.78),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              if (message.attachmentUrl?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 250,
                    height: 190,
                    child: Image.network(
                      message.attachmentUrl!,
                      key: ValueKey(
                        'support-message-image-${message.messageId}',
                      ),
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) =>
                          loadingProgress == null
                          ? child
                          : const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _previewBlue,
                              ),
                            ),
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: foreground.withValues(alpha: 0.08),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: foreground.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (message.message?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 5),
                Text(message.message!, style: TextStyle(color: foreground)),
              ],
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  timestamp == null
                      ? 'Time unavailable'
                      : TimeOfDay.fromDateTime(
                          timestamp.toLocal(),
                        ).format(context),
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.75),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedSupportImage {
  const _SelectedSupportImage({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

class _PreviewNotice extends StatelessWidget {
  final String text;

  const _PreviewNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _previewBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _previewBlue, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
