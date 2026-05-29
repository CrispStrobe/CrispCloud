// test/gdrive_live_test.dart
//
// Live integration tests for Google Drive.
// Requires environment variables:
//   GDRIVE_CLIENT_ID    — OAuth2 client ID from Google Cloud Console
//   GDRIVE_REFRESH_TOKEN — A pre-obtained refresh token
//   GDRIVE_CLIENT_SECRET — (optional) OAuth2 client secret
//
// Run: flutter test test/gdrive_live_test.dart

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/gdrive_client_adapter.dart';
import 'package:crisp_cloud/services/gdrive_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  final clientId = Platform.environment['GDRIVE_CLIENT_ID'];
  final refreshToken = Platform.environment['GDRIVE_REFRESH_TOKEN'];
  final clientSecret = Platform.environment['GDRIVE_CLIENT_SECRET'] ?? '';

  final skip = clientId == null || refreshToken == null
      ? 'Set GDRIVE_CLIENT_ID and GDRIVE_REFRESH_TOKEN to run live tests'
      : null;

  late GDriveClientAdapter adapter;
  late GDriveConfigService configService;
  late InMemorySecureStorage secureStorage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    secureStorage = InMemorySecureStorage();
    configService = GDriveConfigService(
      configPath: '/tmp/gdrive_live_test',
      secureStorage: secureStorage,
    );

    // Pre-seed credentials so restoreCredentials works
    if (clientId != null && refreshToken != null) {
      await configService.saveCredentials({
        'client_id': clientId,
        if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
        'refresh_token': refreshToken,
        'email': 'live-test@example.com',
      });
    }

    adapter = GDriveClientAdapter(config: configService);
  });

  group('GDrive live tests', skip: skip, () {
    test('restoreCredentials succeeds with valid refresh token', () async {
      final result = await adapter.restoreCredentials();
      expect(result, isTrue);
      expect(adapter.isAuthenticated, isTrue);
    });

    test('listPath root returns folders and files', () async {
      await adapter.restoreCredentials();
      final result = await adapter.listPath('/');
      expect(result, containsPair('folders', isA<List>()));
      expect(result, containsPair('files', isA<List>()));
    });

    test('createFolderPath + listPath + deletePath round-trip', () async {
      await adapter.restoreCredentials();
      final testFolder = '/CrispCloud_Test_${Random().nextInt(99999)}';

      // Create
      await adapter.createFolderPath(testFolder);

      // Verify in listing
      final result = await adapter.listPath('/');
      final folders = result['folders'] as List;
      final found = folders.any((f) => f['name'] == testFolder.split('/').last);
      expect(found, isTrue);

      // Cleanup
      await adapter.deletePath(testFolder);
    });

    test('upload + download round-trip', () async {
      await adapter.restoreCredentials();
      final testData = Uint8List.fromList(List.generate(256, (i) => i % 256));
      final testName = 'crispcloud_test_${Random().nextInt(99999)}.bin';

      // Upload
      await adapter.uploadFile(testData, testName, '/');

      // Download
      final downloaded = await adapter.downloadFileBytes('/$testName');
      expect(downloaded, equals(testData));

      // Cleanup
      await adapter.deletePath('/$testName');
    });
  });
}
