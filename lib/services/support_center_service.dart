import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../constants.dart';
import '../models/support_ticket.dart';
import 'patient_session_service.dart';

enum SupportServiceFailureKind {
  missingAuthentication,
  unauthorized,
  forbidden,
  requestRejected,
  http,
  server,
  network,
  timeout,
  invalidResponse,
}

class SupportServiceException implements Exception {
  const SupportServiceException({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  final SupportServiceFailureKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SupportMessageList {
  const SupportMessageList({
    required this.messages,
    this.chatAvailable,
    this.readOnly,
  });

  final List<SupportMessage> messages;
  final bool? chatAvailable;
  final bool? readOnly;
}

class SupportCenterService {
  SupportCenterService({
    PatientSessionService? sessionService,
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 15),
  }) : _sessionService = sessionService ?? patientSessionService,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _baseUrl = baseUrl ?? apiBaseUrl;

  final PatientSessionService _sessionService;
  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final Duration timeout;

  static const _basePath = '/api/patients/support';

  Future<List<SupportTicket>> getMyTickets() async {
    final response = await _getJsonMapOrList(
      '$_basePath/my-tickets',
      cacheBust: true,
    );
    final collection = _requireCollectionResponse(response);
    final rows = _collectionFromBody(collection, const ['tickets', 'data']);
    return rows
        .map((row) => _parseResponse(() => SupportTicket.fromJson(row)))
        .toList(growable: false);
  }

  Future<SupportMessageList> getMessages(String ticketId) async {
    final response = await _getJsonMapOrList(
      '$_basePath/tickets/${Uri.encodeComponent(ticketId)}/messages',
      cacheBust: true,
    );
    final collection = _requireCollectionResponse(response);
    return _parseMessageList(collection);
  }

  SupportMessageList _parseMessageList(Object response) {
    final rows = _collectionFromBody(response, const ['messages', 'data']);
    final body = response is Map<String, dynamic> ? response : null;
    return SupportMessageList(
      messages: rows
          .map((row) => _parseResponse(() => SupportMessage.fromJson(row)))
          .toList(growable: false),
      chatAvailable: body == null ? null : _optionalBool(body, 'chatAvailable'),
      readOnly: body == null ? null : _optionalBool(body, 'readOnly'),
    );
  }

  Future<SupportTicket> createTicket({
    required String category,
    required String subject,
    required String description,
    required String priority,
  }) async {
    final body = await _postJson('$_basePath/tickets', {
      'category': category,
      'subject': subject,
      'description': description,
      'priority': priority,
    });
    final response = _requireSuccessfulBody(body);
    final ticket = response['ticket'] ?? response['data'];
    if (ticket is! Map<String, dynamic>) {
      throw _invalidResponse('The clinic service returned an invalid ticket.');
    }
    return _parseResponse(() => SupportTicket.fromJson(ticket));
  }

  Future<void> cancelTicket(String ticketId) async {
    final body = await _putJson(
      '$_basePath/tickets/${Uri.encodeComponent(ticketId)}/cancel',
    );
    _requireSuccessfulBody(body);
  }

  Future<SupportMessage> sendMessage({
    required String ticketId,
    required String message,
    Uint8List? attachmentBytes,
    String? attachmentName,
    String? attachmentMimeType,
  }) async {
    final path = '$_basePath/tickets/${Uri.encodeComponent(ticketId)}/messages';
    final trimmedMessage = message.trim();
    late final Map<String, dynamic> body;

    if (attachmentBytes == null) {
      if (trimmedMessage.isEmpty) {
        throw const SupportServiceException(
          kind: SupportServiceFailureKind.requestRejected,
          message: 'Write a message or attach an image.',
        );
      }
      body = await _postJson(path, {'message': trimmedMessage});
    } else {
      const maxImageBytes = 10 * 1024 * 1024;
      const allowedMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};
      if (attachmentBytes.isEmpty ||
          attachmentBytes.length > maxImageBytes ||
          attachmentName == null ||
          attachmentName.trim().isEmpty ||
          attachmentMimeType == null ||
          !allowedMimeTypes.contains(attachmentMimeType)) {
        throw const SupportServiceException(
          kind: SupportServiceFailureKind.requestRejected,
          message: 'The selected image is invalid or exceeds 10 MiB.',
        );
      }

      final response = await _sendJson(() async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$_baseUrl$path'),
        )..headers.addAll(_multipartHeaders());
        if (trimmedMessage.isNotEmpty) {
          request.fields['message'] = trimmedMessage;
        }
        request.files.add(
          http.MultipartFile.fromBytes(
            'attachment',
            attachmentBytes,
            filename: attachmentName,
            contentType: MediaType.parse(attachmentMimeType),
          ),
        );
        return http.Response.fromStream(await _client.send(request));
      });
      body = _requireMapResponse(response);
    }

