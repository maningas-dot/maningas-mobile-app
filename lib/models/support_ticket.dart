class SupportTicket {
  const SupportTicket({
    required this.ticketId,
    this.patientId,
    this.subject,
    this.category,
    this.priority,
    this.status,
    this.resolution,
    this.createdAt,
    this.updatedAt,
  });

  final String ticketId;
  final String? patientId;
  final String? subject;
  final String? category;
  final String? priority;
  final String? status;
  final String? resolution;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPatientCancelled {
    final normalizedStatus = (status ?? '').trim().toLowerCase();
    final normalizedResolution = (resolution ?? '').trim().toLowerCase();
    return normalizedStatus == 'cancelled' ||
        normalizedResolution == 'cancelled' ||
        normalizedResolution == 'cancelled by patient';
  }

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    final ticketId = _stringValue(json['ticket_id']);
    if (ticketId == null || ticketId.isEmpty) {
      throw const FormatException('Support ticket is missing its ticket ID.');
    }

    return SupportTicket(
      ticketId: ticketId,
      patientId: _stringValue(json['patient_id']),
      subject: _stringValue(json['subject']),
      category: _stringValue(json['category']),
      priority: _stringValue(json['priority']),
      status: _stringValue(json['status']),
      resolution: _firstNonEmptyStringValue(json, const [
        'resolution',
        'resolution_note',
        'cancellation_reason',
        'close_reason',
      ]),
      createdAt: _dateTimeValue(json['created_at']),
      updatedAt: _dateTimeValue(json['updated_at']),
    );
  }

  Map<String, Object?> toJson() => {
    'ticket_id': ticketId,
    'patient_id': patientId,
    'subject': subject,
    'category': category,
    'priority': priority,
    'status': status,
    'resolution': resolution,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };
}

String? _firstNonEmptyStringValue(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final key in keys) {
    final value = _stringValue(json[key]);
    if (value != null && value.trim().isNotEmpty) return value;
  }
  return null;
}

class SupportMessage {
  const SupportMessage({
    required this.messageId,
    required this.ticketId,
    this.senderId,
    this.senderPatientId,
    this.senderName,
    this.senderRole,
    this.senderType,
    this.message,
    this.attachmentUrl,
    this.attachmentName,
    this.attachmentMimeType,
    this.isRead,
    this.createdAt,
  });

  final String messageId;
  final String ticketId;
  final String? senderId;
  final String? senderPatientId;
  final String? senderName;
  final String? senderRole;
  final String? senderType;
  final String? message;
  final String? attachmentUrl;
  final String? attachmentName;
  final String? attachmentMimeType;
  final bool? isRead;
  final DateTime? createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    final messageId = _stringValue(json['message_id']);
    if (messageId == null || messageId.isEmpty) {
      throw const FormatException('Support message is missing its message ID.');
    }
    final ticketId = _stringValue(json['ticket_id']);
    if (ticketId == null || ticketId.isEmpty) {
      throw const FormatException('Support message is missing its ticket ID.');
    }

    return SupportMessage(
      messageId: messageId,
      ticketId: ticketId,
      senderId: _stringValue(json['sender_id']),
      senderPatientId: _stringValue(json['sender_patient_id']),
      senderName: _stringValue(json['sender_name']),
      senderRole: _stringValue(json['sender_role']),
      senderType: _stringValue(json['sender_type']),
      message: _stringValue(json['message']),
      attachmentUrl: _stringValue(json['attachment_url']),
      attachmentName: _stringValue(json['attachment_name']),
      attachmentMimeType: _stringValue(json['attachment_mime_type']),
      isRead: _boolValue(json['is_read']),
      createdAt: _dateTimeValue(json['created_at']),
    );
  }

  Map<String, Object?> toJson() => {
    'message_id': messageId,
    'ticket_id': ticketId,
    'sender_id': senderId,
    'sender_patient_id': senderPatientId,
    'sender_name': senderName,
    'sender_role': senderRole,
    'sender_type': senderType,
    'message': message,
    'attachment_url': attachmentUrl,
    'attachment_name': attachmentName,
    'attachment_mime_type': attachmentMimeType,
    'is_read': isRead,
    'created_at': createdAt?.toIso8601String(),
  };
}

String? _stringValue(Object? value) {
  if (value is String) return value;
  if (value is num) return value.toString();
  return null;
}

DateTime? _dateTimeValue(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

bool? _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is num) {
    if (value == 1) return true;
    if (value == 0) return false;
  }
  if (value is String) {
    switch (value.toLowerCase()) {
      case '1':
      case 'true':
        return true;
      case '0':
      case 'false':
        return false;
    }
  }
  return null;
}
