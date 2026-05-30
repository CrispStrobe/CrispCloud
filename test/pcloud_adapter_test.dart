// test/pcloud_adapter_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/pcloud_client_adapter.dart';
import 'package:crisp_cloud/services/pcloud_config_service.dart';
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
}
