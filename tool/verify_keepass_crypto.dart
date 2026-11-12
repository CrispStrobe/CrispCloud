import 'dart:typed_data';

// This verifies the vendored crypto adapter against an upstream known answer.
// ignore: implementation_imports
import 'package:kpasslib/src/crypto/argon2.dart';
// ignore: implementation_imports
import 'package:kpasslib/src/crypto/dart/argon2_dart.dart';

Uint8List _fromHex(String hex) => Uint8List.fromList([
  for (var index = 0; index < hex.length; index += 2)
    int.parse(hex.substring(index, index + 2), radix: 16),
]);

/// Public test vector from KPassLib's pinned test/crypto/argon2_test.dart.
/// This must also pass after dart compile js; native int64 math is not enough.
void verifyKeePassArgon2() {
  final salt = Uint8List(32)..[0] = 42;
  final password = _fromHex(
    '5d18f8a5ae0e7ea86f0ad817f0c0d40656ef1da6367d8a88508b3c13cec0d7af',
  );
  final expected = _fromHex(
    '2aecd80625a328efb2029319b0b205ab3b7a9b60fbde1b46194e4f77933297a3',
  );
  final kdf = Argon2Dart(
    type: Argon2Type.argon2id,
    version: Argon2Version.v13,
    parallelism: 2,
    memorySizeKB: 16,
    iterations: 1,
    salt: salt,
  );
  for (var attempt = 0; attempt < 2; attempt++) {
    final actual = kdf.convert(password);
    if (actual.length != expected.length ||
        List.generate(
          actual.length,
          (i) => actual[i] != expected[i],
        ).any((v) => v)) {
      throw StateError('KeePass Argon2 known-answer check failed.');
    }
  }
}

void main() {
  verifyKeePassArgon2();
  // Standalone CLI verification output contains no database or credentials.
  // ignore: avoid_print
  print('PASS: KeePass Argon2id known-answer check');
}
