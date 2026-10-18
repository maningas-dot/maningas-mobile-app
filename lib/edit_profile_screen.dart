import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ph_address_finder/ph_address_finder.dart';

import 'constants.dart';
import 'philippine_address_helper.dart';
import 'zip_code_lookup.dart';

const Map<String, String> _jsonHeaders = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
};

const Color _saveButtonBlue = Color(0xFF0F76FF);

String _addressCharacterKind(int? rune) {
  if (rune == null) return 'end';
  final character = String.fromCharCode(rune);
  if (character.trim().isEmpty) return 'whitespace';
  if (!RegExp(r'^[A-Za-z0-9]$').hasMatch(character)) {
    return 'punctuation-or-symbol';
  }
  return 'letter-or-digit';
}

String _addressDifferenceDiagnostic(String submitted, String returned) {
  final submittedRunes = submitted.runes.toList();
  final returnedRunes = returned.runes.toList();
  final commonLength = submittedRunes.length < returnedRunes.length
      ? submittedRunes.length
      : returnedRunes.length;
  var index = 0;
  while (index < commonLength &&
      submittedRunes[index] == returnedRunes[index]) {
    index++;
  }
  if (index == commonLength && submittedRunes.length == returnedRunes.length) {
    return 'firstDiffIndex=none';
  }
  final submittedRune = index < submittedRunes.length
      ? submittedRunes[index]
      : null;
  final returnedRune = index < returnedRunes.length
      ? returnedRunes[index]
      : null;
  return 'firstDiffIndex=$index, '
      'submittedCharKind=${_addressCharacterKind(submittedRune)}, '
      'returnedCharKind=${_addressCharacterKind(returnedRune)}';
}

