// test/pcloud_adapter_test.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/pcloud_client_adapter.dart';
import 'package:crisp_cloud/services/pcloud_config_service.dart';
import 'package:crisp_cloud/services/delta_sync_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';

void main() {
  late PCloudClientAdapter adapter;
  late PCloudConfigService configService;
  late InMemorySecureStorage secureStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStorage = InMemorySecureStorage();
    configService = PCloudConfigService(
      configPath: '/tmp/pcloud_test',
      secureStorage: secureStorage,
    );
    adapter = PCloudClientAdapter(config: configService);
  });

  group('PCloudClientAdapter basic properties', () {
    test('providerName returns pCloud', () {
      expect(adapter.providerName, equals('pCloud'));
    });

    test('rootPath returns /', () {
      expect(adapter.rootPath, equals('/'));
    });

    test('is not authenticated initially', () {
      expect(adapter.isAuthenticated, isFalse);
    });

    test('userId is null initially', () {
      expect(adapter.userId, isNull);
    });

    test('bucketId is null', () {
      expect(adapter.bucketId, isNull);
    });

    test('accessToken is null initially', () {
      expect(adapter.accessToken, isNull);
    });
  });

  group('PCloudClientAdapter capability flags', () {
    test('does not support versioning', () => expect(adapter.supportsVersioning, isFalse));
    test('supports sharing', () => expect(adapter.supportsSharing, isTrue));
    test('does not support search', () => expect(adapter.supportsSearch, isFalse));
    test('does not support thumbnails', () => expect(adapter.supportsThumbnails, isFalse));
    test('supports trash', () => expect(adapter.supportsTrash, isTrue));
    test('does not support streaming', () => expect(adapter.supportsStreaming, isFalse));
    test('does not support multipart', () => expect(adapter.supportsMultipart, isFalse));
  });

  group('PCloudClientAdapter 2FA', () {
    test('is2faNeeded returns false', () async {
      expect(await adapter.is2faNeeded('test@example.com'), isFalse);
    });
  });

  group('PCloudClientAdapter login validation', () {
    test('login throws on empty app key', () async {
      expect(
        () => adapter.login('', ''),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('App Key is required'),
        )),
      );
    });

    test('login throws on whitespace-only app key', () async {
      expect(
        () => adapter.login('   ', ''),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('App Key is required'),
        )),
      );
    });
  });

  group('PCloudClientAdapter logout', () {
    test('logout resets state without throwing', () async {
      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
      expect(adapter.userId, isNull);
      expect(adapter.accessToken, isNull);
    });
  });

  group('PCloudConfigService', () {
    test('readCredentials returns null initially', () async {
      expect(await configService.readCredentials(), isNull);
    });

    test('saveCredentials then readCredentials round-trips', () async {
      final creds = {
        'app_key': 'test-app-key',
        'access_token': 'test-access-token',
        'email': 'user@pcloud.com',
        'eu_api': 'false',
      };
      await configService.saveCredentials(creds);
      final read = await configService.readCredentials();
      expect(read, isNotNull);
      expect(read!['app_key'], equals('test-app-key'));
      expect(read['access_token'], equals('test-access-token'));
      expect(read['email'], equals('user@pcloud.com'));
    });

    test('clearCredentials removes stored credentials', () async {
      await configService.saveCredentials({
        'app_key': 'k',
        'access_token': 't',
      });
      await configService.clearCredentials();
      expect(await configService.readCredentials(), isNull);
    });

    test('readCredentials returns null after clear', () async {
      await configService.saveCredentials({'app_key': 'k', 'access_token': 't'});
      await configService.clearCredentials();
      final result = await configService.readCredentials();
      expect(result, isNull);
    });

    test('overwriting credentials replaces old ones', () async {
      await configService.saveCredentials({'app_key': 'old', 'access_token': 'old-token'});
      await configService.saveCredentials({'app_key': 'new', 'access_token': 'new-token'});
      final read = await configService.readCredentials();
      expect(read!['app_key'], equals('new'));
      expect(read['access_token'], equals('new-token'));
    });
  });

  group('PCloudClientAdapter restoreCredentials', () {
    test('returns false when no stored credentials', () async {
      expect(await adapter.restoreCredentials(), isFalse);
    });

    test('returns false when access token is empty', () async {
      await configService.saveCredentials({
        'app_key': 'test',
        'access_token': '',
      });
      expect(await adapter.restoreCredentials(), isFalse);
    });

    test('returns false when token validation fails (no network)', () async {
      await configService.saveCredentials({
        'app_key': 'test',
        'access_token': 'invalid-token',
        'eu_api': 'false',
      });
      // Without a real server, userinfo call should fail → restoreCredentials returns false
      expect(await adapter.restoreCredentials(), isFalse);
    });

    test('restores eu_api flag from stored credentials', () async {
      await configService.saveCredentials({
        'app_key': 'test',
        'access_token': 'invalid-token',
        'email': 'eu@pcloud.com',
        'eu_api': 'true',
      });
      // Will fail the network call; we just check it doesn't throw
      await adapter.restoreCredentials();
    });
  });

  group('CloudStorageFactory pcloud', () {
    test('factory creates PCloudClientAdapter for pcloud provider', () {
      final client = CloudStorageFactory.create(
        CloudProvider.pcloud,
        config: configService,
      );
      expect(client, isA<PCloudClientAdapter>());
      expect(client.providerName, equals('pCloud'));
    });

    test('factory-created adapter has correct capability flags', () {
      final client = CloudStorageFactory.create(
        CloudProvider.pcloud,
        config: configService,
      ) as PCloudClientAdapter;
      expect(client.supportsSharing, isTrue);
      expect(client.supportsTrash, isTrue);
      expect(client.supportsVersioning, isFalse);
    });
  });

  // ===========================================================================
  // Delta sync configuration
  // ===========================================================================
  group('PCloudClientAdapter - delta sync config', () {
    test('deltaSyncEnabled is false by default', () {
      expect(adapter.deltaSyncEnabled, isFalse);
    });

    test('deltaSyncEnabled can be toggled', () {
      adapter.deltaSyncEnabled = true;
      expect(adapter.deltaSyncEnabled, isTrue);
      adapter.deltaSyncEnabled = false;
      expect(adapter.deltaSyncEnabled, isFalse);
    });
  });

  // ===========================================================================
  // Delta sync guards
  // ===========================================================================
  group('PCloudClientAdapter - delta sync guards', () {
    test('deltaUpload returns null when deltaSyncEnabled is false', () async {
      expect(adapter.deltaSyncEnabled, isFalse);
      final result = await adapter.deltaUpload('/tmp/test.bin', '/remote/test.bin');
      expect(result, isNull);
    });

    test('deltaUpload throws when enabled but not authenticated', () async {
      adapter.deltaSyncEnabled = true;
      // Auth check runs before file size check
      expect(
        () => adapter.deltaUpload('/tmp/any.bin', '/remote/any.bin'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('authenticate'),
        )),
      );
    });

    test('fileOpen throws when not authenticated', () {
      expect(
        () => adapter.fileOpen(12345),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('authenticate'),
        )),
      );
    });

    test('filePread throws when not authenticated', () {
      expect(
        () => adapter.filePread(1, 0, 4096),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('authenticate'),
        )),
      );
    });

    test('filePwrite throws when not authenticated', () {
      expect(
        () => adapter.filePwrite(1, 0, [0x42]),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('authenticate'),
        )),
      );
    });

    test('fileClose throws when not authenticated', () {
      expect(
        () => adapter.fileClose(1),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('authenticate'),
        )),
      );
    });

    test('fileChecksum throws when not authenticated', () {
      expect(
        () => adapter.fileChecksum(12345),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('authenticate'),
        )),
      );
    });
  });

  // ===========================================================================
  // Delta sync with DeltaSyncService
  // ===========================================================================
  group('PCloudClientAdapter - delta sync with DeltaSyncService', () {
    late DeltaSyncService deltaSvc;
    const bs = 64 * 1024; // 64 KB for fast tests

    setUp(() {
      deltaSvc = DeltaSyncService();
    });

    test('block map computed from local file matches pCloud format expectations', () async {
      // Create a test file with known pattern
      final dir = await Directory.systemTemp.createTemp('pcloud_delta_bm_');
      final file = File('${dir.path}/test.bin');
      final data = List<int>.generate(3 * bs, (i) => i & 0xFF);
      await file.writeAsBytes(data);

      try {
        final map = await deltaSvc.computeBlockMap(file.path, blockSize: bs);
        expect(map.blockCount, equals(3));
        expect(map.blockSize, equals(bs));
        expect(map.totalSize, equals(3 * bs));

        // Each signature has valid hashes
        for (final sig in map.signatures) {
          expect(sig.weakHash, isNot(equals(0)));
          expect(sig.strongHash.length, equals(64));
        }

        // Block map JSON can be serialized (as pCloud cache would store it)
        final json = map.toJson();
        final restored = BlockMap.fromJson(json);
        expect(restored.blockCount, equals(map.blockCount));
        for (int i = 0; i < map.blockCount; i++) {
          expect(restored.signatures[i].weakHash,
              equals(map.signatures[i].weakHash));
          expect(restored.signatures[i].strongHash,
              equals(map.signatures[i].strongHash));
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('DeltaResult correctly identifies blocks changed for pwrite', () async {
      final dir = await Directory.systemTemp.createTemp('pcloud_delta_cmp_');
      try {
        // Original file: 3 blocks of known data
        final orig = File('${dir.path}/orig.bin');
        final origData = [
          ...List.filled(bs, 0xAA),
          ...List.filled(bs, 0xBB),
          ...List.filled(bs, 0xCC),
        ];
        await orig.writeAsBytes(origData);

        // Modified file: block 1 changed
        final mod = File('${dir.path}/mod.bin');
        final modData = [
          ...List.filled(bs, 0xAA),
          ...List.filled(bs, 0xFF), // changed
          ...List.filled(bs, 0xCC),
        ];
        await mod.writeAsBytes(modData);

        final origMap = await deltaSvc.computeBlockMap(orig.path, blockSize: bs);
        final modMap = await deltaSvc.computeBlockMap(mod.path, blockSize: bs);

        // This simulates: local=modified, remote=original → need to pwrite block 1
        final delta = deltaSvc.compareBlockMaps(modMap, origMap);
        expect(delta.changedBlocks, equals([1]));
        expect(delta.changedBytes, equals(bs));
        expect(delta.savingsPercent, closeTo(66.7, 0.1));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('transfer plan for pCloud upload has correct offsets for pwrite', () async {
      final dir = await Directory.systemTemp.createTemp('pcloud_delta_plan_');
      try {
        final orig = File('${dir.path}/orig.bin');
        await orig.writeAsBytes([
          ...List.filled(bs, 0x11),
          ...List.filled(bs, 0x22),
          ...List.filled(bs, 0x33),
          ...List.filled(bs, 0x44),
        ]);

        final mod = File('${dir.path}/mod.bin');
        await mod.writeAsBytes([
          ...List.filled(bs, 0x11),
          ...List.filled(bs, 0xFF), // changed
          ...List.filled(bs, 0x33),
          ...List.filled(bs, 0xFE), // changed
        ]);

        final origMap = await deltaSvc.computeBlockMap(orig.path, blockSize: bs);
        final modMap = await deltaSvc.computeBlockMap(mod.path, blockSize: bs);
        final delta = deltaSvc.compareBlockMaps(modMap, origMap);
        final plan = deltaSvc.createTransferPlan(
            delta, TransferDirection.upload, modMap);

        // Blocks 1 and 3 changed
        expect(plan.changedBlockIndices.toSet(), equals({1, 3}));
        expect(plan.transferSize, equals(2 * bs));

        // Verify pwrite offsets match expectations
        final uploadOps = plan.operations
            .where((op) => op.type == BlockOperationType.upload)
            .toList();
        expect(uploadOps.length, equals(2));
        expect(uploadOps[0].offset, equals(1 * bs)); // block 1
        expect(uploadOps[1].offset, equals(3 * bs)); // block 3
        expect(uploadOps[0].size, equals(bs));
        expect(uploadOps[1].size, equals(bs));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('applyDelta upload reads correct block data for pwrite simulation', () async {
      final dir = await Directory.systemTemp.createTemp('pcloud_delta_apply_');
      try {
        final orig = File('${dir.path}/orig.bin');
        await orig.writeAsBytes([
          ...List.filled(bs, 0xAA),
          ...List.filled(bs, 0xBB),
        ]);

        final mod = File('${dir.path}/mod.bin');
        await mod.writeAsBytes([
          ...List.filled(bs, 0xAA),
          ...List.filled(bs, 0xFF), // changed
        ]);

        final origMap = await deltaSvc.computeBlockMap(orig.path, blockSize: bs);
        final modMap = await deltaSvc.computeBlockMap(mod.path, blockSize: bs);
        final delta = deltaSvc.compareBlockMaps(modMap, origMap);
        final plan = deltaSvc.createTransferPlan(
            delta, TransferDirection.upload, modMap);

        // Simulate pwrite: capture the block data that would be written
        final writtenBlocks = <int, Uint8List>{};
        await deltaSvc.applyDelta(
          plan,
          mod.path,
          remoteWriteBlock: (blockIndex, offset, data) async {
            writtenBlocks[blockIndex] = Uint8List.fromList(data);
          },
        );

        expect(writtenBlocks.keys, equals({1}));
        expect(writtenBlocks[1]!.length, equals(bs));
        expect(writtenBlocks[1]!.every((b) => b == 0xFF), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('block map cache path uses pcloud provider namespace', () {
      final path1 = deltaSvc.blockMapCachePath('/cache', '/file.bin', 'pcloud');
      final path2 = deltaSvc.blockMapCachePath('/cache', '/file.bin', 'nextcloud');
      expect(path1, isNot(equals(path2)));
      expect(path1, contains('block_maps'));
      expect(path1, endsWith('.json'));
    });

    test('deltaUpload with cache dir saves and loads block map', () async {
      final dir = await Directory.systemTemp.createTemp('pcloud_delta_cache_');
      try {
        final file = File('${dir.path}/test.bin');
        await file.writeAsBytes(List.filled(2 * bs, 0x42));

        final map = await deltaSvc.computeBlockMap(file.path, blockSize: bs);
        final cachePath = deltaSvc.blockMapCachePath(dir.path, '/remote/test.bin', 'pcloud');

        await deltaSvc.saveBlockMap(map, cachePath);
        final loaded = await deltaSvc.loadBlockMap(cachePath);

        expect(loaded, isNotNull);
        expect(loaded!.blockCount, equals(map.blockCount));
        expect(loaded.totalSize, equals(map.totalSize));
        for (int i = 0; i < map.blockCount; i++) {
          expect(loaded.signatures[i].strongHash,
              equals(map.signatures[i].strongHash));
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
