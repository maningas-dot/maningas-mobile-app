import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';

class VerificationPage extends StatefulWidget {
  final String? email;
  final Future<bool> Function(String otp, String email)? onVerifyOtp;
  final Future<bool> Function(String email)? onResendOtp;
  final String titleText;
  final String helperText;
  final String actionText;
  final bool allowCancel;

  const VerificationPage({
    super.key,
    this.email,
    this.onVerifyOtp,
    this.onResendOtp,
    this.titleText = 'Verify Email',
    this.helperText = 'We sent a 6-digit verification code to:',
    this.actionText = 'Verify Email',
    this.allowCancel = true,
  });

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final _formKey = GlobalKey<FormState>();

  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  String? _errorMessage;

  @override
  void dispose() {
    for (final controller in _otpControllers) {
      controller.dispose();
    }

    for (final node in _otpFocusNodes) {
      node.dispose();
    }

    super.dispose();
  }

  String get _otp =>
      _otpControllers.map((controller) => controller.text.trim()).join();

  void _clearOtp() {
    for (final controller in _otpControllers) {
      controller.clear();
    }

    if (mounted) {
      _otpFocusNodes.first.requestFocus();
    }
  }

  void _handleOtpChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');

      for (int i = 0; i < 6; i++) {
        _otpControllers[i].text = i < digits.length ? digits[i] : '';
      }

      final focusIndex = digits.length.clamp(0, 5);
      _otpFocusNodes[focusIndex].requestFocus();

      if (digits.length == 6) {
        _verifyOtp();
      }

      return;
    }

    if (value.isNotEmpty && index < 5) {
      _otpFocusNodes[index + 1].requestFocus();
    }

    if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
  }

  Future<void> _verifyOtp() async {
    if (_isLoading) return;

    final otp = _otp;

    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      setState(() {
        _errorMessage = 'Please enter the complete 6-digit code.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.onVerifyOtp != null) {
        final email = (widget.email ?? '').trim().toLowerCase();
        final success = await widget.onVerifyOtp!(otp, email);

        if (!mounted) return;

        if (success) {
          Navigator.of(context).pop(true);
          return;
        }

        setState(() {
          _errorMessage =
              'Verification failed. Please check the code and try again.';
        });

        _clearOtp();
        return;
      }

      final uri = Uri.parse('$apiBaseUrl/api/patients/verify-email');
      final email = (widget.email ?? '').trim().toLowerCase();

      final response = await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': email, 'otp': otp}),
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

      debugPrint('VERIFY EMAIL STATUS: ${response.statusCode}');
      debugPrint('VERIFY EMAIL RESPONSE: ${response.body}');

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        await _showSuccessDialog(
          data['message']?.toString() ??
              'Email verified successfully. Your account has been created. Please sign in.',
        );

        if (!mounted) return;

        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _errorMessage =
            (data['error'] ?? data['message'])?.toString() ??
            'Verification failed. Please check the code and try again.';
      });

      _clearOtp();
    } catch (e) {
      if (!mounted) return;

      debugPrint('VERIFY EMAIL ERROR: $e');

      setState(() {
        _errorMessage =
            'Unable to verify the code. Please check your connection and try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_isResending || _isLoading) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      if (widget.onResendOtp != null) {
        final email = (widget.email ?? '').trim().toLowerCase();
        final success = await widget.onResendOtp!(email);

        if (!mounted) return;

        if (success) {
          _clearOtp();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A new verification code has been sent.'),
            ),
          );
        } else {
          setState(() {
            _errorMessage = 'Unable to resend the verification code.';
          });
        }
        return;
      }

      final uri = Uri.parse('$apiBaseUrl/api/patients/resend-verification');
      final email = (widget.email ?? '').trim().toLowerCase();

      final response = await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': email}),
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

      debugPrint('RESEND VERIFICATION STATUS: ${response.statusCode}');
      debugPrint('RESEND VERIFICATION RESPONSE: ${response.body}');

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          data['success'] == true) {
        _clearOtp();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message']?.toString() ??
                  'A new verification code has been sent to your email.',
            ),
          ),
        );
      } else {
        setState(() {
          _errorMessage =
              (data['error'] ?? data['message'])?.toString() ??
              'Unable to resend the verification code.';
        });
      }
    } catch (e) {
      if (!mounted) return;

      debugPrint('RESEND VERIFICATION ERROR: $e');

      setState(() {
        _errorMessage =
            'Unable to resend the code. Please check your connection and try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  Future<void> _showSuccessDialog(String message) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF22A06B), size: 30),
              SizedBox(width: 10),
              Expanded(child: Text('Account created')),
            ],
          ),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continue to sign in'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 46,
      height: 58,
      child: TextFormField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: index == 5
            ? TextInputAction.done
            : TextInputAction.next,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0F76FF), width: 2),
          ),
        ),
        onChanged: (value) => _handleOtpChanged(index, value),
        onFieldSubmitted: (_) {
          if (index == 5) {
            _verifyOtp();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('Verify Email'),
        backgroundColor: const Color(0xFF0F76FF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Card(
                  elevation: 4,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3FF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.mark_email_read_outlined,
                            color: Color(0xFF0F76FF),
                            size: 38,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.titleText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.helperText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if ((widget.email ?? '').trim().isNotEmpty)
                          Text(
                            widget.email!.trim(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          const Text(
                            'your registered email address',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 26),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(6, _buildOtpBox),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'The verification code expires in 5 minutes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0F0),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFC62828)),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _verifyOtp,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0F76FF),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 21,
                                    height: 21,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    widget.actionText,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextButton(
                          onPressed: (_isResending || _isLoading)
                              ? null
                              : _resendOtp,
                          child: _isResending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Resend verification code'),
                        ),
                        const SizedBox(height: 4),
                        if (widget.allowCancel)
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                      ],
                    ),
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
