@Tags(['live'])
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/sftp_client_adapter.dart';
import 'package:crisp_cloud/services/sftp_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

/// Live integration tests for SFTP adapter.
/// Requires SFTP_HOST, SFTP_USER, and SFTP_PASSWORD environment variables.
/// Optionally SFTP_PORT (default 22).
///
/// Run with: flutter test --tags live test/sftp_live_test.dart
void main() {
  final host = Platform.environment['SFTP_HOST'];
  final user = Platform.environment['SFTP_USER'];
  final password = Platform.environment['SFTP_PASSWORD'];
  final port = Platform.environment['SFTP_PORT'] ?? '22';

  if (host == null || user == null || password == null) {
    test('SKIPPED: SFTP_HOST, SFTP_USER, and SFTP_PASSWORD not set', () {},
        skip: 'Set SFTP env vars to run live tests');
    return;
  }

  late SFTPClientAdapter adapter;
  late String testDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final config = SFTPConfigService(configPath: '/tmp/crispcloud_sftp_test', secureStorage: InMemorySecureStorage());
    adapter = SFTPClientAdapter(config: config);

    final identity = '$user@$host:$port';
    await adapter.login(identity, password);

    testDir = '/tmp/crispcloud_sftp_test_${DateTime.now().millisecondsSinceEpoch}';
    await adapter.createFolderPath(testDir);
  });

  tearDownAll(() async {
    try {
      await adapter.deletePath(testDir);
    } catch (_) {}
    await adapter.logout();
  });

  test('login succeeds', () {
    expect(adapter.isAuthenticated, isTrue);
    expect(adapter.providerName, equals('SFTP'));
  });

  test('listPath returns folder contents', () async {
    final result = await adapter.listPath('/');
    expect(result, containsKey('folders'));
    expect(result, containsKey('files'));
  });

  test('upload and download round-trip', () async {
    final testData = Uint8List.fromList('SFTP round-trip test'.codeUnits);

    await adapter.uploadFile(testData, 'sftp_test.txt', testDir);

    final downloaded = await adapter.downloadFileBytes('$testDir/sftp_test.txt');
    expect(String.fromCharCodes(downloaded), equals('SFTP round-trip test'));
  });

  test('rename works', () async {
    final testData = Uint8List.fromList('rename test'.codeUnits);
    await adapter.uploadFile(testData, 'before_rename.txt', testDir);

    await adapter.renamePath('$testDir/before_rename.txt', 'after_rename.txt');

    final resolved = await adapter.resolvePath('$testDir/after_rename.txt');
    expect(resolved, isNotNull);
  });

  test('delete works', () async {
    final testData = Uint8List.fromList('delete test'.codeUnits);
    await adapter.uploadFile(testData, 'to_delete.txt', testDir);

    await adapter.deletePath('$testDir/to_delete.txt');

    final resolved = await adapter.resolvePath('$testDir/to_delete.txt');
    expect(resolved, isNull);
  });
}
