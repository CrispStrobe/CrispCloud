import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/services/internxt_client_adapter.dart';
import 'package:crisp_cloud/services/internxt_flutter/secure_config_storage.dart';
import 'package:crisp_cloud/services/internxt_flutter/shared_prefs_storage.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/secure_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internxt_client/crypto.dart' as sdk_crypto;
import 'package:internxt_client/internxt_client.dart' as sdk;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _credentials = <String, dynamic>{
  'email': 'fixture@example.test',
  'userId': 'fixture-user',
  'bucketId': '0123456789abcdef01234567',
  'rootFolderId': 'fixture-root',
  'token': 'synthetic-auth-token',
  'newToken': 'synthetic-refresh-token',
  'mnemonic': 'synthetic mnemonic used only by storage fixtures',
  'bridgeUser': 'synthetic-bridge',
};

class _LegacyStorage implements sdk.ConfigStorage {
  final values = <String, String>{};
  int initializations = 0, writes = 0, deletes = 0;
  bool failDeletes = false;
  Completer<void>? readStarted, releaseRead;

  @override
  void init(String dataDir, List<String> subDirs) {
    initializations++;
  }

  @override
  Future<bool> exists(String key) async => values.containsKey(key);

  @override
  Future<String?> read(String key) async {
    final value = values[key];
    readStarted?.complete();
    await releaseRead?.future;
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
    if (failDeletes) throw StateError('Synthetic cleanup failure');
    values.remove(key);
  }
}

class _SecureStorage extends SecureStorage {
  final values = <String, String>{};
  bool failWrites = false, ignoreWrites = false, failReads = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('Synthetic secure-store failure');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Synthetic secure-store failure');
    if (!ignoreWrites) values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> deleteAll() async {
    values.clear();
  }
}

