import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';

const Map<String, String> _jsonHeaders = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
};

const Color _saveButtonBlue = Color(0xFF0F76FF);

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _contactController;
  late final TextEditingController _addressController;
  late final TextEditingController _ageController;

  String _gender = 'Male';
  DateTime? _dob;
  bool _loading = false;

  @override
  void initState() {
    super.initState();

    final p = widget.profile;
    _firstNameController = TextEditingController(text: p['first_name'] ?? '');
    _middleNameController = TextEditingController(text: p['middle_name'] ?? '');
    _lastNameController = TextEditingController(text: p['last_name'] ?? '');
    _emailController = TextEditingController(text: p['email'] ?? '');
    _contactController = TextEditingController(text: p['contact_number'] ?? '');
    _addressController = TextEditingController(text: p['address'] ?? '');
    _ageController = TextEditingController(text: p['age']?.toString() ?? '');
    _gender = (p['gender'] as String?) ?? 'Male';

    final rawDob = p['date_of_birth'] as String?;
    if (rawDob != null && rawDob.isNotEmpty) {
      _dob = DateTime.tryParse(rawDob);
    }

    _syncAgeFromDob();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _syncAgeFromDob() {
    if (_dob == null) {
      _ageController.text = '';
      return;
    }

    final now = DateTime.now();
    var age = now.year - _dob!.year;

    if (now.month < _dob!.month ||
        (now.month == _dob!.month && now.day < _dob!.day)) {
      age--;
    }

    _ageController.text = age.toString();
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1926, 1, 1),
      lastDate: DateTime(2016, 12, 31),
    );

    if (picked != null) {
      setState(() {
        _dob = picked;
        _syncAgeFromDob();
      });
    }
  }

  Future<void> _save() async {
    if (_loading) {
      return;
    }

    final patientId = widget.profile['patient_id']?.toString().trim();
    if (patientId == null || patientId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Patient ID is missing.')));
      return;
    }

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    if (firstName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('First name cannot be empty.')),
      );
      return;
    }

    if (lastName.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Last name cannot be empty.')),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/api/patients/$patientId');
      final fullName = '$firstName $lastName';

      final payload = <String, dynamic>{
        'first_name': firstName,
        'middle_name': _middleNameController.text.trim(),
        'last_name': lastName,
        'name': fullName,
        'email': _emailController.text.trim(),
        'contact_number': _contactController.text.trim(),
        'address': _addressController.text.trim(),
        'gender': _gender,
        if (_dob != null)
          'date_of_birth':
              '${_dob!.year.toString().padLeft(4, '0')}-'
              '${_dob!.month.toString().padLeft(2, '0')}-'
              '${_dob!.day.toString().padLeft(2, '0')}',
      };

      final response = await http
          .put(uri, headers: _jsonHeaders, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && data['success'] == true) {
        Navigator.of(context).pop({
          'first_name': firstName,
          'middle_name': _middleNameController.text.trim(),
          'last_name': lastName,
          'name': fullName,
          'email': _emailController.text.trim(),
          'contact_number': _contactController.text.trim(),
          'contact': _contactController.text.trim(),
          'address': _addressController.text.trim(),
          'gender': _gender,
          'date_of_birth': _dob != null
              ? '${_dob!.year.toString().padLeft(4, '0')}-'
                    '${_dob!.month.toString().padLeft(2, '0')}-'
                    '${_dob!.day.toString().padLeft(2, '0')}'
              : widget.profile['date_of_birth'],
          'age': _ageController.text.trim(),
        });
        return;
      }

      final msg =
          (data['message'] ?? data['error'])?.toString() ??
          'Failed to update profile';

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _firstNameController,
              decoration: const InputDecoration(labelText: 'First name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _middleNameController,
              decoration: const InputDecoration(labelText: 'Middle name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastNameController,
              decoration: const InputDecoration(labelText: 'Last name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactController,
              decoration: const InputDecoration(labelText: 'Contact number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Address'),
              keyboardType: TextInputType.streetAddress,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _gender,
                    decoration: const InputDecoration(labelText: 'Gender'),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _gender = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _pickDob,
                    child: IgnorePointer(
                      child: TextField(
                        controller: _ageController,
                        decoration: InputDecoration(
                          labelText: 'Date of birth',
                          hintText: _dob != null
                              ? '${_dob!.day}/${_dob!.month}/${_dob!.year}'
                              : 'Select',
                          suffixIcon: const Icon(Icons.calendar_today),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _saveButtonBlue,
                foregroundColor: Colors.white,
              ),
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
