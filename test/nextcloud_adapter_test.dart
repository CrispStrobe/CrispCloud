// test/nextcloud_adapter_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';

void main() {
  late NextcloudClientAdapter adapter;
  late NextcloudConfigService configService;
  late InMemorySecureStorage secureStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStorage = InMemorySecureStorage();
    configService = NextcloudConfigService(
      configPath: '/tmp/nextcloud_test',
      secureStorage: secureStorage,
    );
    adapter = NextcloudClientAdapter(config: configService);
  });

  group('NextcloudClientAdapter basic properties', () {
    test('providerName returns Nextcloud', () {
      expect(adapter.providerName, equals('Nextcloud'));
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

    test('bucketId is null initially', () {
      expect(adapter.bucketId, isNull);
    });
  });

  group('NextcloudClientAdapter capability flags', () {
    test('supports versioning', () => expect(adapter.supportsVersioning, isTrue));
    test('supports sharing', () => expect(adapter.supportsSharing, isTrue));
    test('supports search', () => expect(adapter.supportsSearch, isTrue));
    test('supports trash', () => expect(adapter.supportsTrash, isTrue));
    test('does not support streaming', () => expect(adapter.supportsStreaming, isFalse));
    test('does not support multipart', () => expect(adapter.supportsMultipart, isFalse));
    test('does not support thumbnails', () => expect(adapter.supportsThumbnails, isFalse));
  });

  group('NextcloudClientAdapter 2FA', () {
    test('is2faNeeded returns false', () async {
      expect(await adapter.is2faNeeded('user@https://nextcloud.example.com'), isFalse);
    });
  });

  group('NextcloudClientAdapter login format validation', () {
    test('login throws when identity has no @http', () async {
      expect(
        () => adapter.login('invalidformat', 'password'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Format must be username@https://'),
        )),
      );
    });

    test('login throws when username is missing', () async {
      expect(
        () => adapter.login('@https://nextcloud.example.com', 'password'),
        throwsA(isA<Exception>()),
      );
    });

    test('login throws when server URL is missing', () async {
      expect(
        () => adapter.login('user@', 'password'),
        throwsA(isA<Exception>()),
      );
    });

    test('login fails with invalid server (no network)', () async {
      // This will fail at the connection test step, not the format validation
      expect(
        () => adapter.login('user@https://invalid.local.nextcloud.test', 'password'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('NextcloudConfigService', () {
    test('readCredentials returns null initially', () async {
      expect(await configService.readCredentials(), isNull);
    });

    test('saveCredentials then readCredentials round-trips', () async {
      final creds = {
        'username': 'admin',
        'password': 'secret-app-password',
        'serverUrl': 'https://nextcloud.example.com',
      };
      await configService.saveCredentials(creds);
      final read = await configService.readCredentials();
      expect(read, isNotNull);
      expect(read!['username'], equals('admin'));
      expect(read['password'], equals('secret-app-password'));
      expect(read['serverUrl'], equals('https://nextcloud.example.com'));
    });

    test('clearCredentials removes stored credentials', () async {
      await configService.saveCredentials({
        'username': 'admin',
        'password': 'pass',
        'serverUrl': 'https://cloud.example.com',
      });
      await configService.clearCredentials();
      expect(await configService.readCredentials(), isNull);
    });

    test('saveCredentials overwrites previous entry', () async {
      await configService.saveCredentials({
        'username': 'user1',
        'password': 'pass1',
        'serverUrl': 'https://cloud.example.com',
      });
      await configService.saveCredentials({
        'username': 'user2',
        'password': 'pass2',
        'serverUrl': 'https://other.example.com',
      });
      final read = await configService.readCredentials();
      expect(read!['username'], equals('user2'));
      expect(read['password'], equals('pass2'));
    });
  });

  group('NextcloudClientAdapter restoreCredentials', () {
    test('returns false when no stored credentials', () async {
      expect(await adapter.restoreCredentials(), isFalse);
    });

    test('returns false when username is empty', () async {
      await configService.saveCredentials({
        'username': '',
        'password': 'pass',
        'serverUrl': 'https://cloud.example.com',
      });
      expect(await adapter.restoreCredentials(), isFalse);
    });

    test('returns false when password is empty', () async {
      await configService.saveCredentials({
        'username': 'admin',
        'password': '',
        'serverUrl': 'https://cloud.example.com',
      });
      expect(await adapter.restoreCredentials(), isFalse);
    });

    test('returns false when server connectivity fails (no network)', () async {
      await configService.saveCredentials({
        'username': 'admin',
        'password': 'valid-password',
        'serverUrl': 'https://invalid.local.nextcloud.test',
      });
      expect(await adapter.restoreCredentials(), isFalse);
    });
  });

  group('CloudStorageFactory nextcloud', () {
    test('factory creates NextcloudClientAdapter for nextcloud provider', () {
      final client = CloudStorageFactory.create(
        CloudProvider.nextcloud,
        config: configService,
      );
      expect(client, isA<NextcloudClientAdapter>());
      expect(client.providerName, equals('Nextcloud'));
    });

    test('factory falls back to InMemorySecureStorage when config is not NextcloudConfigService', () {
      final client = CloudStorageFactory.create(
        CloudProvider.nextcloud,
        config: 'not_a_config_service',
      );
      expect(client, isA<NextcloudClientAdapter>());
    });
  });

  group('NextcloudClientAdapter logout', () {
    test('logout resets state without throwing', () async {
      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
      expect(adapter.userId, isNull);
      expect(adapter.bucketId, isNull);
    });

    test('logout clears stored credentials', () async {
      await configService.saveCredentials({
        'username': 'admin',
        'password': 'pass',
        'serverUrl': 'https://cloud.example.com',
      });
      await adapter.logout();
      expect(await configService.readCredentials(), isNull);
    });
  });
}
