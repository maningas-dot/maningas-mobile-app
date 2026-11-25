import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:optcare_app/services/try_on_photo_saver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(TryOnPhotoGallerySaver.methodChannelName);

  void setMockHandler(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('TryOnJpegDataUrl.decode', () {
    test('decodes a valid JPEG data URL', () {
      final bytes = _jpegBytes();

      expect(TryOnJpegDataUrl.decode(_dataUrl(bytes)), orderedEquals(bytes));
    });

    test('rejects a non-JPEG MIME type', () {
      expect(
        () => TryOnJpegDataUrl.decode(
          'data:image/png;base64,${base64Encode(_jpegBytes())}',
        ),
        throwsFormatException,
      );
    });

    test('rejects a missing Base64 payload', () {
      expect(
        () => TryOnJpegDataUrl.decode(TryOnJpegDataUrl.dataUrlPrefix),
        throwsFormatException,
      );
    });

    test('rejects invalid Base64', () {
      expect(
        () => TryOnJpegDataUrl.decode(
          '${TryOnJpegDataUrl.dataUrlPrefix}%%%not-base64%%%',
        ),
        throwsFormatException,
      );
    });

    test('rejects a payload without the JPEG signature', () {
      expect(
        () => TryOnJpegDataUrl.decode(
          _dataUrl(Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6])),
        ),
        throwsFormatException,
      );
    });

    test('rejects a payload larger than the configured maximum', () {
      final bytes = Uint8List(TryOnJpegDataUrl.maxPayloadBytes + 1)
        ..[0] = 0xFF
        ..[1] = 0xD8
        ..[2] = 0xFF
        ..[TryOnJpegDataUrl.maxPayloadBytes - 1] = 0xFF
        ..[TryOnJpegDataUrl.maxPayloadBytes] = 0xD9;

      expect(
        () => TryOnJpegDataUrl.decode(_dataUrl(bytes)),
        throwsFormatException,
      );
    });
  });

  group('TryOnPhotoGallerySaver', () {
    test(
      'passes binary JPEG bytes and returns the confirmed saved URI',
      () async {
        final calls = <MethodCall>[];
        setMockHandler((call) async {
          calls.add(call);
          if (call.method ==
              TryOnPhotoGallerySaver.legacyPermissionCheckMethod) {
            return false;
          }
          if (call.method == TryOnPhotoGallerySaver.saveJpegMethod) {
            expect(call.arguments, isA<Uint8List>());
            return 'content://media/external/images/media/17';
          }
          throw MissingPluginException();
        });
        final saver = TryOnPhotoGallerySaver(channel: channel);

        final uri = await saver.saveDataUrl(_dataUrl(_jpegBytes()));

        expect(uri, 'content://media/external/images/media/17');
        expect(calls.map((call) => call.method), <String>[
          TryOnPhotoGallerySaver.legacyPermissionCheckMethod,
          TryOnPhotoGallerySaver.saveJpegMethod,
        ]);
      },
    );

    test('surfaces a native save failure and permits a retry', () async {
      var saveAttempts = 0;
      setMockHandler((call) async {
        if (call.method == TryOnPhotoGallerySaver.legacyPermissionCheckMethod) {
          return false;
        }
        if (call.method == TryOnPhotoGallerySaver.saveJpegMethod) {
          saveAttempts++;
          if (saveAttempts == 1) {
            throw PlatformException(code: 'GALLERY_SAVE_FAILED');
          }
          return 'content://media/external/images/media/18';
        }
        throw MissingPluginException();
      });
      final saver = TryOnPhotoGallerySaver(channel: channel);
      final url = _dataUrl(_jpegBytes());

      await expectLater(
        saver.saveDataUrl(url),
        throwsA(isA<PlatformException>()),
      );
      expect(
        await saver.saveDataUrl(url),
        'content://media/external/images/media/18',
      );
      expect(saveAttempts, 2);
    });

    test(
      'ignores in-flight duplicates and releases the guard after saving',
      () async {
        final saveResults = <Completer<Object?>>[];
        setMockHandler((call) async {
          if (call.method ==
              TryOnPhotoGallerySaver.legacyPermissionCheckMethod) {
            return false;
          }
          if (call.method == TryOnPhotoGallerySaver.saveJpegMethod) {
            final saveResult = Completer<Object?>();
            saveResults.add(saveResult);
            return saveResult.future;
          }
          throw MissingPluginException();
        });
        final saver = TryOnPhotoGallerySaver(channel: channel);
        final url = _dataUrl(_jpegBytes());

        final firstSave = saver.saveDataUrl(url);
        expect(await saver.saveDataUrl(url), isNull);
        await Future<void>.delayed(Duration.zero);
        expect(saveResults, hasLength(1));

        saveResults[0].complete('content://media/external/images/media/19');
        expect(await firstSave, 'content://media/external/images/media/19');
        final nextCapture = saver.saveDataUrl(url);
        await Future<void>.delayed(Duration.zero);
        expect(saveResults, hasLength(2));
        saveResults[1].complete('content://media/external/images/media/22');
        expect(await nextCapture, 'content://media/external/images/media/22');
      },
    );

    test(
      'serializes overlapping captures without dropping the second',
      () async {
        final saveResults = <Completer<Object?>>[];
        setMockHandler((call) async {
          if (call.method ==
              TryOnPhotoGallerySaver.legacyPermissionCheckMethod) {
            return false;
          }
          if (call.method == TryOnPhotoGallerySaver.saveJpegMethod) {
            final result = Completer<Object?>();
            saveResults.add(result);
            return result.future;
          }
          throw MissingPluginException();
        });
        final saver = TryOnPhotoGallerySaver(channel: channel);
        final firstSave = saver.saveDataUrl(_dataUrl(_jpegBytes(1)));
        final secondSave = saver.saveDataUrl(_dataUrl(_jpegBytes(2)));

        await Future<void>.delayed(Duration.zero);
        expect(saveResults, hasLength(1));
        saveResults[0].complete('content://media/external/images/media/20');
        expect(await firstSave, 'content://media/external/images/media/20');

        await Future<void>.delayed(Duration.zero);
        expect(saveResults, hasLength(2));
        saveResults[1].complete('content://media/external/images/media/21');
        expect(await secondSave, 'content://media/external/images/media/21');
      },
    );
  });
}

Uint8List _jpegBytes([int marker = 0]) =>
    Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, marker, 0xFF, 0xD9]);

String _dataUrl(Uint8List bytes) =>
    '${TryOnJpegDataUrl.dataUrlPrefix}${base64Encode(bytes)}';
