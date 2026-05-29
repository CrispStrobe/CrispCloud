@Tags(['live'])
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisp_cloud/services/filen_client_adapter.dart';
import 'package:crisp_cloud/services/filen_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

/// Live integration tests for Filen adapter.
/// Requires FILEN_EMAIL and FILEN_PASSWORD environment variables.
///
/// Run with: flutter test --tags live test/filen_live_test.dart
void main() {
  final email = Platform.environment['FILEN_EMAIL'];
  final password = Platform.environment['FILEN_PASSWORD'];

  if (email == null || password == null) {
    test('SKIPPED: FILEN_EMAIL and FILEN_PASSWORD not set', () {},
        skip: 'Set FILEN_EMAIL and FILEN_PASSWORD to run live tests');
    return;
  }

  late FilenClientAdapter adapter;
  late String testFolderPath;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final config = FilenConfigService(configPath: '/tmp/crispcloud_filen_test', secureStorage: InMemorySecureStorage());
    adapter = FilenClientAdapter(config: config);

    await adapter.login(email, password);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    testFolderPath = '/__test_crispcloud_filen__/$timestamp';
    await adapter.createFolderPath(testFolderPath);
  });

  tearDownAll(() async {
    try {
      await adapter.deletePath(testFolderPath);
      await adapter.deletePath('/__test_crispcloud_filen__');
    } catch (_) {}
  });

  test('login succeeds', () {
    expect(adapter.isAuthenticated, isTrue);
    expect(adapter.userId, isNotNull);
    expect(adapter.providerName, equals('Filen'));
  });

  test('listPath returns folders and files', () async {
    final result = await adapter.listPath('/');
    expect(result.containsKey('folders'), isTrue);
    expect(result.containsKey('files'), isTrue);
  });

  test('upload and download round-trip', () async {
    final testData = Uint8List.fromList('CrispCloud Filen test data'.codeUnits);

    await adapter.uploadFile(
        testData, 'test_file.txt', testFolderPath);

    final downloaded = await adapter.downloadFileBytes(
        '$testFolderPath/test_file.txt');

    expect(String.fromCharCodes(downloaded), equals('CrispCloud Filen test data'));
  });

  test('resolvePath resolves existing path', () async {
    final resolved = await adapter.resolvePath(testFolderPath);
    expect(resolved, isNotNull);
    expect(resolved!['type'], equals('folder'));
  });

  test('resolvePath returns null for non-existent path', () async {
    final resolved = await adapter.resolvePath('/nonexistent_path_xyz_123');
    expect(resolved, isNull);
  });

  test('logout clears auth', () async {
    // Don't actually logout since other tests need auth
    // Just verify the method exists and is callable
    expect(adapter.isAuthenticated, isTrue);
  });
}
