import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app_settings.dart';
import 'constants.dart';
import 'services/password_recovery_service.dart';
import 'services/patient_session_service.dart';
import 'support_service_preview.dart' show SupportServiceScreen;
import 'terms_and_conditions.dart';

enum _PasswordChangeStep { currentPassword, otpAndNewPassword }

class SettingsScreen extends StatefulWidget {
  final String patientId;
  final String? patientEmail;
  final PatientSessionService? sessionService;
  final PasswordRecoveryService? passwordRecoveryService;

  const SettingsScreen({
    super.key,
    required this.patientId,
    this.patientEmail,
    this.sessionService,
    this.passwordRecoveryService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool _notificationsOn = true;
  bool _emailUpdatesOn = true;
  bool _currentPasswordVisible = false;
  bool _newPasswordVisible = false;
  bool _confirmPasswordVisible = false;

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isLoading = true;
  bool _passwordChangeLoading = false;
  bool _ownsPasswordRecoveryService = false;
  _PasswordChangeStep _passwordChangeStep = _PasswordChangeStep.currentPassword;
  int _resendSecondsRemaining = 0;
  Timer? _resendCountdownTimer;
  late final PatientSessionService _sessionService =
      widget.sessionService ?? patientSessionService;
  late final PasswordRecoveryService _passwordRecoveryService;

  @override
  void initState() {
    super.initState();
    _ownsPasswordRecoveryService = widget.passwordRecoveryService == null;
    _passwordRecoveryService =
        widget.passwordRecoveryService ?? ApiPasswordRecoveryService();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await appSettingsController.load();

    final settings = appSettingsController.value;

    if (!mounted) return;

    setState(() {
      _notificationsOn = settings.notificationsOn;
      _emailUpdatesOn = settings.emailUpdatesOn;
      _isLoading = false;
    });
  }

  Future<void> _updateNotification(bool value) async {
    await appSettingsController.setNotificationsOn(value);

    if (!mounted) return;

    setState(() {
      _notificationsOn = value;
    });
  }

  Future<void> _updateEmailUpdates(bool value) async {
    await appSettingsController.setEmailUpdatesOn(value);

    if (!mounted) return;

    setState(() {
      _emailUpdatesOn = value;
    });
  }

  String _sanitizeResponseBody(String body) {
    final trimmed = body.trim();

    if (trimmed.isEmpty) {
      return '(empty response body)';
    }

    try {
      final decoded = jsonDecode(trimmed);

      dynamic redact(dynamic value) {
        if (value is Map) {
          final redacted = <String, dynamic>{};

          for (final entry in value.entries) {
            final key = entry.key.toString().toLowerCase();
            final safeValue = entry.value;

            if (key.contains('password') ||
                key.contains('otp') ||
                key.contains('token') ||
                key.contains('secret') ||
                key.contains('authorization') ||
                key.contains('cookie')) {
              redacted[entry.key.toString()] = '[REDACTED]';
            } else if (key.contains('email')) {
              final rawEmail = safeValue?.toString() ?? '';
              redacted[entry.key.toString()] = rawEmail.contains('@')
                  ? rawEmail.replaceFirst(RegExp(r'(^.).*(@.*$)'), r'$1***$2')
                  : '[REDACTED]';
            } else {
              redacted[entry.key.toString()] = redact(safeValue);
            }
          }

          return redacted;
        }

        if (value is List) {
          return value.map(redact).toList();
        }

        return value;
      }

      final sanitized = redact(decoded);
      return const JsonEncoder.withIndent('  ').convert(sanitized);
    } catch (_) {
      if (trimmed.length > 500) {
        return '${trimmed.substring(0, 500)}...';
      }

      return trimmed;
    }
  }

  String get _patientEmail => (widget.patientEmail ?? '').trim().toLowerCase();

  void _showPasswordChangeMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _startResendCooldown() {
    _resendCountdownTimer?.cancel();
    _resendSecondsRemaining = 60;
    if (mounted) setState(() {});
    _resendCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendSecondsRemaining--);
      if (_resendSecondsRemaining == 0) timer.cancel();
    });
  }

  Future<void> _savePassword() async {
    if (_passwordChangeLoading) return;

    if (_passwordChangeStep == _PasswordChangeStep.currentPassword) {
      await _verifyCurrentPasswordAndRequestOtp();
    } else {
      await _submitPasswordReset();
    }
  }

  Future<void> _verifyCurrentPasswordAndRequestOtp() async {
    if (_currentPasswordController.text.isEmpty) {
      _showPasswordChangeMessage('Enter your current password.');
      return;
    }
    if (widget.patientId.trim().isEmpty) {
      _showPasswordChangeMessage('Patient ID is missing. Please log in again.');
      return;
    }
    if (!_emailPattern.hasMatch(_patientEmail)) {
      _showPasswordChangeMessage(
        'Your registered email is unavailable. Please sign in again or contact support.',
      );
      return;
    }

    setState(() => _passwordChangeLoading = true);
    try {
      await _sessionService.verifyCurrentPassword(
        email: _patientEmail,
        password: _currentPasswordController.text,
      );
      await _passwordRecoveryService.requestOtp(email: _patientEmail);
      if (!mounted) return;
      setState(() {
        _passwordChangeStep = _PasswordChangeStep.otpAndNewPassword;
        _otpController.clear();
      });
      _startResendCooldown();
    } on PatientEmailVerificationRequired {
      _showPasswordChangeMessage(
        'Verify your registered email before changing your password.',
      );
    } on PatientLoginException catch (error) {
      _showPasswordChangeMessage(error.message);
    } on PasswordRecoveryException catch (error) {
      _showPasswordChangeMessage(error.message);
    } on Exception {
      _showPasswordChangeMessage(
        'Password change could not be started. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _passwordChangeLoading = false);
    }
  }

  Future<void> _resendPasswordChangeOtp() async {
    if (_passwordChangeLoading || _resendSecondsRemaining > 0) return;
    if (!_emailPattern.hasMatch(_patientEmail)) {
      _showPasswordChangeMessage(
        'Your registered email is unavailable. Please sign in again or contact support.',
      );
      return;
    }

    setState(() => _passwordChangeLoading = true);
    try {
      await _passwordRecoveryService.requestOtp(email: _patientEmail);
      if (!mounted) return;
      _otpController.clear();
      _startResendCooldown();
      _showPasswordChangeMessage('A new verification code has been requested.');
    } on PasswordRecoveryException catch (error) {
      _showPasswordChangeMessage(error.message);
    } on Exception {
      _showPasswordChangeMessage(
        'Could not request another verification code. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _passwordChangeLoading = false);
    }
  }

  String? _validateNewPassword(String password) {
    if (password.length < 8) return 'Password must be at least 8 characters.';
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
    if (password == _currentPasswordController.text) {
      return 'New password must be different from your current password.';
    }
    return null;
  }

  Future<void> _submitPasswordReset() async {
    if (_passwordChangeLoading) return;
    final otp = _otpController.text;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(otp)) {
      _showPasswordChangeMessage('Enter the complete 6-digit code.');
      return;
    }

    final newPassword = _newPasswordController.text;
    final passwordError = _validateNewPassword(newPassword);
    if (passwordError != null) {
      _showPasswordChangeMessage(passwordError);
      return;
    }
    if (_confirmPasswordController.text != newPassword) {
      _showPasswordChangeMessage('New password and confirmation do not match.');
      return;
    }

    setState(() => _passwordChangeLoading = true);
    try {
      await _passwordRecoveryService.resetPassword(
        email: _patientEmail,
        otp: otp,
        newPassword: newPassword,
      );
      if (!mounted) return;
      _resendCountdownTimer?.cancel();
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _otpController.clear();
      setState(() {
        _passwordChangeStep = _PasswordChangeStep.currentPassword;
        _resendSecondsRemaining = 0;
      });
      _showPasswordChangeMessage('Password changed successfully.');
    } on PasswordRecoveryException catch (error) {
      _showPasswordChangeMessage(error.message);
    } on Exception {
      _showPasswordChangeMessage(
        'Could not change your password. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _passwordChangeLoading = false);
    }
  }

  void _openTermsAndConditions() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TermsAndConditionsScreen()));
  }

  void _openSupportService() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SupportServiceScreen(sessionService: widget.sessionService),
      ),
    );
  }

  @override
  void dispose() {
    _resendCountdownTimer?.cancel();
    if (_ownsPasswordRecoveryService) _passwordRecoveryService.close();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          backgroundColor: const Color(0xFF0F76FF),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF0F76FF),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // =========================================================
            // ACCOUNT PREFERENCES
            // =========================================================
            const Text(
              'Account Preferences',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              elevation: 3,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Notifications'),
                    subtitle: const Text(
                      'Receive alerts for appointment reminders and updates.',
                    ),
                    value: _notificationsOn,
                    activeThumbColor: const Color(0xFF0F76FF),
                    onChanged: _updateNotification,
                  ),

                  const Divider(height: 1),

                  SwitchListTile(
                    title: const Text('Email Updates'),
                    subtitle: const Text(
                      'Receive promo, new lenses, glasses, and update emails.',
                    ),
                    value: _emailUpdatesOn,
                    activeThumbColor: const Color(0xFF0F76FF),
                    onChanged: _updateEmailUpdates,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // =========================================================
            // CHANGE PASSWORD
            // =========================================================
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Change Password',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      _passwordChangeStep == _PasswordChangeStep.currentPassword
                          ? 'Verify your current password to request a code sent to your registered email.'
                          : 'Enter the six-digit code sent to your registered email and choose a new password.',
                      style: TextStyle(color: Colors.black54),
                    ),

                    const SizedBox(height: 14),

                    if (_passwordChangeStep ==
                        _PasswordChangeStep.currentPassword) ...[
                      TextField(
                        key: const ValueKey('currentPasswordField'),
                        controller: _currentPasswordController,
                        obscureText: !_currentPasswordVisible,
                        enabled: !_passwordChangeLoading,
                        decoration: InputDecoration(
                          labelText: 'Current password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            key: const ValueKey('currentPasswordToggle'),
                            icon: Icon(
                              _currentPasswordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: const Color(0xFF0F76FF),
                            ),
                            onPressed: _passwordChangeLoading
                                ? null
                                : () => setState(
                                    () => _currentPasswordVisible =
                                        !_currentPasswordVisible,
                                  ),
                          ),
                        ),
                      ),
                    ] else ...[
                      TextField(
                        key: const ValueKey('passwordChangeOtpField'),
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        enabled: !_passwordChangeLoading,
                        decoration: const InputDecoration(
                          labelText: 'Six-digit verification code',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('newPasswordField'),
                        controller: _newPasswordController,
                        obscureText: !_newPasswordVisible,
                        enabled: !_passwordChangeLoading,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            key: const ValueKey('newPasswordToggle'),
                            icon: Icon(
                              _newPasswordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: const Color(0xFF0F76FF),
                            ),
                            onPressed: _passwordChangeLoading
                                ? null
                                : () => setState(
                                    () => _newPasswordVisible =
                                        !_newPasswordVisible,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('confirmPasswordField'),
                        controller: _confirmPasswordController,
                        obscureText: !_confirmPasswordVisible,
                        enabled: !_passwordChangeLoading,
                        decoration: InputDecoration(
                          labelText: 'Confirm new password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            key: const ValueKey('confirmPasswordToggle'),
                            icon: Icon(
                              _confirmPasswordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: const Color(0xFF0F76FF),
                            ),
                            onPressed: _passwordChangeLoading
                                ? null
                                : () => setState(
                                    () => _confirmPasswordVisible =
                                        !_confirmPasswordVisible,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const ValueKey('passwordChangeResend'),
                          onPressed:
                              !_passwordChangeLoading &&
                                  _resendSecondsRemaining == 0
                              ? _resendPasswordChangeOtp
                              : null,
                          child: Text(
                            _resendSecondsRemaining > 0
                                ? 'Resend code in ${_resendSecondsRemaining}s'
                                : 'Resend code',
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        key: const ValueKey('continuePasswordButton'),
                        onPressed: _passwordChangeLoading
                            ? null
                            : _savePassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F76FF),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade400,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _passwordChangeLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _passwordChangeStep ==
                                        _PasswordChangeStep.currentPassword
                                    ? 'Continue'
                                    : 'Change Password',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            // =========================================================
            // LEGAL
            // =========================================================
            const Text(
              'Legal',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 16),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              elevation: 3,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F76FF).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: Color(0xFF0F76FF),
                  ),
                ),
                title: const Text(
                  'Terms & Conditions',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('View the clinic terms and conditions'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: _openTermsAndConditions,
              ),
            ),

            const SizedBox(height: 16),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              elevation: 3,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F76FF).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.support_agent_outlined,
                    color: Color(0xFF0F76FF),
                  ),
                ),
                title: const Text(
                  'Support Service',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'View support tickets and contact support',
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: _openSupportService,
              ),
            ),

            const SizedBox(height: 24),

            // =========================================================
            // DEVICE PREFERENCES NOTICE
            // =========================================================
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.all(16),
              child: const Text(
                'Preferences are saved automatically and will be kept on this device.',
                style: TextStyle(color: Colors.black87),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
