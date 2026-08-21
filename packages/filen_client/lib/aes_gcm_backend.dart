/// Pluggable AES-256-GCM backend for Filen file-chunk crypto.
///
/// Filen's wire format is [iv(12) | ciphertext | tag(16)] (the tag is appended
/// to the ciphertext, GCM-style). That's the standard AES-GCM layout, so every
/// backend here is byte-interoperable — existing Filen-encrypted chunks decrypt
/// under the fast paths and vice versa.
///
/// Best-available, chosen at startup (each FFI backend self-tests on load and
/// returns null on failure, so the chain degrades safely):
///   1. OS OpenSSL libcrypto via FFI (Linux/desktop)  — AES-NI, ~1280 MB/s
///   2. Windows CNG bcrypt.dll via FFI                — hardware AES-GCM
///   3. package:cryptography                          — hardware via the app's
///      Cryptography.instance (FlutterCryptography → CryptoKit/Keystore when the
///      host app enabled it; WebCrypto on web), else pure-Dart (~10 MB/s)
///   4. pointycastle GCMBlockCipher                   — the original software path
///
/// This replaces the ~1 MB/s pointycastle path that previously ran on every
/// Filen chunk.

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;
import 'package:pointycastle/export.dart'
    show GCMBlockCipher, AESEngine, AEADParameters, KeyParameter;

// FFI backends only exist on native platforms — the real files import
// `dart:ffi`/`dart:io`, which dart2js can't compile. On web the conditional
// import resolves to the stubs (tryLoad() -> null), so the chooser falls
// through to the WebCrypto-backed CryptographyBackend.
import 'bcrypt_aesgcm_stub.dart' if (dart.library.ffi) 'bcrypt_aesgcm.dart';
import 'openssl_aesgcm_stub.dart' if (dart.library.ffi) 'openssl_aesgcm.dart';

abstract class AesGcmBackend {
  String get name;

  /// Returns [iv(12) | ciphertext | tag(16)].
  Future<Uint8List> encryptData(Uint8List key, Uint8List data);

  /// Decrypts [iv(12) | ciphertext | tag(16)]; throws on auth failure.
  Future<Uint8List> decryptData(Uint8List key, Uint8List data);
}

/// Pick the fastest backend available on this platform.
AesGcmBackend chooseAesGcmBackend() {
  final o = OpenSslAesGcm.tryLoad();
  if (o != null) return _OpenSslBackend(o);
  final b = BCryptAesGcm.tryLoad();
  if (b != null) return _BCryptBackend(b);
  return CryptographyBackend();
}

class _OpenSslBackend implements AesGcmBackend {
  final OpenSslAesGcm _o;
  _OpenSslBackend(this._o);
  @override
  String get name => 'openssl';
  @override
  Future<Uint8List> encryptData(Uint8List key, Uint8List data) async =>
      _o.encrypt(key, data);
  @override
  Future<Uint8List> decryptData(Uint8List key, Uint8List data) async =>
      _o.decrypt(key, data);
}

class _BCryptBackend implements AesGcmBackend {
  final BCryptAesGcm _b;
  _BCryptBackend(this._b);
  @override
  String get name => 'bcrypt';
  @override
  Future<Uint8List> encryptData(Uint8List key, Uint8List data) async =>
      _b.encrypt(key, data);
  @override
  Future<Uint8List> decryptData(Uint8List key, Uint8List data) async =>
      _b.decrypt(key, data);
}

/// package:cryptography — uses the host app's Cryptography.instance, so it picks
/// up FlutterCryptography (hardware) when enabled, and BrowserCryptography
/// (WebCrypto) on web; otherwise pure-Dart.
class CryptographyBackend implements AesGcmBackend {
  final cg.AesGcm _algo = cg.AesGcm.with256bits();
  @override
  String get name => 'cryptography';
  @override
  Future<Uint8List> encryptData(Uint8List key, Uint8List data) async {
    final sk = await _algo.newSecretKeyFromBytes(key);
    final nonce = _algo.newNonce(); // 12 bytes
    final box = await _algo.encrypt(data, secretKey: sk, nonce: nonce);
    return Uint8List.fromList([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  @override
  Future<Uint8List> decryptData(Uint8List key, Uint8List data) async {
    if (data.length < 28) {
      throw const FormatException('Data too short for AES-GCM');
    }
    final sk = await _algo.newSecretKeyFromBytes(key);
    final nonce = data.sublist(0, 12);
    final ct = data.sublist(12, data.length - 16);
    final mac = data.sublist(data.length - 16);
    final clear = await _algo.decrypt(
      cg.SecretBox(ct, nonce: nonce, mac: cg.Mac(mac)),
      secretKey: sk,
    );
    return Uint8List.fromList(clear);
  }
}

/// The original pointycastle path (kept as the final fallback). Generates a
/// random 12-byte IV; GCMBlockCipher.process appends the 16-byte tag.
class PointycastleBackend implements AesGcmBackend {
  final Uint8List Function(int) _randomBytes;
  PointycastleBackend(this._randomBytes);
  @override
  String get name => 'pointycastle';
  @override
  Future<Uint8List> encryptData(Uint8List key, Uint8List data) async {
    final iv = _randomBytes(12);
    final c = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return Uint8List.fromList([...iv, ...c.process(data)]);
  }

  @override
  Future<Uint8List> decryptData(Uint8List key, Uint8List data) async {
    final c = GCMBlockCipher(AESEngine())
      ..init(
          false,
          AEADParameters(
              KeyParameter(key), 128, data.sublist(0, 12), Uint8List(0)));
    return c.process(data.sublist(12));
  }
}
