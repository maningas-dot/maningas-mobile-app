import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'appointment_scheduler.dart';
import 'app_notifications.dart';
import 'app_settings.dart';
import 'constants.dart';
import 'notification_screen.dart';
import 'settings_screen.dart';
import 'edit_profile_screen.dart';
import 'try_on_webview_screen.dart';
import 'verification_screen.dart';
import 'terms_and_conditions.dart';
import 'transaction_history_screen.dart';

class Main {
  static const String baseUrl = 'https://gonzalesvisionclinic.onrender.com';
}

const Map<String, String> jsonHeaders = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
};

const Color primaryBlue = Color(0xFF0F76FF);
const Color surfaceWhite = Color(0xFFFFFFFF);
const Color backgroundGray = Color(0xFFF4F7FB);

final DateTime minAllowedBirthDate = DateTime(1926, 1, 1);
final DateTime maxAllowedBirthDate = DateTime(2016, 12, 31);

bool isValidDateOfBirth(DateTime? value) {
  if (value == null) {
    return false;
  }

  return !value.isBefore(minAllowedBirthDate) &&
      !value.isAfter(maxAllowedBirthDate);
}

String normalizeAppointmentStatus(dynamic rawStatus) {
  final value = rawStatus?.toString().trim();

  if (value == null || value.isEmpty) {
    return 'Pending';
  }

  final normalized = value.toLowerCase();

  if (normalized == 'requested' ||
      normalized == 'pending' ||
      normalized == 'new' ||
      normalized == 'submitted') {
    return 'Pending';
  }

  if (normalized == 'confirmed' ||
      normalized == 'approved' ||
      normalized == 'accepted') {
    return 'Confirmed';
  }

  if (normalized == 'cancelled' ||
      normalized == 'canceled' ||
      normalized == 'rejected' ||
      normalized == 'declined') {
    return 'Cancelled';
  }

  return value[0].toUpperCase() + value.substring(1).toLowerCase();
}