String _addressMismatchClassification(String submitted, String returned) {
  String normalizeFormatting(String value) => value
      .replaceAll(RegExp(r'[,.;:]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  return normalizeFormatting(submitted) == normalizeFormatting(returned)
      ? 'formatting_only_candidate'
      : 'content_mismatch';
}

class _AddressChoice {
  final String key;
  final String name;
  final List<Map<String, dynamic>> records;

  const _AddressChoice({
    required this.key,
    required this.name,
    required this.records,
  });

  Map<String, dynamic> get record => records.first;
}

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;

  const EditProfileScreen({super.key, required this.profile});

  static String buildStructuredAddressForSave({
    String? unit,
    required String streetAddress,
    String? zipCode,
    String? province,
    String? city,
    String? barangay,
  }) {
    return buildStructuredAddress(
      unit: unit,
      streetAddress: streetAddress,
      zipCode: zipCode,
      province: province,
      city: city,
      barangay: barangay,
    );
  }

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _contactController;
  late final TextEditingController _unitController;
  late final TextEditingController _addressController;
  late final TextEditingController _ageController;
  late final TextEditingController _zipCodeController;
  late final TextEditingController _provinceController;
  late final TextEditingController _cityController;
  late final TextEditingController _barangayController;

  String _gender = 'Male';
  String _zipCode = '';
  String _province = '';
  String _city = '';
  String _barangay = '';
  String _originalAddress = '';
  String? _selectedProvinceKey;
  String? _selectedCityKey;
  String? _selectedBarangayKey;
  List<_AddressChoice> _provinceChoices = [];
  List<_AddressChoice> _cityChoices = [];
  List<_AddressChoice> _barangayChoices = [];
  bool _addressOptionsLoading = true;
  bool _addressChanged = false;
  bool _zipManuallyEdited = false;
  String? _zipLookupMessage;
  String? _addressOptionsError;
  int _cityLoadGeneration = 0;
  int _barangayLoadGeneration = 0;
  int _zipLookupGeneration = 0;
  DateTime? _dob;
  bool _loading = false;

  bool get _hasCompleteStructuredAddress => [
    _unitController.text.trim(),
    _addressController.text.trim(),
    _barangay.trim(),
    _city.trim(),
    _province.trim(),
    _zipCode.trim(),
  ].every((value) => value.isNotEmpty);

  @override
  void initState() {
    super.initState();

    final p = widget.profile;
    _originalAddress = (p['address'] ?? '').toString();
    String structuredValue(String key) {
      final value = p[key];
      return value is String ? value.trim() : '';
    }

    _firstNameController = TextEditingController(text: p['first_name'] ?? '');
    _middleNameController = TextEditingController(text: p['middle_name'] ?? '');
    _lastNameController = TextEditingController(text: p['last_name'] ?? '');
    _emailController = TextEditingController(text: p['email'] ?? '');
    _contactController = TextEditingController(text: p['contact_number'] ?? '');
    _unitController = TextEditingController(
      text: structuredValue('address_unit'),
    );
    _addressController = TextEditingController(
      text: structuredValue('address_street'),
    );
    _zipCode = structuredValue('address_zip_code');
    _zipCodeController = TextEditingController(text: _zipCode);
    _province = structuredValue('address_province');
    _city = structuredValue('address_city_municipality');
    _barangay = structuredValue('address_barangay');
    _provinceController = TextEditingController(text: _province);
    _cityController = TextEditingController(text: _city);
    _barangayController = TextEditingController(text: _barangay);
    _ageController = TextEditingController(text: p['age']?.toString() ?? '');
    _gender = (p['gender'] as String?) ?? 'Male';

    final rawDob = p['date_of_birth'] as String?;
    if (rawDob != null && rawDob.isNotEmpty) {
      _dob = DateTime.tryParse(rawDob);
    }

    _syncAgeFromDob();
    _initializeAddressChoices();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _unitController.dispose();
    _addressController.dispose();
    _ageController.dispose();
    _zipCodeController.dispose();
    _provinceController.dispose();
    _cityController.dispose();
    _barangayController.dispose();
    super.dispose();
  }

  Future<void> _initializeAddressChoices() async {
    try {
      await AddressData.loadData();
      final rawProvinces = (AddressData.provinces ?? const [])
          .whereType<Map>()
          .map((record) => Map<String, dynamic>.from(record))
          .toList();
      final selectableProvinces = _safeProvinceChoices(
        rawProvinces.where(_isActive).toList(),
      );
      final provinceMatches = selectableProvinces
          .where((choice) => _same(choice.name, _province))
          .toList();

      if (!mounted) return;
      setState(() {
        _provinceChoices = selectableProvinces;
        if (provinceMatches.length == 1) {
          _selectedProvinceKey = provinceMatches.single.key;
        }
      });

      final selectedProvince = _choiceByKey(
        _provinceChoices,
        _selectedProvinceKey,
      );
      if (selectedProvince != null) {
        await _loadCityChoices(selectedProvince, restoreSavedValues: true);
      }

      if (mounted) {
        setState(() => _addressOptionsLoading = false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _addressOptionsError = error.toString();
        _addressOptionsLoading = false;
      });
    }
  }

  Future<void> _loadCityChoices(
    _AddressChoice province, {
    bool restoreSavedValues = false,
  }) async {
    final generation = ++_cityLoadGeneration;
    try {
      await AddressData.loadData();
      final records = (AddressData.municipalities ?? const [])
          .whereType<Map>()
          .map((record) => Map<String, dynamic>.from(record))
          .where((record) => _municipalityMatchesProvince(record, province))
          .toList();
      final choices = _choicesFromRecords(
        records.where(_isActive).toList(),
        idFields: const [
          'RegionNo',
          'MunicipalityID',
          'provinceCode',
          'municipalityCode',
          'municipalityName',
        ],
        nameField: 'municipalityName',
      );

      if (!mounted ||
          generation != _cityLoadGeneration ||
          province.key != _selectedProvinceKey) {
        return;
      }

      final cityMatches = restoreSavedValues
          ? records
                .where((record) => _same(record['municipalityName'], _city))
                .toList()
          : const <Map<String, dynamic>>[];
      setState(() {
        _cityChoices = choices;
        _selectedCityKey = null;
        _barangayChoices = [];
        _selectedBarangayKey = null;
        if (cityMatches.length == 1 && _isActive(cityMatches.single)) {
          _selectedCityKey = _choiceFromRecord(
            cityMatches.single,
            idFields: const [
              'RegionNo',
              'MunicipalityID',
              'provinceCode',
              'municipalityCode',
              'municipalityName',
            ],
            nameField: 'municipalityName',
          ).key;
        }
      });

      if (restoreSavedValues && _selectedCityKey != null) {
        final selectedCity = _choiceByKey(_cityChoices, _selectedCityKey);
        if (selectedCity != null) {
          await _loadBarangayChoices(
            province,
            selectedCity,
            restoreSavedValues: true,
          );
        }
      }
    } catch (error) {
      if (!mounted ||
          generation != _cityLoadGeneration ||
          province.key != _selectedProvinceKey) {
        return;
      }
      setState(() {
        _cityChoices = [];
        _selectedCityKey = null;
        _addressOptionsError = error.toString();
      });
    }
  }

  Future<void> _loadBarangayChoices(
    _AddressChoice province,
    _AddressChoice city, {
    bool restoreSavedValues = false,
  }) async {
    final generation = ++_barangayLoadGeneration;
    try {
      await AddressData.loadBarangayShard(
        _recordValue(province.record, 'provinceCode'),
      );
      final records =
          AddressData.barangayShardRecords(
            _recordValue(province.record, 'provinceCode'),
          ).where((record) {
            return _barangayMatchesContext(record, province, city);
          }).toList();
      final choices = _choicesFromRecords(
        records.where(_isActive).toList(),
        idFields: const [
          'RegionNo',
          'barangayID',
          'provinceCode',
          'municipalityCode',
          'barangayCode',
          'barangayName',
        ],
        nameField: 'barangayName',
      );

      if (!mounted ||
          generation != _barangayLoadGeneration ||
          province.key != _selectedProvinceKey ||
          city.key != _selectedCityKey) {
        return;
      }

      final barangayMatches = restoreSavedValues
          ? records
                .where((record) => _same(record['barangayName'], _barangay))
                .toList()
          : const <Map<String, dynamic>>[];
      setState(() {
        _barangayChoices = choices;
        _selectedBarangayKey = null;
        if (barangayMatches.length == 1 && _isActive(barangayMatches.single)) {
          _selectedBarangayKey = _choiceFromRecord(
            barangayMatches.single,
            idFields: const [
              'RegionNo',
              'barangayID',
              'provinceCode',
              'municipalityCode',
              'barangayCode',
              'barangayName',
            ],
            nameField: 'barangayName',
          ).key;
        }
      });
    } catch (error) {
      if (!mounted ||
          generation != _barangayLoadGeneration ||
          province.key != _selectedProvinceKey ||
          city.key != _selectedCityKey) {
        return;
      }
      setState(() {
        _barangayChoices = [];
        _selectedBarangayKey = null;
        _addressOptionsError = error.toString();
      });
    }
  }

  Future<void> _selectProvince(String? key) async {
    final choice = _choiceByKey(_provinceChoices, key);
    if (choice == null || choice.key == _selectedProvinceKey) return;
    final sameSavedLabel = _same(_province, choice.name);

    setState(() {
      _addressChanged = _addressChanged || !sameSavedLabel;
      _selectedProvinceKey = choice.key;
      _province = _recordValue(choice.record, 'provinceName');
      _provinceController.text = _province;
      if (!sameSavedLabel) {
        _city = '';
        _barangay = '';
        _cityController.clear();
        _barangayController.clear();
      }
      _selectedCityKey = null;
      _selectedBarangayKey = null;
      _cityChoices = [];
      _barangayChoices = [];
      _addressOptionsError = null;
      _zipLookupMessage = null;
      _zipLookupGeneration++;
    });

    await _loadCityChoices(choice, restoreSavedValues: sameSavedLabel);
  }

  Future<void> _selectCity(String? key) async {
    final province = _choiceByKey(_provinceChoices, _selectedProvinceKey);
    final choice = _choiceByKey(_cityChoices, key);
    if (province == null || choice == null || choice.key == _selectedCityKey) {
      return;
    }
    final sameSavedLabel = _same(_city, choice.name);

    setState(() {
      _addressChanged = _addressChanged || !sameSavedLabel;
      _selectedCityKey = choice.key;
      _city = _recordValue(choice.record, 'municipalityName');
      _cityController.text = _city;
      if (!sameSavedLabel) {
        _barangay = '';
        _barangayController.clear();
      }
      _selectedBarangayKey = null;
      _barangayChoices = [];
      _addressOptionsError = null;
      _zipLookupMessage = null;
      _zipLookupGeneration++;
    });

    await _loadBarangayChoices(
      province,
      choice,
      restoreSavedValues: sameSavedLabel,
    );
  }

  void _selectBarangay(String? key) {
    final choice = _choiceByKey(_barangayChoices, key);
    if (choice == null || choice.key == _selectedBarangayKey) return;
    setState(() {
      _addressChanged = true;
      _selectedBarangayKey = choice.key;
      _barangay = _recordValue(choice.record, 'barangayName');
      _barangayController.text = _barangay;
      _zipLookupMessage = 'Checking ZIP Code for this location…';
    });
    _resolveZipForCurrentSelection();
  }

  Future<void> _resolveZipForCurrentSelection() async {
    final province = _province;
    final city = _city;
    final barangay = _barangay;
    final provinceKey = _selectedProvinceKey;
    final cityKey = _selectedCityKey;
    final barangayKey = _selectedBarangayKey;
    final generation = ++_zipLookupGeneration;

    String? verifiedZip;
    try {
      verifiedZip = await PhilippineZipCodeLookup.resolvePostalCode(
        province: province,
        municipality: city,
        barangay: barangay,
      );
    } catch (_) {
      if (!mounted ||
          generation != _zipLookupGeneration ||
          provinceKey != _selectedProvinceKey ||
          cityKey != _selectedCityKey ||
          barangayKey != _selectedBarangayKey) {
        return;
      }
      setState(() {
        _zipLookupMessage =
            'Could not check the ZIP Code. Please confirm or enter it manually.';
      });
      return;
    }

    if (!mounted ||
        generation != _zipLookupGeneration ||
        provinceKey != _selectedProvinceKey ||
        cityKey != _selectedCityKey ||
        barangayKey != _selectedBarangayKey) {
      return;
    }

    final resolvedZip = verifiedZip;
    if (resolvedZip == null) {
      setState(() {
        _zipLookupMessage =
            "We couldn't find a unique ZIP Code for this location. Please verify your location or enter your ZIP Code manually.";
      });
      return;
    }

    if (_zipManuallyEdited) {
      setState(() {
        _zipLookupMessage =
            'A ZIP Code was found for this location, but your manually entered ZIP Code was kept.';
      });
      return;
    }

    setState(() {
      _zipCode = resolvedZip;
      _zipCodeController.text = resolvedZip;
      _addressChanged = true;
      _zipLookupMessage = null;
    });
  }

  bool _municipalityMatchesProvince(
    Map<String, dynamic> record,
    _AddressChoice province,
  ) {
    final parent = province.record;
    return _same(record['RegionNo'], parent['RegionNo']) &&
        _same(record['provinceCode'], parent['provinceCode']) &&
        _same(record['provinceName'], parent['provinceName']) &&
        _same(record['regionCode'], parent['regionCode']) &&
        _recordValue(record, 'MunicipalityID').isNotEmpty &&
        _recordValue(record, 'municipalityCode').isNotEmpty &&
        _recordValue(record, 'municipalityName').isNotEmpty;
  }

  bool _barangayMatchesContext(
    Map<String, dynamic> record,
    _AddressChoice province,
    _AddressChoice city,
  ) {
    final provinceRecord = province.record;
    final cityRecord = city.record;
    final barangayRegionCode = _recordValue(record, 'regionCode');
    final provinceRegionCode = _recordValue(provinceRecord, 'regionCode');
    return _same(record['RegionNo'], provinceRecord['RegionNo']) &&
        _same(record['provinceCode'], provinceRecord['provinceCode']) &&
        _same(record['provinceName'], provinceRecord['provinceName']) &&
        _same(record['municipalityCode'], cityRecord['municipalityCode']) &&
        _same(record['municipalityName'], cityRecord['municipalityName']) &&
        (barangayRegionCode.isEmpty ||
            barangayRegionCode.toUpperCase() == 'NULL' ||
            _same(barangayRegionCode, provinceRegionCode)) &&
        _recordValue(record, 'barangayID').isNotEmpty &&
        _recordValue(record, 'barangayCode').isNotEmpty &&
        _recordValue(record, 'barangayName').isNotEmpty;
  }

  static bool _isActive(Map<String, dynamic> record) =>
      _recordValue(record, 'isActive') == '1';

  static bool _same(dynamic left, dynamic right) {
    final leftValue = _recordValueValue(left);
    final rightValue = _recordValueValue(right);
    return leftValue.isNotEmpty &&
        rightValue.isNotEmpty &&
        leftValue.toLowerCase() == rightValue.toLowerCase();
  }

  static String _recordValue(Map<String, dynamic> record, String field) =>
      _recordValueValue(record[field]);

  static String _recordValueValue(dynamic value) {
    final result = value?.toString().trim() ?? '';
    return result.toUpperCase() == 'NULL' ? '' : result;
  }

  static List<_AddressChoice> _choicesFromRecords(
    List<Map<String, dynamic>> records, {
    required List<String> idFields,
    required String nameField,
  }) {
    final choicesByKey = <String, _AddressChoice>{};
    for (final record in records) {
      final name = _recordValue(record, nameField);
      if (name.isEmpty) continue;
      final choice = _choiceFromRecord(
        record,
        idFields: idFields,
        nameField: nameField,
      );
      choicesByKey.putIfAbsent(choice.key, () => choice);
    }
    return choicesByKey.values.toList()
      ..sort((left, right) => left.name.compareTo(right.name));
  }

  List<_AddressChoice> _safeProvinceChoices(
    List<Map<String, dynamic>> records,
  ) {
    final municipalityCodesByContext = <String, Set<String>>{};
    for (final rawRecord in AddressData.municipalities ?? const []) {
      if (rawRecord is! Map) continue;
      final municipality = Map<String, dynamic>.from(rawRecord);
      if (!_isActive(municipality)) continue;
      final code = _recordValue(municipality, 'municipalityCode');
      if (code.isEmpty) continue;
      municipalityCodesByContext
          .putIfAbsent(_provinceContextKey(municipality), () => <String>{})
          .add(code);
    }

    final byName = <String, List<Map<String, dynamic>>>{};
    for (final record in records) {
      final name = _recordValue(record, 'provinceName');
      if (name.isEmpty) continue;
      byName.putIfAbsent(name.toLowerCase(), () => []).add(record);
    }

    final choices = <_AddressChoice>[];
    for (final sameNameRecords in byName.values) {
      final identityGroups = <String, List<Map<String, dynamic>>>{};
      for (final record in sameNameRecords) {
        final provinceCode = _recordValue(record, 'provinceCode');
        final regionCode = _recordValue(record, 'regionCode');
        final provinceId = _recordValue(record, 'ProvinceID');
        final regionNo = _recordValue(record, 'RegionNo');
        if (provinceCode.isEmpty ||
            regionCode.isEmpty ||
            provinceId.isEmpty ||
            regionNo.isEmpty) {
          identityGroups.clear();
          break;
        }
        final identityKey = jsonEncode([
          _recordValue(record, 'provinceName').toLowerCase(),
          provinceCode,
          regionCode,
        ]);
        identityGroups.putIfAbsent(identityKey, () => []).add(record);
      }

      if (identityGroups.length != 1) continue;
      final members = identityGroups.values.single;
      final childCodeSets = members
          .map(
            (province) => _activeMunicipalityCodeSet(
              province,
              municipalityCodesByContext,
            ),
          )
          .toSet();
      if (childCodeSets.length != 1 || childCodeSets.single.isEmpty) continue;

      final first = members.first;
      final key = jsonEncode([
        _recordValue(first, 'provinceName').toLowerCase(),
        _recordValue(first, 'provinceCode'),
        _recordValue(first, 'regionCode'),
        childCodeSets.single,
      ]);
      choices.add(
        _AddressChoice(
          key: key,
          name: _recordValue(first, 'provinceName'),
          records: members,
        ),
      );
    }

    return choices..sort((left, right) => left.name.compareTo(right.name));
  }

  static String _provinceContextKey(Map<String, dynamic> record) {
    return jsonEncode([
      _recordValue(record, 'RegionNo').toLowerCase(),
      _recordValue(record, 'provinceCode').toLowerCase(),
      _recordValue(record, 'regionCode').toLowerCase(),
      _recordValue(record, 'provinceName').toLowerCase(),
    ]);
  }

  static String _activeMunicipalityCodeSet(
    Map<String, dynamic> province,
    Map<String, Set<String>> municipalityCodesByContext,
  ) {
    final codes =
        municipalityCodesByContext[_provinceContextKey(province)]?.toList() ??
        <String>[];
    codes.sort();
    return jsonEncode(codes);
  }

  static _AddressChoice _choiceFromRecord(
    Map<String, dynamic> record, {
    required List<String> idFields,
    required String nameField,
  }) {
    final identity = idFields
        .map((field) => _recordValue(record, field))
        .toList();
    return _AddressChoice(
      key: jsonEncode(identity),
      name: _recordValue(record, nameField),
      records: [record],
    );
  }

  static _AddressChoice? _choiceByKey(
    List<_AddressChoice> choices,
    String? key,
  ) {
    if (key == null) return null;
    for (final choice in choices) {
      if (choice.key == key) return choice;
    }
    return null;
  }

  Widget _buildAddressChoiceField({
    required String level,
    required String label,
    required String? selectedKey,
    required List<_AddressChoice> choices,
    required TextEditingController controller,
    required ValueChanged<String?> onSelected,
    required ValueChanged<String> onManualChanged,
    required bool parentAvailable,
  }) {
    if (selectedKey != null) {
      return DropdownButtonFormField<String>(
        key: ValueKey('edit-profile-$level-dropdown'),
        initialValue: selectedKey,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: choices
            .map(
              (choice) => DropdownMenuItem<String>(
                value: choice.key,
                child: Text(
                  choice.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: _addressOptionsLoading ? null : onSelected,
      );
    }

    final savedValueIsUnmatched = controller.text.trim().isNotEmpty;
    final hint = !parentAvailable
        ? 'Choose the location above to see options. Your saved entry is kept.'
        : savedValueIsUnmatched
        ? 'We could not find a clear match. Your saved entry is kept; choose a place or edit it.'
        : level == 'province'
        ? 'If your province is not listed, enter it here.'
        : 'Choose a location or enter it manually.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: ValueKey('edit-profile-$level-manual'),
          controller: controller,
          enabled: !_addressOptionsLoading,
          decoration: InputDecoration(labelText: label, helperText: hint),
          onChanged: onManualChanged,
        ),
        if (parentAvailable && choices.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('edit-profile-$level-dropdown'),
            initialValue: null,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Choose $label'),
            items: choices
                .map(
                  (choice) => DropdownMenuItem<String>(
                    value: choice.key,
                    child: Text(
                      choice.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _addressOptionsLoading ? null : onSelected,
          ),
        ],
      ],
    );
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

    final structuredAddressFields = <String, String>{
      'address_unit': _unitController.text.trim(),
      'address_street': _addressController.text.trim(),
      'address_barangay': _barangay.trim(),
      'address_city_municipality': _city.trim(),
      'address_province': _province.trim(),
      'address_zip_code': _zipCode.trim(),
    };
    final missingRequiredAddressFields = structuredAddressFields.entries
        .where((entry) => entry.key != 'address_unit' && entry.value.isEmpty)
        .map((entry) => entry.key)
        .toList();
    final unitIsMissing = structuredAddressFields['address_unit']!.isEmpty;
    if (missingRequiredAddressFields.isNotEmpty || unitIsMissing) {
      final message = missingRequiredAddressFields.isNotEmpty
          ? 'This profile address cannot be saved safely yet because structured address details are missing. The app will not guess or send empty values. This update request also affects the address, so other profile changes cannot be saved separately.'
          : 'House / Unit is optional, but the current API contract does not confirm a safe way to represent an address with no unit. The app will not send an empty or omitted value because that could erase stored data. No profile changes were saved, and this endpoint does not provide a separate profile-only update.';
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/api/patients/${Uri.encodeComponent(patientId)}',
      );
      final fullName = '$firstName $lastName';
      final addressValue = _addressChanged
          ? EditProfileScreen.buildStructuredAddressForSave(
              unit: _unitController.text.trim(),
              streetAddress: _addressController.text.trim(),
              zipCode: _zipCode,
              province: _province,
              city: _city,
              barangay: _barangay,
            )
          : _originalAddress;

      final payload = <String, dynamic>{
        'first_name': firstName,
        'middle_name': _middleNameController.text.trim(),
        'last_name': lastName,
        'name': fullName,
        'email': _emailController.text.trim(),
        'contact_number': _contactController.text.trim(),
        'address': addressValue,
        ...structuredAddressFields,
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

      final decodedResponse = jsonDecode(response.body);
      final putSucceeded =
          response.statusCode == 200 &&
          decodedResponse is Map<String, dynamic> &&
          decodedResponse['success'] == true;
      debugPrint(
        'EDIT PROFILE UPDATE: status=${response.statusCode}, '
        'success=$putSucceeded',
      );

      if (!mounted) return;

      if (putSucceeded) {
        final profileResponse = await http
            .get(uri, headers: _jsonHeaders)
            .timeout(const Duration(seconds: 15));
        final decodedProfile = jsonDecode(profileResponse.body);
        final profileData = decodedProfile is Map<String, dynamic>
            ? decodedProfile
            : null;
        final returnedPatientId =
            profileData?['patient_id'] ?? profileData?['id'];
        final persistedAddress = profileData?['address']?.toString();
        final addressMatches = persistedAddress == addressValue;
        final patientIdMatches =
            returnedPatientId == null ||
            returnedPatientId.toString().trim() == patientId;
        final structuredAddressMatches = structuredAddressFields.map(
          (key, expectedValue) => MapEntry(
            key,
            profileData?[key]?.toString().trim() == expectedValue,
          ),
        );
        final allStructuredAddressFieldsMatch = structuredAddressMatches.values
            .every((matches) => matches);
        final addressDifferenceDetails = addressMatches
            ? ''
            : '${_addressDifferenceDiagnostic(addressValue, persistedAddress ?? '')}, ';
        final addressMismatchClassification = addressMatches
            ? 'none'
            : _addressMismatchClassification(
                addressValue,
                persistedAddress ?? '',
              );
        debugPrint(
          'EDIT PROFILE CONFIRMATION: status=${profileResponse.statusCode}, '
          'addressPresent=${persistedAddress != null}, '
          'addressLength=${persistedAddress?.length ?? 0}, '
          'submittedAddressLength=${addressValue.length}, '
          'addressMatches=$addressMatches, '
          'addressMismatchClassification=$addressMismatchClassification, '
          '$addressDifferenceDetails'
          'patientIdPresent=${returnedPatientId != null}, '
          'patientIdMatches=$patientIdMatches, '
          'topLevelKeys=${profileData?.keys.toList() ?? const []}, '
          'structuredAddressFieldLengths=${structuredAddressFields.map((key, value) => MapEntry(key, value?.toString().length ?? -1))}, '
          'structuredAddressMatches=$structuredAddressMatches',
        );
        if (!mounted) return;
        if (profileResponse.statusCode < 200 ||
            profileResponse.statusCode >= 300 ||
            profileData == null ||
            !addressMatches ||
            !allStructuredAddressFieldsMatch ||
            !patientIdMatches) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The server did not confirm the updated address. Please try again.',
              ),
            ),
          );
          return;
        }

        final verifiedProfile = profileData;
        Navigator.of(context).pop({
          ...widget.profile,
          ...verifiedProfile,
          'patient_id': returnedPatientId ?? patientId,
          'first_name': verifiedProfile['first_name'] ?? firstName,
          'middle_name':
              verifiedProfile['middle_name'] ??
              _middleNameController.text.trim(),
          'last_name': verifiedProfile['last_name'] ?? lastName,
          'name': verifiedProfile['name'] ?? fullName,
          'email': verifiedProfile['email'] ?? _emailController.text.trim(),
          'contact_number':
              verifiedProfile['contact'] ??
              verifiedProfile['contact_number'] ??
              _contactController.text.trim(),
          'contact':
              verifiedProfile['contact'] ??
              verifiedProfile['contact_number'] ??
              _contactController.text.trim(),
          'address': persistedAddress,
          'gender': verifiedProfile['gender'] ?? _gender,
          'date_of_birth':
              verifiedProfile['date_of_birth'] ??
              verifiedProfile['dob'] ??
              verifiedProfile['birth_date'] ??
              (_dob != null
                  ? '${_dob!.year.toString().padLeft(4, '0')}-'
                        '${_dob!.month.toString().padLeft(2, '0')}-'
                        '${_dob!.day.toString().padLeft(2, '0')}'
                  : widget.profile['date_of_birth']),
          'age': verifiedProfile['age'] ?? _ageController.text.trim(),
        });
        return;
      }

      final data = decodedResponse is Map<String, dynamic>
          ? decodedResponse
          : const <String, dynamic>{};

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
            if (!_hasCompleteStructuredAddress) ...[
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('edit-profile-legacy-address-warning'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _originalAddress.trim().isEmpty
                          ? 'The saved address is not available as complete structured fields.'
                          : 'Your saved address is still displayed below.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_originalAddress.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _originalAddress,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Its components are not available in the editable fields. Complete or restore them before saving profile changes; the app cannot reconstruct them automatically.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Email or contact changes cannot currently be saved separately while the structured address is incomplete.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('edit-profile-unit'),
              controller: _unitController,
              decoration: const InputDecoration(
                labelText: 'House / Unit / Lot / Block (if applicable)',
              ),
              onChanged: (_) => _addressChanged = true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Street Address'),
              keyboardType: TextInputType.streetAddress,
              onChanged: (_) => _addressChanged = true,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('edit-profile-zip'),
              controller: _zipCodeController,
              decoration: const InputDecoration(labelText: 'ZIP Code'),
              onChanged: (value) {
                if (_zipCode != value) {
                  setState(() {
                    _addressChanged = true;
                    _zipManuallyEdited = true;
                    _zipCode = value;
                    _zipLookupGeneration++;
                    _zipLookupMessage = null;
                  });
                }
              },
            ),
            if (_zipLookupMessage != null) ...[
              const SizedBox(height: 6),
              if (_zipLookupMessage!.startsWith(
                "We couldn't find a unique ZIP Code",
              ))
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.amber.shade800,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _zipLookupMessage!,
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.deepOrange.shade800,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _zipLookupMessage!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            const SizedBox(height: 12),
            _buildAddressChoiceField(
              level: 'province',
              label: 'Province *',
              selectedKey: _selectedProvinceKey,
              choices: _provinceChoices,
              controller: _provinceController,
              parentAvailable: true,
              onSelected: _selectProvince,
              onManualChanged: (value) {
                setState(() {
                  _addressChanged = true;
                  _province = value;
                  _zipLookupGeneration++;
                  _zipLookupMessage = null;
                });
              },
            ),
            const SizedBox(height: 12),
            _buildAddressChoiceField(
              level: 'city',
              label: 'City / Municipality *',
              selectedKey: _selectedCityKey,
              choices: _cityChoices,
              controller: _cityController,
              parentAvailable: _selectedProvinceKey != null,
              onSelected: _selectCity,
              onManualChanged: (value) {
                setState(() {
                  _addressChanged = true;
                  _city = value;
                  _zipLookupGeneration++;
                  _zipLookupMessage = null;
                });
              },
            ),
            const SizedBox(height: 12),
            _buildAddressChoiceField(
              level: 'barangay',
              label: 'Barangay *',
              selectedKey: _selectedBarangayKey,
              choices: _barangayChoices,
              controller: _barangayController,
              parentAvailable: _selectedCityKey != null,
              onSelected: _selectBarangay,
              onManualChanged: (value) {
                setState(() {
                  _addressChanged = true;
                  _barangay = value;
                  _zipLookupGeneration++;
                  _zipLookupMessage = null;
                });
              },
            ),
            if (_addressOptionsLoading) ...[
              const SizedBox(height: 8),
              const Text('Checking available address options…'),
            ],
            if (_addressOptionsError != null) ...[
              const SizedBox(height: 8),
              Text(
                'Address options could not be loaded: $_addressOptionsError '
                'You can still edit the address fields manually.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
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
