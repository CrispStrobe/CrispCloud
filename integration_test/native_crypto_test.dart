import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:crisp_cloud/services/cryptography_crypto_provider.dart';
import 'package:crisp_cloud/services/encryption_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('native hardware AES-GCM: speed + interop with existing files',
      () async {
    FlutterCryptography.enable(); // route AesGcm to Apple CryptoKit on macOS
    final p = CryptographyCryptoProvider();
    final raw = Uint8List(32)..setAll(0, List.generate(32, (i) => i & 0xff));
    final key = await p.importKey(raw);

    // Hardware speed test on a big payload (provider encrypt + decrypt only).
    final big = Uint8List(32 * 1024 * 1024)
      ..setAll(0, List.generate(32 * 1024 * 1024, (i) => (i * 31 + 7) & 0xff));
    final sw = Stopwatch()..start();
    final enc = await p.encrypt(key, big);
    final ms = sw.elapsedMilliseconds;
    final mbps = 32 / (ms / 1000);
    // ignore: avoid_print
    print(
        'NATIVE_AESGCM 32MB encrypt: ${ms}ms (${mbps.toStringAsFixed(0)} MB/s)');
    expect(await p.decrypt(key, enc), equals(big)); // round-trip
    // Hardware should crush the ~9 MB/s pure-Dart fallback.
    expect(mbps, greaterThan(50),
        reason:
            'expected hardware AES (>50 MB/s), got ${mbps.toStringAsFixed(0)}');

    // Interop on a SMALL payload (pointycastle ~1 MB/s is too slow at 32 MB):
    // a file written by the old pointycastle path must decrypt under the
    // hardware provider, and vice versa.
    final small = Uint8List(64 * 1024)
      ..setAll(0, List.generate(64 * 1024, (i) => (i * 7 + 3) & 0xff));
    final pcEnc = EncryptionService.encrypt(small, raw);
    expect(await p.decrypt(key, pcEnc), equals(small)); // pc file -> hardware
    final hwEnc = await p.encrypt(key, small);
    expect(
        EncryptionService.decrypt(hwEnc, raw), equals(small)); // hardware -> pc
  }, timeout: const Timeout(Duration(minutes: 2)));
}
