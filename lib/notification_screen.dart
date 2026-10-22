import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final DateTime date;
  final bool isRead;
  final String type;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.date,
    required this.isRead,
    required this.type,
  });

  NotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? date,
    bool? isRead,
    String? type,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      date: date ?? this.date,
      isRead: isRead ?? this.isRead,
      type: type ?? this.type,
    );
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final rawId = json['notification_id'] ?? json['id'];
    final rawRead = json['is_read'];

    return NotificationItem(
      id: rawId?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      date:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isRead:
          rawRead == 1 ||
          rawRead == true ||
          rawRead?.toString() == '1' ||
          rawRead?.toString().toLowerCase() == 'true',
      type: json['type']?.toString() ?? '',
    );
  }
}

class NotificationController extends ChangeNotifier {
  List<NotificationItem> _notifications = [];
  String? _patientId;
  String? _patientToken;
  bool _isLoading = false;
  String? _errorMessage;

  List<NotificationItem> get notifications => List.unmodifiable(_notifications);

  int get unreadCount =>
      _notifications.where((notification) => !notification.isRead).length;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Map<String, String> get _headers {
    final token = _patientToken?.trim() ?? '';
    return {
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Uri _patientNotificationsUri(String patientId) {
    return Uri.parse(
      '$apiBaseUrl/api/notifications/patient/${Uri.encodeComponent(patientId)}',
    );
  }

  void setPatientSession({required String patientId, required String token}) {
    final cleanPatientId = patientId.trim();
    final cleanToken = token.trim();

    if (cleanPatientId.isEmpty || cleanToken.isEmpty) {
      throw ArgumentError('A patient ID and patient token are required.');
    }

    _patientId = cleanPatientId;
    _patientToken = cleanToken;
  }

  // Loads notifications for the authenticated patient.
  // Pass the JWT returned by POST /api/patients/login.
  Future<void> load(String patientId, {String? token}) async {
    final cleanPatientId = patientId.trim();

    if (cleanPatientId.isEmpty) {
      _errorMessage = 'Patient ID is unavailable. Please sign in again.';
      debugPrint('NOTIFICATIONS: $_errorMessage');
      notifyListeners();
      return;
    }

    if (token != null && token.trim().isNotEmpty) {
      _patientToken = token.trim();
    }

    _patientId = cleanPatientId;

    if ((_patientToken ?? '').trim().isEmpty) {
      _errorMessage =
          'Patient login token is missing. Connect the existing login session before loading notifications.';
      debugPrint('NOTIFICATIONS: $_errorMessage');
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = _patientNotificationsUri(cleanPatientId);
      debugPrint('NOTIFICATIONS API REQUEST: $uri');

      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('NOTIFICATIONS STATUS: ${response.statusCode}');

      if (response.statusCode == 401 || response.statusCode == 403) {
        _errorMessage =
            _readError(response.body) ??
            'Your patient session is invalid or expired. Please sign in again.';
        debugPrint('NOTIFICATIONS AUTH ERROR: $_errorMessage');
        return;
      }

      if (response.statusCode != 200) {
        _errorMessage =
            _readError(response.body) ??
            'Failed to load notifications (${response.statusCode}).';
        debugPrint('NOTIFICATIONS ERROR: $_errorMessage');
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        _errorMessage =
            'The server returned an unexpected notifications response.';
        debugPrint('NOTIFICATIONS ERROR: $_errorMessage');
        return;
      }

      _notifications = decoded
          .whereType<Map>()
          .map(
            (item) =>
                NotificationItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.id.isNotEmpty)
          .toList();
    } catch (error, stackTrace) {
      _errorMessage =
          'Unable to load notifications. Check your connection and try again.';
      debugPrint('NOTIFICATIONS LOAD ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Gets the unread count from the API, then refreshes local state.
  Future<int?> refreshUnreadCount() async {
    final patientId = _patientId;
    if (patientId == null || patientId.isEmpty || !_hasToken) {
      debugPrint('UNREAD COUNT: Patient session or token is missing.');
      return null;
    }

    try {
      final uri = Uri.parse(
        '${_patientNotificationsUri(patientId).toString()}/unread-count',
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('UNREAD COUNT STATUS: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint(
          'UNREAD COUNT ERROR: ${_readError(response.body) ?? response.body}',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;

      final rawCount = decoded['unread_count'];
      final count = rawCount is num
          ? rawCount.toInt()
          : int.tryParse(rawCount?.toString() ?? '');
      return count;
    } catch (error) {
      debugPrint('UNREAD COUNT REQUEST ERROR: $error');
      return null;
    }
  }

  bool get _hasToken => (_patientToken ?? '').trim().isNotEmpty;

  // Marks one notification as read. The backend checks ownership
  // against the patient identified by the JWT.
  Future<void> markAsRead(String id) async {
    if (!_hasToken) {
      _errorMessage = 'Patient login token is missing. Please sign in again.';
      debugPrint('MARK AS READ: $_errorMessage');
      notifyListeners();
      return;
    }

    final cleanId = id.trim();
    if (cleanId.isEmpty) return;

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/api/notifications/${Uri.encodeComponent(cleanId)}/read',
      );
      final response = await http
          .patch(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('MARK NOTIFICATION READ STATUS: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _notifications = _notifications.map((item) {
          return item.id == cleanId ? item.copyWith(isRead: true) : item;
        }).toList();
        _errorMessage = null;
        notifyListeners();
        return;
      }

      _errorMessage =
          _readError(response.body) ??
          'Failed to mark notification as read (${response.statusCode}).';
      debugPrint('MARK AS READ ERROR: $_errorMessage');
    } catch (error, stackTrace) {
      _errorMessage = 'Unable to update notification. Please try again.';
      debugPrint('MARK NOTIFICATION READ ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    notifyListeners();
  }

  // Marks all notifications for the currently authenticated patient as read.
  Future<void> markAllAsRead() async {
    final patientId = _patientId;

    if (patientId == null || patientId.isEmpty || !_hasToken) {
      _errorMessage =
          'Patient session or token is missing. Please sign in again.';
      debugPrint('MARK ALL AS READ: $_errorMessage');
      notifyListeners();
      return;
    }

    try {
      final uri = Uri.parse(
        '${_patientNotificationsUri(patientId).toString()}/read-all',
      );
      final response = await http
          .patch(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));

      debugPrint('MARK ALL NOTIFICATIONS STATUS: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _notifications = _notifications
            .map((item) => item.copyWith(isRead: true))
            .toList();
        _errorMessage = null;
        notifyListeners();
        return;
      }

      _errorMessage =
          _readError(response.body) ??
          'Failed to mark all notifications as read (${response.statusCode}).';
      debugPrint('MARK ALL AS READ ERROR: $_errorMessage');
    } catch (error, stackTrace) {
      _errorMessage = 'Unable to update notifications. Please try again.';
      debugPrint('MARK ALL NOTIFICATIONS ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    notifyListeners();
  }

  String? _readError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final value = decoded['error'] ?? decoded['message'];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }
    } catch (_) {
      // Response body was not JSON; use the caller's fallback message.
    }
    return null;
  }

  Future<void> clear() async {
    _notifications = [];
    _patientId = null;
    _patientToken = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }
}

final notificationsController = NotificationController();

class NotificationScreen extends StatefulWidget {
  final String patientId;
  final String? token;

  const NotificationScreen({super.key, required this.patientId, this.token});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    notificationsController.load(widget.patientId, token: widget.token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: const Color(0xFF0F76FF),
        actions: [
          TextButton(
            onPressed: notificationsController.markAllAsRead,
            child: const Text(
              'Mark all read',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: notificationsController,
        builder: (context, child) {
          final controller = notificationsController;
          if (controller.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.errorMessage case final error?) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => controller.load(
                        widget.patientId,
                        token: widget.token,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final notifications = controller.notifications;
          if (notifications.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final item = notifications[index];
              return Card(
                color: item.isRead ? Colors.white : Colors.blue.shade50,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: item.isRead
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(item.body),
                  trailing: item.isRead
                      ? null
                      : const Icon(Icons.circle, color: Colors.blue, size: 10),
                  onTap: () => controller.markAsRead(item.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
