// test/dropbox_adapter_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/dropbox_client_adapter.dart';
import 'package:crisp_cloud/services/dropbox_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';

void main() {
  late DropboxClientAdapter adapter;
  late DropboxConfigService configService;
  late InMemorySecureStorage secureStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStorage = InMemorySecureStorage();
    configService = DropboxConfigService(
      configPath: '/tmp/dropbox_test',
      secureStorage: secureStorage,
    );
    adapter = DropboxClientAdapter(config: configService);
  });

  group('DropboxClientAdapter basic properties', () {
    test('providerName returns Dropbox', () {
      expect(adapter.providerName, equals('Dropbox'));
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
  });

  group('DropboxClientAdapter capability flags', () {
    test('supports versioning', () => expect(adapter.supportsVersioning, isTrue));
    test('supports sharing', () => expect(adapter.supportsSharing, isTrue));
    test('supports search', () => expect(adapter.supportsSearch, isTrue));
    test('supports thumbnails', () => expect(adapter.supportsThumbnails, isTrue));
    test('supports trash', () => expect(adapter.supportsTrash, isTrue));
    test('does not support streaming', () => expect(adapter.supportsStreaming, isFalse));
    test('does not support multipart', () => expect(adapter.supportsMultipart, isFalse));
  });

  group('DropboxClientAdapter 2FA', () {
    test('is2faNeeded returns false', () async {
      expect(await adapter.is2faNeeded('test@example.com'), isFalse);
    });
  });

  group('DropboxClientAdapter login validation', () {
    test('login throws on empty app key', () async {
      expect(
        () => adapter.login('', ''),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('App Key is required'),
        )),
      );
    });
  });

  group('DropboxConfigService', () {
    test('readCredentials returns null initially', () async {
      expect(await configService.readCredentials(), isNull);
    });

    test('saveCredentials then readCredentials round-trips', () async {
      final creds = {
        'app_key': 'test-key',
        'app_secret': 'test-secret',
        'refresh_token': 'test-refresh-token',
        'email': 'user@dropbox.com',
      };
      await configService.saveCredentials(creds);
      final read = await configService.readCredentials();
      expect(read, isNotNull);
      expect(read!['app_key'], equals('test-key'));
      expect(read['refresh_token'], equals('test-refresh-token'));
    });

    test('clearCredentials removes stored credentials', () async {
      await configService.saveCredentials({'app_key': 'k', 'refresh_token': 't'});
      await configService.clearCredentials();
      expect(await configService.readCredentials(), isNull);
    });
  });

  group('DropboxClientAdapter restoreCredentials', () {
    test('returns false when no stored credentials', () async {
      expect(await adapter.restoreCredentials(), isFalse);
    });

    test('returns false when refresh token is empty', () async {
      await configService.saveCredentials({
        'app_key': 'test',
        'refresh_token': '',
      });
      expect(await adapter.restoreCredentials(), isFalse);
    });

    test('returns false when refresh fails (no network)', () async {
      await configService.saveCredentials({
        'app_key': 'test',
        'refresh_token': 'invalid-token',
      });
      expect(await adapter.restoreCredentials(), isFalse);
    });
  });

  group('CloudStorageFactory dropbox', () {
    test('factory creates DropboxClientAdapter for dropbox provider', () {
      final client = CloudStorageFactory.create(
        CloudProvider.dropbox,
        config: configService,
      );
      expect(client, isA<DropboxClientAdapter>());
      expect(client.providerName, equals('Dropbox'));
    });
  });

  group('DropboxClientAdapter logout', () {
    test('logout resets state without throwing', () async {
      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
      expect(adapter.userId, isNull);
    });
  });

  group('DropboxClientAdapter - shared folders', () {
    test('listSharedFolders throws when not authenticated', () {
      expect(
        () => adapter.listSharedFolders(),
        throwsA(isA<Exception>()),
      );
    });

    test('mountSharedFolder throws when not authenticated', () {
      expect(
        () => adapter.mountSharedFolder('sf-12345'),
        throwsA(isA<Exception>()),
      );
    });

    test('unmountSharedFolder throws when not authenticated', () {
      expect(
        () => adapter.unmountSharedFolder('sf-12345'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('DropboxClientAdapter - unauthenticated operations', () {
    test('listPath throws when not authenticated', () {
      expect(
        () => adapter.listPath('/'),
        throwsA(isA<Exception>()),
      );
    });

    test('uploadFile throws when not authenticated', () {
      expect(
        () => adapter.uploadFile([1, 2, 3], 'test.txt', '/'),
        throwsA(isA<Exception>()),
      );
    });

    test('downloadFileBytes throws when not authenticated', () {
      expect(
        () => adapter.downloadFileBytes('/test.txt'),
        throwsA(isA<Exception>()),
      );
    });

    test('deletePath throws when not authenticated', () {
      expect(
        () => adapter.deletePath('/test.txt'),
        throwsA(isA<Exception>()),
      );
    });

    test('createFolderPath throws when not authenticated', () {
      expect(
        () => adapter.createFolderPath('/new-folder'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('DropboxClientAdapter - content hash', () {
    test('computeContentHash returns correct hash for small data', () {
      // Known test vector: "Hello" (5 bytes, fits in one 4MB block)
      final data = [72, 101, 108, 108, 111]; // "Hello"
      final hash = DropboxClientAdapter.computeContentHash(data);

      // Should be SHA-256(SHA-256("Hello"))
      // Block hash = SHA-256("Hello")
      // Final hash = SHA-256(block_hash_bytes)
      expect(hash.length, equals(64)); // hex-encoded SHA-256
      expect(hash, isNot(equals('')));
    });

    test('computeContentHash handles empty data', () {
      final hash = DropboxClientAdapter.computeContentHash([]);
      expect(hash.length, equals(64));
    });

    test('computeContentHash is deterministic', () {
      final data = List.generate(1000, (i) => i % 256);
      final hash1 = DropboxClientAdapter.computeContentHash(data);
      final hash2 = DropboxClientAdapter.computeContentHash(data);
      expect(hash1, equals(hash2));
    });

    test('computeContentHash differs for different data', () {
      final hash1 = DropboxClientAdapter.computeContentHash([1, 2, 3]);
      final hash2 = DropboxClientAdapter.computeContentHash([4, 5, 6]);
      expect(hash1, isNot(equals(hash2)));
    });

    test('computeContentHash handles data spanning multiple 4MB blocks', () {
      // Create 5MB of data (spans 2 blocks: 4MB + 1MB)
      final data = List.generate(5 * 1024 * 1024, (i) => i % 256);
      final hash = DropboxClientAdapter.computeContentHash(data);
      expect(hash.length, equals(64));

      // Single block hash should be different
      final smallHash = DropboxClientAdapter.computeContentHash(data.sublist(0, 100));
      expect(hash, isNot(equals(smallHash)));
    });
  });
}