String resolveFrameImageUrl(String? rawUrl) {
  if (rawUrl == null || rawUrl.trim().isEmpty) {
    return '';
  }

  final cleaned = rawUrl.trim();

  if (cleaned.startsWith('http://') || cleaned.startsWith('https://')) {
    return cleaned;
  }

  if (cleaned.startsWith('/')) {
    return '$apiBaseUrl$cleaned';
  }

  return '$apiBaseUrl/${cleaned.replaceFirst(RegExp(r'^/+'), '')}';
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    appSettingsController.load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: appSettingsController,
      builder: (BuildContext context, settings, Widget? child) {
        final currentSettings = settings as dynamic;

        return MaterialApp(
          title: 'Gonzales Vision Clinic',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryBlue,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: backgroundGray,
            appBarTheme: const AppBarTheme(
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            cardTheme: CardThemeData(
              color: surfaceWhite,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  currentSettings.largeTextOn ? 1.3 : 1.0,
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const AuthScreen(),
        );
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  final _firstNameController = TextEditingController();

  final _middleNameController = TextEditingController();

  final _lastNameController = TextEditingController();

  final _emailController = TextEditingController();

  final _passwordController = TextEditingController();

  final _confirmPasswordController = TextEditingController();

  final _contactController = TextEditingController();

  final _addressController = TextEditingController();

  final _zipCodeController = TextEditingController();

  final _ageController = TextEditingController();

  final List<String> _provinces = [
    'Bulacan',
    'Cavite',
    'Laguna',
    'Metro Manila',
    'Quezon',
  ];

  final Map<String, List<String>> _citiesByProvince = {
    'Bulacan': [
      'San Jose Del Monte',
      'Marilao',
      'Meycauayan',
      'Norzagaray',
      'Santa Maria',
    ],
    'Cavite': ['General Trias', 'Dasmariñas', 'Imus', 'Tagaytay'],
    'Laguna': ['Santa Rosa', 'Biñan', 'San Pedro', 'Calamba'],
    'Metro Manila': ['Quezon City', 'Manila', 'Pasig', 'Makati'],
    'Quezon': ['Lucena', 'Tayabas', 'Sariaya', 'Candelaria'],
  };

  final Map<String, List<String>> _barangaysByCity = {
    'San Jose Del Monte': ['Bignay', 'Fatima', 'Gayan', 'Lourdes', 'Poblacion'],
    'Marilao': [
      'Abangan Norte',
      'Abangan Sur',
      'Ibayo',
      'Lambakin',
      'Lias',
      'Loma de Gato',
      'Nagbalon',
      'Patubig',
      'Poblacion I',
      'Poblacion II',
      'Prenza I',
      'Prenza II',
      'Santa Rosa I',
      'Santa Rosa II',
      'Saog',
      'Tabing Ilog',
    ],
    'Meycauayan': [
      'Abangan Norte',
      'Abangan Sur',
      'Ibayo',
      'Lambakin',
      'Lias',
      'Loma de Gato',
      'Nagbalon',
      'Patubig',
      'Poblacion I',
      'Poblacion II',
      'Prenza I',
      'Prenza II',
      'Santa Rosa I',
      'Santa Rosa II',
      'Saog',
      'Tabing Ilog',
    ],
    'Norzagaray': [
      'Bangkal',
      'Baraka',
      'Bigte',
      'Bitungol',
      'Friendship Village Resources',
      'Matictic',
      'Minuyan',
      'Partida',
      'Pinagtulayan',
      'Poblacion',
      'San Lorenzo',
      'San Mateo',
      'Tigbe',
    ],
    'Santa Maria': [
      'Bagbaguin',
      'Balasing',
      'Buenavista',
      'Bulac',
      'Camangyanan',
      'Catmon',
      'Cay Pombo',
      'Caysio',
      'Guyong',
      'Lalakhan',
      'Mag-asawang Sapa',
      'Mahabang Parang',
      'Manggahan',
      'Parada',
      'Poblacion',
      'Pulong Buhangin',
      'San Gabriel',
      'San Jose Patag',
      'San Vicente',
      'Santa Clara',
      'Santa Cruz',
      'Silangan',
      'Tabing Bakod',
      'Tumana',
    ],
    'General Trias': ['San Francisco', 'Pasong Kawayan', 'Panghulo', 'Viga'],
    'Dasmariñas': ['Burol', 'Salawag', 'Langkaan', 'Paliparan'],
    'Imus': ['Anabu', 'Bayan Luma', 'Poblacion', 'Toclong'],
    'Tagaytay': ['Calabuso', 'Sungay', 'Mendez Crossing', 'Patutong'],
    'Santa Rosa': ['Balibago', 'Malitlit', 'Pulong Santa Cruz', 'Tagapo'],
    'Biñan': ['San Antonio', 'Sto. Niño', 'Mabolo', 'Malaban'],
    'San Pedro': ['Landayan', 'Cuyab', 'Nueva', 'San Vicente'],
    'Calamba': ['Real', 'Turbina', 'Bagong Kalsada', 'Palo Alto'],
    'Quezon City': ['Commonwealth', 'Cubao', 'Tatalon', 'Batasan'],
    'Manila': ['Binondo', 'Intramuros', 'Sta. Cruz', 'San Nicolas'],
    'Pasig': ['San Joaquin', 'Bambang', 'Capitolyo', 'Manggahan'],
    'Makati': ['Bel-Air', 'Poblacion', 'San Lorenzo', 'Magallanes'],
    'Lucena': ['Dalahican', 'Mayao', 'Barangay 1', 'Gulang-Gulang'],
    'Tayabas': ['Bukal', 'Calao', 'Ibas', 'Poblacion'],
    'Sariaya': ['Canda', 'Concepcion', 'Mabini', 'Talaan'],
    'Candelaria': ['Masin', 'San Vicente', 'Bahay', 'Poblacion'],
  };

  final Map<String, String> _zipCodeByCity = {
    'San Jose Del Monte': '3023',
    'Marilao': '3019',
    'Meycauayan': '3020',
    'Norzagaray': '3013',
    'Santa Maria': '3022',
    'General Trias': '4107',
    'Dasmariñas': '4114',
    'Imus': '4103',
    'Tagaytay': '4120',
    'Santa Rosa': '4026',
    'Biñan': '4024',
    'San Pedro': '4023',
    'Calamba': '4027',
    'Quezon City': '1101',
    'Manila': '1000',
    'Pasig': '1600',
    'Makati': '1200',
    'Lucena': '4301',
    'Tayabas': '4327',
    'Sariaya': '4322',
    'Candelaria': '4323',
  };

  String _selectedProvince = 'Bulacan';
  String _selectedCity = 'San Jose Del Monte';
  String _selectedBarangay = 'Lourdes';

  DateTime? _selectedDateOfBirth;

  String _selectedGender = 'Male';

  bool _isLogin = true;
  bool _isLoading = false;
  bool _acceptedTerms = false;

  @override
  void initState() {
    super.initState();
    _applySelectedCityZipCode(_selectedCity);
  }

  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();

    int age = now.year - birthDate.year;

    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }

    return age;
  }

  void _applySelectedCityZipCode(String city) {
    final zipCode = _zipCodeByCity[city] ?? '';
    _zipCodeController.text = zipCode;
  }

  Future<void> _pickDateOfBirth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: maxAllowedBirthDate,
      firstDate: minAllowedBirthDate,
      lastDate: maxAllowedBirthDate,
    );

    if (picked == null) {
      return;
    }

    if (!isValidDateOfBirth(picked)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You must be between 10 and 100 years old to register.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _selectedDateOfBirth = picked;

      _ageController.text =
          '${picked.day.toString().padLeft(2, '0')}/'
          '${picked.month.toString().padLeft(2, '0')}/'
          '${picked.year}';
    });
  }

  Future<void> _openTermsAndConditions() async {
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TermsAndConditionsScreen()),
    );

    if (!mounted) return;

    if (accepted == true) {
      setState(() {
        _acceptedTerms = true;
      });
    }
  }

  Future<void> _submit() async {
    if (!_isLogin && !_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please read and accept the Terms and Conditions before registering.',
          ),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final endpoint = _isLogin
          ? '/api/patients/login'
          : '/api/patients/register';

      final uri = Uri.parse('$apiBaseUrl$endpoint');

      // =====================================================
      // LOGIN
      // =====================================================

      if (_isLogin) {
        final loginEmail = _emailController.text.trim().toLowerCase();

        final payload = {
          'email': loginEmail,
          'password': _passwordController.text,
        };

        final response = await http
            .post(uri, headers: jsonHeaders, body: jsonEncode(payload))
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

        debugPrint('LOGIN STATUS: ${response.statusCode}');

        debugPrint('LOGIN RESPONSE: ${response.body}');

        if (!mounted) return;

        // =================================================
        // EMAIL VERIFICATION REQUIRED
        // =================================================

        if (response.statusCode == 403 &&
            data['code']?.toString() == 'EMAIL_VERIFICATION_REQUIRED') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This email still needs verification. Please complete registration verification first.',
              ),
            ),
          );

          return;
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message']?.toString() ?? 'Login successful'),
            ),
          );

          // =================================================
          // BACKEND RETURNS THE PATIENT DIRECTLY
          // =================================================

          final profileData = <String, dynamic>{};

          profileData['patient_id'] =
              data['patient_id'] ?? data['user_id'] ?? data['id'] ?? '';

          profileData['email'] = data['email'] ?? '';

          profileData['email_verified'] = data['email_verified'] ?? true;

          profileData['first_name'] = '';
          profileData['last_name'] = '';

          profileData['contact_number'] =
              data['contact_number'] ?? data['contact'] ?? data['phone'] ?? '';

          profileData['address'] = data['address'] ?? '';

          profileData['gender'] = data['gender'] ?? 'Male';

          profileData['date_of_birth'] =
              data['date_of_birth'] ?? data['dob'] ?? data['birth_date'];

          profileData['age'] = data['age'];

          profileData['created_at'] =
              data['created_at'] ?? data['registered_at'] ?? '';

          // =================================================
          // SPLIT BACKEND "name"
          // INTO FIRST/LAST NAME
          // =================================================

          if (data['name'] != null) {
            final fullName = data['name'].toString().trim();

            if (fullName.isNotEmpty) {
              final parts = fullName.split(' ');

              profileData['first_name'] = parts.first;

              profileData['last_name'] = parts.length > 1
                  ? parts.sublist(1).join(' ')
                  : '';
            }
          }

          debugPrint('LOGIN PROFILE DATA: $profileData');

          // =================================================
          // OPEN DASHBOARD
          // =================================================

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardScreen(profileData: profileData),
            ),
          );
        } else {
          final msg =
              (data['message'] ?? data['error'])?.toString() ?? 'Login failed';

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
      // =====================================================
      // REGISTRATION
      // =====================================================
      else {
        final calculatedAge = _selectedDateOfBirth != null
            ? _calculateAge(_selectedDateOfBirth!)
            : 0;

        final registrationEmail = _emailController.text.trim().toLowerCase();

        final rawContact = _contactController.text.trim();

        if (!isValidPhilippineMobileNumber(rawContact)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Use +63 followed by exactly 10 digits. Example: +63 9123456789',
              ),
            ),
          );
          return;
        }

        final normalizedContact = normalizePhilippineMobileNumber(rawContact);

        final firstName = _firstNameController.text.trim();
        final middleName = _middleNameController.text.trim();
        final lastName = _lastNameController.text.trim();
        final fullNameParts = [
          firstName,
          if (middleName.isNotEmpty) middleName,
          lastName,
        ].where((part) => part.isNotEmpty).toList();

        if (_passwordController.text != _confirmPasswordController.text) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Passwords do not match.')),
          );
          return;
        }

        final structuredAddress = [
          _addressController.text.trim(),
          if (_zipCodeController.text.trim().isNotEmpty)
            'Zip Code: ${_zipCodeController.text.trim()}',
          if (_selectedProvince.isNotEmpty) 'Province: $_selectedProvince',
          if (_selectedCity.isNotEmpty) 'City/Municipality: $_selectedCity',
          if (_selectedBarangay.isNotEmpty) 'Barangay: $_selectedBarangay',
        ].where((part) => part.isNotEmpty).join(', ');

        final payload = {
          'name': fullNameParts.join(' '),

          'age': calculatedAge,

          'date_of_birth': _selectedDateOfBirth != null
              ? '${_selectedDateOfBirth!.year.toString().padLeft(4, '0')}-'
                    '${_selectedDateOfBirth!.month.toString().padLeft(2, '0')}-'
                    '${_selectedDateOfBirth!.day.toString().padLeft(2, '0')}'
              : null,

          'gender': _selectedGender,

          'contact': normalizedContact,

          'address': structuredAddress,

          'email': registrationEmail,

          'password': _passwordController.text,
        };

        debugPrint('REGISTER REQUEST: $uri');

        debugPrint('REGISTER PAYLOAD: $payload');

        final response = await http
            .post(uri, headers: jsonHeaders, body: jsonEncode(payload))
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

        debugPrint('REGISTER STATUS: ${response.statusCode}');

        debugPrint('REGISTER RESPONSE: ${response.body}');

        if (!mounted) return;

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final requiresVerification =
              data['requires_email_verification'] == true ||
              data['email_verified'] == false;

          // =================================================
          // EMAIL VERIFICATION
          // =================================================

          if (requiresVerification) {
            final verified = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => VerificationPage(
                  email: data['email']?.toString() ?? registrationEmail,
                ),
              ),
            );

            if (!mounted) return;

            // After successful verification,
            // return to Login with the registered email.
            if (verified == true) {
              _passwordController.clear();

              setState(() {
                _isLogin = true;
                _acceptedTerms = false;
                _emailController.text =
                    data['email']?.toString() ?? registrationEmail;
              });

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Email verified successfully. Your account has been created. Please sign in.',
                  ),
                ),
              );
            }

            return;
          }

          // =================================================
          // FALLBACK FOR ACCOUNTS THAT DO NOT REQUIRE
          // EMAIL VERIFICATION
          // =================================================

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                data['message']?.toString() ?? 'Registration successful',
              ),
            ),
          );

          _firstNameController.clear();
          _middleNameController.clear();
          _lastNameController.clear();
          _emailController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
          _contactController.clear();
          _addressController.clear();
          _zipCodeController.clear();
          _ageController.clear();

          setState(() {
            _selectedProvince = 'Bulacan';
            _selectedCity = 'San Jose Del Monte';
            _selectedBarangay = 'Lourdes';
            _selectedDateOfBirth = null;
            _selectedGender = 'Male';
            _acceptedTerms = false;
            _isLogin = true;
          });
        } else {
          final msg =
              (data['message'] ?? data['error'])?.toString() ??
              'Registration failed';

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } catch (e) {
      if (!mounted) return;

      debugPrint('AUTH ERROR: $e');

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Connection error: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _zipCodeController.dispose();
    _ageController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FF),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 26,
                  horizontal: 22,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F76FF), Color(0xFF003BB5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  children: const [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.visibility,
                        size: 36,
                        color: Color(0xFF0F76FF),
                      ),
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Gonzales Vision Clinic',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Eye Care and Patient Access',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F76FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        child: Text(
                          _isLogin ? 'Login' : 'Register',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!_isLogin) ...[
                        TextFormField(
                          controller: _firstNameController,
                          decoration: const InputDecoration(
                            labelText: 'First name *',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter first name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _middleNameController,
                          decoration: const InputDecoration(
                            labelText: 'Middle name (optional)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _lastNameController,
                          decoration: const InputDecoration(
                            labelText: 'Last name *',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter last name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email address *',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter email';
                          }

                          if (!value.contains('@')) {
                            return 'Enter a valid email';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_passwordVisible,
                        decoration: InputDecoration(
                          labelText: 'Password *',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _passwordVisible = !_passwordVisible;
                              });
                            },
                            icon: Icon(
                              _passwordVisible
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: const Color(0xFF0F76FF),
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter password';
                          }

                          if (!_isLogin) {
                            if (value.length < 8) {
                              return 'Password must be at least 8 characters';
                            }
                            if (!RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
                              return 'Password must include at least one special character';
                            }
                          }

                          return null;
                        },
                      ),
                      if (!_isLogin) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: !_confirmPasswordVisible,
                          decoration: InputDecoration(
                            labelText: 'Confirm password *',
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _confirmPasswordVisible =
                                      !_confirmPasswordVisible;
                                });
                              },
                              icon: Icon(
                                _confirmPasswordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: const Color(0xFF0F76FF),
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Confirm your password';
                            }
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _pickDateOfBirth,
                          child: IgnorePointer(
                            child: TextFormField(
                              controller: _ageController,
                              decoration: const InputDecoration(
                                labelText: 'Date of birth *',
                                suffixIcon: Icon(Icons.calendar_today),
                              ),
                              validator: (value) {
                                if (_selectedDateOfBirth == null) {
                                  return 'Select date of birth';
                                }
                                if (!isValidDateOfBirth(_selectedDateOfBirth)) {
                                  return 'You must be between 10 and 100 years old to register.';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedGender,
                          decoration: const InputDecoration(
                            labelText: 'Gender *',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Male',
                              child: Text('Male'),
                            ),
                            DropdownMenuItem(
                              value: 'Female',
                              child: Text('Female'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedGender = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              height: 56,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                '+63',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SizedBox(
                                height: 56,
                                child: TextFormField(
                                  controller: _contactController,
                                  decoration: const InputDecoration(
                                    labelText: 'Mobile number *',
                                    counterText: '',
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 16,
                                    ),
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  validator: (value) {
                                    final trimmed = (value ?? '').trim();

                                    if (trimmed.isEmpty) {
                                      return 'Enter contact number';
                                    }

                                    final normalized =
                                        normalizePhilippineMobileNumber(
                                          trimmed,
                                        );

                                    if (!isValidPhilippineMobileNumber(
                                      normalized,
                                    )) {
                                      return 'Use +63 followed by exactly 10 digits';
                                    }

                                    return null;
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _addressController,
                          decoration: const InputDecoration(
                            labelText: 'House no. / Street / Bldg / Landmark *',
                            hintText:
                                'Unit 205, 123 Main St., Bldg A, near market',
                            alignLabelWithHint: true,
                          ),
                          keyboardType: TextInputType.streetAddress,
                          textInputAction: TextInputAction.newline,
                          maxLines: 2,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter house no./street/building/landmark';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _zipCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Zip code *',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter zip code';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedProvince,
                          decoration: const InputDecoration(
                            labelText: 'Province *',
                          ),
                          items: _provinces
                              .map(
                                (province) => DropdownMenuItem(
                                  value: province,
                                  child: Text(province),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedProvince = value;
                              final cities =
                                  _citiesByProvince[value] ?? const [];
                              if (cities.isNotEmpty) {
                                _selectedCity = cities.first;
                                _applySelectedCityZipCode(_selectedCity);
                                final barangays =
                                    _barangaysByCity[_selectedCity] ?? const [];
                                if (barangays.isNotEmpty) {
                                  _selectedBarangay = barangays.first;
                                }
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCity,
                          decoration: const InputDecoration(
                            labelText: 'City / Municipality *',
                          ),
                          items:
                              (_citiesByProvince[_selectedProvince] ?? const [])
                                  .map(
                                    (city) => DropdownMenuItem(
                                      value: city,
                                      child: Text(city),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedCity = value;
                              _applySelectedCityZipCode(value);
                              final barangays =
                                  _barangaysByCity[value] ?? const [];
                              if (barangays.isNotEmpty) {
                                _selectedBarangay = barangays.first;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedBarangay,
                          decoration: const InputDecoration(
                            labelText: 'Barangay *',
                          ),
                          items: (_barangaysByCity[_selectedCity] ?? const [])
                              .map(
                                (barangay) => DropdownMenuItem(
                                  value: barangay,
                                  child: Text(barangay),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedBarangay = value);
                            }
                          },
                        ),
                      ],
                      if (!_isLogin) ...[
                        const SizedBox(height: 16),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _openTermsAndConditions,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: _acceptedTerms,
                                activeColor: const Color(0xFF0F76FF),
                                onChanged: (value) {
                                  if (value == true) {
                                    _openTermsAndConditions();
                                  } else {
                                    setState(() {
                                      _acceptedTerms = false;
                                    });
                                  }
                                },
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Wrap(
                                    children: [
                                      const Text(
                                        'I agree to the ',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                      GestureDetector(
                                        onTap: _openTermsAndConditions,
                                        child: const Text(
                                          'Terms and Conditions',
                                          style: TextStyle(
                                            color: Color(0xFF0F76FF),
                                            fontWeight: FontWeight.w600,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F76FF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color.fromARGB(255, 255, 255, 255),
                                ),
                              )
                            : Text(
                                _isLogin ? 'Sign In' : 'Register',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLogin = !_isLogin;
                            if (_isLogin) {
                              _acceptedTerms = false;
                            }
                          });
                        },
                        child: Text(
                          _isLogin
                              ? 'Create an account? Register'
                              : 'Already have an account? Login',
                          style: const TextStyle(
                            color: Color(0xFF0F76FF),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'Recover Password or contact support',
                  style: TextStyle(
                    color: Color(0xFF0F76FF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FrameModel {
  final int frameId;
  final String name;
  final String? brand;
  final String? material;
  final String? category;
  final String? description;
  final double price;
  final int stockQuantity;
  final String? imageUrl;

  const FrameModel({
    required this.frameId,
    required this.name,
    this.brand,
    this.material,
    this.category,
    this.description,
    required this.price,
    required this.stockQuantity,
    this.imageUrl,
  });

  factory FrameModel.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    final rawStock = json['stock_quantity'] ?? json['stock'];

    final rawName = json['name'] ?? json['frame_name'] ?? '';

    final rawImage = json['image_2d_url'] ?? json['image_url'] ?? json['image'];

    return FrameModel(
      frameId: json['frame_id'] is num
          ? (json['frame_id'] as num).toInt()
          : int.tryParse(json['frame_id']?.toString() ?? '') ?? 0,
      name: rawName.toString(),
      brand: json['brand'] == null ? null : json['brand'].toString(),
      material: json['material'] == null ? null : json['material'].toString(),
      category: json['category'] == null ? null : json['category'].toString(),
      description: json['description'] == null
          ? null
          : json['description'].toString(),
      price: rawPrice is num
          ? rawPrice.toDouble()
          : (rawPrice is String ? double.tryParse(rawPrice) ?? 0.0 : 0.0),
      stockQuantity: rawStock is num
          ? rawStock.toInt()
          : (rawStock is String ? int.tryParse(rawStock) ?? 0 : 0),
      imageUrl: rawImage == null ? null : rawImage.toString(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final Map<String, dynamic> profileData;

  const DashboardScreen({super.key, required this.profileData});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  late Map<String, dynamic> _profile;

  bool _loadingAppointments = false;
  bool _loadingFrames = false;
  bool _framesError = false;

  String? _framesErrorMessage;

  List<dynamic> _appointments = [];

  List<FrameModel> _frames = [];

  final TextEditingController _frameSearchController = TextEditingController();

  String _frameSearchQuery = '';

  String _selectedFrameCategory = 'All';

  List<FrameModel> get _filteredFrames {
    final query = _frameSearchQuery.trim().toLowerCase();

    return _frames.where((frame) {
      final name = frame.name.toLowerCase();

      final brand = (frame.brand ?? '').toLowerCase();

      final material = (frame.material ?? '').toLowerCase();

      final category = (frame.category ?? '').toLowerCase();

      final matchesSearch =
          query.isEmpty ||
          name.contains(query) ||
          brand.contains(query) ||
          material.contains(query) ||
          category.contains(query);

      final matchesCategory =
          _selectedFrameCategory == 'All' ||
          category == _selectedFrameCategory.toLowerCase();

      return matchesSearch && matchesCategory;
    }).toList();
  }

  List<String> get _frameCategories {
    final categories = <String>{};

    for (final frame in _frames) {
      final category = frame.category?.trim();

      if (category != null && category.isNotEmpty) {
        categories.add(category);
      }
    }

    final sortedCategories = categories.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ['All', ...sortedCategories];
  }

  @override
  void initState() {
    super.initState();

    _profile = widget.profileData;

    // Refresh profile from server
    // to pick up recent changes.
    _refreshProfile();

    _loadAppointments();
    _loadFrames();

    final patientId = _profile['patient_id']?.toString().trim() ?? '';

    if (patientId.isNotEmpty) {
      notificationsController.load(patientId);
    }
  }

  // =====================================================
  // TRY ON
  // =====================================================

  void _openTryOn(FrameModel frame) {
    debugPrint('OPENING TRY-ON FOR FRAME: ${frame.frameId}');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TryOnWebViewScreen(frameId: frame.frameId),
      ),
    );
  }

  // =====================================================
  // PROFILE
  // =====================================================

  Future<void> _refreshProfile() async {
    try {
      final pid = _profile['patient_id'];

      if (pid == null || pid.toString().trim().isEmpty) {
        debugPrint('PROFILE REFRESH: No patient ID available.');
        return;
      }

      // =====================================================
      // EXPRESS PROFILE ENDPOINT
      // GET /api/patients/:id
      // =====================================================

      final uri = Uri.parse(
        '$apiBaseUrl/api/patients/'
        '${Uri.encodeComponent(pid.toString())}',
      );

      debugPrint('PROFILE API REQUEST: $uri');

      final response = await http
          .get(uri, headers: jsonHeaders)
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'PROFILE API STATUS: '
        '${response.statusCode}',
      );

      debugPrint(
        'PROFILE API RESPONSE: '
        '${response.body}',
      );

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

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // =================================================
        // EXPRESS ENDPOINT RETURNS
        // THE PATIENT DIRECTLY
        // =================================================

        setState(() {
          _profile = {
            ..._profile,
            ...data,

            // Map backend field names
            // to the names already used
            // by the Flutter UI.
            'patient_id': data['patient_id'] ?? _profile['patient_id'],

            'email': data['email'] ?? _profile['email'],

            'contact_number':
                data['contact'] ??
                data['contact_number'] ??
                _profile['contact_number'],

            'middle_name': data['middle_name'] ?? _profile['middle_name'],

            'gender': data['gender'] ?? _profile['gender'],

            'age': data['age'] ?? _profile['age'],

            'date_of_birth':
                data['date_of_birth'] ??
                data['dob'] ??
                data['birth_date'] ??
                _profile['date_of_birth'],

            'created_at': data['created_at'] ?? _profile['created_at'],

            'last_visit': data['last_visit'] ?? _profile['last_visit'],
          };

          // =================================================
          // SPLIT "name" INTO FIRST/LAST NAME
          // =================================================

          if (data['name'] != null) {
            final fullName = data['name'].toString().trim();

            if (fullName.isNotEmpty) {
              final parts = fullName.split(RegExp(r'\s+'));

              _profile['first_name'] = parts.first;

              if (parts.length > 2) {
                _profile['middle_name'] = parts
                    .sublist(1, parts.length - 1)
                    .join(' ');
                _profile['last_name'] = parts.last;
              } else if (parts.length > 1) {
                _profile['middle_name'] = '';
                _profile['last_name'] = parts.sublist(1).join(' ');
              } else {
                _profile['middle_name'] = '';
                _profile['last_name'] = '';
              }
            }
          }
        });

        debugPrint('PROFILE REFRESH SUCCESS: $_profile');
      } else {
        debugPrint(
          'PROFILE REFRESH FAILED: '
          '${data['message'] ?? data['error']}',
        );
      }
    } catch (e) {
      debugPrint('Unable to refresh profile: $e');
    }
  }

  // =====================================================
  // LOAD APPOINTMENTS
  // =====================================================

  Future<void> _loadAppointments() async {
    if (!mounted) return;

    setState(() => _loadingAppointments = true);

    try {
      final patientId = _profile['patient_id']?.toString().trim();

      if (patientId == null || patientId.isEmpty) {
        debugPrint('APPOINTMENTS: No patient ID available.');

        setState(() => _appointments = []);

        return;
      }

      // =====================================================
      // EXPRESS APPOINTMENT ENDPOINT
      // GET /api/appointments/patient/:patient_id
      // =====================================================

      final uri = Uri.parse(
        '$apiBaseUrl/api/appointments/patient/'
        '${Uri.encodeComponent(patientId)}',
      );

      debugPrint('APPOINTMENTS API REQUEST: $uri');

      final response = await http
          .get(uri, headers: jsonHeaders)
          .timeout(const Duration(seconds: 15));

      debugPrint(
        'APPOINTMENTS API STATUS: '
        '${response.statusCode}',
      );

      debugPrint(
        'APPOINTMENTS API RESPONSE: '
        '${response.body}',
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);

        if (decoded is List) {
          setState(() {
            _appointments = decoded;
          });

          debugPrint(
            'APPOINTMENTS LOAD SUCCESS: '
            '${_appointments.length} appointment(s)',
          );
        } else {
          debugPrint(
            'APPOINTMENTS ERROR: '
            'Expected List but received '
            '${decoded.runtimeType}',
          );

          setState(() {
            _appointments = [];
          });
        }

        return;
      }

      // =====================================================
      // SERVER ERROR
      // =====================================================

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}

      final message =
          (data['message'] ?? data['error'])?.toString() ??
          'Failed to load appointments.';

      debugPrint('APPOINTMENTS API ERROR: $message');

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e, st) {
      debugPrint('APPOINTMENTS API EXCEPTION: $e');

      debugPrint('APPOINTMENTS API STACK: $st');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load appointments: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingAppointments = false);
      }
    }
  }

  // =====================================================
  // LOAD FRAME MODELS
  // GET /api/frames
  // =====================================================

  Future<void> _loadFrames() async {
    if (!mounted) return;

    setState(() {
      _loadingFrames = true;
      _framesError = false;
      _framesErrorMessage = null;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/api/frames');

      debugPrint('FRAME API REQUEST: $uri');

      final response = await http
          .get(uri, headers: jsonHeaders)
          .timeout(const Duration(seconds: 20));

      debugPrint(
        'FRAME API STATUS: '
        '${response.statusCode}',
      );

      debugPrint(
        'FRAME API RESPONSE: '
        '${response.body}',
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);

        if (decoded is List) {
          final frames = decoded
              .whereType<Map<String, dynamic>>()
              .map((item) => FrameModel.fromJson(item))
              .toList();

          setState(() {
            _frames = frames;
            _framesError = false;
            _framesErrorMessage = null;
          });

          debugPrint(
            'FRAME LOAD SUCCESS: '
            '${_frames.length} frame(s)',
          );
        } else {
          debugPrint(
            'FRAME API ERROR: '
            'Expected List but received '
            '${decoded.runtimeType}',
          );

          setState(() {
            _frames = [];
            _framesError = true;
            _framesErrorMessage =
                'Unexpected frame data received from the server.';
          });
        }

        return;
      }

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}

      final message =
          (data['message'] ?? data['error'])?.toString() ??
          'Failed to load frame models.';

      debugPrint('FRAME API ERROR: $message');

      setState(() {
        _framesError = true;
        _framesErrorMessage = message;
      });
    } catch (e, st) {
      debugPrint('FRAME API EXCEPTION: $e');

      debugPrint('FRAME API STACK: $st');

      if (!mounted) return;

      setState(() {
        _framesError = true;
        _framesErrorMessage = 'Unable to load frame models right now.';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingFrames = false);
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void dispose() {
    _frameSearchController.dispose();
    super.dispose();
  }

  // =====================================================
  // HOME TAB
  // =====================================================

  Widget _buildHomeTab() {
    final firstName = (_profile['first_name'] as String?)?.trim() ?? '';
    final middleName = (_profile['middle_name'] as String?)?.trim() ?? '';
    final lastName = (_profile['last_name'] as String?)?.trim() ?? '';

    var userName = [
      firstName,
      if (middleName.isNotEmpty) middleName,
      lastName,
    ].where((part) => part.isNotEmpty).join(' ').trim();

    if (userName.isEmpty) {
      userName = (_profile['email'] as String?)?.trim() ?? 'Patient';
    }

    final patientId = _profile['patient_id']?.toString().trim() ?? '';

    final emailVerified =
        _profile['email_verified'] == true ||
        _profile['email_verified']?.toString() == '1';

    String lastVisitText = 'No visit recorded';
    final rawLastVisit = _profile['last_visit'];

    if (rawLastVisit != null && rawLastVisit.toString().trim().isNotEmpty) {
      final parsed = DateTime.tryParse(rawLastVisit.toString());
      if (parsed != null) {
        lastVisitText = _formatProfileDate(parsed.toIso8601String());
      } else {
        lastVisitText = rawLastVisit.toString();
      }
    }

    String daysSinceVisit = '—';
    if (rawLastVisit != null && rawLastVisit.toString().trim().isNotEmpty) {
      final parsed = DateTime.tryParse(rawLastVisit.toString());
      if (parsed != null) {
        final days = DateTime.now().difference(parsed.toLocal()).inDays;
        daysSinceVisit = days < 0 ? '0' : days.toString();
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          // =====================================================
          // WELCOME HEADER
          // =====================================================
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F76FF), Color(0xFF0757C9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.visibility_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Welcome back,',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Your eye care dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Manage appointments, explore frames, and keep your clinic information up to date.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                if (patientId.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.badge_outlined,
                          color: Colors.white,
                          size: 17,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'Patient ID: $patientId',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // =====================================================
          // ACCOUNT STATUS
          // =====================================================
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: emailVerified
                        ? Colors.green.withValues(alpha: 0.10)
                        : Colors.orange.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    emailVerified
                        ? Icons.verified_outlined
                        : Icons.info_outline,
                    color: emailVerified ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        emailVerified
                            ? 'Email verified'
                            : 'Email verification required',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        (_profile['email'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (emailVerified)
                  const Icon(Icons.check_circle, color: Colors.green, size: 22),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Quick actions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _DashboardTile(
                label: 'Book Appointment',
                icon: Icons.calendar_month,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AppointmentSchedulerScreen(
                        patientId: _profile['patient_id'],
                        onScheduled: _loadAppointments,
                      ),
                    ),
                  );
                },
              ),
              _DashboardTile(
                label: 'Explore Frames',
                icon: Icons.grid_view_rounded,
                onTap: () => _onItemTapped(1),
              ),
              _DashboardTile(
                label: 'My Profile',
                icon: Icons.person_outline,
                onTap: () => _onItemTapped(3),
              ),
              _DashboardTile(
                label: 'My Appointments',
                icon: Icons.event_available_outlined,
                onTap: () => _onItemTapped(2),
              ),
              _DashboardTile(
                label: 'Transaction History',
                icon: Icons.receipt_long_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TransactionHistoryScreen(
                        patientId: _profile['patient_id']?.toString(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // =====================================================
          // APPOINTMENT SUMMARY
          // =====================================================
          const Text(
            'Your clinic activity',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  value: _appointments.length.toString(),
                  label: 'Booked visits',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  value: _appointments
                      .where((item) {
                        final data = item as Map<String, dynamic>;
                        final status = normalizeAppointmentStatus(
                          data['appointment_status'] ?? data['status'],
                        );
                        return status.toLowerCase() == 'confirmed';
                      })
                      .length
                      .toString(),
                  label: 'Confirmed',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  value: daysSinceVisit,
                  label: 'Days since visit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // =====================================================
          // LAST VISIT
          // =====================================================
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F76FF).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.history_outlined,
                    color: Color(0xFF0F76FF),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last clinic visit',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        lastVisitText,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // FRAME DETAILS
  // =====================================================

  void _showFrameDetails(FrameModel frame) {
    final imageUrl = resolveFrameImageUrl(frame.imageUrl);

    final inStock = frame.stockQuantity > 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            height: 220,
                            width: double.infinity,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) {
                                return child;
                              }

                              return Container(
                                height: 220,
                                color: const Color(0xFFEAF2FF),
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => Container(
                              height: 220,
                              width: double.infinity,
                              color: const Color(0xFFEAF2FF),
                              child: const Icon(
                                Icons.remove_red_eye,
                                size: 52,
                                color: Color(0xFF0F76FF),
                              ),
                            ),
                          )
                        : Container(
                            height: 220,
                            width: double.infinity,
                            color: const Color(0xFFEAF2FF),
                            child: const Icon(
                              Icons.remove_red_eye,
                              size: 52,
                              color: Color(0xFF0F76FF),
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    frame.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (frame.brand != null && frame.brand!.trim().isNotEmpty)
                    Text(
                      frame.brand!,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '₱${frame.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F76FF),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: inStock
                              ? Colors.green.withValues(alpha: 0.12)
                              : Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          inStock ? 'Available' : 'Out of stock',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: inStock ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  _InfoRow(
                    label: 'Stock quantity',
                    value: frame.stockQuantity.toString(),
                  ),
                  if (frame.material != null &&
                      frame.material!.trim().isNotEmpty)
                    _InfoRow(label: 'Material', value: frame.material!),
                  if (frame.category != null &&
                      frame.category!.trim().isNotEmpty)
                    _InfoRow(label: 'Category', value: frame.category!),
                  const SizedBox(height: 12),
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (frame.description != null &&
                            frame.description!.trim().isNotEmpty)
                        ? frame.description!
                        : 'No description available for this frame.',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();

                        _openTryOn(frame);
                      },
                      icon: const Icon(Icons.view_in_ar),
                      label: const Text('Try On'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F76FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFramesTab() {
    if (_loadingFrames && _frames.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_framesError && _frames.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                _framesErrorMessage ?? 'Unable to load frame models.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadFrames,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_frames.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFrames,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 250),
            Center(
              child: Text(
                'No frames available.',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          ],
        ),
      );
    }

    final filteredFrames = _filteredFrames;
    final categories = _frameCategories;

    return Column(
      children: [
        // =====================================================
        // SEARCH BAR
        // =====================================================

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _frameSearchController,
            onChanged: (value) {
              setState(() {
                _frameSearchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search frames, brands...',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF0F76FF)),
              suffixIcon: _frameSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _frameSearchController.clear();

                        setState(() {
                          _frameSearchQuery = '';
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF0F76FF),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),

        // =====================================================
        // CATEGORY FILTERS
        // =====================================================
        SizedBox(
          height: 48,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = categories[index];

              final isSelected = _selectedFrameCategory == category;

              return ChoiceChip(
                label: Text(category),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _selectedFrameCategory = category;
                  });
                },
                selectedColor: const Color(0xFF0F76FF),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF0F76FF)
                      : Colors.grey.shade300,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // =====================================================
        // RESULT COUNT
        // =====================================================
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                '${filteredFrames.length} '
                '${filteredFrames.length == 1 ? 'frame' : 'frames'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const Spacer(),
              if (_frameSearchQuery.isNotEmpty ||
                  _selectedFrameCategory != 'All')
                TextButton(
                  onPressed: () {
                    _frameSearchController.clear();

                    setState(() {
                      _frameSearchQuery = '';
                      _selectedFrameCategory = 'All';
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                  ),
                  child: const Text(
                    'Clear filters',
                    style: TextStyle(
                      color: Color(0xFF0F76FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // =====================================================
        // FRAME GRID
        // =====================================================
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadFrames,
            child: filteredFrames.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 100),
                      Icon(
                        Icons.search_off,
                        size: 52,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      const Center(
                        child: Text(
                          'No frames found',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Center(
                        child: Text(
                          'Try another search or category.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,

                          // FIX:
                          // Give every card enough vertical space
                          // instead of calculating height from width.
                          mainAxisExtent: 260,
                        ),
                    itemCount: filteredFrames.length,
                    itemBuilder: (context, index) {
                      final frame = filteredFrames[index];

                      final imageUrl = resolveFrameImageUrl(frame.imageUrl);

                      final inStock = frame.stockQuantity > 0;

                      return InkWell(
                        onTap: () => _showFrameDetails(frame),
                        borderRadius: BorderRadius.circular(20),
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // =================================================
                              // IMAGE
                              // =================================================

                              SizedBox(
                                height: 120,
                                width: double.infinity,
                                child: imageUrl.isNotEmpty
                                    ? Image.network(
                                        imageUrl,
                                        width: double.infinity,
                                        height: 120,
                                        fit: BoxFit.contain,
                                        loadingBuilder:
                                            (context, child, loadingProgress) {
                                              if (loadingProgress == null) {
                                                return child;
                                              }

                                              return Container(
                                                width: double.infinity,
                                                height: 120,
                                                color: const Color(0xFFEAF2FF),
                                                child: const Center(
                                                  child: SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                ),
                                              );
                                            },
                                        errorBuilder: (_, __, ___) {
                                          return Container(
                                            width: double.infinity,
                                            height: 120,
                                            color: const Color(0xFFEAF2FF),
                                            child: const Icon(
                                              Icons.remove_red_eye,
                                              size: 34,
                                              color: Color(0xFF0F76FF),
                                            ),
                                          );
                                        },
                                      )
                                    : Container(
                                        width: double.infinity,
                                        height: 120,
                                        color: const Color(0xFFEAF2FF),
                                        child: const Icon(
                                          Icons.remove_red_eye,
                                          size: 34,
                                          color: Color(0xFF0F76FF),
                                        ),
                                      ),
                              ),

                              // =================================================
                              // DETAILS
                              // =================================================
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  12,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // FRAME NAME
                                    Text(
                                      frame.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    // BRAND
                                    if (frame.brand != null &&
                                        frame.brand!.trim().isNotEmpty)
                                      Text(
                                        frame.brand!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          height: 1.1,
                                          color: Colors.black54,
                                        ),
                                      ),

                                    const SizedBox(height: 8),

                                    // PRICE + STOCK
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '₱${frame.price.toStringAsFixed(2)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0F76FF),
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 6),

                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: inStock
                                                ? Colors.green.withValues(
                                                    alpha: 0.12,
                                                  )
                                                : Colors.red.withValues(
                                                    alpha: 0.12,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            inStock ? 'Available' : 'Sold out',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: inStock
                                                  ? Colors.green
                                                  : Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  // =====================================================
  // APPOINTMENTS TAB
  // =====================================================

  Widget _buildAppointmentsTab() {
    return RefreshIndicator(
      onRefresh: _loadAppointments,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F76FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: const Icon(
                      Icons.event_available,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'My Appointments',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Review your upcoming visits and booking details.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AppointmentSchedulerScreen(
                              patientId: _profile['patient_id'],
                              onScheduled: _loadAppointments,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Schedule New Appointment'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F76FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_loadingAppointments)
            const Center(child: CircularProgressIndicator())
          else if (_appointments.isEmpty)
            Center(
              child: Text(
                'No appointments found for patient ${_profile['patient_id'] ?? 'unknown'}. Pull down to refresh.',
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._appointments.map((appointment) {
              final data = appointment as Map<String, dynamic>;

              final purposeOfVisit = (data['purpose_of_visit'] ?? '')
                  .toString();

              final provider = (data['provider'] ?? '').toString().trim();

              final appointmentType = (data['appointment_type'] ?? '')
                  .toString()
                  .trim();

              final parsedProvider = provider.isNotEmpty
                  ? provider
                  : (purposeOfVisit.contains(' - ')
                            ? purposeOfVisit.split(' - ').first
                            : purposeOfVisit)
                        .trim();

              final parsedType = appointmentType.isNotEmpty
                  ? appointmentType
                  : (purposeOfVisit.contains(' - ')
                            ? purposeOfVisit.split(' - ').last
                            : 'General')
                        .trim();

              final status = normalizeAppointmentStatus(
                data['appointment_status'] ?? data['status'],
              );

              final statusKey = status.toLowerCase();

              final statusColor = statusKey == 'confirmed'
                  ? Colors.green
                  : statusKey == 'pending'
                  ? Colors.orange
                  : statusKey == 'cancelled'
                  ? Colors.red
                  : Colors.grey;

              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${data['appointment_date']} · ${data['appointment_time']}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Color.fromRGBO(
                                (statusColor.r * 255.0).round(),
                                (statusColor.g * 255.0).round(),
                                (statusColor.b * 255.0).round(),
                                0.12,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              status.isEmpty ? 'UNKNOWN' : status.toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Provider: ${parsedProvider.isEmpty ? '-' : parsedProvider}',
                        style: const TextStyle(color: Colors.black87),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Type: ${parsedType.isEmpty ? '-' : parsedType}',
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  String _formatProfileDate(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return '-';
    }

    final rawValue = value.toString().trim();

    // Try to parse normal database date/datetime values.
    final parsed = DateTime.tryParse(rawValue);

    if (parsed != null) {
      return '${parsed.day.toString().padLeft(2, '0')}/'
          '${parsed.month.toString().padLeft(2, '0')}/'
          '${parsed.year}';
    }

    // Fallback for values that may already contain
    // something like "04/08/2004 at 00:00".
    final cleaned = rawValue.split(' at ').first.trim();

    if (cleaned.isEmpty) {
      return '-';
    }

    return cleaned;
  }

  // =====================================================
  // PROFILE TAB
  // =====================================================

  Widget _buildProfileTab() {
    final firstName = (_profile['first_name'] as String?)?.trim() ?? '';
    final middleName = (_profile['middle_name'] as String?)?.trim() ?? '';
    final lastName = (_profile['last_name'] as String?)?.trim() ?? '';
    final fullName =
        [
          firstName,
          if (middleName.isNotEmpty) middleName,
          lastName,
        ].where((part) => part.isNotEmpty).join(' ').trim().isNotEmpty
        ? [
            firstName,
            if (middleName.isNotEmpty) middleName,
            lastName,
          ].where((part) => part.isNotEmpty).join(' ').trim()
        : (_profile['name']?.toString().trim().isNotEmpty == true
              ? _profile['name'].toString().trim()
              : 'Patient');

    final initials = fullName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    final email = _profile['email']?.toString().trim() ?? '';
    final contact = (_profile['contact_number'] ?? _profile['contact'] ?? '')
        .toString()
        .trim();
    final address = (_profile['address'] ?? '').toString().trim();
    final patientId = _profile['patient_id']?.toString().trim() ?? '-';
    final gender = _profile['gender']?.toString().trim() ?? '';
    final age = _profile['age']?.toString().trim() ?? '';
    final status = _profile['status']?.toString().trim().isNotEmpty == true
        ? _profile['status'].toString().trim()
        : 'Active';

    final emailVerified =
        _profile['email_verified'] == true ||
        _profile['email_verified']?.toString() == '1';

    final dateOfBirth = _profile['date_of_birth']?.toString();
    final lastVisit = _profile['last_visit']?.toString();

    return RefreshIndicator(
      onRefresh: _refreshProfile,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          // =====================================================
          // PROFILE HEADER
          // =====================================================
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F76FF), Color(0xFF0757C9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: Colors.white,
                      child: Text(
                        initials.isEmpty ? 'P' : initials,
                        style: const TextStyle(
                          color: Color(0xFF0F76FF),
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            email.isEmpty ? 'No email address' : email,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: emailVerified
                                  ? Colors.white.withValues(alpha: 0.16)
                                  : Colors.orange.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  emailVerified
                                      ? Icons.verified_outlined
                                      : Icons.info_outline,
                                  size: 15,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  emailVerified
                                      ? 'Email verified'
                                      : 'Email not verified',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Patient ID',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        patientId,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // =====================================================
          // EDIT PROFILE
          // =====================================================
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final result = await Navigator.of(context)
                    .push<Map<String, dynamic>>(
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(profile: _profile),
                      ),
                    );

                if (result != null && mounted) {
                  setState(() {
                    _profile = {..._profile, ...result};
                  });
                  await _refreshProfile();
                }
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F76FF),
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF0F76FF)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),

          const Text(
            'Personal information',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                children: [
                  _ProfileInfoRow(
                    icon: Icons.email_outlined,
                    label: 'Email address',
                    value: email.isEmpty ? '-' : email,
                  ),
                  _ProfileInfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Contact number',
                    value: contact.isEmpty ? '-' : contact,
                  ),
                  _ProfileInfoRow(
                    icon: Icons.home_outlined,
                    label: 'Address',
                    value: address.isEmpty ? '-' : address,
                  ),
                  _ProfileInfoRow(
                    icon: Icons.cake_outlined,
                    label: 'Date of birth',
                    value: (dateOfBirth == null || dateOfBirth.trim().isEmpty)
                        ? '-'
                        : _formatProfileDate(dateOfBirth),
                  ),
                  _ProfileInfoRow(
                    icon: Icons.person_outline,
                    label: 'Gender',
                    value: gender.isEmpty ? '-' : gender,
                  ),
                  _ProfileInfoRow(
                    icon: Icons.numbers_outlined,
                    label: 'Age',
                    value: age.isEmpty ? '-' : age,
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),

          const Text(
            'Clinic information',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                children: [
                  _ProfileInfoRow(
                    icon: Icons.badge_outlined,
                    label: 'Patient ID',
                    value: patientId,
                  ),
                  _ProfileInfoRow(
                    icon: Icons.verified_user_outlined,
                    label: 'Account status',
                    value: status,
                    valueColor: status.toLowerCase() == 'active'
                        ? Colors.green
                        : Colors.orange,
                  ),
                  _ProfileInfoRow(
                    icon: Icons.history_outlined,
                    label: 'Last visit',
                    value: (lastVisit == null || lastVisit.trim().isEmpty)
                        ? 'No visit recorded'
                        : _formatProfileDate(lastVisit),
                  ),
                  _ProfileInfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Registered',
                    value: _formatProfileDate(_profile['created_at']),
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Pull down to refresh your profile information.',
              style: TextStyle(color: Colors.black45, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _buildHomeTab(),
      _buildFramesTab(),
      _buildAppointmentsTab(),
      _buildProfileTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        centerTitle: true,
        title: const Text(
          'Gonzales Vision Clinic',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0F76FF),
        actions: [
          // =====================================================
          // NOTIFICATIONS
          // =====================================================

          IconButton(
            icon: Stack(
              alignment: Alignment.topRight,
              children: [
                const Icon(Icons.notifications),
                if (notificationsController.unreadCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Notifications',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NotificationScreen(
                    patientId: _profile['patient_id']?.toString() ?? '',
                  ),
                ),
              );
            },
          ),

          // =====================================================
          // SETTINGS
          // =====================================================
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      SettingsScreen(patientId: _profile['patient_id']),
                ),
              );
            },
          ),

          // =====================================================
          // LOGOUT
          // =====================================================
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: tabs[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: const Color(0xFF0F76FF),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Frames'),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Appointments',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _DashboardTile({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF0F76FF), size: 28),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String value;
  final String label;

  const _SummaryTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F76FF),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool showDivider;

  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F76FF).withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: const Color(0xFF0F76FF), size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: valueColor ?? Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: Colors.grey.shade200),
      ],
    );
  }
}

class _ProfileDetail extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileDetail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
