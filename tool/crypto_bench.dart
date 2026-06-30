// Headless cross-path crypto check + benchmark — NO app window.
//
//   dart run tool/crypto_bench.dart
//
// Covers correctness (round-trip + the cross-path interop matrix proving every
// AES-GCM path is byte-compatible) and benchmarks the paths reachable in the
// Dart VM: pointycastle and package:cryptography's pure-Dart impl.
//
// NOTE: the platform HARDWARE path (cryptography_flutter -> CryptoKit/Keystore)
// needs the Flutter engine, so it is NOT exercised here — that requires
// `flutter test integration_test/native_crypto_test.dart -d <device>`. WebCrypto
// likewise needs a browser. This tool is the fast, windowless correctness gate.

import 'dart:typed_data';

import 'package:crisp_cloud/services/encryption_service.dart';
import 'package:crisp_cloud/services/web_crypto_provider.dart';
import 'package:crisp_cloud/services/cryptography_crypto_provider.dart';

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> main() async {
  final raw = Uint8List(32)
    ..setAll(0, List.generate(32, (i) => (i * 7 + 3) & 0xff));
  final pc = const PointycastleCryptoProvider();
  final cg = CryptographyCryptoProvider();
  final pcKey = await pc.importKey(raw);
  final cgKey = await cg.importKey(raw);

  final paths = <String,
      (
    Future<Uint8List> Function(Uint8List),
    Future<Uint8List> Function(Uint8List)
  )>{
    'pointycastle-static': (
      (d) async => EncryptionService.encrypt(d, raw),
      (d) async => EncryptionService.decrypt(d, raw)
    ),
    'pointycastle-provider': (
      (d) => pc.encrypt(pcKey, d),
      (d) => pc.decrypt(pcKey, d)
    ),
    'cryptography(pure-Dart)': (
      (d) => cg.encrypt(cgKey, d),
      (d) => cg.decrypt(cgKey, d)
    ),
  };

  // Cross-path interop matrix (correctness).
  var ok = true;
  final sample = Uint8List(4097)
    ..setAll(0, List.generate(4097, (i) => (i * 13 + 5) & 0xff));
  for (final e in paths.entries) {
    for (final d in paths.entries) {
      final back = await d.value.$2(await e.value.$1(sample));
      if (!_eq(back, sample)) {
        ok = false;
        print('MISMATCH: encrypt=${e.key} -> decrypt=${d.key}');
      }
    }
  }
  print(
      'cross-path interop matrix (3x3): ${ok ? "ALL byte-exact ✅" : "FAILED ❌"}');

  // Throughput (8 MB) for the VM-reachable paths.
  final big = Uint8List(8 * 1024 * 1024)
    ..setAll(0, List.generate(8 * 1024 * 1024, (i) => (i * 31 + 7) & 0xff));
  print('\nThroughput (8 MB, this machine / Dart VM):');
  for (final e in paths.entries) {
    final sw = Stopwatch()..start();
    await e.value.$1(big);
    final ms = sw.elapsedMilliseconds;
    print('  ${e.key.padRight(24)} ${ms.toString().padLeft(6)} ms  '
        '(${(8 / (ms / 1000)).toStringAsFixed(0)} MB/s)');
  }
  print(
      '\n(web WebCrypto ~1300 MB/s and native hardware ~300 MB/s are measured '
      'by the browser smoke / integration test — they need a browser / Flutter engine.)');
}
