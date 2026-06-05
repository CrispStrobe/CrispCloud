// test/azure_blob_live_test.dart
//
// Live integration tests for Azure Blob Storage adapter.
//
// Requires environment variables:
//   AZURE_ACCOUNT_NAME — Storage account name
//   AZURE_ACCOUNT_KEY  — Base64-encoded account key (SharedKey auth)
//   AZURE_CONTAINER    — Container to use for tests (must already exist)
//
// Optional:
//   AZURE_SAS_TOKEN — SAS token (raw query string or full SAS URL) for
//                     additional SAS-auth tests. Requires AZURE_ACCOUNT_NAME
//                     and AZURE_CONTAINER to also be set.
//
// Run: flutter test --tags live test/azure_blob_live_test.dart

@Tags(['live'])
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/azure_blob_adapter.dart';
import 'package:crisp_cloud/services/azure_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Generate unique name to prevent cross-run collisions.
String _uniqueName(String base) =>
    '${base}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

/// 1 KB of deterministic bytes (0x00–0xFF repeated).
Uint8List _smallPayload() =>
    Uint8List.fromList(List.generate(1024, (i) => i & 0xFF));

/// 1 MB of deterministic bytes.
Uint8List _largePayload() =>
    Uint8List.fromList(List.generate(1024 * 1024, (i) => i & 0xFF));

