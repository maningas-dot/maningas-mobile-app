import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'services/api_service.dart';

abstract interface class PasswordRecoveryService {
  Future<void> requestOtp({required String email});

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  });

  void close();
}

class PasswordRecoveryException implements Exception {
  const PasswordRecoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiPasswordRecoveryService implements PasswordRecoveryService {
  ApiPasswordRecoveryService({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  Uri _endpoint(String path) =>
      Uri.parse('${ApiService.endpointUrl}/$path');

  Future<(http.Response, Map<String, dynamic>?)> _post(
    String path,
    Map<String, String> body,
  ) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint(path),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const PasswordRecoveryException(
        'The request timed out. Please try again.',
      );
    } on http.ClientException {
      throw const PasswordRecoveryException(
        'Network error. Check your connection and try again.',
      );
    }

    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      data = null;
    }
    return (response, data);
  }

  @override
  Future<void> requestOtp({required String email}) async {
    final (response, data) = await _post(
      'forgot-password',
      {'email': email},
    );
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        data?['success'] == true) {
      return;
    }
    if (response.statusCode >= 500) {
      throw const PasswordRecoveryException(
        'The server could not process the request. Please try again later.',
      );
    }
    throw const PasswordRecoveryException(
      'Could not request a password reset code. Please try again.',
    );
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final (response, data) = await _post(
      'reset-password',
      {'email': email, 'otp': otp, 'newPassword': newPassword},
    );
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        data?['success'] == true) {
      return;
    }
    if (response.statusCode == 400) {
      final message = data?['message'];
      if (message is String && message.trim().isNotEmpty) {
        throw PasswordRecoveryException(message.trim());
      }
      throw const PasswordRecoveryException(
        'The code is invalid or has expired. Request a new code and try again.',
      );
    }
    if (response.statusCode >= 500) {
      throw const PasswordRecoveryException(
        'The server could not reset your password. Please try again later.',
      );
    }
    throw const PasswordRecoveryException(
      'Could not reset the password. Check your details and try again.',
    );
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}

