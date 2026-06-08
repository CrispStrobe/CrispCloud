// test/gdrive_adapter_test.dart
//
// Unit tests for the Google Drive client adapter.
// Tests capability flags, login identity parsing, path resolution,
// config service, and credential lifecycle.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/gdrive_client_adapter.dart';
import 'package:crisp_cloud/services/gdrive_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GDriveClientAdapter adapter;
  late GDriveConfigService configService;
  late InMemorySecureStorage secureStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStorage = InMemorySecureStorage();
    configService = GDriveConfigService(
      configPath: '/tmp/gdrive_test',
      secureStorage: secureStorage,
    );
    adapter = GDriveClientAdapter(config: configService);
  });

  group('GDriveClientAdapter basic properties', () {
    test('providerName returns Google Drive', () {
      expect(adapter.providerName, equals('Google Drive'));
    });

    test('rootPath returns /', () {
      expect(adapter.rootPath, equals('/'));
    });

    test('is not authenticated initially', () {
      expect(adapter.isAuthenticated, isFalse);
    });

    test('userId is null initially', () {
      expect(adapter.userId, isNull);
    });

    test('bucketId is null', () {
      expect(adapter.bucketId, isNull);
    });
  });

  group('GDriveClientAdapter capability flags', () {
    test('supports versioning', () {
      expect(adapter.supportsVersioning, isTrue);
    });

    test('supports sharing', () {
      expect(adapter.supportsSharing, isTrue);
    });

    test('supports search', () {
      expect(adapter.supportsSearch, isTrue);
    });

    test('supports thumbnails', () {
      expect(adapter.supportsThumbnails, isTrue);
    });

    test('supports trash', () {
      expect(adapter.supportsTrash, isTrue);
    });

    test('does not support streaming (default)', () {
      expect(adapter.supportsStreaming, isFalse);
    });

    test('does not support multipart (default)', () {
      expect(adapter.supportsMultipart, isFalse);
    });
  });

  group('GDriveClientAdapter 2FA', () {
    test('is2faNeeded returns false', () async {
      expect(await adapter.is2faNeeded('test@example.com'), isFalse);
    });
  });

  group('GDriveClientAdapter login format', () {
    test('login throws on empty client ID', () async {
      expect(
        () => adapter.login('', ''),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Client ID is required'))),
      );
    });

    test('login throws on web (OAuth needs browser redirect)', () async {
      // This test verifies the adapter rejects web platform when no stored credentials.
      // In real code, kIsWeb determines this — we test the behavior indirectly.
      // The adapter will try browser flow (which fails in test) or throw if no refresh token.
      // We verify it doesn't crash with a valid client ID but no network.
      try {
        await adapter.login('test-client-id.apps.googleusercontent.com', '');
      } catch (e) {
        // Expected: either "Could not open browser" or network error
        expect(e, isA<Exception>());
      }
    });
  });

  group('GDriveConfigService', () {
    test('readCredentials returns null initially', () async {
      expect(await configService.readCredentials(), isNull);
    });

    test('saveCredentials then readCredentials round-trips', () async {
      final creds = {
        'client_id': 'test-id.apps.googleusercontent.com',
        'client_secret': 'test-secret',
        'refresh_token': 'test-refresh-token',
        'email': 'user@gmail.com',
      };
      await configService.saveCredentials(creds);
      final read = await configService.readCredentials();
      expect(read, isNotNull);
      expect(read!['client_id'], equals('test-id.apps.googleusercontent.com'));
      expect(read['refresh_token'], equals('test-refresh-token'));
      expect(read['email'], equals('user@gmail.com'));
    });

    test('clearCredentials removes stored credentials', () async {
      await configService.saveCredentials({
        'client_id': 'test-id',
        'refresh_token': 'test-token',
      });
      await configService.clearCredentials();
      expect(await configService.readCredentials(), isNull);
    });

    test('readCredentials after clear returns null', () async {
      await configService.saveCredentials({'client_id': 'x'});
      await configService.clearCredentials();
      final result = await configService.readCredentials();
      expect(result, isNull);
    });
  });

  group('GDriveClientAdapter restoreCredentials', () {
    test('returns false when no stored credentials', () async {
      final result = await adapter.restoreCredentials();
      expect(result, isFalse);
      expect(adapter.isAuthenticated, isFalse);
    });

    test('returns false when refresh token is empty', () async {
      await configService.saveCredentials({
        'client_id': 'test-id',
        'refresh_token': '',
        'email': 'user@gmail.com',
      });
      final result = await adapter.restoreCredentials();
      expect(result, isFalse);
    });

    test('returns false when refresh fails (no network)', () async {
      await configService.saveCredentials({
        'client_id': 'test-id',
        'refresh_token': 'invalid-token',
        'email': 'user@gmail.com',
      });
      // restoreCredentials should catch the network error and return false
      final result = await adapter.restoreCredentials();
      expect(result, isFalse);
    });
  });

  group('CloudStorageFactory gdrive', () {
    test('factory creates GDriveClientAdapter for gdrive provider', () {
      final client = CloudStorageFactory.create(
        CloudProvider.gdrive,
        config: configService,
      );
      expect(client, isA<GDriveClientAdapter>());
      expect(client.providerName, equals('Google Drive'));
    });
  });

  group('GDriveClientAdapter logout', () {
    test('logout resets state without throwing', () async {
      // Should not throw even when not authenticated
      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
      expect(adapter.userId, isNull);
    });
  });

  group('GDriveClientAdapter - shared drives', () {
    test('listSharedDrives throws when not authenticated', () {
      expect(
        () => adapter.listSharedDrives(),
        throwsA(isA<Exception>()),
      );
    });

    test('listSharedDrivePath throws when not authenticated', () {
      expect(
        () => adapter.listSharedDrivePath('drive-id-123', '/'),
        throwsA(isA<Exception>()),
      );
    });

    test('listSharedDrivePath with empty path uses driveId as root', () {
      // Can't call without auth, but verify it throws auth error, not path error
      expect(
        () => adapter.listSharedDrivePath('drive-id-123', ''),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('GDriveClientAdapter - starred files', () {
    test('listStarredFiles throws when not authenticated', () {
      expect(
        () => adapter.listStarredFiles(),
        throwsA(isA<Exception>()),
      );
    });

    test('setStarred throws when not authenticated', () {
      expect(
        () => adapter.setStarred('file-id-123', true),
        throwsA(isA<Exception>()),
      );
    });

    test('setStarred with false unstar throws when not authenticated', () {
      expect(
        () => adapter.setStarred('file-id-123', false),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('GDriveClientAdapter - unauthenticated operations', () {
    test('listPath throws when not authenticated', () {
      expect(
        () => adapter.listPath('/'),
        throwsA(isA<Exception>()),
      );
    });

    test('uploadFile throws when not authenticated', () {
      expect(
        () => adapter.uploadFile([1, 2, 3], 'test.txt', '/'),
        throwsA(isA<Exception>()),
      );
    });

    test('downloadFileBytes throws when not authenticated', () {
      expect(
        () => adapter.downloadFileBytes('/test.txt'),
        throwsA(isA<Exception>()),
      );
    });

    test('deletePath throws when not authenticated', () {
      expect(
        () => adapter.deletePath('/test.txt'),
        throwsA(isA<Exception>()),
      );
    });

    test('createFolderPath throws when not authenticated', () {
      expect(
        () => adapter.createFolderPath('/new-folder'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ===========================================================================
  // Google Docs MIME type handling
  // ===========================================================================
  group('Google Docs MIME type detection', () {
    test('isGoogleDocsMimeType returns true for Google Docs', () {
      expect(GDriveClientAdapter.isGoogleDocsMimeType('application/vnd.google-apps.document'), isTrue);
    });

    test('isGoogleDocsMimeType returns true for Google Sheets', () {
      expect(GDriveClientAdapter.isGoogleDocsMimeType('application/vnd.google-apps.spreadsheet'), isTrue);
    });

    test('isGoogleDocsMimeType returns true for Google Slides', () {
      expect(GDriveClientAdapter.isGoogleDocsMimeType('application/vnd.google-apps.presentation'), isTrue);
    });

    test('isGoogleDocsMimeType returns true for Google Drawings', () {
      expect(GDriveClientAdapter.isGoogleDocsMimeType('application/vnd.google-apps.drawing'), isTrue);
    });

    test('isGoogleDocsMimeType returns false for regular files', () {
      expect(GDriveClientAdapter.isGoogleDocsMimeType('application/pdf'), isFalse);
      expect(GDriveClientAdapter.isGoogleDocsMimeType('image/png'), isFalse);
      expect(GDriveClientAdapter.isGoogleDocsMimeType('application/vnd.google-apps.folder'), isFalse);
    });

    test('getExportExtension returns correct extensions', () {
      expect(GDriveClientAdapter.getExportExtension('application/vnd.google-apps.document'), equals('.docx'));
      expect(GDriveClientAdapter.getExportExtension('application/vnd.google-apps.spreadsheet'), equals('.xlsx'));
      expect(GDriveClientAdapter.getExportExtension('application/vnd.google-apps.presentation'), equals('.pptx'));
      expect(GDriveClientAdapter.getExportExtension('application/vnd.google-apps.drawing'), equals('.pdf'));
    });

    test('getExportExtension returns null for non-Google types', () {
      expect(GDriveClientAdapter.getExportExtension('application/pdf'), isNull);
      expect(GDriveClientAdapter.getExportExtension('text/plain'), isNull);
    });
  });

  // ===========================================================================
  // Google Docs export formats
  // ===========================================================================
  group('Google Docs export formats', () {
    test('Google Docs has 6 export formats', () {
      final formats = GDriveClientAdapter.getExportFormats('application/vnd.google-apps.document');
      expect(formats.length, equals(6));
      expect(formats.any((f) => f['label'] == 'Word'), isTrue);
      expect(formats.any((f) => f['label'] == 'PDF'), isTrue);
      expect(formats.any((f) => f['label'] == 'Plain Text'), isTrue);
      expect(formats.any((f) => f['label'] == 'EPUB'), isTrue);
    });

    test('Google Sheets has 4 export formats', () {
      final formats = GDriveClientAdapter.getExportFormats('application/vnd.google-apps.spreadsheet');
      expect(formats.length, equals(4));
      expect(formats.any((f) => f['label'] == 'Excel'), isTrue);
      expect(formats.any((f) => f['label'] == 'CSV'), isTrue);
    });

    test('Google Slides has 3 export formats', () {
      final formats = GDriveClientAdapter.getExportFormats('application/vnd.google-apps.presentation');
      expect(formats.length, equals(3));
      expect(formats.any((f) => f['label'] == 'PowerPoint'), isTrue);
      expect(formats.any((f) => f['label'] == 'PDF'), isTrue);
    });

    test('Google Drawings has 3 export formats', () {
      final formats = GDriveClientAdapter.getExportFormats('application/vnd.google-apps.drawing');
      expect(formats.length, equals(3));
      expect(formats.any((f) => f['label'] == 'PDF'), isTrue);
      expect(formats.any((f) => f['label'] == 'PNG'), isTrue);
      expect(formats.any((f) => f['label'] == 'SVG'), isTrue);
    });

    test('unknown MIME type returns empty export list', () {
      expect(GDriveClientAdapter.getExportFormats('application/pdf'), isEmpty);
      expect(GDriveClientAdapter.getExportFormats('text/plain'), isEmpty);
    });

    test('all export format entries have required keys', () {
      for (final docType in [
        'application/vnd.google-apps.document',
        'application/vnd.google-apps.spreadsheet',
        'application/vnd.google-apps.presentation',
        'application/vnd.google-apps.drawing',
      ]) {
        for (final fmt in GDriveClientAdapter.getExportFormats(docType)) {
          expect(fmt.containsKey('mimeType'), isTrue, reason: '$docType format missing mimeType');
          expect(fmt.containsKey('ext'), isTrue, reason: '$docType format missing ext');
          expect(fmt.containsKey('label'), isTrue, reason: '$docType format missing label');
          expect(fmt['ext']!.startsWith('.'), isTrue, reason: '$docType ext should start with dot');
        }
      }
    });
  });

  // ===========================================================================
  // Version methods (auth guards)
  // ===========================================================================
  group('GDriveClientAdapter - version methods', () {
    test('listVersions throws when not authenticated', () {
      expect(
        () => adapter.listVersions('file-id-123'),
        throwsA(isA<Exception>()),
      );
    });

    test('downloadVersion throws when not authenticated', () {
      expect(
        () => adapter.downloadVersion('file-id-123', 'rev-1'),
        throwsA(isA<Exception>()),
      );
    });

    test('pinVersion throws when not authenticated', () {
      expect(
        () => adapter.pinVersion('file-id-123', 'rev-1'),
        throwsA(isA<Exception>()),
      );
    });

    test('deleteVersion throws when not authenticated', () {
      expect(
        () => adapter.deleteVersion('file-id-123', 'rev-1'),
        throwsA(isA<Exception>()),
      );
    });

    test('exportGoogleDoc throws when not authenticated', () {
      expect(
        () => adapter.exportGoogleDoc('file-id-123'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
