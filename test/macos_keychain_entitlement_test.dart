import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes errSecMissingEntitlement from flutter_secure_storage', () {
    expect(
      PlatformSecureStorage.isMissingEntitlementError(
        PlatformException(
          code: 'Unexpected security result code',
          message:
              "Code: -34018, Message: A required entitlement isn't present.",
        ),
      ),
      isTrue,
    );
  });

  test(
    'locked or denied keychains are not mistaken for a missing entitlement',
    () {
      for (final code in ['-25308', '-128', '-25293', '-25300']) {
        expect(
          PlatformSecureStorage.isMissingEntitlementError(
            PlatformException(
              code: 'Unexpected security result code',
              message: 'Code: $code',
            ),
          ),
          isFalse,
          reason: code,
        );
      }
    },
  );

  test('defaults to the data-protection keychain until detection runs', () {
    expect(PlatformSecureStorage.usesMacOsDataProtection, isTrue);
  });
}
