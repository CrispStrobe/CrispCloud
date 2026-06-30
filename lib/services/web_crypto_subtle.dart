// lib/services/web_crypto_subtle.dart
//
// Web-only WebCryptoProvider backed by the browser's native WebCrypto
// (`crypto.subtle`). Two SOTA wins over the pure-Dart pointycastle path:
//   * native-speed PBKDF2 → SOTA iteration counts (600k) cost ~ms, not seconds
//   * the derived AES-GCM key is NON-EXTRACTABLE: the raw key bytes never exist
//     in JS-readable memory, so an XSS payload can't exfiltrate it.
//
// Selected only on the web build via the conditional-import factory; the Dart
// VM / native fallback keeps using PointycastleCryptoProvider. The wire format
// matches that provider exactly (AES-256-GCM, [nonce(12)|ct|tag(16)]), and
// PBKDF2/AES-GCM are standardized, so this decrypts data written by the old
// pointycastle path for the same (password, salt, iterations).

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_crypto_provider.dart';

class WebCryptoSubtleProvider implements WebCryptoProvider {
  const WebCryptoSubtleProvider();

  web.SubtleCrypto get _subtle => web.window.crypto.subtle;

  /// Build a JS algorithm/params object from Dart entries.
  static JSObject _obj(Map<String, JSAny?> entries) {
    final o = JSObject();
    entries.forEach((k, v) => o[k] = v);
    return o;
  }

  @override
  Future<Object> deriveKey(
      String password, Uint8List salt, int iterations) async {
    final baseKey = await _subtle
        .importKey(
          'raw',
          Uint8List.fromList(utf8.encode(password)).toJS,
          'PBKDF2'.toJS,
          false,
          <JSString>['deriveKey'.toJS].toJS,
        )
        .toDart;
    final derived = await _subtle
        .deriveKey(
          _obj({
            'name': 'PBKDF2'.toJS,
            'salt': salt.toJS,
            'iterations': iterations.toJS,
            'hash': 'SHA-256'.toJS,
          }),
          baseKey,
          _obj({'name': 'AES-GCM'.toJS, 'length': 256.toJS}),
          false, // extractable = false → non-extractable key
          <JSString>['encrypt'.toJS, 'decrypt'.toJS].toJS,
        )
        .toDart;
    return derived as web.CryptoKey;
  }

  @override
  Future<Uint8List> encrypt(Object key, Uint8List plaintext) async {
    final nonce = Uint8List(12);
    web.window.crypto.getRandomValues(nonce.toJS);
    final ctBuf = await _subtle
        .encrypt(
          _obj({
            'name': 'AES-GCM'.toJS,
            'iv': nonce.toJS,
            'tagLength': 128.toJS,
          }),
          key as web.CryptoKey,
          plaintext.toJS,
        )
        .toDart;
    final ct = (ctBuf as JSArrayBuffer).toDart.asUint8List();
    final out = Uint8List(12 + ct.length);
    out.setRange(0, 12, nonce);
    out.setRange(12, 12 + ct.length, ct);
    return out;
  }

  @override
  Future<Uint8List> decrypt(Object key, Uint8List data) async {
    if (data.length < 28) {
      throw const FormatException('Data too short for AES-GCM');
    }
    final nonce = data.sublist(0, 12);
    final ctTag = data.sublist(12);
    final plainBuf = await _subtle
        .decrypt(
          _obj({
            'name': 'AES-GCM'.toJS,
            'iv': nonce.toJS,
            'tagLength': 128.toJS,
          }),
          key as web.CryptoKey,
          ctTag.toJS,
        )
        .toDart;
    return (plainBuf as JSArrayBuffer).toDart.asUint8List();
  }
}