    final response = _requireSuccessfulBody(body);
    final chatMessage = response['chatMessage'];
    if (chatMessage is! Map<String, dynamic>) {
      throw _invalidResponse(
        'The clinic service returned an invalid support message.',
      );
    }
    return _parseResponse(() => SupportMessage.fromJson(chatMessage));
  }

  Future<int> markMessagesRead(String ticketId) async {
    final body = await _putJson(
      '$_basePath/tickets/${Uri.encodeComponent(ticketId)}/messages/read',
    );
    final response = _requireSuccessfulBody(body);
    final updatedCount = response['updatedCount'];
    if (updatedCount is! num || updatedCount < 0) {
      throw _invalidResponse(
        'The clinic service returned an invalid read receipt.',
      );
    }
    return updatedCount.toInt();
  }

  Future<Object> _getJsonMapOrList(String path, {bool cacheBust = false}) {
    final query = cacheBust
        ? '?_=${DateTime.now().millisecondsSinceEpoch}'
        : '';
    return _sendJson(
      () => _client.get(Uri.parse('$_baseUrl$path$query'), headers: _headers()),
      allowList: true,
    );
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> payload,
  ) async {
    final response = await _sendJson(
      () => _client.post(
        Uri.parse('$_baseUrl$path'),
        headers: _headers(),
        body: jsonEncode(payload),
      ),
    );
    return _requireMapResponse(response);
  }

  Future<Map<String, dynamic>> _putJson(String path) async {
    final response = await _sendJson(
      () => _client.put(Uri.parse('$_baseUrl$path'), headers: _headers()),
      allowEmptyResponse: true,
    );
    return _requireMapResponse(response);
  }

  Map<String, String> _headers() {
    final token = _sessionService.token?.trim();
    if (token == null || token.isEmpty) {
      throw const SupportServiceException(
        kind: SupportServiceFailureKind.missingAuthentication,
        message: 'Please sign in to your patient account first.',
      );
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, String> _multipartHeaders() {
    final headers = _headers();
    headers.remove('Content-Type');
    return headers;
  }

  Future<Object> _sendJson(
    Future<http.Response> Function() send, {
    bool allowList = false,
    bool allowEmptyResponse = false,
  }) async {
    late final http.Response response;
    try {
      response = await send().timeout(timeout);
    } on TimeoutException {
      throw const SupportServiceException(
        kind: SupportServiceFailureKind.timeout,
        message: 'The request timed out. Please try again.',
      );
    } on http.ClientException {
      throw const SupportServiceException(
        kind: SupportServiceFailureKind.network,
        message: 'Unable to reach the clinic service. Check your connection.',
      );
    }

    Object? decoded;
    try {
      decoded = response.body.isEmpty && allowEmptyResponse
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _httpFailure(response.statusCode);
      }
      throw _invalidResponse(
        'The clinic service returned an invalid response.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = decoded is Map<String, dynamic> ? decoded : null;
      final message = body?['error'] ?? body?['message'];
      throw _httpFailure(
        response.statusCode,
        message: message is String ? message : null,
      );
    }

    if (decoded is Map<String, dynamic>) return decoded;
    if (allowList && decoded is List) return decoded;
    throw _invalidResponse('The clinic service returned an invalid response.');
  }

  Map<String, dynamic> _requireMapResponse(Object response) {
    if (response is Map<String, dynamic>) return response;
    throw _invalidResponse('The clinic service returned an invalid response.');
  }

  SupportServiceException _httpFailure(int statusCode, {String? message}) {
    final kind = switch (statusCode) {
      401 => SupportServiceFailureKind.unauthorized,
      403 => SupportServiceFailureKind.forbidden,
      >= 500 => SupportServiceFailureKind.server,
      _ => SupportServiceFailureKind.http,
    };
    final fallbackMessage = switch (statusCode) {
      401 => 'Your login session has expired. Please sign in again.',
      403 => 'This account cannot access patient support.',
      >= 500 => 'The clinic service is temporarily unavailable.',
      _ => 'The support request could not be completed.',
    };
    return SupportServiceException(
      kind: kind,
      statusCode: statusCode,
      message: message != null && message.trim().isNotEmpty
          ? message.trim()
          : fallbackMessage,
    );
  }

  SupportServiceException _invalidResponse(String message) =>
      SupportServiceException(
        kind: SupportServiceFailureKind.invalidResponse,
        message: message,
      );

  T _parseResponse<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException catch (error) {
      throw _invalidResponse(error.message);
    }
  }

  Map<String, dynamic> _requireSuccessfulBody(Object response) {
    if (response is! Map<String, dynamic>) {
      throw _invalidResponse(
        'The clinic service returned an invalid response.',
      );
    }
    if (response['success'] == false) {
      final message = response['message'] ?? response['error'];
      throw SupportServiceException(
        kind: SupportServiceFailureKind.requestRejected,
        message: message is String && message.trim().isNotEmpty
            ? message.trim()
            : 'The support request could not be completed.',
      );
    }
    return response;
  }

  Object _requireCollectionResponse(Object response) {
    if (response is Map<String, dynamic>) {
      return _requireSuccessfulBody(response);
    }
    if (response is List<Object?>) return response;
    throw _invalidResponse(
      'The clinic service returned an invalid support collection.',
    );
  }

  List<Map<String, dynamic>> _collectionFromBody(
    Object response,
    List<String> keys,
  ) {
    final values = switch (response) {
      List<Object?> list => list,
      Map<String, dynamic> body => _listFromBody(body, keys),
      _ => throw _invalidResponse(
        'The clinic service returned an invalid support collection.',
      ),
    };
    return values
        .map((value) {
          if (value is! Map<String, dynamic>) {
            throw _invalidResponse(
              'The clinic service returned an invalid support record.',
            );
          }
          return value;
        })
        .toList(growable: false);
  }

  List<Object?> _listFromBody(Map<String, dynamic> body, List<String> keys) {
    for (final key in keys) {
      final value = body[key];
      if (value is List<Object?>) return value;
    }
    throw _invalidResponse(
      'The clinic service returned an invalid support collection.',
    );
  }

  bool? _optionalBool(Map<String, dynamic> body, String key) {
    final value = body[key];
    if (value is bool) return value;
    if (value == 1 || value == '1' || value == 'true') return true;
    if (value == 0 || value == '0' || value == 'false') return false;
    return null;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
