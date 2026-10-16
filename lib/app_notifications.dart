import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final DateTime date;
  final bool isRead;
  final String type;

  NotificationItem({
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

  factory NotificationItem.fromJson(
    Map<String, dynamic> json,
  ) {
    return NotificationItem(
      id: json['notification_id'].toString(),

      title: json['title']?.toString() ?? '',

      body: json['body']?.toString() ?? '',

      date: DateTime.tryParse(
            json['created_at']?.toString() ?? '',
          ) ??
          DateTime.now(),

      isRead:
          json['is_read'] == 1 ||
          json['is_read'] == true ||
          json['is_read']?.toString() == '1',

      type: json['type']?.toString() ?? '',
    );
  }
}

class NotificationController extends ChangeNotifier {
  List<NotificationItem> _notifications = [];

  String? _patientId;

  List<NotificationItem> get notifications =>
      List.unmodifiable(_notifications);

  int get unreadCount =>
      _notifications.where((item) => !item.isRead).length;

  // ======================================================
  // LOAD NOTIFICATIONS FROM EXPRESS API
  // ======================================================
  Future<void> load(String patientId) async {
    final trimmedPatientId = patientId.trim();

    if (trimmedPatientId.isEmpty) {
      debugPrint(
        'NOTIFICATIONS: No patient ID available.',
      );
      return;
    }

    _patientId = trimmedPatientId;

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/api/notifications/patient/'
        '${Uri.encodeComponent(trimmedPatientId)}',
      );

      debugPrint(
        'NOTIFICATIONS API REQUEST: $uri',
      );

      final response = await http
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
            },
          )
          .timeout(
            const Duration(seconds: 15),
          );

      debugPrint(
        'NOTIFICATIONS STATUS: ${response.statusCode}',
      );

      debugPrint(
        'NOTIFICATIONS RESPONSE: ${response.body}',
      );

      if (response.statusCode != 200) {
        debugPrint(
          'NOTIFICATIONS ERROR: '
          'Failed to load notifications.',
        );
        return;
      }

      final decoded = jsonDecode(response.body);

      if (decoded is List) {
        _notifications = decoded
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => NotificationItem.fromJson(item),
            )
            .toList();
      } else {
        _notifications = [];
      }

      notifyListeners();
    } catch (error) {
      debugPrint(
        '❌ NOTIFICATIONS LOAD ERROR: $error',
      );
    }
  }

  // ======================================================
  // MARK ONE NOTIFICATION AS READ
  // ======================================================
  Future<void> markAsRead(String id) async {
    try {
      final uri = Uri.parse(
        '$apiBaseUrl/api/notifications/$id/read',
      );

      final response = await http
          .patch(
            uri,
            headers: const {
              'Accept': 'application/json',
            },
          )
          .timeout(
            const Duration(seconds: 15),
          );

      debugPrint(
        'MARK NOTIFICATION READ STATUS: '
        '${response.statusCode}',
      );

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        _notifications = _notifications.map((item) {
          if (item.id == id) {
            return item.copyWith(isRead: true);
          }

          return item;
        }).toList();

        notifyListeners();
      }
    } catch (error) {
      debugPrint(
        '❌ MARK NOTIFICATION READ ERROR: $error',
      );
    }
  }

  // ======================================================
  // MARK ALL NOTIFICATIONS AS READ
  // ======================================================
  Future<void> markAllAsRead() async {
    final patientId = _patientId;

    if (patientId == null || patientId.isEmpty) {
      return;
    }

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/api/notifications/patient/'
        '${Uri.encodeComponent(patientId)}/read-all',
      );

      final response = await http
          .patch(
            uri,
            headers: const {
              'Accept': 'application/json',
            },
          )
          .timeout(
            const Duration(seconds: 15),
          );

      debugPrint(
        'MARK ALL NOTIFICATIONS STATUS: '
        '${response.statusCode}',
      );

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        _notifications = _notifications
            .map(
              (item) => item.copyWith(
                isRead: true,
              ),
            )
            .toList();

        notifyListeners();
      }
    } catch (error) {
      debugPrint(
        '❌ MARK ALL NOTIFICATIONS ERROR: $error',
      );
    }
  }

  Future<void> clear() async {
    _notifications = [];
    notifyListeners();
  }
}

final notificationsController =
    NotificationController();