String _legacyEnvelope({String source = 'static', String? secret}) =>
    jsonEncode({
      'fmt': 'inxt-cred-v1',
      'src': source,
      'ct': sdk_crypto.encryptTextWithKey(
        jsonEncode(_credentials),
        secret ?? '6KYQBP847D4ATSFA',
      ),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _SecureStorage secure;
  late _LegacyStorage legacy;
  late sdk.ConfigService config;

  sdk.ConfigService create({
    String directory = 'fixture-config',
    String? Function()? environmentKey,
    String namespace = 'internxt',
  }) => sdk.ConfigService(
    configPath: directory,
    storage: InternxtSecureConfigStorage(
      secureStorage: secure,
      legacyStorage: legacy,
      legacyEnvironmentKey: environmentKey ?? () => null,
      namespace: namespace,
    ),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secure = _SecureStorage();
    legacy = _LegacyStorage();
    config = create();
  });

  test(
    'SDK saves and refreshes credentials through the secure backend only',
    () async {
      await config.saveCredentials(_credentials);
      expect(await config.readCredentials(), _credentials);
      final refreshed = {
        ..._credentials,
        'newToken': 'rotated-synthetic-token',
      };
      await config.saveCredentials(refreshed);
      expect(await config.readCredentials(), refreshed);
      expect(secure.values, hasLength(1));
      expect(legacy.initializations, 0);
      expect(legacy.writes, 0);
      expect(legacy.values, isEmpty);
    },
  );

  test(
    'legacy public-key envelope migrates only after secure persistence',
    () async {
      legacy.values[config.credentialsFile] = _legacyEnvelope();
      expect(await config.readCredentials(), _credentials);
      expect(secure.values, hasLength(1));
      expect(legacy.values, isEmpty);
      expect(legacy.writes, 0);
      expect(await create().readCredentials(), _credentials);
    },
  );

  test(
    'legacy plaintext credentials and SDK batch state are preserved',
    () async {
      legacy.values[config.credentialsFile] = jsonEncode(_credentials);
      legacy.values[config.getBatchStateFilePath('synthetic')] = jsonEncode({
        'completed': 2,
      });
      expect(await config.readCredentials(), _credentials);
      expect(await config.loadBatchState('synthetic'), {'completed': 2});
      await config.saveBatchState('synthetic', {'completed': 3});
      expect(await config.loadBatchState('synthetic'), {'completed': 3});
      expect(legacy.values, isEmpty);
      expect(legacy.writes, 0);
    },
  );

  test(
    'environment-wrapped legacy credentials require the original key',
    () async {
      final old = _legacyEnvelope(source: 'env', secret: 'synthetic-env-key');
      legacy.values[config.credentialsFile] = old;
      await expectLater(config.readCredentials(), throwsStateError);
      expect(legacy.values[config.credentialsFile], old);
      expect(secure.values, isEmpty);
      final withKey = create(environmentKey: () => 'synthetic-env-key');
      expect(await withKey.readCredentials(), _credentials);
      expect(legacy.values, isEmpty);
    },
  );

  for (final invalid in ['{broken', '{"fmt":"unknown","ct":"secret"}', '[]']) {
    test(
      'invalid legacy data is retained and never included in an error: $invalid',
      () async {
        legacy.values[config.credentialsFile] = invalid;
        await expectLater(
          config.readCredentials(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Existing Internxt credentials could not be migrated.',
            ),
          ),
        );
        expect(legacy.values[config.credentialsFile], invalid);
        expect(secure.values, isEmpty);
      },
    );
  }

  for (final failure in ['throw', 'drop', 'read']) {
    test(
      'secure-store $failure failure leaves legacy credentials intact',
      () async {
        final old = _legacyEnvelope();
        legacy.values[config.credentialsFile] = old;
        secure.failWrites = failure == 'throw';
        secure.ignoreWrites = failure == 'drop';
        secure.failReads = failure == 'read';
        await expectLater(config.readCredentials(), throwsStateError);
        expect(legacy.values[config.credentialsFile], old);
        expect(legacy.deletes, 0);
      },
    );
  }

  test(
    'secure state wins and logout tombstone prevents legacy resurrection',
    () async {
      legacy.values[config.credentialsFile] = _legacyEnvelope();
      legacy.failDeletes = true;
      expect(await config.readCredentials(), _credentials);
      final refreshed = {..._credentials, 'newToken': 'new-synthetic-token'};
      await config.saveCredentials(refreshed);
      expect(await create().readCredentials(), refreshed);
      await config.clearCredentials();
      expect(await create().readCredentials(), isNull);
      expect(await config.storage.exists(config.credentialsFile), isFalse);
      expect(secure.values.values.single, isNot(contains('synthetic')));
      expect(legacy.values, isNotEmpty);
      legacy.failDeletes = false;
      expect(await config.readCredentials(), isNull);
      expect(legacy.values, isEmpty);
    },
  );

  test('failed secure logout preserves the saved credentials', () async {
    await config.saveCredentials(_credentials);
    secure.failWrites = true;
    await expectLater(config.clearCredentials(), throwsStateError);
    secure.failWrites = false;
    expect(await config.readCredentials(), _credentials);
  });

  test('container path changes retain credentials; account namespaces isolate them', () async {
    await config.saveCredentials(_credentials);
    final moved = create(directory: 'new-container/config');
    expect(await moved.readCredentials(), _credentials);
    final separate = create(namespace: 'second-account');
    expect(await separate.readCredentials(), isNull);
    await separate.saveCredentials({'userId': 'second'});
    expect(await config.readCredentials(), _credentials);
    expect(await separate.readCredentials(), {'userId': 'second'});
  });

  test('legacy migration cannot overwrite a concurrent new login', () async {
    legacy.values[config.credentialsFile] = _legacyEnvelope();
    legacy.readStarted = Completer<void>();
    legacy.releaseRead = Completer<void>();
    final migrating = config.readCredentials();
    await legacy.readStarted!.future;
    final refreshed = {..._credentials, 'newToken': 'newer-synthetic-token'};
    final saving = create().saveCredentials(refreshed);
    legacy.releaseRead!.complete();
    await migrating;
    await saving;
    expect(await config.readCredentials(), refreshed);
  });

  test('SDK keys cannot escape the config directory', () async {
    await expectLater(
      config.storage.read(p.join('fixture-config', '..', 'other')),
      throwsArgumentError,
    );
    await expectLater(
      config.storage.write(p.join('fixture-config', '..', 'other'), 'x'),
      throwsArgumentError,
    );
    await expectLater(
      config.storage.delete(p.join('fixture-config', '..', 'other')),
      throwsArgumentError,
    );
    expect(secure.values, isEmpty);
    expect(legacy.deletes, 0);
  });

  test('native helper migrates an actual SDK file without creating extra directories', () async {
    final dir = await Directory.systemTemp.createTemp('crisp-internxt-secure-');
    addTearDown(() => dir.delete(recursive: true));
    final old = File(p.join(dir.path, '.inxtcli-dart-creds.json'));
    await old.writeAsString(_legacyEnvelope());
    final host = createSecureInternxtConfig(
      configPath: dir.path,
      secureStorage: secure,
    );
    expect(await host.readCredentials(), _credentials);
    expect(await old.exists(), isFalse);
    expect(await dir.list().toList(), isEmpty);
    await host.saveCredentials({
      ..._credentials,
      'newToken': 'next-synthetic-token',
    });
    expect(await dir.list().toList(), isEmpty);
  });

  test('web migration requires unlock and stores only ciphertext in the browser backend', () async {
    final browser = InMemoryWebStorageBackend();
    final vault = WebEncryptedStorage(browser, newVaultIterations: 1000);
    final oldPrefs = SharedPreferencesStorage();
    final webConfig = sdk.ConfigService(
      configPath: 'web-config',
      storage: InternxtSecureConfigStorage(
        secureStorage: vault,
        legacyStorage: oldPrefs,
      ),
    );
    await oldPrefs.write(webConfig.credentialsFile, jsonEncode(_credentials));
    await expectLater(webConfig.readCredentials(), throwsStateError);
    expect(
      await oldPrefs.read(webConfig.credentialsFile),
      jsonEncode(_credentials),
    );
    await vault.initialize('synthetic-master-password');
    expect(await webConfig.readCredentials(), _credentials);
    expect(await oldPrefs.exists(webConfig.credentialsFile), isFalse);
    for (final key in await browser.allKeys()) {
      final value = await browser.getItem(key);
      expect(value, isNot(contains('synthetic-auth-token')));
      expect(value, isNot(contains(_credentials['mnemonic'])));
    }
    expect(await webConfig.readCredentials(), _credentials);
  });

  test(
    'host adapter uses secure config and logout clears in-memory SDK secrets',
    () async {
      final host = InternxtClientAdapter.forHost(
        configPath: p.join('fixture-config', 'host'),
        secureStorage: secure,
      );
      expect(host.config.storage, isA<InternxtSecureConfigStorage>());
      final client = sdk.InternxtClient(config: config)..setAuth(_credentials);
      await config.saveCredentials(_credentials);
      final adapter = InternxtClientAdapter.withClient(client);
      expect(adapter.isAuthenticated, isTrue);
      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
      expect(client.authToken, isNull);
      expect(client.newToken, isNull);
      expect(client.mnemonic, isNull);
      expect(client.bridgeUser, isNull);
      expect(client.userIdForAuth, isNull);
      expect(client.bucketId, isNull);
      expect(client.rootFolderId, isNull);
      expect(await config.readCredentials(), isNull);
    },
  );
}
