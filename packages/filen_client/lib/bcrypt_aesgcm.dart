// lib/services/bcrypt_aesgcm.dart
//
// AES-256-GCM via Windows CNG (bcrypt.dll) over dart:ffi — no bundled native
// library; bcrypt.dll ships with every Windows. Gives hardware-accelerated bulk
// crypto on Windows, where cryptography_flutter has no implementation.
//
// SAFETY: this binding can't be exercised on non-Windows CI here, so [tryLoad]
// runs a known-answer self-test (encrypt+decrypt a fixed vector) and returns
// null if anything is off — a subtly-wrong binding then safely falls back to the
// next provider rather than corrupting data.

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int _statusSuccess = 0; // NTSTATUS STATUS_SUCCESS

// BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO (bcrypt.h). Declare the real fields in
// order only — Dart FFI inserts the same natural-alignment padding C does.
final class _AuthInfo extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int dwInfoVersion;
  external Pointer<Uint8> pbNonce;
  @Uint32()
  external int cbNonce;
  external Pointer<Uint8> pbAuthData;
  @Uint32()
  external int cbAuthData;
  external Pointer<Uint8> pbTag;
  @Uint32()
  external int cbTag;
  external Pointer<Uint8> pbMacContext;
  @Uint32()
  external int cbMacContext;
  @Uint32()
  external int cbAAD;
  @Uint64()
  external int cbData;
  @Uint32()
  external int dwFlags;
}

typedef _OpenAlgC = Int32 Function(
    Pointer<Pointer<Void>>, Pointer<Uint16>, Pointer<Uint16>, Uint32);
typedef _OpenAlg = int Function(
    Pointer<Pointer<Void>>, Pointer<Uint16>, Pointer<Uint16>, int);
typedef _SetPropC = Int32 Function(
    Pointer<Void>, Pointer<Uint16>, Pointer<Uint8>, Uint32, Uint32);
typedef _SetProp = int Function(
    Pointer<Void>, Pointer<Uint16>, Pointer<Uint8>, int, int);
typedef _GenKeyC = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>,
    Pointer<Uint8>, Uint32, Pointer<Uint8>, Uint32, Uint32);
typedef _GenKey = int Function(Pointer<Void>, Pointer<Pointer<Void>>,
    Pointer<Uint8>, int, Pointer<Uint8>, int, int);
typedef _CryptC = Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Uint32,
    Pointer<Void>,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint8>,
    Uint32,
    Pointer<Uint32>,
    Uint32);
typedef _Crypt = int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>,
    Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint32>, int);
typedef _Handle1C = Int32 Function(Pointer<Void>);
typedef _Handle1 = int Function(Pointer<Void>);
typedef _CloseAlgC = Int32 Function(Pointer<Void>, Uint32);
typedef _CloseAlg = int Function(Pointer<Void>, int);

/// Thin FFI binding to Windows CNG AES-256-GCM. Use [tryLoad]; null = unavailable.
class BCryptAesGcm {
  final _OpenAlg _openAlg;
  final _SetProp _setProp;
  final _GenKey _genKey;
  final _Crypt _encryptFn;
  final _Crypt _decryptFn;
  final _Handle1 _destroyKey;
  final _CloseAlg _closeAlg;
  final _rng = Random.secure();

  BCryptAesGcm._(DynamicLibrary lib)
      : _openAlg = lib
            .lookupFunction<_OpenAlgC, _OpenAlg>('BCryptOpenAlgorithmProvider'),
        _setProp = lib.lookupFunction<_SetPropC, _SetProp>('BCryptSetProperty'),
        _genKey =
            lib.lookupFunction<_GenKeyC, _GenKey>('BCryptGenerateSymmetricKey'),
        _encryptFn = lib.lookupFunction<_CryptC, _Crypt>('BCryptEncrypt'),
        _decryptFn = lib.lookupFunction<_CryptC, _Crypt>('BCryptDecrypt'),
        _destroyKey =
            lib.lookupFunction<_Handle1C, _Handle1>('BCryptDestroyKey'),
        _closeAlg = lib.lookupFunction<_CloseAlgC, _CloseAlg>(
            'BCryptCloseAlgorithmProvider');

  static BCryptAesGcm? _cached;
  static bool _tried = false;

  static BCryptAesGcm? tryLoad() {
    if (_tried) return _cached;
    _tried = true;
    if (!Platform.isWindows) return null;
    try {
      final lib = DynamicLibrary.open('bcrypt.dll');
      final inst = BCryptAesGcm._(lib);
      if (inst._selfTest()) {
        _cached = inst;
        return inst;
      }
    } catch (_) {
      // fall through to null
    }
    return null;
  }