enum _RecoveryStep { email, otp, resetPassword, success }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.service});

  final PasswordRecoveryService? service;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());

  _RecoveryStep _step = _RecoveryStep.email;
  String? _otpError;
  bool _loading = false;
  bool _newPasswordVisible = false;
  bool _confirmPasswordVisible = false;
  late final PasswordRecoveryService _service;
  late final bool _ownsService;
  Timer? _codeCountdownTimer;
  DateTime? _codeExpiresAt;
  String? _serviceError;
  String? _serviceMessage;

  String get _email => _emailController.text.trim().toLowerCase();
  String get _otp =>
      _otpControllers.map((controller) => controller.text).join();

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? ApiPasswordRecoveryService();
  }

  @override
  void dispose() {
    _codeCountdownTimer?.cancel();
    if (_ownsService) _service.close();
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final node in _otpFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _continueFromEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    await _runService(() async {
      await _service.requestOtp(email: _email);
      if (!mounted) return;
      _startCodeCountdown();
      for (final controller in _otpControllers) {
        controller.clear();
      }
      setState(() {
        _step = _RecoveryStep.otp;
        _otpError = null;
        _serviceMessage =
            'If an account exists for this email, a code has been sent.';
      });
    });
  }

  Future<void> _continueFromOtp() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_otp)) {
      setState(() => _otpError = 'Enter the complete 6-digit code.');
      return;
    }
    setState(() => _otpError = null);
    setState(() => _step = _RecoveryStep.resetPassword);
  }

  Future<void> _resetPassword() async {
    if (!_resetFormKey.currentState!.validate()) return;
    await _runService(() async {
      await _service.resetPassword(
        email: _email,
        otp: _otp,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      _codeCountdownTimer?.cancel();
      for (final controller in _otpControllers) {
        controller.clear();
      }
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      setState(() => _step = _RecoveryStep.success);
    });
  }

  Future<void> _runService(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _serviceError = null;
      _serviceMessage = null;
    });
    try {
      await action();
    } on PasswordRecoveryException catch (error) {
      if (mounted) setState(() => _serviceError = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _serviceError =
              'Password recovery could not be completed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startCodeCountdown() {
    _codeCountdownTimer?.cancel();
    _codeExpiresAt = DateTime.now().add(const Duration(minutes: 5));
    _codeCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_codeExpiresAt!.difference(DateTime.now()).inSeconds <= 0) {
        _codeCountdownTimer?.cancel();
      }
    });
  }

  String get _codeTimeRemaining {
    final expiresAt = _codeExpiresAt;
    if (expiresAt == null) return '';
    final seconds = expiresAt.difference(DateTime.now()).inSeconds.clamp(
      0,
      5 * 60,
    );
    final minutesText = (seconds ~/ 60).toString().padLeft(2, '0');
    final secondsText = (seconds % 60).toString().padLeft(2, '0');
    return '$minutesText:$secondsText';
  }

  Future<void> _resendCode() async {
    await _runService(() async {
      await _service.requestOtp(email: _email);
      if (!mounted) return;
      _startCodeCountdown();
      for (final controller in _otpControllers) {
        controller.clear();
      }
      setState(() {
        _otpError = null;
        _serviceMessage =
            'If an account exists for this email, a new code has been requested.';
      });
    });
  }

  void _goToLogin() {
    _codeCountdownTimer?.cancel();
    Navigator.of(context).pop();
  }

  void _goBack() {
    if (_step == _RecoveryStep.success) {
      _goToLogin();
    } else if (_step != _RecoveryStep.email) {
      setState(() {
        _step = _RecoveryStep.values[_step.index - 1];
        _otpError = null;
      });
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Widget _buildFeedback() {
    if (_serviceError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          _serviceError!,
          key: const ValueKey('forgot-password-service-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_serviceMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          _serviceMessage!,
          key: const ValueKey('forgot-password-service-message'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF174A83)),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSuccessStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_outline, color: Colors.green, size: 52),
        const SizedBox(height: 16),
        const Text(
          'Your password has been reset successfully.',
          key: ValueKey('forgot-password-success'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('forgot-password-back-to-login'),
          onPressed: _goToLogin,
          child: const Text('Back to Login'),
        ),
      ],
    );
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Enter the email address registered to your account.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          TextFormField(
            key: const ValueKey('forgot-password-email'),
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Registered email address',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) {
              final email = (value ?? '').trim();
              if (email.isEmpty) return 'Enter your registered email address.';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                return 'Enter a valid email address.';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('forgot-password-continue'),
            onPressed: _loading ? null : _continueFromEmail,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter the six-digit code for your registered email.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 8),
        Text(
          'Code expires in $_codeTimeRemaining. The server determines whether the code is valid.',
          key: const ValueKey('forgot-password-countdown'),
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            _otpControllers.length,
            (index) => SizedBox(
              width: 42,
              child: TextField(
                key: ValueKey('forgot-password-otp-$index'),
                controller: _otpControllers[index],
                focusNode: _otpFocusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                decoration: const InputDecoration(counterText: ''),
                onChanged: (value) {
                  if (value.isNotEmpty && index < _otpFocusNodes.length - 1) {
                    _otpFocusNodes[index + 1].requestFocus();
                  } else if (value.isEmpty && index > 0) {
                    _otpFocusNodes[index - 1].requestFocus();
                  }
                  if (_otpError != null) setState(() => _otpError = null);
                },
              ),
            ),
          ),
        ),
        if (_otpError != null) ...[
          const SizedBox(height: 8),
          Text(
            _otpError!,
            key: const ValueKey('forgot-password-otp-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('forgot-password-continue-to-reset'),
          onPressed: _loading ? null : _continueFromOtp,
          child: const Text('Continue'),
        ),
        TextButton(
          key: const ValueKey('forgot-password-resend'),
          onPressed: _loading ? null : _resendCode,
          child: const Text('Request another code'),
        ),
      ],
    );
  }

  Widget _buildResetStep() {
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose a new password and confirm it.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          TextFormField(
            key: const ValueKey('forgot-password-new'),
            controller: _newPasswordController,
            obscureText: !_newPasswordVisible,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                key: ValueKey('forgot-password-new-visibility'),
                onPressed: () => setState(
                  () => _newPasswordVisible = !_newPasswordVisible,
                ),
                icon: Icon(
                  _newPasswordVisible
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
              ),
            ),
            validator: (value) {
              final password = value ?? '';
              if (password.length < 8) {
                return 'Password must be at least 8 characters.';
              }
              if (password.length > 128) {
                return 'Password must not exceed 128 characters.';
              }
              if (RegExp(r'\s').hasMatch(password)) {
                return 'Password must not contain spaces.';
              }
              if (!RegExp(r'[a-z]').hasMatch(password)) {
                return 'Password must contain a lowercase letter.';
              }
              if (!RegExp(r'[A-Z]').hasMatch(password)) {
                return 'Password must contain an uppercase letter.';
              }
              if (!RegExp(r'[0-9]').hasMatch(password)) {
                return 'Password must contain a number.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('forgot-password-confirm'),
            controller: _confirmPasswordController,
            obscureText: !_confirmPasswordVisible,
            decoration: InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                key: ValueKey('forgot-password-confirm-visibility'),
                onPressed: () => setState(
                  () => _confirmPasswordVisible = !_confirmPasswordVisible,
                ),
                icon: Icon(
                  _confirmPasswordVisible
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
              ),
            ),
            validator: (value) {
              if ((value ?? '').isEmpty) return 'Confirm your new password.';
              if (value != _newPasswordController.text) {
                return 'Passwords do not match.';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'The code is validated by the server when you reset your password.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
            FilledButton(
            key: const ValueKey('forgot-password-reset'),
            onPressed: _loading ? null : _resetPassword,
            child: const Text('Reset password'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stepContent = switch (_step) {
      _RecoveryStep.email => _buildEmailStep(),
      _RecoveryStep.otp => _buildOtpStep(),
      _RecoveryStep.resetPassword => _buildResetStep(),
      _RecoveryStep.success => _buildSuccessStep(),
    };

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('forgot-password-back'),
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Forgot Password?'),
        backgroundColor: const Color(0xFF0F76FF),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 4,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.lock_reset,
                        color: Color(0xFF0F76FF),
                        size: 44,
                      ),
                      const SizedBox(height: 16),
                      _buildFeedback(),
                      stepContent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
