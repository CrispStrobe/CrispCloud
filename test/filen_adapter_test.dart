import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/filen_client_adapter.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  late FilenClientAdapter adapter;
  late FilenConfigService configService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    configService = FilenConfigService(configPath: '/tmp/filen_test_config', secureStorage: InMemorySecureStorage());
    adapter = FilenClientAdapter(config: configService);
  });

  group('FilenClientAdapter', () {
    test('providerName returns Filen', () {
      expect(adapter.providerName, equals('Filen'));
    });

    test('rootPath returns /', () {
      expect(adapter.rootPath, equals('/'));
    });

    test('isAuthenticated returns false initially', () {
      expect(adapter.isAuthenticated, isFalse);
    });

    test('isAuthenticated returns true after setAuth with apiKey', () {
      adapter.client.setAuth({
        'apiKey': 'test-api-key-123',
        'masterKeys': 'key1|key2',
        'baseFolderUUID': 'some-uuid',
      });
      expect(adapter.isAuthenticated, isTrue);
    });

    test('is2faNeeded always returns false', () async {
      final result = await adapter.is2faNeeded('test@example.com');
      expect(result, isFalse);
    });

    test('logout clears auth state', () async {
      // First set some auth
      adapter.client.setAuth({
        'apiKey': 'test-api-key-123',
        'masterKeys': 'key1|key2',
        'baseFolderUUID': 'some-uuid',
      });
      expect(adapter.isAuthenticated, isTrue);

      // Now logout
      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
    });

    test('userId returns null when not authenticated', () {
      expect(adapter.userId, isNull);
    });

    test('bucketId always returns null', () {
      expect(adapter.bucketId, isNull);
    });

    test('debugMode defaults to false', () {
      expect(adapter.debugMode, isFalse);
    });

    test('debugMode can be set', () {
      adapter.debugMode = true;
      expect(adapter.debugMode, isTrue);
    });

    test('filenConfig is accessible', () {
      expect(adapter.filenConfig, same(configService));
    });

    test('client is accessible', () {
      expect(adapter.client, isNotNull);
    });
  });
}
