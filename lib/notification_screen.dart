import 'package:flutter/material.dart';

import 'app_notifications.dart';

class NotificationScreen extends StatefulWidget {
  final String patientId;

  const NotificationScreen({
    super.key,
    required this.patientId,
  });

  @override
  State<NotificationScreen> createState() =>
      _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  void initState() {
    super.initState();

    notificationsController.load(
      widget.patientId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: const Color(0xFF0F76FF),
        actions: [
          TextButton(
            onPressed: () async {
              await notificationsController.markAllAsRead();
            },
            child: const Text(
              'Mark all read',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),

      body: AnimatedBuilder(
        animation: notificationsController,
        builder: (context, child) {
          final notifications =
              notificationsController.notifications;

          if (notifications.isEmpty) {
            return const Center(
              child: Text('No notifications yet.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final item = notifications[index];

              return Card(
                color: item.isRead
                    ? Colors.white
                    : Colors.blue.shade50,
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
                      : const Icon(
                          Icons.circle,
                          color: Colors.blue,
                          size: 10,
                        ),

                  onTap: () async {
                    await notificationsController
                        .markAsRead(item.id);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}