AzureBlobAdapter _makeAdapter() {
  SharedPreferences.setMockInitialValues({});
  final config = AzureConfigService(secureStorage: InMemorySecureStorage());
  return AzureBlobAdapter(config: config);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── Credential resolution ────────────────────────────────────────────────

  final accountName = Platform.environment['AZURE_ACCOUNT_NAME'];
  final accountKey = Platform.environment['AZURE_ACCOUNT_KEY'];
  final containerName = Platform.environment['AZURE_CONTAINER'];
  final sasToken = Platform.environment['AZURE_SAS_TOKEN'];

  final sharedKeySkip =
      (accountName == null || accountName.isEmpty ||
              accountKey == null || accountKey.isEmpty ||
              containerName == null || containerName.isEmpty)
          ? 'Set AZURE_ACCOUNT_NAME, AZURE_ACCOUNT_KEY, AZURE_CONTAINER to run live tests'
          : null;

  final sasSkip = (sharedKeySkip != null ||
          sasToken == null || sasToken.isEmpty)
      ? 'Set AZURE_SAS_TOKEN (plus AZURE_ACCOUNT_NAME / AZURE_CONTAINER) to run SAS live tests'
      : null;

  // ── SharedKey group ───────────────────────────────────────────────────────

  group('Azure Blob Live — SharedKey auth', skip: sharedKeySkip, () {
    late AzureBlobAdapter adapter;
    // All blobs created during the test suite are prefixed so tearDownAll can
    // sweep them even if individual cleanup steps fail.
    final testPrefix = _uniqueName('crispcloud_live_test');
    final containerPath = '/$containerName';

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      adapter = _makeAdapter();
      await adapter.loginWithKey(
        accountName: accountName!,
        accountKey: accountKey!,
        container: containerName,
      );
    });

    tearDownAll(() async {
      // Best-effort cleanup: delete everything under our test prefix.
      try {
        await adapter.deletePath('$containerPath/$testPrefix/');
      } catch (_) {}
      try {
        await adapter.logout();
      } catch (_) {}
    });

    // ── Identity / capabilities ─────────────────────────────────────────────

    test('providerName is "Azure Blob"', () {
      expect(adapter.providerName, equals('Azure Blob'));
    });

    test('isAuthenticated is true after loginWithKey', () {
      expect(adapter.isAuthenticated, isTrue);
    });

    test('userId equals the account name', () {
      expect(adapter.userId, equals(accountName));
    });

    test('bucketId equals the configured container', () {
      expect(adapter.bucketId, equals(containerName));
    });

    test('supportsServerSideCopy is true', () {
      expect(adapter.supportsServerSideCopy, isTrue);
    });

    test('supportsStreaming is true', () {
      expect(adapter.supportsStreaming, isTrue);
    });

    // ── Root listing ────────────────────────────────────────────────────────

    test('listPath("/") returns containers at root', () async {
      final result = await adapter.listPath('/');
      expect(result, containsPair('folders', isA<List>()));
      final folders = result['folders'] as List;
      // The configured container must be visible among the listed containers.
      final found =
          folders.any((f) => (f as Map)['name'] == containerName);
      expect(found, isTrue,
          reason: 'Container "$containerName" not found in root listing');
    });

    test('listPath root has no "files" entries at service level', () async {
      final result = await adapter.listPath('/');
      final files = result['files'] as List? ?? [];
      expect(files, isEmpty);
    });

    // ── Container listing ───────────────────────────────────────────────────

    test('listPath container returns files and folders keys', () async {
      final result = await adapter.listPath(containerPath);
      expect(result.containsKey('files'), isTrue);
      expect(result.containsKey('folders'), isTrue);
    });

    test('listPath container path key starts with /$containerName', () async {
      final result = await adapter.listPath(containerPath);
      expect((result['path'] as String).startsWith('/$containerName'), isTrue);
    });

    // ── Upload — small file ──────────────────────────────────────────────────

    test('uploadFile 1KB succeeds without error', () async {
      final data = _smallPayload();
      final name = '$testPrefix/small_upload.bin';
      await adapter.uploadFile(data, name, containerPath);
      // If no exception was thrown, the upload succeeded.
    });

    // ── Download — round-trip ───────────────────────────────────────────────

    test('downloadFileBytes returns the exact uploaded content', () async {
      final data = _smallPayload();
      final blobName = '$testPrefix/roundtrip.bin';
      await adapter.uploadFile(data, blobName, containerPath);

      final downloaded =
          await adapter.downloadFileBytes('$containerPath/$blobName');
      expect(downloaded, equals(data));
    });

    test('downloadFileBytes length matches uploaded size', () async {
      final data = _smallPayload();
      final blobName = '$testPrefix/size_check.bin';
      await adapter.uploadFile(data, blobName, containerPath);

      final downloaded =
          await adapter.downloadFileBytes('$containerPath/$blobName');
      expect(downloaded.length, equals(data.length));
    });

    // ── resolvePath ──────────────────────────────────────────────────────────

    test('resolvePath returns non-null for existing blob', () async {
      final blobName = '$testPrefix/resolve_check.bin';
      await adapter.uploadFile(_smallPayload(), blobName, containerPath);

      final info =
          await adapter.resolvePath('$containerPath/$blobName');
      expect(info, isNotNull);
      expect(info!['isFolder'], isFalse);
    });

    test('resolvePath returns null for non-existent blob', () async {
      final info = await adapter.resolvePath(
          '$containerPath/does_not_exist_${Random().nextInt(99999)}.bin');
      expect(info, isNull);
    });

    test('resolvePath for container returns isFolder true', () async {
      final info = await adapter.resolvePath(containerPath);
      expect(info, isNotNull);
      expect(info!['isFolder'], isTrue);
    });

    // ── Rename ──────────────────────────────────────────────────────────────

    test('renamePath moves blob to new name', () async {
      final original = '$testPrefix/before_rename.bin';
      final renamed = '$testPrefix/after_rename.bin';

      await adapter.uploadFile(_smallPayload(), original, containerPath);
      await adapter.renamePath('$containerPath/$original', 'after_rename.bin');

      final found = await adapter.resolvePath('$containerPath/$renamed');
      expect(found, isNotNull);

      // Original should be gone
      final old = await adapter.resolvePath('$containerPath/$original');
      expect(old, isNull);
    });

    // ── Copy ────────────────────────────────────────────────────────────────

    test('copyPath produces an independent copy of the blob', () async {
      final src = '$testPrefix/copy_src.bin';
      final dst = '$testPrefix/copy_dst.bin';
      final data = _smallPayload();

      await adapter.uploadFile(data, src, containerPath);
      await adapter.copyPath(
          '$containerPath/$src', '$containerPath/$dst');

      // Both should exist
      final srcInfo = await adapter.resolvePath('$containerPath/$src');
      final dstInfo = await adapter.resolvePath('$containerPath/$dst');
      expect(srcInfo, isNotNull);
      expect(dstInfo, isNotNull);

      // Content of the copy must match
      final copied =
          await adapter.downloadFileBytes('$containerPath/$dst');
      expect(copied, equals(data));
    });

    // ── Delete ──────────────────────────────────────────────────────────────

    test('deletePath removes a blob', () async {
      final blobName = '$testPrefix/to_delete.bin';
      await adapter.uploadFile(_smallPayload(), blobName, containerPath);

      await adapter.deletePath('$containerPath/$blobName');

      final info = await adapter.resolvePath('$containerPath/$blobName');
      expect(info, isNull);
    });

    test('deletePath on non-existent blob throws', () async {
      await expectLater(
        adapter.deletePath(
            '$containerPath/ghost_${Random().nextInt(99999)}.bin'),
        throwsException,
      );
    });

    // ── Virtual folders ──────────────────────────────────────────────────────

    test('createFolderPath is a no-op (does not throw)', () async {
      // Azure has no real folder objects; the method must complete silently.
      await adapter.createFolderPath('$containerPath/$testPrefix/fake_folder');
    });

    test('upload inside a virtual folder prefix succeeds', () async {
      final folderPrefix = '$testPrefix/virtual_folder';
      final data = _smallPayload();
      await adapter.uploadFile(
          data, 'file_in_folder.bin', '$containerPath/$folderPrefix/');

      final info = await adapter.resolvePath(
          '$containerPath/$folderPrefix/file_in_folder.bin');
      expect(info, isNotNull);
    });

    test('listPath with prefix filter shows only blobs under that prefix',
        () async {
      final prefix = '$testPrefix/prefix_filter';
      await adapter.uploadFile(
          _smallPayload(), 'a.bin', '$containerPath/$prefix/');
      await adapter.uploadFile(
          _smallPayload(), 'b.bin', '$containerPath/$prefix/');

      final result =
          await adapter.listPath('$containerPath/$prefix');
      final files = result['files'] as List;
      final fileNames =
          files.map((f) => (f as Map)['name'] as String).toSet();
      expect(fileNames, containsAll({'a.bin', 'b.bin'}));
    });

    test('delete by prefix sweeps all blobs under a virtual folder', () async {
      final prefix = '$testPrefix/sweep_folder';
      await adapter.uploadFile(
          _smallPayload(), 'x.bin', '$containerPath/$prefix/');
      await adapter.uploadFile(
          _smallPayload(), 'y.bin', '$containerPath/$prefix/');

      // deletePath with trailing '/' triggers prefix deletion
      await adapter.deletePath('$containerPath/$prefix/');

      final result =
          await adapter.listPath('$containerPath/$prefix');
      final files = result['files'] as List;
      expect(files, isEmpty);
    });

    // ── Blob tier ────────────────────────────────────────────────────────────

    test('setBlobTier to Cool completes without error', () async {
      final blobName = '$testPrefix/tier_test.bin';
      await adapter.uploadFile(_smallPayload(), blobName, containerPath);

      // setBlobTier may return 202 (Accepted) on GPv2 accounts; it is allowed
      // to throw only if the account genuinely does not support tiering.
      try {
        await adapter.setBlobTier(
            '$containerPath/$blobName', AzureBlobTier.cool);
        // Success — no assertion needed beyond no exception.
      } catch (e) {
        // Some storage account types (e.g. classic) do not support tiering;
        // skip rather than fail in that case.
        if (e.toString().contains('BlobAccessTierNotSupported') ||
            e.toString().contains('409')) {
          markTestSkipped('Account does not support blob tiering');
        } else {
          rethrow;
        }
      }
    });

    test('setBlobTier to Hot restores tier', () async {
      final blobName = '$testPrefix/tier_restore.bin';
      await adapter.uploadFile(_smallPayload(), blobName, containerPath);

      try {
        await adapter.setBlobTier(
            '$containerPath/$blobName', AzureBlobTier.hot);
      } catch (e) {
        if (e.toString().contains('BlobAccessTierNotSupported') ||
            e.toString().contains('409')) {
          markTestSkipped('Account does not support blob tiering');
        } else {
          rethrow;
        }
      }
    });

    // ── Upload — large file ──────────────────────────────────────────────────

    test('uploadFile 1MB round-trip verifies content', () async {
      final data = _largePayload();
      final blobName = '$testPrefix/large_1mb.bin';
      await adapter.uploadFile(data, blobName, containerPath);

      final downloaded =
          await adapter.downloadFileBytes('$containerPath/$blobName');
      expect(downloaded.length, equals(data.length));
      expect(downloaded, equals(data));
    });

    // ── Special characters ───────────────────────────────────────────────────

    test('upload and download blob with spaces in filename', () async {
      final blobName = '$testPrefix/file with spaces.bin';
      final data = _smallPayload();
      await adapter.uploadFile(data, 'file with spaces.bin',
          '$containerPath/$testPrefix');

      final info =
          await adapter.resolvePath('$containerPath/$blobName');
      expect(info, isNotNull);

      final downloaded =
          await adapter.downloadFileBytes('$containerPath/$blobName');
      expect(downloaded, equals(data));
    });

    test('upload and download blob with unicode filename', () async {
      final blobName = '$testPrefix/fichier_été_\u00e9\u00e0.bin';
      final data = _smallPayload();
      await adapter.uploadFile(
          data, 'fichier_été_\u00e9\u00e0.bin', '$containerPath/$testPrefix');

      final info =
          await adapter.resolvePath('$containerPath/$blobName');
      expect(info, isNotNull);

      final downloaded =
          await adapter.downloadFileBytes('$containerPath/$blobName');
      expect(downloaded, equals(data));
    });

    // ── Streaming ────────────────────────────────────────────────────────────

    test('downloadStream yields the correct bytes', () async {
      final data = _smallPayload();
      final blobName = '$testPrefix/stream_download.bin';
      await adapter.uploadFile(data, blobName, containerPath);

      final chunks = <List<int>>[];
      await for (final chunk
          in adapter.downloadStream('$containerPath/$blobName')) {
        chunks.add(chunk);
      }
      final assembled = Uint8List.fromList(chunks.expand((c) => c).toList());
      expect(assembled, equals(data));
    });

    test('uploadStream and downloadFileBytes round-trip', () async {
      final data = _smallPayload();
      final blobName = '$testPrefix/stream_upload.bin';
      final stream = Stream.value(data.toList());
      await adapter.uploadStream(
          stream, data.length, blobName, containerPath);

      final downloaded =
          await adapter.downloadFileBytes('$containerPath/$blobName');
      expect(downloaded, equals(data));
    });

    // ── Logout / re-login ────────────────────────────────────────────────────

    test('logout clears isAuthenticated', () async {
      final local = _makeAdapter();
      await local.loginWithKey(
        accountName: accountName!,
        accountKey: accountKey!,
        container: containerName,
      );
      expect(local.isAuthenticated, isTrue);

      await local.logout();
      expect(local.isAuthenticated, isFalse);
      expect(local.userId, isNull);
    });

    test('logout clears bucketId', () async {
      final local = _makeAdapter();
      await local.loginWithKey(
        accountName: accountName!,
        accountKey: accountKey!,
        container: containerName,
      );
      await local.logout();
      expect(local.bucketId, isNull);
    });

    test('re-login after logout succeeds', () async {
      final local = _makeAdapter();
      await local.loginWithKey(
        accountName: accountName!,
        accountKey: accountKey!,
        container: containerName,
      );
      await local.logout();

      await local.loginWithKey(
        accountName: accountName,
        accountKey: accountKey!,
        container: containerName,
      );
      expect(local.isAuthenticated, isTrue);
      await local.logout();
    });

    test('operations after logout throw or behave safely', () async {
      final local = _makeAdapter();
      await local.loginWithKey(
        accountName: accountName!,
        accountKey: accountKey!,
        container: containerName,
      );
      await local.logout();

      // Attempting to list after logout should throw (StateError or similar).
      await expectLater(
        local.listPath('/'),
        throwsA(anything),
      );
    });
  });

  // ── SAS token group ───────────────────────────────────────────────────────

  group('Azure Blob Live — SAS token auth', skip: sasSkip, () {
    late AzureBlobAdapter adapter;
    final testPrefix = _uniqueName('crispcloud_sas_test');
    final containerPath = '/$containerName';

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      adapter = _makeAdapter();
      await adapter.loginWithSas(
        accountName: accountName!,
        sasTokenOrUrl: sasToken!,
        container: containerName,
      );
    });

    tearDownAll(() async {
      try {
        await adapter.deletePath('$containerPath/$testPrefix/');
      } catch (_) {}
      try {
        await adapter.logout();
      } catch (_) {}
    });

    test('isAuthenticated is true after loginWithSas', () {
      expect(adapter.isAuthenticated, isTrue);
    });

    test('providerName is "Azure Blob" under SAS auth', () {
      expect(adapter.providerName, equals('Azure Blob'));
    });

    test('listPath container succeeds with SAS token', () async {
      final result = await adapter.listPath(containerPath);
      expect(result.containsKey('files'), isTrue);
      expect(result.containsKey('folders'), isTrue);
    });

    test('SAS upload and download round-trip', () async {
      final data = _smallPayload();
      final blobName = '$testPrefix/sas_roundtrip.bin';
      await adapter.uploadFile(data, blobName, containerPath);

      final downloaded =
          await adapter.downloadFileBytes('$containerPath/$blobName');
      expect(downloaded, equals(data));
    });

    test('SAS delete removes blob', () async {
      final blobName = '$testPrefix/sas_delete.bin';
      await adapter.uploadFile(_smallPayload(), blobName, containerPath);

      await adapter.deletePath('$containerPath/$blobName');
      final info = await adapter.resolvePath('$containerPath/$blobName');
      expect(info, isNull);
    });

    test('SAS logout clears auth state', () async {
      final local = _makeAdapter();
      await local.loginWithSas(
        accountName: accountName!,
        sasTokenOrUrl: sasToken!,
        container: containerName,
      );
      expect(local.isAuthenticated, isTrue);

      await local.logout();
      expect(local.isAuthenticated, isFalse);
    });
  });
}
