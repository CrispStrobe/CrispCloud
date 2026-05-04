// Phase 6.c live verification — drives the rewired
// InternxtClientAdapter against the real Internxt gateway.
//
// What this proves: the published internxt_client package, plumbed
// through cloud-dart's adapter (URL overrides + ConfigService +
// path facade), matches the behavior the embedded copy used to
// have. End-to-end: login → list → upload bytes → download bytes
// → trash. Each call exercises a code path the Flutter UI uses.
//
// CREDS: reads IXT_ACCOUNT / IXT_PWD. Looks in three places:
//   1. process env (e.g. `IXT_ACCOUNT=… IXT_PWD=… flutter test …`)
//   2. cloud-dart/.env
//   3. ../internxt-cli/.env (the existing CLI repo's .env)
// Auto-skips with a clear message if none provide the creds —
// CI without secrets sees a clean skip rather than a failure.
//
// LEAVES NO REMOTE DEBRIS: each upload uses a unique random name
// at /__cloud_dart_rewire_smoke__/<run-id>/ and is trashed at end
// of the test (try/finally), so a flaky run doesn't accumulate
// junk in the real account.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/internxt_client_adapter.dart';

// ---------- credential loading ----------

final Map<String, String> _envOverrides = {};

void _loadDotEnvIfPresent() {
  final candidates = <File>[
    File('${Directory.current.path}/.env'),
    // Walk up to the sibling internxt-cli repo where the .env
    // currently lives.
    File('${Directory.current.path}/../internxt-cli/.env'),
  ];
  for (final f in candidates) {
    if (!f.existsSync()) continue;
    for (final line in f.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || !trimmed.contains('=')) {
        continue;
      }
      final eq = trimmed.indexOf('=');
      final k = trimmed.substring(0, eq).trim();
      final v = trimmed
          .substring(eq + 1)
          .trim()
          .replaceAll('"', '')
          .replaceAll("'", '');
      _envOverrides.putIfAbsent(k, () => v);
    }
  }
}

String? _env(String key) =>
    _envOverrides[key] ?? Platform.environment[key];

// ---------- helpers ----------

String _uniqueHex(int bytes) {
  final rng = Random.secure();
  return List.generate(bytes, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

void main() {
  _loadDotEnvIfPresent();

  final email = _env('IXT_ACCOUNT');
  final password = _env('IXT_PWD');
  final skipLive = _env('DART_TEST_SKIP_LIVE') == '1';

  final skipReason = skipLive
      ? 'DART_TEST_SKIP_LIVE=1 set'
      : (email == null || password == null
          ? 'IXT_ACCOUNT / IXT_PWD not set (env or .env or ../internxt-cli/.env)'
          : null);

  if (skipReason != null) {
    test('live rewire (skipped: $skipReason)', () {});
    return;
  }

  group('Phase 6.c live rewire — adapter against real gateway', () {
    late InternxtClientAdapter adapter;
    late Directory tmpCfg;
    final runId = _uniqueHex(4);
    const sentinelFolder = '/__cloud_dart_rewire_smoke__';
    final runFolder = '$sentinelFolder/$runId';
    final probeName = 'probe-${_uniqueHex(4)}.bin';
    final probeRemotePath = '$runFolder/$probeName';
    final probePayload = Uint8List.fromList(
        utf8.encode('cloud-dart Phase 6.c probe ${DateTime.now().toIso8601String()}'));

    setUpAll(() async {
      tmpCfg = Directory.systemTemp.createTempSync('cloud-dart-rewire-live-');
      adapter = InternxtClientAdapter.forHost(configPath: tmpCfg.path);

      // is2faNeeded should not fail for a real account, regardless of
      // whether 2FA is enabled. Confirms the adapter's auth path
      // reaches the gateway.
      final needs2fa = await adapter.is2faNeeded(email!);
      if (needs2fa) {
        // Can't proceed automated if 2FA is required. Skip the rest.
        markTestSkipped(
            '2FA enabled on $email — live rewire test needs a non-2FA account');
        return;
      }

      await adapter.login(email, password!);
      expect(adapter.isAuthenticated, isTrue,
          reason: 'login should populate userId on success');
      expect(adapter.lastLoginResponse, isNotNull,
          reason: 'login response should be captured for AppState');

      // Prepare the per-run subfolder. createFolderPath is idempotent
      // — if a previous run left the sentinel folder, that's fine.
      await adapter.createFolderPath(sentinelFolder);
      await adapter.createFolderPath(runFolder);
    });

    tearDownAll(() async {
      // Best-effort cleanup. Don't throw if the run folder didn't
      // get created (e.g. login failed) or trash fails.
      try {
        await adapter.deletePath(runFolder);
      } catch (_) {/* swallow */}
      if (tmpCfg.existsSync()) {
        tmpCfg.deleteSync(recursive: true);
      }
    });

    test('listPath: root resolves and returns folder/file lists', () async {
      final listing = await adapter.listPath('/');
      expect(listing, isA<Map<String, dynamic>>());
      expect(listing.containsKey('folders'), isTrue);
      expect(listing.containsKey('files'), isTrue);
    });

    test('uploadFile (path facade) → resolvePath finds it', () async {
      await adapter.uploadFile(probePayload, probeName, runFolder);
      final resolved = await adapter.resolvePath(probeRemotePath);
      expect(resolved, isNotNull,
          reason: 'uploaded file should be resolvable by path');
      expect(resolved!['type'], equals('file'));
    });

    test('downloadFileBytes round-trips the upload', () async {
      // Depends on the previous test having uploaded the probe.
      final downloaded = await adapter.downloadFileBytes(probeRemotePath);
      expect(downloaded.length, equals(probePayload.length));
      expect(downloaded, equals(probePayload),
          reason: 'downloaded bytes should match uploaded payload');
    });

    test('deletePath trashes the probe file', () async {
      await adapter.deletePath(probeRemotePath);
      // After trash, resolvePath should NOT find it (trashed items
      // are excluded from the active listing).
      final after = await adapter.resolvePath(probeRemotePath);
      expect(after, isNull,
          reason: 'trashed file should not resolve in active tree');
    });

    test('listPath of run folder reflects mutations', () async {
      // After the trash, the run folder should be empty (or at most
      // contain other test artifacts if the suite is extended).
      final listing = await adapter.listPath(runFolder);
      final files = listing['files'] as List;
      final probesRemaining = files
          .where((f) {
            final m = f as Map<String, dynamic>;
            final name = (m['plainName'] ?? '') as String;
            return name.startsWith('probe-');
          })
          .toList();
      expect(probesRemaining, isEmpty,
          reason: 'no probe-* files should remain after trash');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
