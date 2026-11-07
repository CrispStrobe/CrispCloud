import 'dart:io';

import 'package:filen_client/config.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/sftp_config_service.dart';
import 'package:crisp_cloud/services/webdav_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

const _filenCredentials = <String, String>{
  'email': 'User@example.test',
  'apiKey': 'synthetic-api-key',
  'masterKeys': 'synthetic-key-one|synthetic-key-two',
  'baseFolderUUID': 'synthetic-root',
  'userId': '123',
};

class _FilenPersistentStorage extends InMemorySecureStorage {
  String failure = '';

  @override
  bool get isPersistent => true;

  @override
  Future<void> write(String key, String value) async {
    if (failure == 'throw') throw StateError('Synthetic private write detail');
    if (failure == 'drop') return;
    await super.write(key, failure == 'alter' ? '$value ' : value);
  }

  @override
  Future<String?> read(String key) async {
    if (failure == 'read') throw StateError('Synthetic private read detail');
    return super.read(key);
  }

  @override
  Future<void> delete(String key) async {
    if (failure == 'drop-delete') return;
    await super.delete(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('FilenConfigService', () {
    late InMemorySecureStorage secure;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      secure = InMemorySecureStorage();
    });

    test('readCredentials returns null when empty', () async {
      final config = FilenConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      final creds = await config.readCredentials();
      expect(creds, isNull);
    });

    test('saveCredentials and readCredentials round-trip', () async {
      final config = FilenConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      await config.saveCredentials({
        'email': 'user@example.com',
        'apiKey': 'test-key',
        'masterKeys': 'mk1|mk2',
        'baseFolderUUID': 'uuid-123',
      });

      final creds = await config.readCredentials();
      expect(creds, isNotNull);
      expect(creds!['email'], equals('user@example.com'));
      expect(creds['apiKey'], equals('test-key'));
    });

    test('clearCredentials removes stored data', () async {
      final config = FilenConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      await config.saveCredentials({'email': 'test@test.com'});
      await config.clearCredentials();
      final creds = await config.readCredentials();
      expect(creds, isNull);
    });

    test('generateBatchId returns non-empty string', () {
      final config = FilenConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      final id = config.generateBatchId('upload', ['file.txt'], '/docs');
      expect(id, isNotEmpty);
    });

    test('batch state CRUD', () async {
      final config = FilenConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      final batchId = 'test-batch';

      await config.saveBatchState(batchId, {'status': 'running'});
      final state = await config.readBatchState(batchId);
      expect(state, isNotNull);
      expect(state!['status'], equals('running'));

      await config.deleteBatchState(batchId);
      final deleted = await config.readBatchState(batchId);
      expect(deleted, isNull);
    });

    test('getAllBatchIds returns matching keys', () async {
      final config = FilenConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      await config.saveBatchState('batch1', {'a': 1});
      await config.saveBatchState('batch2', {'b': 2});

      final ids = await config.getAllBatchIds();
      expect(ids, containsAll(['batch1', 'batch2']));
    });

    test('provider preference CRUD', () async {
      final config = FilenConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      await config.saveProviderPreference('filen');
      final pref = await config.getProviderPreference();
      expect(pref, equals('filen'));
    });

    test(
      'SDK config uses secure storage and removes legacy plaintext',
      () async {
        final directory = Directory.systemTemp.createTempSync('crisp-filen-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final legacy = File(p.join(directory.path, 'credentials.json'))
          ..writeAsStringSync('{"legacy":"plaintext"}');
        final config = FilenConfigService(
          configPath: directory.path,
          secureStorage: _FilenPersistentStorage(),
        );

        await config.sdkStorage.saveCredentials({'apiKey': 'secure-key'});
        expect(await config.sdkStorage.readCredentials(), {
          'apiKey': 'secure-key',
        });
        expect(await legacy.exists(), isFalse);
        expect(await config.readCredentials(), {'apiKey': 'secure-key'});

        await config.clearCredentials();
        expect(await config.sdkStorage.readCredentials(), isNull);
      },
    );

    test('app and SDK preserve the complete Filen credential shape', () async {
      final config = FilenConfigService(
        configPath: 'unused-session-directory',
        secureStorage: secure,
      );
      final sdkConfig = sdk.ConfigService(
        configPath: config.configPath,
        storage: config.sdkStorage,
      );
      expect(config.sdkStorage, same(config.sdkStorage));

      await sdkConfig.saveCredentials(_filenCredentials);

      expect(await config.readCredentials(), _filenCredentials);
      final returned = await sdkConfig.readCredentials();
      expect(returned, _filenCredentials);
      returned!['masterKeys'] = 'changed-copy';
      expect(await sdkConfig.readCredentials(), _filenCredentials);
      await config.saveCredentials({..._filenCredentials, 'userId': '456'});
      expect((await sdkConfig.readCredentials())!['userId'], '456');
    });

    test('injected SDK config never creates CLI directories', () async {
      final root = Directory.systemTemp.createTempSync('crisp-filen-host-');
      addTearDown(() => root.deleteSync(recursive: true));
      final missing = Directory(p.join(root.path, 'not-created'));
      final config = FilenConfigService(
        configPath: missing.path,
        secureStorage: secure,
      );
      final sdkConfig = sdk.ConfigService(
        configPath: config.configPath,
        storage: config.sdkStorage,
      );

      await sdkConfig.saveCredentials(_filenCredentials);
      expect(await sdkConfig.readCredentials(), _filenCredentials);
      await sdkConfig.clearCredentials();

      expect(missing.existsSync(), isFalse);
      expect(root.listSync(), isEmpty);
    });

    for (final source in ['app', 'SDK']) {
      for (final failure in ['throw', 'drop', 'alter', 'read']) {
        test(
          '$source $failure save failure preserves the legacy file',
          () async {
            final directory = Directory.systemTemp.createTempSync(
              'crisp-filen-',
            );
            addTearDown(() => directory.deleteSync(recursive: true));
            const legacyContents = '{"apiKey":"legacy-private-key"}';
            final legacy = File(p.join(directory.path, 'credentials.json'))
              ..writeAsStringSync(legacyContents);
            final storage = _FilenPersistentStorage()..failure = failure;
            final config = FilenConfigService(
              configPath: directory.path,
              secureStorage: storage,
            );

            await expectLater(
              source == 'app'
                  ? config.saveCredentials(_filenCredentials)
                  : config.sdkStorage.saveCredentials(_filenCredentials),
              throwsA(
                isA<FilenCredentialSaveFailure>().having(
                  (error) => error.toString(),
                  'redacted failure',
                  isNot(contains('private')),
                ),
              ),
            );

            expect(legacy.readAsStringSync(), legacyContents);
            storage.failure = '';
            await config.sdkStorage.saveCredentials(_filenCredentials);
            expect(legacy.existsSync(), isFalse);
            expect(await config.readCredentials(), _filenCredentials);
          },
        );
      }
    }

    test(
      'session-only app and SDK operations preserve durable legacy data',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'crisp-filen-session-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        const legacyContents = '{"apiKey":"durable-old-key"}';
        final legacy = File(p.join(directory.path, 'credentials.json'))
          ..writeAsStringSync(legacyContents);
        SharedPreferences.setMockInitialValues({
          'filen_credentials': legacyContents,
        });
        final config = FilenConfigService(
          configPath: directory.path,
          secureStorage: secure,
        );

        expect(await config.sdkStorage.readCredentials(), isNull);
        await config.sdkStorage.saveCredentials(_filenCredentials);
        expect(await config.readCredentials(), _filenCredentials);
        await config.sdkStorage.clearCredentials();
        await config.saveCredentials(_filenCredentials);
        await config.clearCredentials();

        expect(await config.sdkStorage.readCredentials(), isNull);
        expect(legacy.readAsStringSync(), legacyContents);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('filen_credentials'), legacyContents);
        expect(prefs.containsKey('secure_storage_migration_v1'), isFalse);
      },
    );

    test(
      'unexpected legacy directory fails save and logout without removing data',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'crisp-filen-directory-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final unexpected = Directory(p.join(directory.path, 'credentials.json'))
          ..createSync();
        final sentinel = File(p.join(unexpected.path, 'keep.txt'))
          ..writeAsStringSync('keep');
        final storage = _FilenPersistentStorage();
        final config = FilenConfigService(
          configPath: directory.path,
          secureStorage: storage,
        );

        await expectLater(
          config.sdkStorage.saveCredentials(_filenCredentials),
          throwsA(isA<FilenCredentialSaveFailure>()),
        );
        expect(await config.readCredentials(), _filenCredentials);
        await expectLater(
          config.sdkStorage.clearCredentials(),
          throwsA(isA<FilenCredentialDeletionFailure>()),
        );
        expect(sentinel.readAsStringSync(), 'keep');
        expect(await config.readCredentials(), _filenCredentials);

        unexpected.deleteSync(recursive: true);
        await config.sdkStorage.clearCredentials();
        expect(await config.readCredentials(), isNull);
      },
    );

