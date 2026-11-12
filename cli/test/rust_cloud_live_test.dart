// Live Filen/Internxt round trip through the CLI adapter and the native Rust
// engine. Opt-in: skipped unless the credentials and the library are set:
//   CRISP_CLOUD_LIBRARY=/abs/path/libcrisp_cloud_bridge.dylib
//   CRISP_LIVE_FILEN_EMAIL / CRISP_LIVE_FILEN_PASSWORD
//   CRISP_LIVE_INTERNXT_EMAIL / CRISP_LIVE_INTERNXT_PASSWORD (test account!)
//   optional CRISP_LIVE_<PROVIDER>_TOTP_SECRET for accounts with 2FA
// Everything happens in a uniquely named scratch folder that is trashed
// afterwards.
import 'dart:convert';
import 'dart:io';

import 'package:crisp/adapters/cli_adapter_factory.dart';
import 'package:crisp/adapters/cli_storage_client.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

/// RFC 6238 TOTP (SHA-1, 6 digits, 30 s) from a base32 secret, for test
/// accounts protected by 2FA (`CRISP_LIVE_<PROVIDER>_TOTP_SECRET`).
String _totp(String base32Secret) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final clean = base32Secret.toUpperCase().replaceAll(RegExp('[^A-Z2-7]'), '');
  final bytes = <int>[];
  var buffer = 0, bits = 0;
  for (final char in clean.split('')) {
    buffer = (buffer << 5) | alphabet.indexOf(char);
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((buffer >> bits) & 0xff);
    }
  }
  var counter = DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 30;
  final message = List<int>.filled(8, 0);
  for (var i = 7; i >= 0; i--) {
    message[i] = counter & 0xff;
    counter >>= 8;
  }
  final hash = Hmac(sha1, bytes).convert(message).bytes;
  final offset = hash.last & 0x0f;
  final code =
      ((hash[offset] & 0x7f) << 24 |
          hash[offset + 1] << 16 |
          hash[offset + 2] << 8 |
          hash[offset + 3]) %
      1000000;
  return code.toString().padLeft(6, '0');
}

String? _env(String key) {
  final value = Platform.environment[key];
  return value == null || value.isEmpty ? null : value;
}

void main() {
  for (final provider in ['filen', 'internxt']) {
    final email = _env('CRISP_LIVE_${provider.toUpperCase()}_EMAIL');
    final password = _env('CRISP_LIVE_${provider.toUpperCase()}_PASSWORD');
    final skip = _env('CRISP_CLOUD_LIBRARY') == null
        ? 'Set CRISP_CLOUD_LIBRARY'
        : email == null || password == null
        ? 'Set CRISP_LIVE_${provider.toUpperCase()}_EMAIL/_PASSWORD'
        : null;

    test(
      '$provider: CLI round trip in a scratch folder',
      () async {
        final totpSecret = _env(
          'CRISP_LIVE_${provider.toUpperCase()}_TOTP_SECRET',
        );
        final adapter = createAdapter(provider, {
          'type': provider,
          'email': email,
          'password': password,
          if (totpSecret != null) 'twoFactorCode': _totp(totpSecret),
        });
        final scratch =
            '/crisp-cli-live-${DateTime.now().toUtc().millisecondsSinceEpoch}';
        final local = await Directory.systemTemp.createTemp('crisp-cli-live-');
        try {
          await adapter.createDirectory(scratch);
          expect((await adapter.stat(scratch))?.isDirectory, isTrue);

          final payload = utf8.encode('CrispCloud CLI ${DateTime.now()}\n');
          await adapter.upload(payload, 'note.txt', scratch);
          final listed = await adapter.list(scratch);
          expect(listed.map((e) => e.name), contains('note.txt'));
          expect(
            listed.firstWhere((e) => e.name == 'note.txt').size,
            payload.length,
          );

          expect(await adapter.downloadBytes('$scratch/note.txt'), payload);

          final file = File('${local.path}/big.bin')
            ..writeAsBytesSync(List<int>.generate(300 * 1024, (i) => i % 251));
          var progressed = false;
          await uploadLocalFile(
            adapter,
            file,
            'big.bin',
            scratch,
            onProgress: (_, _) => progressed = true,
          );
          final back = '${local.path}/back.bin';
          await adapter.download('$scratch/big.bin', back);
          expect(File(back).readAsBytesSync(), file.readAsBytesSync());
          expect(progressed, isTrue);

          await adapter.createDirectory('$scratch/sub');
          await adapter.move('$scratch/note.txt', '$scratch/sub/renamed.txt');
          expect(await adapter.stat('$scratch/note.txt'), isNull);
          expect(
            (await adapter.list('$scratch/sub')).map((e) => e.name),
            contains('renamed.txt'),
          );

          await adapter.delete('$scratch/big.bin');
          expect(await adapter.stat('$scratch/big.bin'), isNull);
        } finally {
          try {
            await adapter.delete(scratch);
          } catch (_) {}
          await adapter.dispose();
          await local.delete(recursive: true);
        }
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
