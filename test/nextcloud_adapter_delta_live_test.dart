// test/nextcloud_adapter_delta_live_test.dart
//
// Live integration tests for the ACTUAL NextcloudClientAdapter delta sync
// methods (deltaUpload, deltaDownload, fetchServerBlockMap) against the
// Nextcloud 33 instance running on localhost:8888.
//
// These tests exercise the full adapter code path — not the standalone CLI
// or raw curl commands. This is the code that CrispCloud actually runs.
//
// Run:  flutter test test/nextcloud_adapter_delta_live_test.dart --run-skipped
@Tags(['live'])

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/delta_sync_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

const _ncUrl = 'http://localhost:8888';
const _ncUser = 'admin';
const _ncPass = 'admin2026';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Upload a file via WebDAV (bypasses adapter for test setup).
Future<void> _webdavUpload(String remoteName, List<int> data) async {
  final uri = Uri.parse('$_ncUrl/remote.php/dav/files/$_ncUser/$remoteName');
  final resp = await http.put(uri, headers: {
    'Authorization': 'Basic ${_base64Auth(_ncUser, _ncPass)}',
    'Content-Type': 'application/octet-stream',
  }, body: data);
  if (resp.statusCode != 201 && resp.statusCode != 204) {
    throw Exception('WebDAV upload failed: ${resp.statusCode}');
  }
}

/// Delete a file via WebDAV.
Future<void> _webdavDelete(String remoteName) async {
  final uri = Uri.parse('$_ncUrl/remote.php/dav/files/$_ncUser/$remoteName');
  await http.delete(uri, headers: {
    'Authorization': 'Basic ${_base64Auth(_ncUser, _ncPass)}',
  });
}

/// Download a file via WebDAV.
Future<Uint8List> _webdavDownload(String remoteName) async {
  final uri = Uri.parse('$_ncUrl/remote.php/dav/files/$_ncUser/$remoteName');
  final resp = await http.get(uri, headers: {
    'Authorization': 'Basic ${_base64Auth(_ncUser, _ncPass)}',
  });
  return resp.bodyBytes;
}

