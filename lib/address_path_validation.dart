enum AddressPathValidationStatus { verified, conflicting, insufficientEvidence }

enum AddressPathValidationReason {
  authoritativeMappingMatched,
  noAuthoritativeMapping,
  incompleteSelectedIdentity,
  identityDoesNotMatchMapping,
  municipalityRegionMismatch,
  municipalityProvinceIdMismatch,
  municipalityProvinceCodeMismatch,
  municipalityProvinceNameMismatch,
  municipalityRegionCodeMismatch,
  barangayRegionMismatch,
  barangayParentProvinceIdMismatch,
  barangayParentMunicipalityIdMismatch,
  barangayProvinceCodeMismatch,
  barangayMunicipalityCodeMismatch,
  barangayProvinceNameMismatch,
  barangayMunicipalityNameMismatch,
  barangayRegionCodeMismatch,
}

class AddressPathValidationResult {
  const AddressPathValidationResult({
    required this.status,
    required this.reason,
  });

  final AddressPathValidationStatus status;
  final AddressPathValidationReason reason;
}

class AddressPathIdentity {
  const AddressPathIdentity({
    required this.regionNo,
    required this.regionCode,
    required this.provinceId,
    required this.provinceCode,
    required this.provinceName,
    required this.municipalityId,
    required this.municipalityCode,
    required this.municipalityName,
    required this.barangayId,
    required this.barangayCode,
    required this.barangayName,
  });

  final String regionNo;
  final String? regionCode;
  final String provinceId;
  final String provinceCode;
  final String provinceName;
  final String municipalityId;
  final String municipalityCode;
  final String municipalityName;
  final String barangayId;
  final String barangayCode;
  final String barangayName;
}

class AddressPathParentEvidence {
  const AddressPathParentEvidence({
    this.municipalityRegionNo,
    this.municipalityRegionCode,
    this.municipalityParentProvinceId,
    this.municipalityParentProvinceCode,
    this.municipalityParentProvinceName,
    this.barangayRegionNo,
    this.barangayRegionCode,
    this.barangayParentProvinceId,
    this.barangayParentMunicipalityId,
    this.barangayParentProvinceCode,
    this.barangayParentMunicipalityCode,
    this.barangayParentProvinceName,
    this.barangayParentMunicipalityName,
  });

  final String? municipalityRegionNo;
  final String? municipalityRegionCode;
  final String? municipalityParentProvinceId;
  final String? municipalityParentProvinceCode;
  final String? municipalityParentProvinceName;
  final String? barangayRegionNo;
  final String? barangayRegionCode;
  final String? barangayParentProvinceId;
  final String? barangayParentMunicipalityId;
  final String? barangayParentProvinceCode;
  final String? barangayParentMunicipalityCode;
  final String? barangayParentProvinceName;
  final String? barangayParentMunicipalityName;
}

AddressPathValidationResult validateAddressPath({
  required AddressPathIdentity selected,
  required AddressPathParentEvidence parentEvidence,
  required Iterable<AddressPathIdentity> authoritativeMappings,
}) {
  final conflict = _findParentConflict(selected, parentEvidence);
  if (conflict != null) {
    return AddressPathValidationResult(
      status: AddressPathValidationStatus.conflicting,
      reason: conflict,
    );
  }

  if (!_hasStableIdentifiers(selected)) {
    return const AddressPathValidationResult(
      status: AddressPathValidationStatus.insufficientEvidence,
      reason: AddressPathValidationReason.incompleteSelectedIdentity,
    );
  }

  final mappings = authoritativeMappings.toList(growable: false);
  final hasExactMapping = mappings.any(
    (mapping) => _sameIdentity(selected, mapping),
  );
  if (hasExactMapping) {
    return const AddressPathValidationResult(
      status: AddressPathValidationStatus.verified,
      reason: AddressPathValidationReason.authoritativeMappingMatched,
    );
  }

  final hasSameIdentifiers = mappings.any(
    (mapping) => _sameIdentifiers(selected, mapping),
  );
  return AddressPathValidationResult(
    status: AddressPathValidationStatus.insufficientEvidence,
    reason: hasSameIdentifiers
        ? AddressPathValidationReason.identityDoesNotMatchMapping
        : AddressPathValidationReason.noAuthoritativeMapping,
  );
}

bool _hasStableIdentifiers(AddressPathIdentity identity) {
  return [
    identity.regionNo,
    identity.provinceId,
    identity.provinceCode,
    identity.municipalityId,
    identity.municipalityCode,
    identity.barangayId,
    identity.barangayCode,
  ].every((value) => _normalize(value) != null);
}

