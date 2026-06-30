// lib/services/openssl_aesgcm.dart
//
// AES-256-GCM via the OS's OpenSSL `libcrypto` over dart:ffi — no bundled native
// library. This is what the official Internxt/Filen Node CLIs effectively use
// (Node's `crypto` is OpenSSL), and it gives hardware-accelerated (AES-NI) bulk
// crypto on Linux/desktop where cryptography_flutter has no implementation.
//
// `libcrypto` ships with virtually every Linux distro; on macOS we look for a
// Homebrew OpenSSL (used to validate this binding). Windows uses BCrypt/CNG via
// a separate binding. If the library or a symbol can't be resolved, [tryLoad]
// returns null and the caller falls back (webcrypto / pure-Dart).

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// EVP_CIPHER_CTX_ctrl command constants (stable across OpenSSL 1.1 / 3.x).
const int _ctrlSetIvLen = 0x9;
const int _ctrlGetTag = 0x10;
const int _ctrlSetTag = 0x11;

// Native function typedefs.
typedef _PtrFnC = Pointer<Void> Function();
typedef _PtrFn = Pointer<Void> Function();
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeFn = void Function(Pointer<Void>);
typedef _Init2C = Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>,
    Pointer<Uint8>, Pointer<Uint8>);
typedef _Init2 = int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>,
    Pointer<Uint8>, Pointer<Uint8>);
typedef _UpdateC = Int32 Function(
    Pointer<Void>, Pointer<Uint8>, Pointer<Int32>, Pointer<Uint8>, Int32);
typedef _UpdateFn = int Function(
    Pointer<Void>, Pointer<Uint8>, Pointer<Int32>, Pointer<Uint8>, int);
typedef _FinalC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int32>);
typedef _FinalFn = int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int32>);
typedef _CtrlC = Int32 Function(Pointer<Void>, Int32, Int32, Pointer<Void>);
typedef _CtrlFn = int Function(Pointer<Void>, int, int, Pointer<Void>);

/// Thin FFI binding to OpenSSL EVP AES-256-GCM. Use [tryLoad]; null = unavailable.
class OpenSslAesGcm {
  final _PtrFn _ctxNew;
  final _FreeFn _ctxFree;
  final _PtrFn _aes256gcm;
  final _Init2 _encryptInit;
  final _UpdateFn _encryptUpdate;
  final _FinalFn _encryptFinal;
  final _Init2 _decryptInit;
  final _UpdateFn _decryptUpdate;
  final _FinalFn _decryptFinal;
  final _CtrlFn _ctrl;
  final _rng = Random.secure();

  OpenSslAesGcm._(DynamicLibrary lib)
      : _ctxNew = lib.lookupFunction<_PtrFnC, _PtrFn>('EVP_CIPHER_CTX_new'),
        _ctxFree = lib.lookupFunction<_FreeC, _FreeFn>('EVP_CIPHER_CTX_free'),
        _aes256gcm = lib.lookupFunction<_PtrFnC, _PtrFn>('EVP_aes_256_gcm'),
        _encryptInit =
            lib.lookupFunction<_Init2C, _Init2>('EVP_EncryptInit_ex'),
        _encryptUpdate =
            lib.lookupFunction<_UpdateC, _UpdateFn>('EVP_EncryptUpdate'),
        _encryptFinal =
            lib.lookupFunction<_FinalC, _FinalFn>('EVP_EncryptFinal_ex'),
        _decryptInit =
            lib.lookupFunction<_Init2C, _Init2>('EVP_DecryptInit_ex'),
        _decryptUpdate =
            lib.lookupFunction<_UpdateC, _UpdateFn>('EVP_DecryptUpdate'),
        _decryptFinal =
            lib.lookupFunction<_FinalC, _FinalFn>('EVP_DecryptFinal_ex'),
        _ctrl = lib.lookupFunction<_CtrlC, _CtrlFn>('EVP_CIPHER_CTX_ctrl');

  static OpenSslAesGcm? _cached;
  static bool _tried = false;

  /// Load + self-test once. Returns null if libcrypto/symbols aren't available
  /// or the self-test (a known-answer round-trip) fails.
  static OpenSslAesGcm? tryLoad() {
    if (_tried) return _cached;
    _tried = true;
    for (final name in _candidates()) {
      try {
        final lib = DynamicLibrary.open(name);
        final inst = OpenSslAesGcm._(lib);
        if (inst._selfTest()) {
          _cached = inst;
          return inst;
        }
      } catch (_) {
        // try the next candidate
      }
    }
    return null;
  }

