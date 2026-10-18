Map<String, String> parseStructuredAddress(String? rawAddress) {
  final result = {
    'streetAddress': '',
    'zipCode': '',
    'province': '',
    'city': '',
    'barangay': '',
  };

  final address = (rawAddress ?? '').trim();
  if (address.isEmpty) {
    return result;
  }

  final parts = address.split(RegExp(r',\s*'));
  final collectedStreetParts = <String>[];

  for (final part in parts) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) {
      continue;
    }

    final normalized = trimmed.toLowerCase();

    if (normalized.startsWith('zip code:')) {
      result['zipCode'] = trimmed.substring('Zip Code:'.length).trim();
      continue;
    }

    if (normalized.startsWith('province:')) {
      result['province'] = trimmed.substring('Province:'.length).trim();
      continue;
    }

    if (normalized.startsWith('city/municipality:')) {
      result['city'] = trimmed.substring('City/Municipality:'.length).trim();
      continue;
    }

    if (normalized.startsWith('barangay:')) {
      result['barangay'] = trimmed.substring('Barangay:'.length).trim();
      continue;
    }

    collectedStreetParts.add(trimmed);
  }

  result['streetAddress'] = collectedStreetParts.join(', ');
  return result;
}

String buildStructuredAddress({
  String? unit,
  required String streetAddress,
  String? zipCode,
  String? province,
  String? city,
  String? barangay,
}) {
  final cleanedUnit = (unit ?? '').trim();
  final cleanedStreetAddress = streetAddress.trim();

  final parts = <String>[];
  if (cleanedUnit.isNotEmpty) {
    parts.add(cleanedUnit);
  }
  if (cleanedStreetAddress.isNotEmpty) {
    parts.add(cleanedStreetAddress);
  }

  if ((zipCode ?? '').trim().isNotEmpty) {
    parts.add('Zip Code: ${zipCode!.trim()}');
  }

  if ((province ?? '').trim().isNotEmpty) {
    parts.add('Province: ${province!.trim()}');
  }

  if ((city ?? '').trim().isNotEmpty) {
    parts.add('City/Municipality: ${city!.trim()}');
  }

  if ((barangay ?? '').trim().isNotEmpty) {
    parts.add('Barangay: ${barangay!.trim()}');
  }

  return parts.join(', ');
}

List<Map<String, dynamic>> deduplicateAddressOptions(
  List<Map<String, dynamic>> items, {
  required String codeKey,
  required String nameKey,
}) {
  final deduplicated = <String, Map<String, dynamic>>{};

  for (final item in items) {
    final code = item[codeKey]?.toString().trim();
    final name = item[nameKey]?.toString().trim() ?? '';
    final normalizedCode = code != null && code.isNotEmpty
        ? code.toLowerCase()
        : '';
    final normalizedName = name.toLowerCase();
    final uniqueKey = (normalizedCode.isNotEmpty)
        ? 'code:$normalizedCode'
        : (normalizedName.isNotEmpty
              ? 'name:$normalizedName'
              : 'index:${deduplicated.length}');

    deduplicated.putIfAbsent(uniqueKey, () => item);
  }

  return deduplicated.values.toList();
}

String? resolveSelectedDropdownValue({
  required String? currentValue,
  required List<Map<String, dynamic>> items,
  required String codeKey,
  required String nameKey,
}) {
  final normalizedCurrentValue = (currentValue ?? '').trim();
  if (normalizedCurrentValue.isEmpty) {
    return null;
  }

  final normalizedLookup = normalizedCurrentValue.toLowerCase();

  for (final item in items) {
    final code = item[codeKey]?.toString().trim();
    final name = item[nameKey]?.toString().trim();

    if (code == normalizedCurrentValue) {
      return code;
    }

    if (code != null && code.toLowerCase() == normalizedLookup) {
      return code;
    }

    if (name != null && name.toLowerCase() == normalizedLookup) {
      return code ?? name;
    }
  }

  return null;
}
