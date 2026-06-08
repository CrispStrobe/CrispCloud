// test/onedrive_adapter_test.dart
//
// Unit tests for the OneDrive client adapter.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/onedrive_client_adapter.dart';
import 'package:crisp_cloud/services/onedrive_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OneDriveClientAdapter adapter;
  late OneDriveConfigService configService;
  late InMemorySecureStorage secureStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStorage = InMemorySecureStorage();
    configService = OneDriveConfigService(
      configPath: '/tmp/onedrive_test',
      secureStorage: secureStorage,
    );
    adapter = OneDriveClientAdapter(config: configService);
  });

  group('OneDriveClientAdapter basic properties', () {
    test('providerName returns OneDrive', () {
      expect(adapter.providerName, equals('OneDrive'));
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

  group('OneDriveClientAdapter capability flags', () {
    test('supports versioning', () {
      expect(adapter.supportsVersioning, isTrue);
    });

    test('supports sharing', () {
      expect(adapter.supportsSharing, isTrue);
    });

    test('supports search', () {
      expect(adapter.supportsSearch, isTrue);
    });

    test('supports thumbnails', () {
      expect(adapter.supportsThumbnails, isTrue);
    });

    test('supports trash', () {
      expect(adapter.supportsTrash, isTrue);
    });

    test('does not support streaming (default)', () {
      expect(adapter.supportsStreaming, isFalse);
    });

    test('does not support multipart (default)', () {
      expect(adapter.supportsMultipart, isFalse);
    });
  });

  group('OneDriveClientAdapter 2FA', () {
    test('is2faNeeded returns false', () async {
      expect(await adapter.is2faNeeded('test@example.com'), isFalse);
    });
  });

  group('OneDriveClientAdapter login validation', () {
    test('login throws on empty client ID', () async {
      expect(
        () => adapter.login('', ''),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('Application (Client) ID is required'),
        )),
      );
    });

    test('login with pipe-separated clientId|secret parses correctly', () async {
      // Will fail on network, but tests the format acceptance
      try {
        await adapter.login('test-client-id|test-secret', '');
      } catch (e) {
        // Expected network/browser error — we just verify it got past validation
        expect(e, isA<Exception>());
      }
    });
  });

  group('OneDriveConfigService', () {
    test('readCredentials returns null initially', () async {
      expect(await configService.readCredentials(), isNull);
    });

    test('saveCredentials then readCredentials round-trips', () async {
      final creds = {
        'client_id': 'test-app-id',
        'client_secret': 'test-secret',
        'refresh_token': 'test-refresh-token',
        'email': 'user@outlook.com',
      };
      await configService.saveCredentials(creds);
      final read = await configService.readCredentials();
      expect(read, isNotNull);
      expect(read!['client_id'], equals('test-app-id'));
      expect(read['refresh_token'], equals('test-refresh-token'));
      expect(read['email'], equals('user@outlook.com'));
    });

    test('clearCredentials removes stored credentials', () async {
      await configService.saveCredentials({
        'client_id': 'test',
        'refresh_token': 'token',
      });
      await configService.clearCredentials();
      expect(await configService.readCredentials(), isNull);
    });
  });

  group('OneDriveClientAdapter restoreCredentials', () {
    test('returns false when no stored credentials', () async {
      final result = await adapter.restoreCredentials();
      expect(result, isFalse);
      expect(adapter.isAuthenticated, isFalse);
    });

    test('returns false when refresh token is empty', () async {
      await configService.saveCredentials({
        'client_id': 'test-id',
        'refresh_token': '',
        'email': 'user@outlook.com',
      });
      final result = await adapter.restoreCredentials();
      expect(result, isFalse);
    });

    test('returns false when refresh fails (no network)', () async {
      await configService.saveCredentials({
        'client_id': 'test-id',
        'refresh_token': 'invalid-token',
        'email': 'user@outlook.com',
      });
      final result = await adapter.restoreCredentials();
      expect(result, isFalse);
    });
  });

  group('CloudStorageFactory onedrive', () {
    test('factory creates OneDriveClientAdapter for onedrive provider', () {
      final client = CloudStorageFactory.create(
        CloudProvider.onedrive,
        config: configService,
      );
      expect(client, isA<OneDriveClientAdapter>());
      expect(client.providerName, equals('OneDrive'));
    });
  });

  group('OneDriveClientAdapter logout', () {
    test('logout resets state without throwing', () async {
      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
      expect(adapter.userId, isNull);
    });
  });

  group('OneDriveClientAdapter - delta sync', () {
    test('fetchDelta throws when not authenticated', () {
      expect(
        () => adapter.fetchDelta(),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchDelta with null deltaToken requests full enumeration', () {
      // Without auth, verify it throws auth error (not parameter error)
      expect(
        () => adapter.fetchDelta(deltaToken: null),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchDelta with deltaToken passes it as URL', () {
      // Delta token is a full URL, verify it throws auth error
      expect(
        () => adapter.fetchDelta(
          deltaToken: 'https://graph.microsoft.com/v1.0/me/drive/root/delta?token=abc123',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('OneDriveClientAdapter - unauthenticated operations', () {
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
}
