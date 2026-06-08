// test/provider_enhancements_live_test.dart
//
// Live tests for session 11 provider enhancements.
// Require real credentials — run manually:
//   flutter test test/provider_enhancements_live_test.dart --tags live
@Tags(['live'])

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/gdrive_client_adapter.dart';
import 'package:crisp_cloud/services/gdrive_config_service.dart';
import 'package:crisp_cloud/services/onedrive_client_adapter.dart';
import 'package:crisp_cloud/services/onedrive_config_service.dart';
import 'package:crisp_cloud/services/dropbox_client_adapter.dart';
import 'package:crisp_cloud/services/dropbox_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // S3 Presigned URL Live Tests
  // =========================================================================

  group('S3 presigned URL — live', () {
    late S3ClientAdapter adapter;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      final config = S3ConfigService(
        configPath: '/tmp/s3_live_test',
        secureStorage: InMemorySecureStorage(),
      );
      adapter = S3ClientAdapter(config: config);

      // TODO: Replace with real S3 credentials
      // await adapter.login(
      //   'AKIAEXAMPLE@https://s3.amazonaws.com/my-bucket?region=us-east-1',
      //   'secret-key-here',
      // );
    });

    test('presigned GET URL can be fetched with plain HTTP client', () async {
      // TODO: Upload a test file, generate presigned URL, fetch with http.get
      // final url = adapter.generatePresignedUrl('/test-file.txt');
      // final resp = await http.get(Uri.parse(url));
      // expect(resp.statusCode, equals(200));
    }, skip: 'Requires real S3 credentials');

    test('presigned PUT URL allows anonymous upload', () async {
      // TODO: Generate presigned PUT URL, upload data with http.put
      // final url = adapter.generatePresignedUploadUrl('/upload-test.txt');
      // final resp = await http.put(Uri.parse(url), body: 'Hello presigned');
      // expect(resp.statusCode, equals(200));
    }, skip: 'Requires real S3 credentials');

    test('SSE-S3 encrypted upload has encryption header in response', () async {
      // TODO: Upload with SSE-S3, verify response header
      // adapter.encryption = S3Encryption.sseS3;
      // await adapter.uploadFile(utf8.encode('secret'), 'sse-test.txt', '/');
      // HEAD should return x-amz-server-side-encryption: AES256
    }, skip: 'Requires real S3 credentials');

    test('storage class is applied to uploaded object', () async {
      // TODO: Upload with STANDARD_IA, check via HEAD or GetObjectAttributes
      // adapter.storageClass = S3StorageClass.standardIa;
      // await adapter.uploadFile(data, 'ia-test.txt', '/');
    }, skip: 'Requires real S3 credentials');
  });

  // =========================================================================
  // Google Drive Shared Drives Live Tests
  // =========================================================================

  group('GDrive shared drives — live', () {
    late GDriveClientAdapter adapter;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      final config = GDriveConfigService(
        configPath: '/tmp/gdrive_live_test',
        secureStorage: InMemorySecureStorage(),
      );
      adapter = GDriveClientAdapter(config: config);

      // TODO: Replace with real GDrive credentials (requires OAuth)
    });

    test('listSharedDrives returns a list of drives', () async {
      // final drives = await adapter.listSharedDrives();
      // expect(drives, isA<List>());
      // for (final drive in drives) {
      //   expect(drive['id'], isNotEmpty);
      //   expect(drive['name'], isNotEmpty);
      // }
    }, skip: 'Requires real GDrive credentials with Workspace');

    test('listSharedDrivePath lists files in shared drive root', () async {
      // final drives = await adapter.listSharedDrives();
      // if (drives.isNotEmpty) {
      //   final result = await adapter.listSharedDrivePath(drives.first['id']!, '/');
      //   expect(result['folders'], isA<List>());
      //   expect(result['files'], isA<List>());
      // }
    }, skip: 'Requires real GDrive credentials with Workspace');

    test('listStarredFiles returns starred items', () async {
      // final starred = await adapter.listStarredFiles();
      // expect(starred, isA<List>());
    }, skip: 'Requires real GDrive credentials');

    test('setStarred toggles star on a file', () async {
      // const fileId = 'known-file-id';
      // await adapter.setStarred(fileId, true);
      // final starred = await adapter.listStarredFiles();
      // expect(starred.any((f) => f['uuid'] == fileId), isTrue);
      // await adapter.setStarred(fileId, false);
    }, skip: 'Requires real GDrive credentials');
  });

  // =========================================================================
  // OneDrive Delta Sync Live Tests
  // =========================================================================

  group('OneDrive delta sync — live', () {
    late OneDriveClientAdapter adapter;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      final config = OneDriveConfigService(
        configPath: '/tmp/onedrive_live_test',
        secureStorage: InMemorySecureStorage(),
      );
      adapter = OneDriveClientAdapter(config: config);
    });

    test('initial fetchDelta returns full enumeration with deltaToken', () async {
      // final result = await adapter.fetchDelta();
      // expect(result['added'], isA<List>());
      // expect(result['deleted'], isA<List>());
      // expect(result['deltaToken'], isNotNull);
      // expect((result['deltaToken'] as String).contains('delta'), isTrue);
    }, skip: 'Requires real OneDrive credentials');

    test('subsequent fetchDelta with token returns only changes', () async {
      // final initial = await adapter.fetchDelta();
      // final deltaToken = initial['deltaToken'] as String;
      //
      // // Upload a new file to create a change
      // await adapter.uploadFile(utf8.encode('delta test'), 'delta-test.txt', '/');
      //
      // final changes = await adapter.fetchDelta(deltaToken: deltaToken);
      // expect(changes['added'], isNotEmpty);
      // final names = (changes['added'] as List).map((i) => i['name']).toList();
      // expect(names, contains('delta-test.txt'));
    }, skip: 'Requires real OneDrive credentials');

    test('fetchDelta deleted items are tracked', () async {
      // final initial = await adapter.fetchDelta();
      // await adapter.uploadFile(utf8.encode('to delete'), 'to-delete.txt', '/');
      // final afterUpload = await adapter.fetchDelta(deltaToken: initial['deltaToken'] as String);
      // await adapter.deletePath('/to-delete.txt');
      // final afterDelete = await adapter.fetchDelta(deltaToken: afterUpload['deltaToken'] as String);
      // expect(afterDelete['deleted'], isNotEmpty);
    }, skip: 'Requires real OneDrive credentials');
  });

  // =========================================================================
  // Dropbox Shared Folders Live Tests
  // =========================================================================

  group('Dropbox shared folders — live', () {
    late DropboxClientAdapter adapter;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      final config = DropboxConfigService(
        configPath: '/tmp/dropbox_live_test',
        secureStorage: InMemorySecureStorage(),
      );
      adapter = DropboxClientAdapter(config: config);
    });

    test('listSharedFolders returns list with metadata', () async {
      // final folders = await adapter.listSharedFolders();
      // expect(folders, isA<List>());
      // for (final folder in folders) {
      //   expect(folder['name'], isNotEmpty);
      //   expect(folder['sharedFolderId'], isNotEmpty);
      //   expect(folder['accessType'], isNotEmpty);
      // }
    }, skip: 'Requires real Dropbox credentials');

    test('content_hash from listPath matches computeContentHash', () async {
      // Upload a known file, list it, compare hashes
      // final data = utf8.encode('Hello, Dropbox content hash!');
      // await adapter.uploadFile(data, 'hash-test.txt', '/');
      //
      // final listing = await adapter.listPath('/');
      // final file = (listing['files'] as List).firstWhere((f) => f['name'] == 'hash-test.txt');
      // final serverHash = file['content_hash'];
      // final localHash = DropboxClientAdapter.computeContentHash(data);
      // expect(localHash, equals(serverHash));
    }, skip: 'Requires real Dropbox credentials');

    test('mountSharedFolder adds folder to namespace', () async {
      // final folders = await adapter.listSharedFolders();
      // if (folders.isNotEmpty) {
      //   final folderId = folders.first['sharedFolderId'] as String;
      //   await adapter.mountSharedFolder(folderId);
      //   // Folder should now appear in listing
      // }
    }, skip: 'Requires real Dropbox credentials');
  });
}
