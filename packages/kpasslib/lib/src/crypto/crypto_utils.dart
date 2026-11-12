import 'dart:math';
import 'dart:typed_data';

/// Encryption utility functions
abstract final class CryptoUtils {
  static const _byteRange = 1 << 8;

  /// Best-effort clearing of a mutable buffer before releasing it.
  static void wipeData(List<int>? data) {
    if (data != null) data.fillRange(0, data.length, 0);
  }

  /// Generates random bytes with requested [length].
  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(_byteRange);
    }
    return bytes;
  }

  /// Returns result of XOR applied to [data] with [salt].
  static List<int> transformXor({
    required List<int> data,
    required List<int> salt,
  }) =>
      List.generate(data.length, (i) => data[i] ^ salt[i % salt.length]);
}
