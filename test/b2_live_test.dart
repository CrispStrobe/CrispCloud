// test/b2_live_test.dart
//
// Live integration tests for Backblaze B2 native API adapter.
//
// Requires environment variables:
//   B2_KEY_ID      — Application key ID
//   B2_APP_KEY     — Application key secret
//   B2_BUCKET_NAME — Bucket to use for tests (must already exist)
//
// Run: flutter test --tags live test/b2_live_test.dart

@Tags(['live'])
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/b2_client_adapter.dart';
import 'package:crisp_cloud/services/b2_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Unique name prefix to avoid cross-run collisions.
String _uniqueName(String base) =>
    '${base}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

/// 1 KB of deterministic bytes (0x00–0xFF repeated).
Uint8List _smallPayload() =>
    Uint8List.fromList(List.generate(1024, (i) => i & 0xFF));

/// 1 MB of deterministic bytes.
Uint8List _largePayload() =>
    Uint8List.fromList(List.generate(1024 * 1024, (i) => i & 0xFF));

/// Hex-encoded SHA1 of [bytes] — mirrors what the adapter sends in
/// X-Bz-Content-Sha1.
String _sha1Hex(List<int> bytes) =>
    sha1.convert(bytes).toString();

B2ClientAdapter _makeAdapter() {
  SharedPreferences.setMockInitialValues({});
  final config = B2ConfigService(secureStorage: InMemorySecureStorage());
  return B2ClientAdapter(config: config);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Credential resolution ────────────────────────────────────────────────

  final keyId = Platform.environment['B2_KEY_ID'];
  final appKey = Platform.environment['B2_APP_KEY'];
  final bucketName = Platform.environment['B2_BUCKET_NAME'];

  final skip =
      (keyId == null || keyId.isEmpty ||
              appKey == null || appKey.isEmpty ||
              bucketName == null || bucketName.isEmpty)
          ? 'Set B2_KEY_ID, B2_APP_KEY, B2_BUCKET_NAME to run live tests'
          : null;

  group('Backblaze B2 Live', skip: skip, () {
    late B2ClientAdapter adapter;

    // All objects written during the test run share a common prefix so that
    // tearDownAll can sweep them in a single pass even if individual
    // cleanup steps fail.
    final testPrefix = _uniqueName('crispcloud_live_test');

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      adapter = _makeAdapter();
      // login() calls b2_authorize_account internally.
      await adapter.login(keyId!, appKey!);
    });

    tearDownAll(() async {
      // Best-effort: delete the test prefix folder, which cascades to contents.
      try {
        await adapter.deletePath('/$testPrefix/', hardDelete: true);
      } catch (_) {}
      try {
        await adapter.logout();
      } catch (_) {}
    });

    // ── Identity / capabilities ─────────────────────────────────────────────

    test('providerName is "Backblaze B2"', () {
      expect(adapter.providerName, equals('Backblaze B2'));
    });

    test('isAuthenticated is true after login', () {
      expect(adapter.isAuthenticated, isTrue);
    });

    test('userId equals the key ID', () {
      expect(adapter.userId, equals(keyId));
    });

    test('supportsVersioning is true', () {
      expect(adapter.supportsVersioning, isTrue);
    });

    test('supportsMultipart is true', () {
      expect(adapter.supportsMultipart, isTrue);
    });

    test('supportsTrash is true (b2_hide_file)', () {
      expect(adapter.supportsTrash, isTrue);
    });

    // ── Authorize account ───────────────────────────────────────────────────

    test('b2_authorize_account populates config cache', () {
      // After login the config service should have an auth token and API URL.
      final apiUrl = adapter.config.getApiUrl();
      final downloadUrl = adapter.config.getDownloadUrl();
      expect(apiUrl, isNotNull);
      expect(apiUrl, startsWith('https://'));
      expect(downloadUrl, isNotNull);
      expect(downloadUrl, startsWith('https://'));
    });

    test('accountId is populated after authorize', () {
      expect(adapter.config.accountId, isNotNull);
      expect(adapter.config.accountId, isNotEmpty);
    });

    // ── List buckets ─────────────────────────────────────────────────────────

    test('listPath("/") returns at least one bucket', () async {
      final result = await adapter.listPath('/');
      expect(result.containsKey('files'), isTrue);
      final items = result['files'] as List;
      expect(items, isNotEmpty);
    });

    test('listPath("/") contains the configured bucket', () async {
      final result = await adapter.listPath('/');
      final items = result['files'] as List;
      final found =
          items.any((f) => (f as Map)['name'] == bucketName);
      expect(found, isTrue,
          reason: 'Bucket "$bucketName" not found in root listing');
    });

    test('each bucket entry has isFolder true', () async {
      final result = await adapter.listPath('/');
      final items = result['files'] as List;
      for (final item in items) {
        expect((item as Map)['isFolder'], isTrue);
      }
    });

    // ── List bucket contents ─────────────────────────────────────────────────

    test('listPath bucket returns files and folders keys', () async {
      final result = await adapter.listPath('/$bucketName');
      expect(result.containsKey('files'), isTrue);
    });

    // ── Upload — small file with SHA1 ────────────────────────────────────────

    test('uploadFile 1KB succeeds without error', () async {
      final data = _smallPayload();
      await adapter.uploadFile(
          data, 'small_upload.bin', '/$testPrefix');
    });

    test('SHA1 of payload matches expected hex', () {
      // Verify our helper produces the same hex that the adapter will sign with.
      final data = _smallPayload();
      final hex = _sha1Hex(data);
      expect(hex.length, equals(40));
      expect(hex, matches(RegExp(r'^[0-9a-f]{40}$')));
    });

    // ── Download — round-trip ────────────────────────────────────────────────

    test('downloadFileBytes returns exact uploaded content', () async {
      final data = _smallPayload();
      final fileName = '$testPrefix/roundtrip.bin';
      await adapter.uploadFile(data, 'roundtrip.bin', '/$testPrefix');

      final downloaded = await adapter.downloadFileBytes('/$fileName');
      expect(downloaded, equals(data));
    });

    test('download length matches upload size', () async {
      final data = _smallPayload();
      final fileName = '$testPrefix/size_check.bin';
      await adapter.uploadFile(data, 'size_check.bin', '/$testPrefix');

      final downloaded = await adapter.downloadFileBytes('/$fileName');
      expect(downloaded.length, equals(data.length));
    });

    test('downloaded content SHA1 matches original', () async {
      final data = _smallPayload();
      final fileName = '$testPrefix/sha1_verify.bin';
      await adapter.uploadFile(data, 'sha1_verify.bin', '/$testPrefix');

      final downloaded = await adapter.downloadFileBytes('/$fileName');
      expect(_sha1Hex(downloaded), equals(_sha1Hex(data)));
    });

    // ── resolvePath ──────────────────────────────────────────────────────────

    test('resolvePath returns non-null for existing file', () async {
      final fileName = '$testPrefix/resolve_check.bin';
      await adapter.uploadFile(
          _smallPayload(), 'resolve_check.bin', '/$testPrefix');

      final info = await adapter.resolvePath('/$fileName');
      expect(info, isNotNull);
      expect(info!['isFolder'], isFalse);
    });

    test('resolvePath returns null for non-existent path', () async {
      final info = await adapter.resolvePath(
          '/$testPrefix/ghost_${Random().nextInt(99999)}.bin');
      expect(info, isNull);
    });

    // ── Delete (hide) ────────────────────────────────────────────────────────

    test('deletePath (hide) makes file invisible via resolvePath', () async {
      final fileName = '$testPrefix/to_hide.bin';
      await adapter.uploadFile(
          _smallPayload(), 'to_hide.bin', '/$testPrefix');

      // Soft-delete via b2_hide_file
      await adapter.deletePath('/$fileName');

      final info = await adapter.resolvePath('/$fileName');
      expect(info, isNull);
    });

    test('deletePath with hardDelete removes file version permanently',
        () async {
      final fileName = '$testPrefix/to_hard_delete.bin';
      await adapter.uploadFile(
          _smallPayload(), 'to_hard_delete.bin', '/$testPrefix');

      await adapter.deletePath('/$fileName', hardDelete: true);

      final info = await adapter.resolvePath('/$fileName');
      expect(info, isNull);
    });

    // ── Virtual folders ──────────────────────────────────────────────────────

    test('createFolderPath uploads a zero-byte placeholder with trailing slash',
        () async {
      final folderPath = '/$testPrefix/my_folder';
      await adapter.createFolderPath(folderPath);

      // The placeholder file name is the folder key with a trailing '/'.
      final info = await adapter.resolvePath('$folderPath/');
      expect(info, isNotNull);
    });

    test('upload inside a virtual folder prefix succeeds', () async {
      final folderPath = '/$testPrefix/sub_folder';
      await adapter.createFolderPath(folderPath);
      final data = _smallPayload();
      await adapter.uploadFile(data, 'nested.bin', folderPath);

      final info = await adapter.resolvePath('$folderPath/nested.bin');
      expect(info, isNotNull);
    });

    test('listPath with prefix returns only items under that prefix', () async {
      final prefix = '$testPrefix/prefix_filter';
      await adapter.uploadFile(_smallPayload(), 'a.bin', '/$prefix');
      await adapter.uploadFile(_smallPayload(), 'b.bin', '/$prefix');

      final result = await adapter.listPath('/$prefix');
      final items = result['files'] as List;
      final names = items.map((f) => (f as Map)['name'] as String).toSet();
      expect(names, containsAll({'a.bin', 'b.bin'}));
    });

    test('delete folder contents leaves prefix empty', () async {
      final prefix = '$testPrefix/sweep_folder';
      await adapter.uploadFile(_smallPayload(), 'x.bin', '/$prefix');
      await adapter.uploadFile(_smallPayload(), 'y.bin', '/$prefix');

      // Hard-delete each file under the prefix.
      final result = await adapter.listPath('/$prefix');
      final items = result['files'] as List;
      for (final item in items) {
        final path = (item as Map)['path'] as String? ?? '/$prefix/${item['name']}';
        await adapter.deletePath(path, hardDelete: true);
      }

      final after = await adapter.listPath('/$prefix');
      final remaining =
          (after['files'] as List).where((f) => (f as Map)['isFolder'] != true).toList();
      expect(remaining, isEmpty);
    });

    // ── Rename ───────────────────────────────────────────────────────────────

    test('renamePath moves file to new name', () async {
      final srcPath = '/$testPrefix/rename_src.bin';
      final dstName = 'rename_dst.bin';
      final data = _smallPayload();

      await adapter.uploadFile(data, 'rename_src.bin', '/$testPrefix');
      await adapter.renamePath(srcPath, dstName);

      final dstInfo =
          await adapter.resolvePath('/$testPrefix/$dstName');
      expect(dstInfo, isNotNull);

      final srcInfo = await adapter.resolvePath(srcPath);
      expect(srcInfo, isNull);
    });

    // ── Large file upload ────────────────────────────────────────────────────

    test('uploadFile 1MB round-trip verifies content and SHA1', () async {
      final data = _largePayload();
      final fileName = '$testPrefix/large_1mb.bin';
      await adapter.uploadFile(data, 'large_1mb.bin', '/$testPrefix');

      final downloaded = await adapter.downloadFileBytes('/$fileName');
      expect(downloaded.length, equals(data.length));
      expect(_sha1Hex(downloaded), equals(_sha1Hex(data)));
    });

    // ── Special characters ───────────────────────────────────────────────────

    test('upload and download file with spaces in filename', () async {
      final data = _smallPayload();
      final rawName = 'file with spaces.bin';
      final fileName = '$testPrefix/$rawName';

      await adapter.uploadFile(data, rawName, '/$testPrefix');

      final info = await adapter.resolvePath('/$fileName');
      expect(info, isNotNull);

      final downloaded = await adapter.downloadFileBytes('/$fileName');
      expect(downloaded, equals(data));
    });

    test('upload and download file with unicode filename', () async {
      final data = _smallPayload();
      final rawName = 'fichier_\u00e9t\u00e9.bin'; // fichier_été.bin
      final fileName = '$testPrefix/$rawName';

      await adapter.uploadFile(data, rawName, '/$testPrefix');

      final info = await adapter.resolvePath('/$fileName');
      expect(info, isNotNull);

      final downloaded = await adapter.downloadFileBytes('/$fileName');
      expect(downloaded, equals(data));
    });

    // ── Quota ─────────────────────────────────────────────────────────────────

    test('getQuota returns null (B2 does not expose quota for app keys)', () async {
      final quota = await adapter.getQuota();
      expect(quota, isNull);
    });

    // ── Logout / re-login ─────────────────────────────────────────────────────

    test('logout clears isAuthenticated', () async {
      final local = _makeAdapter();
      await local.login(keyId!, appKey!);
      expect(local.isAuthenticated, isTrue);

      await local.logout();
      expect(local.isAuthenticated, isFalse);
    });

    test('logout clears auth cache (authToken becomes null)', () async {
      final local = _makeAdapter();
      await local.login(keyId!, appKey!);
      await local.logout();
      expect(local.config.authToken, isNull);
    });

    test('logout clears userId', () async {
      final local = _makeAdapter();
      await local.login(keyId!, appKey!);
      await local.logout();
      expect(local.userId, isNull);
    });

    test('re-login after logout re-authenticates successfully', () async {
      final local = _makeAdapter();
      await local.login(keyId!, appKey!);
      await local.logout();

      await local.login(keyId!, appKey!);
      expect(local.isAuthenticated, isTrue);
      await local.logout();
    });
  });
}
