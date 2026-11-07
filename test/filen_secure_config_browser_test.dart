@TestOn('browser')
library;

import 'package:crisp_cloud/services/filen_client_adapter.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Exercise the persistent policy branch without depending on a platform
// keychain. Browser vault cryptography is covered by secure_storage_web_test.
class _PersistentBrowserFixture extends InMemorySecureStorage {
  @override
  bool get isPersistent => true;
}

const _credentials = <String, String>{
  'email': 'fixture@example.test',
  'apiKey': 'synthetic-api-key',
  'masterKeys': 'synthetic-key-one|synthetic-key-two',
  'baseFolderUUID': 'synthetic-root',
  'userId': '123',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'browser Filen SDK uses the host store without filesystem operations',
    () async {
      expect(kIsWeb, isTrue);
      SharedPreferences.setMockInitialValues({});
      final storage = _PersistentBrowserFixture();
      final config = FilenConfigService(configPath: '', secureStorage: storage);
      final adapter = FilenClientAdapter(config: config);

      expect(adapter.client.config.storage, same(config.sdkStorage));
      await adapter.client.config.saveCredentials(_credentials);
      expect(await config.readCredentials(), _credentials);
      adapter.client.setAuth((await adapter.client.config.readCredentials())!);
      expect(adapter.client.masterKeys, [
        'synthetic-key-one',
        'synthetic-key-two',
      ]);

      await adapter.logout();

      expect(adapter.isAuthenticated, isFalse);
      expect(adapter.client.masterKeys, isEmpty);
      expect(await adapter.client.config.readCredentials(), isNull);
      expect(await storage.read('filen_credentials'), isNull);
    },
  );

  test(
    'browser session-only SDK operations preserve durable preferences',
    () async {
      const legacy = '{"apiKey":"durable-old-key"}';
      SharedPreferences.setMockInitialValues({'filen_credentials': legacy});
      final config = FilenConfigService(
        configPath: '',
        secureStorage: InMemorySecureStorage(),
      );
      final adapter = FilenClientAdapter(config: config);
      expect(await adapter.client.config.readCredentials(), isNull);

      await adapter.client.config.saveCredentials(_credentials);
      adapter.client.setAuth(_credentials);
      await adapter.logout();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('filen_credentials'), legacy);
      expect(prefs.containsKey('secure_storage_migration_v1'), isFalse);
      expect(await config.readCredentials(), isNull);
    },
  );
}
