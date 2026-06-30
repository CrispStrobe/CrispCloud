// Live native crypto test — runs on a real device/desktop (e.g. macOS) where
// FlutterCryptography routes AES-GCM to the platform's hardware crypto (Apple
// CryptoKit / Android Keystore). Validates hardware throughput AND that a real
// file round-trips byte-exact and stays interoperable with the pointycastle
// wire format (so existing encrypted files remain readable).
//
//   flutter test integration_test/native_crypto_test.dart -d macos

import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:crisp_cloud/services/cryptography_crypto_provider.dart';
import 'package:crisp_cloud/services/encryption_service.dart';

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
      'native hardware AES-GCM: throughput, real-file + edge round-trip, interop',
      () async {
    FlutterCryptography.enable(); // route AesGcm to platform hardware crypto
    final p = CryptographyCryptoProvider();
    final raw = Uint8List(32)..setAll(0, List.generate(32, (i) => i & 0xff));
    final key = await p.importKey(raw);

    // 1) Hardware throughput on a big payload (encrypt + decrypt only).
    final big = Uint8List(32 * 1024 * 1024)
      ..setAll(0, List.generate(32 * 1024 * 1024, (i) => (i * 31 + 7) & 0xff));
    final sw = Stopwatch()..start();
    final enc = await p.encrypt(key, big);
    final ms = sw.elapsedMilliseconds;
    final mbps = 32 / (ms / 1000);
    // ignore: avoid_print
    print(
        'NATIVE_AESGCM 32MB encrypt: ${ms}ms (${mbps.toStringAsFixed(0)} MB/s)');
    expect(_eq(await p.decrypt(key, enc), big), isTrue); // round-trip
    expect(mbps, greaterThan(50),
        reason:
            'expected hardware AES (>50 MB/s), got ${mbps.toStringAsFixed(0)}');

    // 2) Real file (the app icon PNG) — byte-exact round-trip + cross-path
    //    interop with the pointycastle wire format (existing files).
    final realFile = (await rootBundle.load('assets/images/app_icon.png'))
        .buffer
        .asUint8List();
    expect(realFile.length, greaterThan(1000));
    expect(_eq(await p.decrypt(key, await p.encrypt(key, realFile)), realFile),
        isTrue,
        reason: 'real-file hardware round-trip not byte-exact');
    // pointycastle-written file -> hardware decrypt
    expect(
        _eq(await p.decrypt(key, EncryptionService.encrypt(realFile, raw)),
            realFile),
        isTrue,
        reason: 'existing pointycastle file must decrypt under hardware');
    // hardware-written file -> pointycastle decrypt
    expect(
        _eq(EncryptionService.decrypt(await p.encrypt(key, realFile), raw),
            realFile),
        isTrue);

    // 3) Block-boundary + empty + odd edge sizes round-trip on hardware.
    for (final n in [0, 1, 15, 16, 17, 31, 32, 4097]) {
      final d = Uint8List(n)
        ..setAll(0, List.generate(n, (i) => (i * 13 + 5) & 0xff));
      expect(_eq(await p.decrypt(key, await p.encrypt(key, d)), d), isTrue,
          reason: '$n-byte hardware round-trip not byte-exact');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
