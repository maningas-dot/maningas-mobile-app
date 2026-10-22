import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_settings.dart';
import 'constants.dart';
import 'support_service_preview.dart' show SupportServiceScreen;
import 'terms_and_conditions.dart';
import 'verification_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String patientId;

  const SettingsScreen({super.key, required this.patientId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _passwordChangeUnavailableMessage =
      'Change Password is temporarily unavailable because the backend does not currently support patient password-change OTP verification. Please contact support or wait for backend support.';

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
  bool _otpLoading = false;

  @override
  void initState() {
    super.initState();
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

  Future<bool> _requestPasswordChangeOtp(
    String patientId,
    String currentPassword,
  ) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Change Password is temporarily unavailable because the backend does not currently support patient password-change OTP verification.',
          ),
        ),
      );
    }

    return false;
  }

  Future<void> _openPasswordVerificationFlow(
    String patientId,
    String newPassword,
  ) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Change Password is temporarily unavailable because the backend does not currently support patient password-change OTP verification.',
          ),
        ),
      );
    }
  }

  Future<void> _savePassword() async {
    final currentPassword = _currentPasswordController.text.trim();

    final newPassword = _newPasswordController.text;

    final confirmPassword = _confirmPasswordController.text;

    if (currentPassword.isEmpty ||
        newPassword.isEmpty ||
        confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all password fields.')),
      );
      return;
    }

    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password must be at least 6 characters.'),
        ),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password and confirmation do not match.'),
        ),
      );
      return;
    }

    if (currentPassword == newPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'New password must be different from your current password.',
          ),
        ),
      );
      return;
    }

    if (widget.patientId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Patient ID is missing. Please log in again.'),
        ),
      );
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Change Password is temporarily unavailable because the backend does not currently support patient password-change OTP verification. Please contact support or wait for backend support.',
          ),
        ),
      );
    }

    return;
  }

  void _openTermsAndConditions() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TermsAndConditionsScreen()));
  }

  void _openSupportService() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SupportServiceScreen()));
  }

  @override
  void dispose() {
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

                    const Text(
                      'A verification code will be sent to your registered email before your password is changed.',
                      style: TextStyle(color: Colors.black54),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      key: const ValueKey('currentPasswordField'),
                      controller: _currentPasswordController,
                      obscureText: !_currentPasswordVisible,
                      enabled: !_otpLoading,
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
                          onPressed: _otpLoading
                              ? null
                              : () {
                                  setState(() {
                                    _currentPasswordVisible =
                                        !_currentPasswordVisible;
                                  });
                                },
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      key: const ValueKey('newPasswordField'),
                      controller: _newPasswordController,
                      obscureText: !_newPasswordVisible,
                      enabled: !_otpLoading,
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
                          onPressed: _otpLoading
                              ? null
                              : () {
                                  setState(() {
                                    _newPasswordVisible = !_newPasswordVisible;
                                  });
                                },
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      key: const ValueKey('confirmPasswordField'),
                      controller: _confirmPasswordController,
                      obscureText: !_confirmPasswordVisible,
                      enabled: !_otpLoading,
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
                          onPressed: _otpLoading
                              ? null
                              : () {
                                  setState(() {
                                    _confirmPasswordVisible =
                                        !_confirmPasswordVisible;
                                  });
                                },
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        key: const ValueKey('continuePasswordButton'),
                        onPressed: _otpLoading ? null : _savePassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F76FF),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade400,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _otpLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Continue'),
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
                subtitle: const Text('View support tickets (preview only)'),
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