AddressPathValidationReason? _findParentConflict(
  AddressPathIdentity selected,
  AddressPathParentEvidence evidence,
) {
  final municipalityRegionNo = _normalize(evidence.municipalityRegionNo);
  if (municipalityRegionNo != null &&
      municipalityRegionNo != _normalize(selected.regionNo)) {
    return AddressPathValidationReason.municipalityRegionMismatch;
  }

  final municipalityProvinceId = _normalize(
    evidence.municipalityParentProvinceId,
  );
  if (municipalityProvinceId != null &&
      municipalityProvinceId != _normalize(selected.provinceId)) {
    return AddressPathValidationReason.municipalityProvinceIdMismatch;
  }

  final municipalityProvinceCode = _normalize(
    evidence.municipalityParentProvinceCode,
  );
  if (municipalityProvinceCode != null &&
      municipalityProvinceCode != _normalize(selected.provinceCode)) {
    return AddressPathValidationReason.municipalityProvinceCodeMismatch;
  }

  final municipalityProvinceName = _normalize(
    evidence.municipalityParentProvinceName,
  );
  if (municipalityProvinceName != null &&
      municipalityProvinceName != _normalize(selected.provinceName)) {
    return AddressPathValidationReason.municipalityProvinceNameMismatch;
  }

  final municipalityRegionCode = _normalize(evidence.municipalityRegionCode);
  final selectedRegionCode = _normalize(selected.regionCode);
  if (municipalityRegionCode != null &&
      selectedRegionCode != null &&
      municipalityRegionCode != selectedRegionCode) {
    return AddressPathValidationReason.municipalityRegionCodeMismatch;
  }

  final barangayRegionNo = _normalize(evidence.barangayRegionNo);
  if (barangayRegionNo != null &&
      barangayRegionNo != _normalize(selected.regionNo)) {
    return AddressPathValidationReason.barangayRegionMismatch;
  }

  final barangayProvinceId = _normalize(evidence.barangayParentProvinceId);
  if (barangayProvinceId != null &&
      barangayProvinceId != _normalize(selected.provinceId)) {
    return AddressPathValidationReason.barangayParentProvinceIdMismatch;
  }

  final barangayMunicipalityId = _normalize(
    evidence.barangayParentMunicipalityId,
  );
  if (barangayMunicipalityId != null &&
      barangayMunicipalityId != _normalize(selected.municipalityId)) {
    return AddressPathValidationReason.barangayParentMunicipalityIdMismatch;
  }

  final barangayProvinceCode = _normalize(evidence.barangayParentProvinceCode);
  if (barangayProvinceCode != null &&
      barangayProvinceCode != _normalize(selected.provinceCode)) {
    return AddressPathValidationReason.barangayProvinceCodeMismatch;
  }

  final barangayMunicipalityCode = _normalize(
    evidence.barangayParentMunicipalityCode,
  );
  if (barangayMunicipalityCode != null &&
      barangayMunicipalityCode != _normalize(selected.municipalityCode)) {
    return AddressPathValidationReason.barangayMunicipalityCodeMismatch;
  }

  final barangayProvinceName = _normalize(evidence.barangayParentProvinceName);
  if (barangayProvinceName != null &&
      barangayProvinceName != _normalize(selected.provinceName)) {
    return AddressPathValidationReason.barangayProvinceNameMismatch;
  }

  final barangayMunicipalityName = _normalize(
    evidence.barangayParentMunicipalityName,
  );
  if (barangayMunicipalityName != null &&
      barangayMunicipalityName != _normalize(selected.municipalityName)) {
    return AddressPathValidationReason.barangayMunicipalityNameMismatch;
  }

  final barangayRegionCode = _normalize(evidence.barangayRegionCode);
  if (barangayRegionCode != null &&
      selectedRegionCode != null &&
      barangayRegionCode != selectedRegionCode) {
    return AddressPathValidationReason.barangayRegionCodeMismatch;
  }

  return null;
}

bool _sameIdentity(AddressPathIdentity left, AddressPathIdentity right) {
  return _sameIdentifiers(left, right) &&
      _normalize(left.regionCode) == _normalize(right.regionCode) &&
      _normalize(left.provinceName) == _normalize(right.provinceName) &&
      _normalize(left.municipalityName) == _normalize(right.municipalityName) &&
      _normalize(left.barangayName) == _normalize(right.barangayName);
}

bool _sameIdentifiers(AddressPathIdentity left, AddressPathIdentity right) {
  return _normalize(left.regionNo) == _normalize(right.regionNo) &&
      _normalize(left.provinceId) == _normalize(right.provinceId) &&
      _normalize(left.provinceCode) == _normalize(right.provinceCode) &&
      _normalize(left.municipalityId) == _normalize(right.municipalityId) &&
      _normalize(left.municipalityCode) == _normalize(right.municipalityCode) &&
      _normalize(left.barangayId) == _normalize(right.barangayId) &&
      _normalize(left.barangayCode) == _normalize(right.barangayCode);
}

String? _normalize(String? value) {
  final normalized = value
      ?.trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();
  return normalized == null || normalized.isEmpty || normalized == 'null'
      ? null
      : normalized;
}
