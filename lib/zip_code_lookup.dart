import 'dart:convert';

import 'package:flutter/services.dart';

/// Verified offline ZIP dataset provenance:
/// - Source: https://github.com/0xC0000094/unified-zip-code
/// - Data file: data/unified-zip-codes.csv
/// - License: MIT
/// - Coverage: barangay-level mapping across the Philippines with province,
///   municipality, barangay, PSGC, unified code, and postal fields.
/// - Granularity: exact barangay / municipality / province lookup, suitable for
///   verified ZIP auto-fill when an exact match is present.
class PhilippineZipCodeLookup {
  static final Map<String, String> _cache = {};

  static const Map<String, String> _locationAliases = {
    'nueva vizcaya|sta. fe|poblacion': 'nueva vizcaya|santa fe|poblacion',
    'nueva vizcaya|vilaverde|poblacion': 'nueva vizcaya|villaverde|poblacion',
    'nueva vizcaya|alfonso castaã±eda|abuyo':
        'nueva vizcaya|alfonso castaneda|abuyo',
    'nueva vizcaya|bagabag|quirino (pob.)': 'nueva vizcaya|bagabag|quirino',
    'nueva vizcaya|solano|osme¥a': 'nueva vizcaya|solano|osmena',
    'nueva vizcaya|solano|osmeña': 'nueva vizcaya|solano|osmena',
    'nueva vizcaya|vilaverde|negbitin': 'nueva vizcaya|villaverde|nagbitin',
    'cagayan|sta. ana|batu-parada': 'cagayan|santa ana|batu-parada',
    'abra|bangued|cosili east (proper)': 'abra|bangued|cosili east',
  };

  static String _normalizeName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static Future<Map<String, String>> _loadLookup() async {
    if (_cache.isNotEmpty) {
      return _cache;
    }

    final jsonString = await rootBundle.loadString(
      'assets/philippine_zip_codes.json',
    );
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;

    for (final entry in decoded.entries) {
      _cache[entry.key] = entry.value.toString();
    }

    return _cache;
  }

  static Future<String?> resolvePostalCode({
    required String province,
    required String municipality,
    required String barangay,
  }) async {
    final normalizedProvince = _normalizeName(province);
    final normalizedMunicipality = _normalizeName(municipality);
    final normalizedBarangay = _normalizeName(barangay);

    if (normalizedProvince.isEmpty ||
        normalizedMunicipality.isEmpty ||
        normalizedBarangay.isEmpty) {
      return null;
    }

    final lookup = await _loadLookup();
    var key = [
      normalizedProvince,
      normalizedMunicipality,
      normalizedBarangay,
    ].join('|');

    if (const {'bulacan', 'davao occidental'}.contains(normalizedProvince) &&
        const {'sta maria', 'sta. maria'}.contains(normalizedMunicipality)) {
      key = '$normalizedProvince|santa maria|$normalizedBarangay';
    } else {
      key = _locationAliases[key] ?? key;
    }

    final postalCode = lookup[key];
    if (postalCode == null || postalCode.trim().isEmpty) {
      return null;
    }

    final normalizedPostalCode = postalCode.trim();
    return RegExp(r'^\d{4}$').hasMatch(normalizedPostalCode)
        ? normalizedPostalCode
        : null;
  }

  static String preserveManualZipEntry({
    required String currentZip,
    required String? verifiedZip,
  }) {
    final trimmedCurrentZip = currentZip.trim();

    if (trimmedCurrentZip.isEmpty) {
      return verifiedZip ?? '';
    }

    return trimmedCurrentZip;
  }
}
