// test/config_test.dart
//
// Tests for CliConfig: read/write, provider save/remove, default provider.

import 'dart:io';

import 'package:test/test.dart';

import 'package:crisp/config/cli_config.dart';

void main() {
  late Directory tmp;
  late String configPath;
  late CliConfig config;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('crisp_test_');
    configPath = '${tmp.path}/config.yaml';
    config = CliConfig(path: configPath);
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  test('read returns empty map when file does not exist', () {
    expect(config.read(), isEmpty);
  });

  test('saveProvider persists and providerConfig retrieves it', () {
    config.saveProvider('my-s3', {
      'type': 's3',
      'access_key': 'AKIA',
      'secret_key': 'secret',
      'endpoint': 'https://s3.amazonaws.com',
      'bucket': 'mybucket',
      'region': 'us-east-1',
    });

    final cfg = config.providerConfig('my-s3');
    expect(cfg, isNotNull);
    expect(cfg!['type'], equals('s3'));
    expect(cfg['bucket'], equals('mybucket'));
    expect(cfg['region'], equals('us-east-1'));
  });

  test('providerNames returns sorted list', () {
    config.saveProvider('zzz', {'type': 'sftp'});
    config.saveProvider('aaa', {'type': 'webdav'});
    expect(config.providerNames(), equals(['aaa', 'zzz']));
  });

  test('removeProvider removes entry', () {
    config.saveProvider('to-remove', {'type': 's3'});
    config.removeProvider('to-remove');
    expect(config.providerConfig('to-remove'), isNull);
    expect(config.providerNames(), isEmpty);
  });

  test('defaultProvider getter/setter round-trips', () {
    config.saveProvider('p1', {'type': 's3'});
    config.defaultProvider = 'p1';
    expect(config.defaultProvider, equals('p1'));

    config.defaultProvider = null;
    expect(config.defaultProvider, isNull);
  });

  test('removeProvider clears defaultProvider if it was the default', () {
    config.saveProvider('p1', {'type': 's3'});
    config.defaultProvider = 'p1';
    config.removeProvider('p1');
    expect(config.defaultProvider, isNull);
  });

  test('resolveProviderName returns explicit name', () {
    config.saveProvider('p1', {'type': 's3'});
    expect(config.resolveProviderName('p1'), equals('p1'));
  });

  test('resolveProviderName falls back to defaultProvider', () {
    config.saveProvider('p1', {'type': 's3'});
    config.defaultProvider = 'p1';
    expect(config.resolveProviderName(null), equals('p1'));
  });

  test('resolveProviderName throws when no default and no explicit name', () {
    expect(
      () => config.resolveProviderName(null),
      throwsA(isA<CliConfigException>()),
    );
  });

  test('config file is created when saving a provider', () {
    config.saveProvider('p1', {'type': 's3'});
    expect(File(configPath).existsSync(), isTrue);
  });

  test('save multiple providers and read them back independently', () {
    config.saveProvider('s3-prod', {'type': 's3', 'bucket': 'prod'});
    config.saveProvider('sftp-home', {'type': 'sftp', 'host': 'home.server'});

    final s3 = config.providerConfig('s3-prod');
    final sftp = config.providerConfig('sftp-home');

    expect(s3!['bucket'], equals('prod'));
    expect(sftp!['host'], equals('home.server'));
  });
}
