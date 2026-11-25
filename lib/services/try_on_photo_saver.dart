import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class TryOnJpegDataUrl {
  static const String dataUrlPrefix = 'data:image/jpeg;base64,';
  static const int maxPayloadBytes = 10 * 1024 * 1024;

  static bool isSupported(String dataUrl) => dataUrl.startsWith(dataUrlPrefix);

  static Uint8List decode(String dataUrl) {
    if (!isSupported(dataUrl)) {
      throw const FormatException('Expected a JPEG Base64 data URL.');
    }

    final payload = dataUrl.substring(dataUrlPrefix.length);
    if (payload.isEmpty) {
      throw const FormatException('The JPEG payload is empty.');
    }

    final maxEncodedLength = ((maxPayloadBytes + 2) ~/ 3) * 4;
    if (payload.length > maxEncodedLength) {
      throw const FormatException('The JPEG payload exceeds the size limit.');
    }

    final bytes = base64Decode(payload);
    if (bytes.isEmpty || bytes.length > maxPayloadBytes) {
      throw const FormatException('The JPEG payload has an invalid size.');
    }

    if (!_hasJpegSignature(bytes)) {
      throw const FormatException('The payload is not a valid JPEG image.');
    }

    return bytes;
  }

  static bool _hasJpegSignature(Uint8List bytes) =>
      bytes.length >= 5 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF &&
      bytes[bytes.length - 2] == 0xFF &&
      bytes[bytes.length - 1] == 0xD9;
}

class TryOnPhotoGallerySaver {
  TryOnPhotoGallerySaver({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(methodChannelName);

  static const String methodChannelName =
      'com.gonzalesvisionclinic.optcare_app/try_on_gallery';
  static const String legacyPermissionCheckMethod =
      'requiresLegacyStoragePermission';
  static const String saveJpegMethod = 'saveTryOnJpeg';

  final MethodChannel _channel;
  final Set<int> _inFlightCaptures = <int>{};
  Future<void> _saveQueue = Future<void>.value();

  Future<String?> saveDataUrl(String dataUrl) {
    final bytes = TryOnJpegDataUrl.decode(dataUrl);
    final fingerprint = Object.hash(dataUrl.length, dataUrl.hashCode);
    if (_inFlightCaptures.contains(fingerprint)) {
      return Future<String?>.value();
    }

    _inFlightCaptures.add(fingerprint);
    final previousSave = _saveQueue;
    final saveFinished = Completer<void>();
    _saveQueue = saveFinished.future;

    return previousSave.then((_) async {
      try {
        final requiresLegacyPermission = await _channel.invokeMethod<bool>(
          legacyPermissionCheckMethod,
        );
        if (requiresLegacyPermission == true) {
          final permissionStatus = await Permission.storage.request();
          if (!permissionStatus.isGranted) {
            throw const TryOnPhotoPermissionDeniedException();
          }
        }

        final savedUri = await _channel.invokeMethod<String>(
          saveJpegMethod,
          bytes,
        );
        if (savedUri == null || savedUri.isEmpty) {
          throw const TryOnPhotoSaveFailedException();
        }

        return savedUri;
      } finally {
        _inFlightCaptures.remove(fingerprint);
        saveFinished.complete();
      }
    });
  }
}

class TryOnPhotoPermissionDeniedException implements Exception {
  const TryOnPhotoPermissionDeniedException();
}

class TryOnPhotoSaveFailedException implements Exception {
  const TryOnPhotoSaveFailedException();
}