    for (final linkDirectory in [false, true]) {
      test(
        'legacy cleanup refuses ${linkDirectory ? 'directory' : 'file'} symlinks',
        () async {
          final directory = Directory.systemTemp.createTempSync(
            'crisp-filen-link-',
          );
          addTearDown(() => directory.deleteSync(recursive: true));
          final targetDirectory = Directory(p.join(directory.path, 'target'))
            ..createSync();
          final target = File(p.join(targetDirectory.path, 'credentials.json'))
            ..writeAsStringSync('preserve linked data');
          final configDirectory = p.join(directory.path, 'config');
          final Link link;
          if (linkDirectory) {
            link = Link(configDirectory)..createSync(targetDirectory.path);
          } else {
            Directory(configDirectory).createSync();
            link = Link(p.join(configDirectory, 'credentials.json'))
              ..createSync(target.path);
          }
          final config = FilenConfigService(
            configPath: configDirectory,
            secureStorage: _FilenPersistentStorage(),
          );

          await expectLater(
            config.saveCredentials(_filenCredentials),
            throwsA(isA<FilenCredentialSaveFailure>()),
          );
          await expectLater(
            config.clearCredentials(),
            throwsA(isA<FilenCredentialDeletionFailure>()),
          );
          expect(link.existsSync(), isTrue);
          expect(target.readAsStringSync(), 'preserve linked data');
        },
        skip: Platform.isWindows,
      ); // Windows symlink creation needs extra privileges.
    }

