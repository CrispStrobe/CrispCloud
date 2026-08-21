/// Cryptographic primitives for the Filen protocol.
///
/// Filen uses AES-256-GCM for both metadata and file chunk encryption,
/// PBKDF2-HMAC-SHA512 for key derivation (200,000 iterations for auth),
/// and HMAC-SHA256 for filename hashing.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:hex/hex.dart';
import 'package:pointycastle/export.dart' hide Digest, HMac, SHA512Digest;

import 'package:filen_client/utils.dart';
import 'package:filen_client/aes_gcm_backend.dart';

class FilenCrypto {
  final Random _random;

  /// AES-256-GCM backend for file chunks — hardware-accelerated where available
  /// (OpenSSL/BCrypt FFI, or the host app's Cryptography.instance), else
  /// pure-Dart. Replaces the ~1 MB/s pointycastle path on the chunk hot path.
  final AesGcmBackend _aesGcm;

  FilenCrypto({Random? random, AesGcmBackend? aesGcm})
      : _random = random ?? Random.secure(),
        _aesGcm = aesGcm ?? chooseAesGcmBackend();

  // --- Metadata encryption (v2 format: "002" + IV + ciphertext) ---

  Future<String> encryptMetadata002(String text, String key) async {
    final ivStr = _randomString(12);
    final dk = pbkdf2(utf8.encode(key), utf8.encode(key), 1, 32);
    final c = GCMBlockCipher(AESEngine())
      ..init(
          true,
          AEADParameters(KeyParameter(dk), 128,
              Uint8List.fromList(utf8.encode(ivStr)), Uint8List(0)));
    return '002$ivStr${base64.encode(c.process(Uint8List.fromList(utf8.encode(text))))}';
  }

  Future<String> decryptMetadata002(String m, String key) async {
    if (!m.startsWith('002')) throw Exception('Invalid version');
    final iv = m.substring(3, 15);
    final dk = pbkdf2(utf8.encode(key), utf8.encode(key), 1, 32);
    final c = GCMBlockCipher(AESEngine())
      ..init(
          false,
          AEADParameters(KeyParameter(dk), 128,
              Uint8List.fromList(utf8.encode(iv)), Uint8List(0)));
    return utf8.decode(c.process(base64.decode(m.substring(15))));
  }

  // --- File data encryption (AES-256-GCM, IV prepended) ---

  // File-chunk AES-256-GCM, [iv(12) | ciphertext | tag(16)]. Delegated to the
  // selected backend (hardware where available); the wire format is unchanged,
  // so existing Filen-encrypted chunks remain readable.
  Future<Uint8List> encryptData(Uint8List data, Uint8List key) =>
      _aesGcm.encryptData(key, data);

  Future<Uint8List> decryptData(Uint8List data, Uint8List key) =>
      _aesGcm.decryptData(key, data);

  // --- Key decoding ---

  Uint8List decodeUniversalKey(String k) {
    // A 32-character string drawn entirely from the key alphabet is a raw
    // UTF-8 key (Filen's "32-char key" convention), not base64. Anchor the
    // match to the whole string — a loose `contains` would treat almost any
    // 32-char base64 blob as a raw key.
    if (k.length == 32 && RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(k)) {
      return Uint8List.fromList(utf8.encode(k));
    }
    try {
      return base64Url.decode(base64Url.normalize(k));
    } catch (_) {}
    try {
      return base64.decode(base64.normalize(k));
    } catch (_) {}
    try {
      return Uint8List.fromList(HEX.decode(k));
    } catch (_) {}
    throw Exception('Key decode failed');
  }

  /// Try decrypting with all available master keys (newest first).
  Future<String> tryDecrypt(String s, List<String> masterKeys) async {
    for (var k in masterKeys.reversed) {
      try {
        return await decryptMetadata002(s, k);
      } catch (_) {}
    }
    throw Exception('Decrypt failed');
  }

  // --- PBKDF2 ---

  Uint8List pbkdf2(
      List<int> password, List<int> salt, int iterations, int length) {
    final mac = crypto.Hmac(crypto.sha512, password);
    final out = Uint8List(length);
    final blocks = (length / 64).ceil();
    for (var i = 1; i <= blocks; i++) {
      var u = mac.convert([
        ...salt,
        ...Uint8List(4)..buffer.asByteData().setInt32(0, i, Endian.big)
      ]).bytes;
      var t = Uint8List.fromList(u);
      for (var j = 1; j < iterations; j++) {
        u = mac.convert(u).bytes;
        for (var k = 0; k < t.length; k++) t[k] ^= u[k];
      }
      final off = (i - 1) * 64;
      out.setRange(off, off + min(64, length - off), t);
    }
    return out;
  }

  // --- Key derivation for auth ---

  Future<Map<String, String>> deriveKeys(
      String password, int version, String salt) async {
    final k = HEX
        .encode(pbkdf2(utf8.encode(password), utf8.encode(salt), 200000, 64))
        .toLowerCase();
    return (version == 2)
        ? {
            'masterKey': k.substring(0, 64),
            'password': HEX
                .encode(
                    crypto.sha512.convert(utf8.encode(k.substring(64))).bytes)
                .toLowerCase()
          }
        : {'masterKey': k, 'password': k};
  }

  // --- Filename hashing ---

  Future<String> generateHMACKey(List<String> masterKeys, String email) async {
    final mk = masterKeys.last;
    if (mk.isEmpty) throw Exception('No master keys available');
    final emailBytes = utf8.encode(email.toLowerCase());
    final mkBytes = utf8.encode(mk);
    final derived = pbkdf2(mkBytes, emailBytes, 1, 32);
    return HEX.encode(derived).toLowerCase();
  }

  Future<String> hashFileName(
      String name, List<String> masterKeys, String email) async {
    final hmacKey = await generateHMACKey(masterKeys, email);
    final hmacKeyBytes = HEX.decode(hmacKey);
    final hmac = crypto.Hmac(crypto.sha256, hmacKeyBytes);
    final digest = hmac.convert(utf8.encode(name.toLowerCase()));
    return HEX.encode(digest.bytes).toLowerCase();
  }

  // --- File hashing ---

  Future<String> hashFile(File file) async {
    final digestSink = DigestSink();
    final byteSink = crypto.sha512.startChunkedConversion(digestSink);

    final raf = await file.open();
    const chunkSize = 1048576; // 1MB chunks

    try {
      while (true) {
        final bytes = await raf.read(chunkSize);
        if (bytes.isEmpty) break;
        byteSink.add(bytes);
      }

      byteSink.close();
      return HEX.encode(digestSink.value?.bytes ?? []).toLowerCase();
    } finally {
      await raf.close();
    }
  }

  // --- Random generation ---

  Uint8List randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  String uuid() {
    final b = randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = HEX.encode(b);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  String randomString(int length) => _randomString(length);

  String _randomString(int length) => List.generate(
      length,
      (_) => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'[
          _random.nextInt(64)]).join();
}
