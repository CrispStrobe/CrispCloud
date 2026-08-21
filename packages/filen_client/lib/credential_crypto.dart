/// Credential-at-rest encryption for the file-backed CLI.
///
/// Wraps the credentials JSON in an AES-256-GCM envelope keyed by a wrapping
/// secret (env-supplied or a static obfuscation constant). This is *not* part
/// of the Filen wire protocol — it only protects the local credentials file, so
/// the format is our own and self-describing:
///
///   hex( salt(16) | iv(12) | ciphertext | tag(16) )
///
/// The 32-byte AES key is PBKDF2-HMAC-SHA256(secret, salt, 100k). Kept on
/// pointycastle (tiny one-shot payload, no hot path) so it has no FFI/async
/// dependency and works identically everywhere.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:hex/hex.dart';
import 'package:pointycastle/export.dart'
    show GCMBlockCipher, AESEngine, AEADParameters, KeyParameter;

const int _saltLen = 16;
const int _ivLen = 12;
const int _pbkdf2Iterations = 100000;

/// Encrypts [text] under [secret], returning a hex envelope.
String encryptTextWithKey(String text, String secret) {
  final rnd = Random.secure();
  final salt =
      Uint8List.fromList(List.generate(_saltLen, (_) => rnd.nextInt(256)));
  final iv = Uint8List.fromList(List.generate(_ivLen, (_) => rnd.nextInt(256)));
  final key = _deriveKey(secret, salt);

  final gcm = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  final body = gcm.process(Uint8List.fromList(utf8.encode(text))); // ct | tag

  final blob = Uint8List(_saltLen + _ivLen + body.length)
    ..setAll(0, salt)
    ..setAll(_saltLen, iv)
    ..setAll(_saltLen + _ivLen, body);
  return HEX.encode(blob);
}

/// Decrypts a hex envelope produced by [encryptTextWithKey]. Throws on a wrong
/// key or tampered ciphertext (GCM auth failure).
String decryptTextWithKey(String hexEnvelope, String secret) {
  final blob = Uint8List.fromList(HEX.decode(hexEnvelope));
  if (blob.length < _saltLen + _ivLen + 16) {
    throw const FormatException('Credential envelope too short');
  }
  final salt = blob.sublist(0, _saltLen);
  final iv = blob.sublist(_saltLen, _saltLen + _ivLen);
  final body = blob.sublist(_saltLen + _ivLen);
  final key = _deriveKey(secret, salt);

  final gcm = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  return utf8.decode(gcm.process(body));
}

/// PBKDF2-HMAC-SHA256 → 32 bytes (one block; dkLen == hLen, so block index 1).
Uint8List _deriveKey(String secret, Uint8List salt) {
  final mac = crypto.Hmac(crypto.sha256, utf8.encode(secret));
  var u =
      Uint8List.fromList(mac.convert([...salt, 0, 0, 0, 1]).bytes); // INT(1)
  final t = Uint8List.fromList(u);
  for (var i = 1; i < _pbkdf2Iterations; i++) {
    u = Uint8List.fromList(mac.convert(u).bytes);
    for (var k = 0; k < t.length; k++) {
      t[k] ^= u[k];
    }
  }
  return t;
}
