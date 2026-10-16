import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class TryOnWebViewScreen extends StatefulWidget {
  final int frameId;

  const TryOnWebViewScreen({super.key, required this.frameId});

  @override
  State<TryOnWebViewScreen> createState() => _TryOnWebViewScreenState();
}

class _TryOnWebViewScreenState extends State<TryOnWebViewScreen> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();

    _initializeWebView();
  }

  Future<void> _initializeWebView() async {
    // --------------------------------------------------
    // 1. REQUEST ANDROID CAMERA PERMISSION
    // --------------------------------------------------

    final cameraPermission = await Permission.camera.request();

    debugPrint('📷 APP CAMERA PERMISSION: $cameraPermission');

    if (cameraPermission.isGranted) {
      debugPrint('✅ Android camera permission granted.');
    } else {
      debugPrint('❌ Android camera permission was not granted.');
    }

    // --------------------------------------------------
    // 2. BUILD TRY-ON URL
    // --------------------------------------------------

    final url = Uri.parse('https://gonzalesvisionclinic.onrender.com').replace(
      queryParameters: {
        'frameId': widget.frameId.toString(),
        'mobileTryOn': 'true',
      },
    );

    debugPrint('TRY-ON URL: $url');

    // --------------------------------------------------
    // 3. CREATE WEBVIEW CONTROLLER
    // --------------------------------------------------

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // --------------------------------------------------
      // RECEIVE JAVASCRIPT LOGS FROM THE VTO WEBSITE
      // --------------------------------------------------
      ..addJavaScriptChannel(
        'FlutterLog',
        onMessageReceived: (message) {
          debugPrint('📱 VTO JS: ${message.message}');
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('TRY-ON PAGE STARTED: $url');
          },

          onPageFinished: (url) {
            debugPrint('TRY-ON PAGE FINISHED: $url');
          },

          onWebResourceError: (error) {
            debugPrint('TRY-ON WEBVIEW ERROR: ${error.description}');
          },
        ),
      );

    // --------------------------------------------------
    // 4. HANDLE WEBVIEW CAMERA PERMISSION
    // --------------------------------------------------

    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;

      androidController.setOnPlatformPermissionRequest((request) async {
        debugPrint(
          '🌐 WEBVIEW PERMISSION REQUEST: '
          '${request.types}',
        );

        if (request.types.contains(WebViewPermissionResourceType.camera)) {
          final permission = await Permission.camera.status;

          debugPrint('📷 CURRENT CAMERA STATUS: $permission');

          if (permission.isGranted) {
            debugPrint('✅ GRANTING WEBVIEW CAMERA');

            await request.grant();
          } else {
            debugPrint('❌ CAMERA NOT GRANTED - DENYING WEBVIEW');

            await request.deny();
          }
        } else {
          debugPrint('❌ UNKNOWN WEBVIEW PERMISSION - DENY');

          await request.deny();
        }
      });
    }

    // --------------------------------------------------
    // 5. LOAD WEB TRY-ON
    // --------------------------------------------------

    debugPrint('🌐 LOADING TRY-ON WEBPAGE...');

    await controller.loadRequest(url);

    // --------------------------------------------------
    // 6. SAVE CONTROLLER
    // --------------------------------------------------

    if (!mounted) return;

    setState(() {
      _controller = controller;
    });

    debugPrint('✅ TRY-ON WEBVIEW INITIALIZED');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Virtual Try-On')),
      body: _controller == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: _controller!),
    );
  }
}