  static List<String> _candidates() {
    if (Platform.isLinux) {
      return const ['libcrypto.so.3', 'libcrypto.so.1.1', 'libcrypto.so'];
    }
    if (Platform.isMacOS) {
      return const [
        '/opt/homebrew/opt/openssl@3/lib/libcrypto.dylib',
        '/usr/local/opt/openssl@3/lib/libcrypto.dylib',
        'libcrypto.dylib',
      ];
    }
    if (Platform.isWindows) {
      return const [
        'libcrypto-3-x64.dll',
        'libcrypto-1_1-x64.dll',
        'libcrypto.dll'
      ];
    }
    return const [];
  }

  bool _selfTest() {
    try {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final nonce = Uint8List.fromList(List.generate(12, (i) => i + 1));
      final pt = Uint8List.fromList(List.generate(40, (i) => (i * 7) & 0xff));
      final ct = _gcm(true, key, nonce, pt, null);
      final back = _gcm(false, key, nonce, ct.$1, ct.$2);
      if (back.$1.length != pt.length) return false;
      for (var i = 0; i < pt.length; i++) {
        if (back.$1[i] != pt[i]) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Encrypt: returns [nonce(12) | ciphertext | tag(16)].
  Uint8List encrypt(Uint8List key, Uint8List plaintext) {
    final nonce =
        Uint8List.fromList(List.generate(12, (_) => _rng.nextInt(256)));
    final r = _gcm(true, key, nonce, plaintext, null);
    final out = Uint8List(12 + r.$1.length + 16);
    out.setRange(0, 12, nonce);
    out.setRange(12, 12 + r.$1.length, r.$1);
    out.setRange(12 + r.$1.length, out.length, r.$2!);
    return out;
  }

  /// Decrypt [nonce(12) | ciphertext | tag(16)]; throws on auth failure.
  Uint8List decrypt(Uint8List key, Uint8List data) {
    if (data.length < 28) {
      throw const FormatException('Data too short for AES-GCM');
    }
    final nonce = data.sublist(0, 12);
    final ct = data.sublist(12, data.length - 16);
    final tag = data.sublist(data.length - 16);
    return _gcm(false, key, nonce, ct, tag).$1;
  }

  /// Core EVP GCM call. For encrypt, [tagIn] is null and the 16-byte tag is
  /// returned in `.$2`; for decrypt, [tagIn] is the expected tag and `.$2` is null.
  (Uint8List, Uint8List?) _gcm(bool encrypting, Uint8List key, Uint8List nonce,
      Uint8List input, Uint8List? tagIn) {
    final ctx = _ctxNew();
    if (ctx == nullptr) throw StateError('EVP_CIPHER_CTX_new failed');
    final keyP = malloc<Uint8>(key.length);
    final ivP = malloc<Uint8>(nonce.length);
    final inP = malloc<Uint8>(input.isEmpty ? 1 : input.length);
    final outP = malloc<Uint8>(input.length + 16);
    final outLen = malloc<Int32>();
    final tagP = malloc<Uint8>(16);
    try {
      keyP.asTypedList(key.length).setAll(0, key);
      ivP.asTypedList(nonce.length).setAll(0, nonce);
      if (input.isNotEmpty) inP.asTypedList(input.length).setAll(0, input);

      final init = encrypting ? _encryptInit : _decryptInit;
      final update = encrypting ? _encryptUpdate : _decryptUpdate;
      final fin = encrypting ? _encryptFinal : _decryptFinal;

      _check(init(ctx, _aes256gcm(), nullptr, nullptr, nullptr), 'init-cipher');
      _check(_ctrl(ctx, _ctrlSetIvLen, nonce.length, nullptr), 'set-ivlen');
      _check(init(ctx, nullptr, nullptr, keyP, ivP), 'init-key');

      var total = 0;
      if (input.isNotEmpty) {
        _check(update(ctx, outP, outLen, inP, input.length), 'update');
        total = outLen.value;
      }

      if (!encrypting) {
        tagP.asTypedList(16).setAll(0, tagIn!);
        _check(_ctrl(ctx, _ctrlSetTag, 16, tagP.cast()), 'set-tag');
      }

      final finRet = fin(ctx, outP + total, outLen);
      if (!encrypting && finRet <= 0) {
        throw const FormatException('GCM authentication failed');
      }
      _check(finRet, 'final');
      total += outLen.value;

      final result = Uint8List.fromList(outP.asTypedList(total));
      if (encrypting) {
        _check(_ctrl(ctx, _ctrlGetTag, 16, tagP.cast()), 'get-tag');
        return (result, Uint8List.fromList(tagP.asTypedList(16)));
      }
      return (result, null);
    } finally {
      _ctxFree(ctx);
      malloc.free(keyP);
      malloc.free(ivP);
      malloc.free(inP);
      malloc.free(outP);
      malloc.free(outLen);
      malloc.free(tagP);
    }
  }

  void _check(int ret, String what) {
    if (ret <= 0) throw StateError('OpenSSL $what failed (ret=$ret)');
  }
}
