import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_settings.dart';
import 'constants.dart';
import 'terms_and_conditions.dart';

class SettingsScreen extends StatefulWidget {
  final String patientId;

  const SettingsScreen({super.key, required this.patientId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  // =========================================================
  // REQUEST PASSWORD CHANGE OTP
  // =========================================================

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

    setState(() {
      _otpLoading = true;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/api/patients/request-password-change');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'patient_id': widget.patientId.trim(),
              'current_password': currentPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        data = {};
      }

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        setState(() {
          _otpLoading = false;
        });

        _showPasswordOtpDialog(widget.patientId.trim(), newPassword);
      } else {
        setState(() {
          _otpLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['error']?.toString() ??
                  data['message']?.toString() ??
                  'Unable to send verification code.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _otpLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to connect to the server. Please try again.'),
        ),
      );
    }
  }

  // =========================================================
  // OTP VERIFICATION DIALOG
  // =========================================================

  Future<void> _showPasswordOtpDialog(
    String patientId,
    String newPassword,
  ) async {
    _otpController.clear();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool verifying = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Verify Password Change'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A 6-digit verification code has been sent to your registered email address.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 4,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Verification Code',
                      hintText: '000000',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: verifying
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: verifying
                      ? null
                      : () async {
                          final otp = _otpController.text.trim();

                          if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Enter the 6-digit verification code.',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            verifying = true;
                          });

                          final success = await _confirmPasswordChange(
                            patientId,
                            newPassword,
                            otp,
                          );

                          if (!mounted) return;

                          if (success) {
                            Navigator.of(dialogContext).pop();
                          } else {
                            setDialogState(() {
                              verifying = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F76FF),
                    foregroundColor: Colors.white,
                  ),
                  child: verifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verify'),
                ),
              ],
            );
          },
        );
      },
    );

    if (mounted) {
      _otpController.clear();
    }
  }

  // =========================================================
  // CONFIRM PASSWORD CHANGE
  // =========================================================

  Future<bool> _confirmPasswordChange(
    String patientId,
    String newPassword,
    String otp,
  ) async {
    try {
      final uri = Uri.parse('$apiBaseUrl/api/patients/confirm-password-change');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'patient_id': patientId,
              'otp': otp,
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {
        data = {};
      }

      if (!mounted) return false;

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        _otpController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message']?.toString() ?? 'Password changed successfully.',
            ),
            backgroundColor: Colors.green,
          ),
        );

        return true;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data['error']?.toString() ??
                data['message']?.toString() ??
                'Invalid verification code.',
          ),
        ),
      );

      return false;
    } catch (_) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to connect to the server. Please try again.'),
        ),
      );

      return false;
    }
  }

  void _openTermsAndConditions() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TermsAndConditionsScreen()));
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
