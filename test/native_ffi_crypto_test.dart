// Per-platform native FFI crypto assertion. Runs headless in `flutter test` on
// each OS's CI runner and ASSERTS the expected system-crypto binding actually
// loads and is byte-exact + interoperable with existing pointycastle files:
//   - Windows  -> BCrypt / CNG (bcrypt.dll)   [validates the binding we can't run on the dev Mac]
//   - Linux    -> OpenSSL libcrypto
//   - macOS    -> OpenSSL must stay disabled; the app uses CryptoKit through
//                 cryptography_flutter. Loading Homebrew libcrypto causes an
//                 unrecoverable sandbox abort in App Store/TestFlight builds.
//
// Because each binding self-tests at load and returns null on failure, a broken
// binding would otherwise silently fall back — this test makes that a CI failure
// on the affected platform instead.

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/openssl_aesgcm.dart';
import 'package:crisp_cloud/services/bcrypt_aesgcm.dart';
import 'package:crisp_cloud/services/encryption_service.dart';
import 'package:filen_client/openssl_aesgcm.dart' as filen_openssl;

void main() {
  test('platform native FFI AES-GCM loads + byte-exact + pointycastle interop',
      () {
    // Pick the binding that MUST work on this OS.
    final dynamic provider;
    final String name;
    if (Platform.isWindows) {
      provider = BCryptAesGcm.tryLoad();
      name = 'BCrypt';
      expect(provider, isNotNull,
          reason: 'BCrypt FFI must load + self-test on Windows');
    } else if (Platform.isLinux) {
      provider = OpenSslAesGcm.tryLoad();
      name = 'OpenSSL';
      expect(provider, isNotNull,
          reason: 'OpenSSL libcrypto FFI must load on Linux');
    } else if (Platform.isMacOS) {
      provider = OpenSslAesGcm.tryLoad();
      expect(provider, isNull,
          reason: 'macOS must not attempt to load external libcrypto');
      expect(filen_openssl.OpenSslAesGcm.tryLoad(), isNull,
          reason: 'filen_client must not load external libcrypto on macOS');
      return;
    } else {
      provider = OpenSslAesGcm.tryLoad();
      name = 'OpenSSL';
      if (provider == null) {
        markTestSkipped('no system libcrypto here (macOS users use CryptoKit)');
        return;
      }
    }

    final key = Uint8List(32)
      ..setAll(0, List.generate(32, (i) => (i * 7 + 3) & 0xff));
    for (final n in [0, 1, 15, 16, 17, 31, 32, 4096, 4097]) {
      final d = Uint8List(n)
        ..setAll(0, List.generate(n, (i) => (i * 13 + 5) & 0xff));
      expect(provider.decrypt(key, provider.encrypt(key, d)), equals(d),
          reason: '$name $n-byte round-trip');
      // An existing pointycastle-encrypted file must decrypt under the native
      // binding, and vice versa (wire-format compatibility).
      expect(
          provider.decrypt(key, EncryptionService.encrypt(d, key)), equals(d),
          reason: '$name decrypts pointycastle file ($n B)');
      expect(
          EncryptionService.decrypt(provider.encrypt(key, d), key), equals(d),
          reason: 'pointycastle decrypts $name output ($n B)');
    }

    // GCM integrity: a flipped tag bit must be rejected.
    final ct =
        provider.encrypt(key, Uint8List.fromList(List.generate(100, (i) => i)));
    ct[ct.length - 1] ^= 0xff;
    expect(() => provider.decrypt(key, ct), throwsA(anything),
        reason: '$name must reject a tampered tag');
  });
}
