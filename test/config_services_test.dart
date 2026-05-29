import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/sftp_config_service.dart';
import 'package:crisp_cloud/services/webdav_config_service.dart';

void main() {
  group('FilenConfigService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('readCredentials returns null when empty', () async {
      final config = FilenConfigService(configPath: '/tmp/test');
      final creds = await config.readCredentials();
      expect(creds, isNull);
    });

    test('saveCredentials and readCredentials round-trip', () async {
      final config = FilenConfigService(configPath: '/tmp/test');
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
      final config = FilenConfigService(configPath: '/tmp/test');
      await config.saveCredentials({'email': 'test@test.com'});
      await config.clearCredentials();
      final creds = await config.readCredentials();
      expect(creds, isNull);
    });

    test('generateBatchId returns non-empty string', () {
      final config = FilenConfigService(configPath: '/tmp/test');
      final id = config.generateBatchId('upload', ['file.txt'], '/docs');
      expect(id, isNotEmpty);
    });

    test('batch state CRUD', () async {
      final config = FilenConfigService(configPath: '/tmp/test');
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
      final config = FilenConfigService(configPath: '/tmp/test');
      await config.saveBatchState('batch1', {'a': 1});
      await config.saveBatchState('batch2', {'b': 2});

      final ids = await config.getAllBatchIds();
      expect(ids, containsAll(['batch1', 'batch2']));
    });

    test('provider preference CRUD', () async {
      final config = FilenConfigService(configPath: '/tmp/test');
      await config.saveProviderPreference('filen');
      final pref = await config.getProviderPreference();
      expect(pref, equals('filen'));
    });
  });

  group('SFTPConfigService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('readCredentials returns null when empty', () async {
      final config = SFTPConfigService(configPath: '/tmp/test');
      final creds = await config.readCredentials();
      expect(creds, isNull);
    });

    test('saveCredentials and readCredentials round-trip', () async {
      final config = SFTPConfigService(configPath: '/tmp/test');
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
      final config = SFTPConfigService(configPath: '/tmp/test');
      await config.saveCredentials({'host': 'test.com'});
      await config.clearCredentials();
      final creds = await config.readCredentials();
      expect(creds, isNull);
    });
  });

  group('WebDavConfigService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('readCredentials returns null when empty', () async {
      final config = WebDavConfigService(configPath: '/tmp/test');
      final creds = await config.readCredentials();
      expect(creds, isNull);
    });

    test('saveCredentials and readCredentials round-trip', () async {
      final config = WebDavConfigService(configPath: '/tmp/test');
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
