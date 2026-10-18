import 'package:flutter_test/flutter_test.dart';
import 'package:optcare_app/address_path_validation.dart';

// These mapping fixtures are synthetic and do not assert actual Philippine
// address relationships.
void main() {
  group('Address path validation', () {
    test('verifies a path included in an explicit synthetic mapping', () {
      final selected = _path(
        regionNo: 'test-region',
        provinceId: 'test-province-id',
        provinceCode: 'test-province-code',
        provinceName: 'Test Province',
        municipalityId: 'test-municipality-id',
        municipalityCode: 'test-municipality-code',
        municipalityName: 'Test Municipality',
        barangayId: 'test-barangay-id',
        barangayCode: 'test-barangay-code',
        barangayName: 'Test Barangay',
      );

      final result = validateAddressPath(
        selected: selected,
        parentEvidence: const AddressPathParentEvidence(
          municipalityRegionNo: 'test-region',
          municipalityParentProvinceId: 'test-province-id',
          municipalityParentProvinceCode: 'test-province-code',
          municipalityParentProvinceName: ' Test   Province ',
          barangayRegionNo: 'test-region',
          barangayParentProvinceId: 'test-province-id',
          barangayParentMunicipalityId: 'test-municipality-id',
          barangayParentProvinceCode: 'test-province-code',
          barangayParentMunicipalityCode: 'test-municipality-code',
          barangayParentProvinceName: 'test province',
          barangayParentMunicipalityName: 'test municipality',
        ),
        authoritativeMappings: [selected],
      );

      expect(result.status, AddressPathValidationStatus.verified);
      expect(
        result.reason,
        AddressPathValidationReason.authoritativeMappingMatched,
      );
    });

    test('rejects the Baguio City and Benguet parent contradiction', () {
      final selected = _path(
        regionNo: '1',
        regionCode: '15',
        provinceId: '79',
        provinceCode: '8',
        provinceName: 'Baguio City',
        municipalityId: '191',
        municipalityCode: '14',
        municipalityName: 'Baguio City',
        barangayId: '2922',
        barangayCode: '1',
        barangayName: 'A. Bonifacio-Caguioa-Rimando',
      );

      final result = validateAddressPath(
        selected: selected,
        parentEvidence: const AddressPathParentEvidence(
          municipalityRegionNo: '1',
          municipalityRegionCode: '2',
          municipalityParentProvinceName: 'Benguet',
          barangayRegionNo: '1',
          barangayRegionCode: '2',
          barangayParentProvinceName: 'Benguet',
          barangayParentMunicipalityName: 'Baguio City',
        ),
        authoritativeMappings: [selected],
      );

      expect(result.status, AddressPathValidationStatus.conflicting);
      expect(
        result.reason,
        AddressPathValidationReason.municipalityProvinceNameMismatch,
      );
    });

    test('does not verify when raw parent names are missing', () {
      final selected = _path(
        regionNo: 'test-region',
        provinceId: 'province-id',
        provinceCode: 'province-code',
        provinceName: 'Test Province',
        municipalityId: 'municipality-id',
        municipalityCode: 'municipality-code',
        municipalityName: 'Test Municipality',
        barangayId: 'barangay-id',
        barangayCode: 'barangay-code',
        barangayName: 'Test Barangay',
      );

      final result = validateAddressPath(
        selected: selected,
        parentEvidence: const AddressPathParentEvidence(
          municipalityRegionNo: 'test-region',
          municipalityParentProvinceName: 'NULL',
          barangayRegionNo: 'test-region',
          barangayParentProvinceName: 'NULL',
          barangayParentMunicipalityName: 'NULL',
        ),
        authoritativeMappings: const [],
      );

      expect(result.status, AddressPathValidationStatus.insufficientEvidence);
      expect(result.reason, AddressPathValidationReason.noAuthoritativeMapping);
    });

    test('rejects a barangay supplied from a different RegionNo', () {
      final selected = _path(
        regionNo: '1',
        provinceId: 'province-id',
        provinceCode: 'province-code',
        provinceName: 'Test Province',
        municipalityId: 'municipality-id',
        municipalityCode: 'municipality-code',
        municipalityName: 'Test Municipality',
        barangayId: 'barangay-id',
        barangayCode: 'barangay-code',
        barangayName: 'Supplemental Barangay',
      );

      final result = validateAddressPath(
        selected: selected,
        parentEvidence: const AddressPathParentEvidence(
          municipalityRegionNo: '1',
          municipalityParentProvinceName: 'Test Province',
          barangayRegionNo: '2',
          barangayParentProvinceName: 'Test Province',
          barangayParentMunicipalityName: 'Test Municipality',
        ),
        authoritativeMappings: [selected],
      );

      expect(result.status, AddressPathValidationStatus.conflicting);
      expect(result.reason, AddressPathValidationReason.barangayRegionMismatch);
    });

    test('does not conflate duplicate visible labels with different IDs', () {
      final firstIdentity = _path(
        regionNo: 'test-region',
        provinceId: 'province-id-one',
        provinceCode: 'province-code-one',
        provinceName: 'Same Province Label',
        municipalityId: 'municipality-id-one',
        municipalityCode: 'municipality-code-one',
        municipalityName: 'Same Municipality Label',
        barangayId: 'barangay-id-one',
        barangayCode: 'barangay-code-one',
        barangayName: 'Same Barangay Label',
      );
      final otherIdentity = _path(
        regionNo: 'test-region',
        provinceId: 'province-id-two',
        provinceCode: 'province-code-two',
        provinceName: 'Same Province Label',
        municipalityId: 'municipality-id-two',
        municipalityCode: 'municipality-code-two',
        municipalityName: 'Same Municipality Label',
        barangayId: 'barangay-id-two',
        barangayCode: 'barangay-code-two',
        barangayName: 'Same Barangay Label',
      );

      final result = validateAddressPath(
        selected: otherIdentity,
        parentEvidence: const AddressPathParentEvidence(),
        authoritativeMappings: [firstIdentity],
      );

      expect(result.status, AddressPathValidationStatus.insufficientEvidence);
      expect(result.reason, AddressPathValidationReason.noAuthoritativeMapping);
    });

    test('returns insufficient evidence without an authoritative mapping', () {
      final selected = _path(
        regionNo: 'test-region',
        provinceId: 'province-id',
        provinceCode: 'province-code',
        provinceName: 'Test Province',
        municipalityId: 'municipality-id',
        municipalityCode: 'municipality-code',
        municipalityName: 'Test Municipality',
        barangayId: 'barangay-id',
        barangayCode: 'barangay-code',
        barangayName: 'Test Barangay',
      );

      final result = validateAddressPath(
        selected: selected,
        parentEvidence: const AddressPathParentEvidence(),
        authoritativeMappings: const [],
      );

      expect(result.status, AddressPathValidationStatus.insufficientEvidence);
      expect(result.reason, AddressPathValidationReason.noAuthoritativeMapping);
    });
  });
}

AddressPathIdentity _path({
  required String regionNo,
  String? regionCode,
  required String provinceId,
  required String provinceCode,
  required String provinceName,
  required String municipalityId,
  required String municipalityCode,
  required String municipalityName,
  required String barangayId,
  required String barangayCode,
  required String barangayName,
}) {
  return AddressPathIdentity(
    regionNo: regionNo,
    regionCode: regionCode,
    provinceId: provinceId,
    provinceCode: provinceCode,
    provinceName: provinceName,
    municipalityId: municipalityId,
    municipalityCode: municipalityCode,
    municipalityName: municipalityName,
    barangayId: barangayId,
    barangayCode: barangayCode,
    barangayName: barangayName,
  );
}
