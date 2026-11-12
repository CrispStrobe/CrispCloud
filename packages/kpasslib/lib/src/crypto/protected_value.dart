import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'crypto_utils.dart';

/// A wrapper for protection sensitive data in memory
class ProtectedData {
  final List<int> _data;
  final List<int> _salt;

  /// Byte length without materializing an unprotected copy.
  int get length => _data.length;

  const ProtectedData._(this._data, this._salt);

  /// Constructs [ProtectedData] from [bytes] already protected with [salt].
  const ProtectedData.fromProtectedBytes({
    required List<int> bytes,
    required List<int> salt,
  }) : this._(bytes, salt);

  /// Constructs [ProtectedData] from [text], protected with random salt.
  factory ProtectedData.fromString(String text) {
    final bytes = utf8.encode(text);
    try {
      return ProtectedData.fromBytes(bytes);
    } finally {
      CryptoUtils.wipeData(bytes);
    }
  }

  /// Constructs [ProtectedData] from [bytes] protected with random salt.
  factory ProtectedData.fromBytes(List<int> bytes) {
    final salt = CryptoUtils.randomBytes(bytes.length);
    final data = CryptoUtils.transformXor(data: bytes, salt: salt);
    return ProtectedData._(data, salt);
  }

  /// The hash of the plain data.
  List<int> get hash {
    final bytes = this.bytes;
    final hash = sha256.convert(bytes).bytes;
    CryptoUtils.wipeData(bytes);
    return hash;
  }

  /// The plain data as text.
  String get text {
    final data = bytes;
    try {
      return utf8.decode(data);
    } finally {
      CryptoUtils.wipeData(data);
    }
  }

  /// Best-effort clearing; immutable strings returned earlier cannot be wiped.
  void dispose() {
    CryptoUtils.wipeData(_data);
    CryptoUtils.wipeData(_salt);
  }

  /// The plain data as bytes.
  List<int> get bytes => CryptoUtils.transformXor(
        data: _data,
        salt: _salt,
      );
}