    for (final invalid in <Object?>[
      null,
      42,
      ['private-key'],
      {'key': 'private-key'},
    ]) {
      test(
        'SDK rejects ${invalid.runtimeType} credential values without changing storage',
        () async {
          final config = FilenConfigService(
            configPath: 'unused',
            secureStorage: secure,
          );
          await config.saveCredentials(_filenCredentials);
          final before = await secure.read('filen_credentials');

          await expectLater(
            config.sdkStorage.saveCredentials({
              ..._filenCredentials,
              'masterKeys': invalid,
            }),
            throwsA(
              isA<FormatException>().having(
                (error) => error.toString(),
                'redacted failure',
                isNot(contains('private')),
              ),
            ),
          );
          expect(await secure.read('filen_credentials'), before);
        },
      );
    }

    test(
      'malformed stored credentials fail closed through app and SDK',
      () async {
        final config = FilenConfigService(
          configPath: 'unused',
          secureStorage: secure,
        );
        for (final raw in [
          'private invalid JSON',
          '[]',
          '{"masterKeys":["private-key"]}',
        ]) {
          await secure.write('filen_credentials', raw);

          await expectLater(
            config.readCredentials(),
            throwsA(isA<FilenCredentialReadFailure>()),
          );
          await expectLater(
            config.sdkStorage.readCredentials(),
            throwsA(isA<FilenCredentialReadFailure>()),
          );
          expect(await secure.read('filen_credentials'), raw);
        }
      },
    );

    test(
      'SDK logout verifies deletion and permits retry after a no-op',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'crisp-filen-delete-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final storage = _FilenPersistentStorage();
        final config = FilenConfigService(
          configPath: directory.path,
          secureStorage: storage,
        );
        await config.sdkStorage.saveCredentials(_filenCredentials);
        storage.failure = 'drop-delete';

        await expectLater(
          config.sdkStorage.clearCredentials(),
          throwsA(isA<FilenCredentialDeletionFailure>()),
        );
        expect(await config.readCredentials(), _filenCredentials);
        storage.failure = '';
        await config.sdkStorage.clearCredentials();
        expect(await config.readCredentials(), isNull);
      },
    );
  });

  group('SFTPConfigService', () {
    late InMemorySecureStorage secure;

    setUp(() {
      secure = InMemorySecureStorage();
    });

    test('readCredentials returns null when empty', () async {
      final config = SFTPConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      final creds = await config.readCredentials();
      expect(creds, isNull);
    });

    test('saveCredentials and readCredentials round-trip', () async {
      final config = SFTPConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      await config.saveCredentials({
        'host': 'example.com',
        'port': '22',
        'username': 'user',
      });

      final creds = await config.readCredentials();
      expect(creds, isNotNull);
      expect(creds!['host'], equals('example.com'));
    });

    test('clearCredentials removes data', () async {
      final config = SFTPConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      await config.saveCredentials({'host': 'test.com'});
      await config.clearCredentials();
      final creds = await config.readCredentials();
      expect(creds, isNull);
    });
  });

  group('WebDavConfigService', () {
    late InMemorySecureStorage secure;

    setUp(() {
      secure = InMemorySecureStorage();
    });

    test('readCredentials returns null when empty', () async {
      final config = WebDavConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      final creds = await config.readCredentials();
      expect(creds, isNull);
    });

    test('saveCredentials and readCredentials round-trip', () async {
      final config = WebDavConfigService(
        configPath: '/tmp/test',
        secureStorage: secure,
      );
      await config.saveCredentials({
        'url': 'https://dav.example.com',
        'username': 'admin',
      });

      final creds = await config.readCredentials();
      expect(creds, isNotNull);
      expect(creds!['url'], equals('https://dav.example.com'));
    });
  });
}
