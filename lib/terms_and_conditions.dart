import 'package:flutter/material.dart';

class TermsAndConditionsScreen extends StatefulWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  State<TermsAndConditionsScreen> createState() =>
      _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState
    extends State<TermsAndConditionsScreen> {
  bool agreed = false;

  // Gonzales Vision Clinic UI colors
  static const Color primaryBlue = Color(0xFF0F76FF);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color backgroundGray = Color(0xFFF4F7FB);
  static const Color textGray = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGray,

      // --------------------------------------------------
      // TOP HEADER
      // --------------------------------------------------
      appBar: AppBar(
        backgroundColor: primaryBlue,
        elevation: 0,
        centerTitle: true,

        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: surfaceWhite,
            size: 21,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: const Text(
          'Terms & Conditions',
          style: TextStyle(
            color: surfaceWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // --------------------------------------------------
      // BODY
      // --------------------------------------------------
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  24,
                  20,
                  10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Terms and Conditions',
                      style: TextStyle(
                        color: primaryBlue,
                        fontSize: 27,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Please read these Terms and Conditions carefully '
                      'before using our services. By continuing, you agree '
                      'to be bound by these terms.',
                      style: TextStyle(
                        color: textGray,
                        fontSize: 15,
                        height: 1.55,
                      ),
                    ),

                    const SizedBox(height: 20),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: surfaceWhite,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFDDE5EE),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _termSection(
                            '1. Acceptance of Terms',
                            'By using the Gonzales Vision Clinic mobile '
                            'application, you agree to be bound by these '
                            'Terms and Conditions. If you do not agree '
                            'with any part of these terms, you must not '
                            'use our services.',
                          ),
                          _termSection(
                            '2. Services',
                            'The application provides services such as '
                            'appointment booking, viewing patient '
                            'information, checking available frames, '
                            'notifications, and other clinic-related '
                            'features.',
                          ),
                          _termSection(
                            '3. User Accounts',
                            'You are responsible for keeping your account '
                            'credentials secure. You should not share your '
                            'password with others and should immediately '
                            'notify the clinic if you suspect unauthorized '
                            'access to your account.',
                          ),
                          _termSection(
                            '4. Appointments',
                            'Appointment requests submitted through the '
                            'application are subject to confirmation by '
                            'Gonzales Vision Clinic. Appointment schedules '
                            'may be changed or cancelled when necessary.',
                          ),
                          _termSection(
                            '5. Privacy',
                            'Gonzales Vision Clinic values your privacy. '
                            'Personal information submitted through the '
                            'application should be handled according to '
                            'the clinic’s privacy practices and applicable '
                            'data protection requirements.',
                          ),
                          _termSection(
                            '6. User Responsibilities',
                            'Users agree to provide accurate information '
                            'and use the application only for legitimate '
                            'clinic-related purposes. Users must not attempt '
                            'to access or modify information belonging to '
                            'other users.',
                          ),
                          _termSection(
                            '7. Service Availability',
                            'The application may occasionally become '
                            'unavailable due to maintenance, technical '
                            'problems, network issues, or other circumstances '
                            'outside the control of the clinic.',
                          ),
                          _termSection(
                            '8. Changes to These Terms',
                            'Gonzales Vision Clinic may update these Terms '
                            'and Conditions when necessary. Updated terms '
                            'may be presented to users before continued use '
                            'of the application.',
                          ),
                          _termSection(
                            '9. Contact Us',
                            'For questions or concerns regarding these '
                            'Terms and Conditions, please contact Gonzales '
                            'Vision Clinic through its official contact '
                            'channels.',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: surfaceWhite,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        agreed = !agreed;
                      });
                    },
                    child: Row(
                      children: [
                        Checkbox(
                          value: agreed,
                          activeColor: primaryBlue,
                          onChanged: (value) {
                            setState(() {
                              agreed = value ?? false;
                            });
                          },
                        ),
                        const Expanded(
                          child: Text(
                            'I have read and agree to the Terms and Conditions.',
                            style: TextStyle(
                              color: primaryBlue,
                              fontSize: 14,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: agreed
                          ? () {
                              Navigator.pop(context, true);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        disabledBackgroundColor: const Color(0xFFBFCBD7),
                        foregroundColor: surfaceWhite,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Continue',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 10),
                          Icon(Icons.arrow_forward, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _termSection(
    String title,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: primaryBlue,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            description,
            style: const TextStyle(
              color: textGray,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
