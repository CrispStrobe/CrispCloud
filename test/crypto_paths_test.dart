// Cross-path file-crypto correctness: every AES-256-GCM path must be
// byte-compatible so existing encrypted files stay readable no matter which
// backend (pointycastle, package:cryptography pure-Dart, native hardware, or
// WebCrypto) wrote them. This file covers the paths reachable in the Dart VM;
// the native-hardware path is covered by integration_test/native_crypto_test.dart
// and the WebCrypto path by the headless-Chrome smoke (see the perf comparison
// in the PR description). Real-file (a PNG) + block-boundary edge sizes are
// exercised for each, plus a full round-trip through EncryptedStorageWrapper.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/encryption_service.dart';
import 'package:crisp_cloud/services/encrypted_storage_wrapper.dart';
import 'package:crisp_cloud/services/web_crypto_provider.dart';
import 'package:crisp_cloud/services/cryptography_crypto_provider.dart';

typedef EncFn = Future<Uint8List> Function(Uint8List);
typedef DecFn = Future<Uint8List> Function(Uint8List);

class _Path {
  final String name;
  final EncFn enc;
  final DecFn dec;
  _Path(this.name, this.enc, this.dec);
}

/// Minimal in-memory inner client — stores the uploaded (encrypted) bytes and
/// serves them back. Unused interface members forward to noSuchMethod.
class _MemInner implements CloudStorageClient {
  Uint8List? stored;

  @override
  Future<void> uploadFile(
      List<int> fileData, String fileName, String targetPath,
      {Function(int, int)? onProgress}) async {
    stored = Uint8List.fromList(fileData);
  }

  @override
  Future<Uint8List> downloadFileBytes(String remotePath,
          {Function(int, int)? onProgress}) async =>
      stored!;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A real binary file (the app icon PNG); falls back to a synthetic blob.
Uint8List _realFile() {
  for (final p in [
    'assets/images/app_icon.png',
    'web/icons/Icon-512.png',
  ]) {
    final f = File(p);
    if (f.existsSync()) return f.readAsBytesSync();
  }
  return Uint8List(200000)
    ..setAll(0, List.generate(200000, (i) => (i * 131 + 7) & 0xff));
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  // Same raw 32-byte key for every path (PBKDF2/derivation is tested elsewhere).
  final rawKey = Uint8List(32)
    ..setAll(0, List.generate(32, (i) => (i * 7 + 3) & 0xff));

  late List<_Path> paths;
  final realFile = _realFile();
  // Block-boundary + odd + empty + real-file sizes.
  final sizes = <int>[0, 1, 15, 16, 17, 31, 32, 4096, 4097, 1024 * 1024];

  setUpAll(() async {
    final pcProvider = const PointycastleCryptoProvider();
    final cgProvider = CryptographyCryptoProvider();
    final pcKey = await pcProvider.importKey(rawKey);
    final cgKey = await cgProvider.importKey(rawKey);
    paths = [
      // The original on-disk format (sync pointycastle via EncryptionService).
      _Path(
          'pointycastle-static',
          (d) async => EncryptionService.encrypt(d, rawKey),
          (d) async => EncryptionService.decrypt(d, rawKey)),
      _Path('pointycastle-provider', (d) => pcProvider.encrypt(pcKey, d),
          (d) => pcProvider.decrypt(pcKey, d)),
      _Path('cryptography', (d) => cgProvider.encrypt(cgKey, d),
          (d) => cgProvider.decrypt(cgKey, d)),
    ];
  });

  group('per-path round-trip (real file + edge sizes)', () {
    test('each path round-trips byte-exact', () async {
      for (final path in paths) {
        // real file
        final enc = await path.enc(realFile);
        expect(_bytesEqual(await path.dec(enc), realFile), isTrue,
            reason: '${path.name}: real-file round-trip not byte-exact');
        // edge sizes
        for (final n in sizes) {
          final data = Uint8List(n)
            ..setAll(0, List.generate(n, (i) => (i * 13 + 5) & 0xff));
          final e = await path.enc(data);
          expect(_bytesEqual(await path.dec(e), data), isTrue,
              reason: '${path.name}: $n-byte round-trip not byte-exact');
        }
      }
    });
  });

  group('cross-path interop matrix (wire-format compatibility)', () {
    test('every path decrypts every other path\'s output, byte-exact',
        () async {
      final payloads = <Uint8List>[
        realFile,
        Uint8List(0),
        Uint8List(16)..setAll(0, List.generate(16, (i) => i)),
        Uint8List(4097)..setAll(0, List.generate(4097, (i) => (i * 3) & 0xff)),
      ];
      for (final enc in paths) {
        for (final dec in paths) {
          for (final data in payloads) {
            final ct = await enc.enc(data);
            final back = await dec.dec(ct);
            expect(_bytesEqual(back, data), isTrue,
                reason: 'encrypt=${enc.name} -> decrypt=${dec.name} '
                    '(${data.length}B) not byte-exact');
          }
        }
      }
    });

    test('a tampered tag is rejected (GCM integrity) on every path', () async {
      for (final path in paths) {
        final ct = await path.enc(realFile);
        final tampered = Uint8List.fromList(ct)
          ..[ct.length - 1] ^= 0xff; // flip a tag bit
        expect(() => path.dec(tampered), throwsA(anything),
            reason: '${path.name}: tampered ciphertext must not decrypt');
      }
    });
  });

  group('full EncryptedStorageWrapper round-trip (real file)', () {
    for (final useCrypto in [false, true]) {
      test('${useCrypto ? 'cryptography' : 'pointycastle'} provider', () async {
        final mock = _MemInner();
        final wrapper = EncryptedStorageWrapper(
          inner: mock,
          encryptionKey: rawKey,
          cryptoProvider: useCrypto
              ? CryptographyCryptoProvider()
              : const PointycastleCryptoProvider(),
        );
        await wrapper.uploadFile(realFile, 'icon.png', '/');
        // The stored bytes are ciphertext (the plaintext must not appear).
        final stored = mock.stored!;
        expect(_bytesEqual(stored, realFile), isFalse);
        // Round-trip back through the wrapper.
        final out = await wrapper.downloadFileBytes('/icon.png');
        expect(_bytesEqual(out, realFile), isTrue,
            reason: 'wrapper round-trip not byte-exact');
      });
    }
  });
}
