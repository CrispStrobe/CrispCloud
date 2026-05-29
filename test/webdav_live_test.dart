@Tags(['live'])
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/webdav_client_adapter.dart';
import 'package:crisp_cloud/services/webdav_config_service.dart';

/// Live integration tests for WebDAV adapter.
/// Requires WEBDAV_URL, WEBDAV_USER, and WEBDAV_PASSWORD environment variables.
///
/// Run with: flutter test --tags live test/webdav_live_test.dart
void main() {
  final url = Platform.environment['WEBDAV_URL'];
  final user = Platform.environment['WEBDAV_USER'];
  final password = Platform.environment['WEBDAV_PASSWORD'];

  if (url == null || user == null || password == null) {
    test('SKIPPED: WEBDAV_URL, WEBDAV_USER, and WEBDAV_PASSWORD not set', () {},
        skip: 'Set WEBDAV env vars to run live tests');
    return;
  }

  late WebDavClientAdapter adapter;
  late String testDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final config = WebDavConfigService(configPath: '/tmp/crispcloud_webdav_test');
    adapter = WebDavClientAdapter(config: config);

    final identity = '$user@$url';
    await adapter.login(identity, password);

    testDir = '/crispcloud_webdav_test_${DateTime.now().millisecondsSinceEpoch}';
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
    expect(adapter.providerName, equals('WebDAV'));
  });

  test('listPath returns folder contents', () async {
    final result = await adapter.listPath('/');
    expect(result, containsKey('folders'));
    expect(result, containsKey('files'));
  });

  test('upload and download round-trip', () async {
    final testData = Uint8List.fromList('WebDAV round-trip test'.codeUnits);

    await adapter.uploadFile(testData, 'webdav_test.txt', testDir);

    final downloaded =
        await adapter.downloadFileBytes('$testDir/webdav_test.txt');
    expect(String.fromCharCodes(downloaded), equals('WebDAV round-trip test'));
  });

  test('delete works', () async {
    final testData = Uint8List.fromList('delete me'.codeUnits);
    await adapter.uploadFile(testData, 'to_delete.txt', testDir);

    await adapter.deletePath('$testDir/to_delete.txt');

    final resolved = await adapter.resolvePath('$testDir/to_delete.txt');
    expect(resolved, isNull);
  });
}