String _base64Auth(String user, String pass) {
  final bytes = '${user}:${pass}'.codeUnits;
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final result = StringBuffer();
  for (var i = 0; i < bytes.length; i += 3) {
    final b0 = bytes[i];
    final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    result.write(chars[(b0 >> 2) & 0x3F]);
    result.write(chars[((b0 << 4) | (b1 >> 4)) & 0x3F]);
    result.write(i + 1 < bytes.length ? chars[((b1 << 2) | (b2 >> 6)) & 0x3F] : '=');
    result.write(i + 2 < bytes.length ? chars[b2 & 0x3F] : '=');
  }
  return result.toString();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late NextcloudClientAdapter adapter;
  late Directory tempDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    final secureStorage = InMemorySecureStorage();
    final configService = NextcloudConfigService(
      configPath: '/tmp/nc_adapter_live_test',
      secureStorage: secureStorage,
    );
    adapter = NextcloudClientAdapter(config: configService);

    // Login to the test Nextcloud instance
    await adapter.login('$_ncUser@$_ncUrl', _ncPass);

    // Create temp directory for cache
    tempDir = await Directory.systemTemp.createTemp('nc_adapter_delta_live_');
  });

  tearDown(() async {
    try { await adapter.logout(); } catch (_) {}
    try { await tempDir.delete(recursive: true); } catch (_) {}
  });

  // =========================================================================
  // Adapter state after login
  // =========================================================================
  group('Adapter login + delta sync detection', () {
    test('adapter is authenticated after login', () {
      expect(adapter.isAuthenticated, isTrue);
    });

    test('delta sync server app is auto-detected on login', () {
      expect(adapter.deltaSyncServerAppUrl, isNotNull);
      expect(adapter.deltaSyncServerAppUrl, contains('crispcloud_delta'));
    });

    test('deltaSyncEnabled defaults to false', () {
      expect(adapter.deltaSyncEnabled, isFalse);
    });
  });

  // =========================================================================
  // fetchServerBlockMap via actual adapter
  // =========================================================================
  group('fetchServerBlockMap (adapter code path)', () {
    const testFile = 'adapter-delta-blockmap.bin';
    const blockSize = 4 * 1024 * 1024;

    setUpAll(() async {
      // Upload a 12 MB file for block map tests
      final data = List<int>.generate(3 * blockSize, (i) => (i * 5 + 3) & 0xFF);
      await _webdavUpload(testFile, data);
    });

    tearDownAll(() async {
      await _webdavDelete(testFile);
    });

    test('returns block map with correct structure', () async {
      final map = await adapter.fetchServerBlockMap(testFile);
      expect(map, isNotNull);
      expect(map!.blockCount, equals(3));
      expect(map.blockSize, equals(blockSize));
      expect(map.totalSize, equals(3 * blockSize));
      expect(map.signatures.length, equals(3));
    });

    test('block map hashes match DeltaSyncService computation', () async {
      // Download the file and compute locally
      final data = await _webdavDownload(testFile);
      final tmpFile = File('${tempDir.path}/verify.bin');
      await tmpFile.writeAsBytes(data);

      final svc = DeltaSyncService();
      final localMap = await svc.computeBlockMap(tmpFile.path);
      final serverMap = await adapter.fetchServerBlockMap(testFile);

      expect(serverMap, isNotNull);
      for (int i = 0; i < localMap.blockCount; i++) {
        expect(localMap.signatures[i].weakHash,
            equals(serverMap!.signatures[i].weakHash),
            reason: 'Block $i weak hash mismatch');
        expect(localMap.signatures[i].strongHash,
            equals(serverMap.signatures[i].strongHash),
            reason: 'Block $i strong hash mismatch');
      }
    });

    test('returns null for non-existent file', () async {
      final map = await adapter.fetchServerBlockMap('nonexistent-xyz-${DateTime.now().microsecondsSinceEpoch}.bin');
      expect(map, isNull);
    });
  });

  // =========================================================================
  // deltaUpload via actual adapter
  // =========================================================================
  group('deltaUpload (adapter code path)', () {
    const testFile = 'adapter-delta-upload.bin';
    const blockSize = 4 * 1024 * 1024;

    test('full round-trip: upload → modify → deltaUpload → verify', () async {
      adapter.deltaSyncEnabled = true;

      // Step 1: Upload original 12 MB file via WebDAV
      final originalData = List<int>.generate(
          3 * blockSize, (i) => (i * 7 + 11) & 0xFF);
      await _webdavUpload(testFile, originalData);

      // Step 2: Modify block 1 locally
      final modifiedData = List<int>.from(originalData);
      for (int i = blockSize; i < 2 * blockSize; i++) {
        modifiedData[i] = 0x00; // zero out block 1
      }
      final localFile = File('${tempDir.path}/modified.bin');
      await localFile.writeAsBytes(modifiedData);

      // Step 3: Delta upload via adapter
      final result = await adapter.deltaUpload(
        localFile.path,
        testFile,
        cacheDir: tempDir.path,
      );

      expect(result, isNotNull, reason: 'deltaUpload should return DeltaResult');
      expect(result!.changedBlocks, equals([1]),
          reason: 'Only block 1 should be changed');
      expect(result.changedBlocks.length, equals(1));
      expect(result.savingsPercent, closeTo(66.7, 0.1));

      // Step 4: Download from server and verify byte-for-byte
      final downloaded = await _webdavDownload(testFile);
      expect(downloaded.length, equals(modifiedData.length),
          reason: 'Downloaded size should match');

      // Verify block 0 preserved
      for (int i = 0; i < blockSize; i++) {
        if (downloaded[i] != modifiedData[i]) {
          fail('Block 0 byte $i mismatch: ${downloaded[i]} != ${modifiedData[i]}');
        }
      }
      // Verify block 1 updated
      for (int i = blockSize; i < 2 * blockSize; i++) {
        expect(downloaded[i], equals(0x00),
            reason: 'Block 1 should be all zeros');
      }
      // Verify block 2 preserved
      for (int i = 2 * blockSize; i < 3 * blockSize; i++) {
        if (downloaded[i] != modifiedData[i]) {
          fail('Block 2 byte $i mismatch: ${downloaded[i]} != ${modifiedData[i]}');
        }
      }

      // Cleanup
      await _webdavDelete(testFile);
    });

    test('returns null when deltaSyncEnabled is false', () async {
      adapter.deltaSyncEnabled = false;
      final localFile = File('${tempDir.path}/disabled.bin');
      await localFile.writeAsBytes(List.filled(12 * 1024 * 1024, 0x42));

      final result = await adapter.deltaUpload(localFile.path, 'any.bin');
      expect(result, isNull);
    });

    test('returns null when file is too small', () async {
      adapter.deltaSyncEnabled = true;
      final localFile = File('${tempDir.path}/small.bin');
      await localFile.writeAsBytes(List.filled(1024, 0x42));

      final result = await adapter.deltaUpload(localFile.path, 'any.bin');
      expect(result, isNull);
    });

    test('identical file returns empty changed list', () async {
      adapter.deltaSyncEnabled = true;

      // Upload a file
      final data = List<int>.generate(3 * blockSize, (i) => (i * 3) & 0xFF);
      const identicalFile = 'adapter-delta-identical.bin';
      await _webdavUpload(identicalFile, data);

      // Write same data locally
      final localFile = File('${tempDir.path}/identical.bin');
      await localFile.writeAsBytes(data);

      // Delta upload should detect no changes
      final result = await adapter.deltaUpload(
        localFile.path,
        identicalFile,
        cacheDir: tempDir.path,
      );

      expect(result, isNotNull);
      expect(result!.changedBlocks, isEmpty,
          reason: 'Identical file should have no changed blocks');
      expect(result.savingsPercent, equals(100.0));

      await _webdavDelete(identicalFile);
    });
  });

  // =========================================================================
  // deltaDownload via actual adapter
  // =========================================================================
  group('deltaDownload (adapter code path)', () {
    const testFile = 'adapter-delta-download.bin';
    const blockSize = 4 * 1024 * 1024;

    test('download preserves unchanged blocks', () async {
      adapter.deltaSyncEnabled = true;

      // Step 1: Create original file on server and locally
      final originalData = List<int>.generate(
          3 * blockSize, (i) => (i * 13 + 7) & 0xFF);
      await _webdavUpload(testFile, originalData);
      final localFile = File('${tempDir.path}/download-test.bin');
      await localFile.writeAsBytes(originalData);

      // Step 2: Modify block 2 on the server (upload full modified file)
      final modifiedData = List<int>.from(originalData);
      for (int i = 2 * blockSize; i < 3 * blockSize; i++) {
        modifiedData[i] = 0xEE;
      }
      await _webdavUpload(testFile, modifiedData);

      // Step 3: Delta download — should only fetch block 2
      final result = await adapter.deltaDownload(
        testFile,
        localFile.path,
        cacheDir: tempDir.path,
      );

      expect(result, isNotNull, reason: 'deltaDownload should return DeltaResult');
      expect(result!.changedBlocks, equals([2]),
          reason: 'Only block 2 should be changed');

      // Step 4: Verify local file
      final resultBytes = await localFile.readAsBytes();

      // Block 0 preserved
      for (int i = 0; i < blockSize; i++) {
        expect(resultBytes[i], equals(originalData[i]),
            reason: 'Block 0 byte $i should be preserved');
      }
      // Block 1 preserved
      for (int i = blockSize; i < 2 * blockSize; i++) {
        expect(resultBytes[i], equals(originalData[i]),
            reason: 'Block 1 byte $i should be preserved');
      }
      // Block 2 updated
      for (int i = 2 * blockSize; i < 3 * blockSize; i++) {
        expect(resultBytes[i], equals(0xEE),
            reason: 'Block 2 should be 0xEE');
      }

      await _webdavDelete(testFile);
    });

    test('returns null when deltaSyncEnabled is false', () async {
      adapter.deltaSyncEnabled = false;
      final localFile = File('${tempDir.path}/disabled-dl.bin');
      await localFile.writeAsBytes(List.filled(12 * 1024 * 1024, 0x42));

      final result = await adapter.deltaDownload('any.bin', localFile.path);
      expect(result, isNull);
    });

    test('returns null when local file does not exist', () async {
      adapter.deltaSyncEnabled = true;
      final result = await adapter.deltaDownload(
          'any.bin', '${tempDir.path}/nonexistent.bin');
      expect(result, isNull);
    });
  });

  // =========================================================================
  // Edge cases
  // =========================================================================
  group('Delta sync edge cases', () {
    const blockSize = 4 * 1024 * 1024;

    test('file with all blocks changed uploads all blocks', () async {
      adapter.deltaSyncEnabled = true;
      const testFile = 'adapter-delta-allchanged.bin';

      // Upload original
      final original = List<int>.filled(3 * blockSize, 0xAA);
      await _webdavUpload(testFile, original);

      // Create completely different local file
      final modified = List<int>.filled(3 * blockSize, 0xBB);
      final localFile = File('${tempDir.path}/allchanged.bin');
      await localFile.writeAsBytes(modified);

      final result = await adapter.deltaUpload(
        localFile.path,
        testFile,
        cacheDir: tempDir.path,
      );

      expect(result, isNotNull);
      expect(result!.changedBlocks.length, equals(3));
      expect(result.savingsPercent, equals(0.0));

      // Verify server has new data
      final downloaded = await _webdavDownload(testFile);
      expect(downloaded.every((b) => b == 0xBB), isTrue);

      await _webdavDelete(testFile);
    });

    test('block map cached after deltaUpload can be used for next sync', () async {
      adapter.deltaSyncEnabled = true;
      const testFile = 'adapter-delta-cache-reuse.bin';

      // Upload original
      final original = List<int>.generate(3 * blockSize, (i) => (i * 2) & 0xFF);
      await _webdavUpload(testFile, original);

      // First delta upload (block 0 changed)
      final mod1 = List<int>.from(original);
      for (int i = 0; i < blockSize; i++) mod1[i] = 0xFF;
      final localFile = File('${tempDir.path}/cache-reuse.bin');
      await localFile.writeAsBytes(mod1);

      final result1 = await adapter.deltaUpload(
        localFile.path,
        testFile,
        cacheDir: tempDir.path,
      );
      expect(result1, isNotNull);
      expect(result1!.changedBlocks, equals([0]));

      // Second delta upload (block 2 changed) — should reuse cached map
      final mod2 = List<int>.from(mod1);
      for (int i = 2 * blockSize; i < 3 * blockSize; i++) mod2[i] = 0xEE;
      await localFile.writeAsBytes(mod2);

      final result2 = await adapter.deltaUpload(
        localFile.path,
        testFile,
        cacheDir: tempDir.path,
      );
      expect(result2, isNotNull);
      expect(result2!.changedBlocks, equals([2]));

      // Verify final state
      final downloaded = await _webdavDownload(testFile);
      // Block 0 = 0xFF, Block 1 = original pattern, Block 2 = 0xEE
      expect(downloaded[0], equals(0xFF));
      expect(downloaded[blockSize], equals(original[blockSize]));
      expect(downloaded[2 * blockSize], equals(0xEE));

      await _webdavDelete(testFile);
    });
  });
}