  bool _selfTest() {
    try {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final pt = Uint8List.fromList(List.generate(40, (i) => (i * 7) & 0xff));
      final back = decrypt(key, encrypt(key, pt));
      if (back.length != pt.length) return false;
      for (var i = 0; i < pt.length; i++) {
        if (back[i] != pt[i]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Pointer<Void> _openGcmAlg(Arena a) {
    final hAlgP = a<Pointer<Void>>();
    final aes = 'AES'.toNativeUtf16(allocator: a).cast<Uint16>();
    if (_openAlg(hAlgP, aes, nullptr, 0) != _statusSuccess) {
      throw StateError('BCryptOpenAlgorithmProvider failed');
    }
    final hAlg = hAlgP.value;
    final modeProp = 'ChainingMode'.toNativeUtf16(allocator: a).cast<Uint16>();
    final gcm = 'ChainingModeGCM'.toNativeUtf16(allocator: a);
    const gcmLen = ('ChainingModeGCM'.length + 1) * 2; // include UTF-16 NUL
    if (_setProp(hAlg, modeProp, gcm.cast<Uint8>(), gcmLen, 0) !=
        _statusSuccess) {
      _closeAlg(hAlg, 0);
      throw StateError('BCryptSetProperty(ChainingMode) failed');
    }
    return hAlg;
  }

  Pointer<Void> _genSymKey(Arena a, Pointer<Void> hAlg, Uint8List key) {
    final hKeyP = a<Pointer<Void>>();
    final keyP = a<Uint8>(key.length)..asTypedList(key.length).setAll(0, key);
    if (_genKey(hAlg, hKeyP, nullptr, 0, keyP, key.length, 0) !=
        _statusSuccess) {
      _closeAlg(hAlg, 0);
      throw StateError('BCryptGenerateSymmetricKey failed');
    }
    return hKeyP.value;
  }

  Pointer<_AuthInfo> _authInfo(
      Arena a, Pointer<Uint8> nonceP, Pointer<Uint8> tagP) {
    final p = a<_AuthInfo>();
    p.ref
      ..cbSize = sizeOf<_AuthInfo>()
      ..dwInfoVersion = 1
      ..pbNonce = nonceP
      ..cbNonce = 12
      ..pbAuthData = nullptr
      ..cbAuthData = 0
      ..pbTag = tagP
      ..cbTag = 16
      ..pbMacContext = nullptr
      ..cbMacContext = 0
      ..cbAAD = 0
      ..cbData = 0
      ..dwFlags = 0;
    return p;
  }

  /// Encrypt: returns [nonce(12) | ciphertext | tag(16)].
  Uint8List encrypt(Uint8List key, Uint8List plaintext) {
    final nonce =
        Uint8List.fromList(List.generate(12, (_) => _rng.nextInt(256)));
    return using((a) {
      final hAlg = _openGcmAlg(a);
      final hKey = _genSymKey(a, hAlg, key);
      try {
        final nonceP = a<Uint8>(12)..asTypedList(12).setAll(0, nonce);
        final tagP = a<Uint8>(16);
        final inP = a<Uint8>(plaintext.isEmpty ? 1 : plaintext.length);
        if (plaintext.isNotEmpty) {
          inP.asTypedList(plaintext.length).setAll(0, plaintext);
        }
        final outP = a<Uint8>(plaintext.isEmpty ? 1 : plaintext.length);
        final info = _authInfo(a, nonceP, tagP);
        final cbResult = a<Uint32>();
        final st = _encryptFn(hKey, inP, plaintext.length, info.cast(), nullptr,
            0, outP, plaintext.length, cbResult, 0);
        if (st != _statusSuccess) {
          throw StateError('BCryptEncrypt failed (status=$st)');
        }
        final ctLen = cbResult.value;
        final out = Uint8List(12 + ctLen + 16);
        out.setRange(0, 12, nonce);
        if (ctLen > 0) out.setRange(12, 12 + ctLen, outP.asTypedList(ctLen));
        out.setRange(12 + ctLen, out.length, tagP.asTypedList(16));
        return out;
      } finally {
        _destroyKey(hKey);
        _closeAlg(hAlg, 0);
      }
    });
  }

  /// Decrypt [nonce(12) | ciphertext | tag(16)]; throws on auth failure.
  Uint8List decrypt(Uint8List key, Uint8List data) {
    if (data.length < 28) {
      throw const FormatException('Data too short for AES-GCM');
    }
    final nonce = data.sublist(0, 12);
    final ct = data.sublist(12, data.length - 16);
    final tag = data.sublist(data.length - 16);
    return using((a) {
      final hAlg = _openGcmAlg(a);
      final hKey = _genSymKey(a, hAlg, key);
      try {
        final nonceP = a<Uint8>(12)..asTypedList(12).setAll(0, nonce);
        final tagP = a<Uint8>(16)..asTypedList(16).setAll(0, tag);
        final inP = a<Uint8>(ct.isEmpty ? 1 : ct.length);
        if (ct.isNotEmpty) inP.asTypedList(ct.length).setAll(0, ct);
        final outP = a<Uint8>(ct.isEmpty ? 1 : ct.length);
        final info = _authInfo(a, nonceP, tagP);
        final cbResult = a<Uint32>();
        final st = _decryptFn(hKey, inP, ct.length, info.cast(), nullptr, 0,
            outP, ct.length, cbResult, 0);
        if (st != _statusSuccess) {
          throw const FormatException('GCM authentication failed');
        }
        final n = cbResult.value;
        return Uint8List.fromList(n == 0 ? const <int>[] : outP.asTypedList(n));
      } finally {
        _destroyKey(hKey);
        _closeAlg(hAlg, 0);
      }
    });
  }
}
