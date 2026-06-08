// test/integration/s3_flow_test.dart
//
// Full user-flow integration tests for S3ClientAdapter using MockS3Server.
// Each test group starts a real HTTP server on port 0 and makes real I/O
// requests through the adapter.
//
// Run in isolation:
//   flutter test test/integration/s3_flow_test.dart --tags integration
@Tags(['integration'])

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/s3_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

import '../mock_server/mock_s3_server.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _bucket = 'test-bucket';
const _accessKey = 'test-access-key';
const _secretKey = 'test-secret-key';
const _region = 'us-east-1';

/// Build a fresh adapter already connected to [server].
Future<S3ClientAdapter> _connect(MockS3Server server) async {
  SharedPreferences.setMockInitialValues({});
  final config = S3ConfigService(
    configPath: '/tmp/s3_integration_test',
    secureStorage: InMemorySecureStorage(),
  );
  final adapter = S3ClientAdapter(config: config);

  // Login identity format: accessKey@endpoint/bucket?region=...
  final identity =
      '$_accessKey@${server.baseUrl}/$_bucket?region=$_region';
  await adapter.login(identity, _secretKey);
  return adapter;
}

/// Generate deterministic test data of [length] bytes.
Uint8List _testData(int length, {int seed = 0xAB}) {
  return Uint8List.fromList(
    List.generate(length, (i) => (i + seed) & 0xFF),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('S3ClientAdapter integration – basic lifecycle', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('server starts on a non-zero port', () {
      expect(server.port, greaterThan(0));
    });

    test('login succeeds and isAuthenticated is true', () {
      expect(adapter.isAuthenticated, isTrue);
    });

    test('userId equals the access key after login', () {
      expect(adapter.userId, equals(_accessKey));
    });

    test('bucketId equals the bucket name after login', () {
      expect(adapter.bucketId, equals(_bucket));
    });

    test('logout sets isAuthenticated to false', () async {
      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
    });

    test('providerName is S3', () {
      expect(adapter.providerName, equals('S3'));
    });

    test('rootPath is /', () {
      expect(adapter.rootPath, equals('/'));
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – empty bucket listing', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('listPath("/") returns empty folders and files on fresh bucket', () async {
      final result = await adapter.listPath('/');
      expect(result['folders'], isEmpty);
      expect(result['files'], isEmpty);
    });

    test('listPath returns map with folders and files keys', () async {
      final result = await adapter.listPath('/');
      expect(result, containsPair('folders', isA<List>()));
      expect(result, containsPair('files', isA<List>()));
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – single file upload and download', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('uploadFile places file in bucket', () async {
      final data = _testData(1024);
      await adapter.uploadFile(data, 'hello.bin', '/');

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'hello.bin'), isTrue);
    });

    test('uploadFile reports correct file size in listing', () async {
      final data = _testData(1024);
      await adapter.uploadFile(data, 'sized.bin', '/');

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      final entry = files.firstWhere((f) => f['name'] == 'sized.bin');
      expect(entry['size'], equals(1024));
    });

    test('downloadFileBytes returns exact uploaded content', () async {
      final data = _testData(1024);
      await adapter.uploadFile(data, 'roundtrip.bin', '/');

      final downloaded = await adapter.downloadFileBytes('/roundtrip.bin');
      expect(downloaded, equals(data));
    });

    test('downloadFileBytes returns correct length', () async {
      final data = _testData(512);
      await adapter.uploadFile(data, 'len_check.bin', '/');

      final downloaded = await adapter.downloadFileBytes('/len_check.bin');
      expect(downloaded.length, equals(512));
    });

    test('uploadFile with progress callback invokes callback', () async {
      final data = _testData(256);
      int? calledLoaded;
      int? calledTotal;

      await adapter.uploadFile(
        data,
        'progress.bin',
        '/',
        onProgress: (loaded, total) {
          calledLoaded = loaded;
          calledTotal = total;
        },
      );

      expect(calledLoaded, equals(256));
      expect(calledTotal, equals(256));
    });

    test('downloadFileBytes with progress callback invokes callback', () async {
      final data = _testData(128);
      await adapter.uploadFile(data, 'dl_progress.bin', '/');

      int? calledLoaded;
      int? calledTotal;

      await adapter.downloadFileBytes(
        '/dl_progress.bin',
        onProgress: (loaded, total) {
          calledLoaded = loaded;
          calledTotal = total;
        },
      );

      expect(calledLoaded, equals(128));
      expect(calledTotal, equals(128));
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – rename', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('renamePath moves file to new name', () async {
      final data = _testData(256);
      await adapter.uploadFile(data, 'original.bin', '/');

      await adapter.renamePath('/original.bin', 'renamed.bin');

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      final names = files.map((f) => f['name']).toList();
      expect(names, contains('renamed.bin'));
      expect(names, isNot(contains('original.bin')));
    });

    test('renamePath preserves file content', () async {
      final data = _testData(512);
      await adapter.uploadFile(data, 'before.bin', '/');

      await adapter.renamePath('/before.bin', 'after.bin');

      final downloaded = await adapter.downloadFileBytes('/after.bin');
      expect(downloaded, equals(data));
    });

    test('renamePath removes old key from listing', () async {
      final data = _testData(64);
      await adapter.uploadFile(data, 'old_name.bin', '/');
      await adapter.renamePath('/old_name.bin', 'new_name.bin');

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'old_name.bin'), isFalse);
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – folder operations', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('createFolderPath creates folder prefix in listing', () async {
      await adapter.createFolderPath('/documents');

      final result = await adapter.listPath('/');
      final folders = result['folders'] as List;
      expect(folders.any((f) => f['name'] == 'documents'), isTrue);
    });

    test('upload inside folder shows in nested listing', () async {
      await adapter.createFolderPath('/photos');
      final data = _testData(256);
      await adapter.uploadFile(data, 'picture.bin', '/photos');

      final result = await adapter.listPath('/photos');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'picture.bin'), isTrue);
    });

    test('nested file does not appear in root listing files', () async {
      await adapter.createFolderPath('/nested');
      final data = _testData(64);
      await adapter.uploadFile(data, 'inner.bin', '/nested');

      final root = await adapter.listPath('/');
      final rootFiles = root['files'] as List;
      expect(rootFiles.any((f) => f['name'] == 'inner.bin'), isFalse);
    });

    test('nested folder appears as folder in root listing', () async {
      await adapter.createFolderPath('/music');

      final root = await adapter.listPath('/');
      final folders = root['folders'] as List;
      expect(folders.any((f) => f['name'] == 'music'), isTrue);
    });

    test('file in subfolder can be downloaded', () async {
      await adapter.createFolderPath('/videos');
      final data = _testData(512);
      await adapter.uploadFile(data, 'clip.bin', '/videos');

      final downloaded = await adapter.downloadFileBytes('/videos/clip.bin');
      expect(downloaded, equals(data));
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – delete', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('deletePath removes file from listing', () async {
      final data = _testData(128);
      await adapter.uploadFile(data, 'to_delete.bin', '/');

      await adapter.deletePath('/to_delete.bin');

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'to_delete.bin'), isFalse);
    });

    test('listing is empty after deleting the only file', () async {
      final data = _testData(64);
      await adapter.uploadFile(data, 'sole.bin', '/');
      await adapter.deletePath('/sole.bin');

      final result = await adapter.listPath('/');
      expect(result['files'], isEmpty);
    });

    test('deleting one file does not remove sibling files', () async {
      final data = _testData(64);
      await adapter.uploadFile(data, 'keep_me.bin', '/');
      await adapter.uploadFile(data, 'delete_me.bin', '/');

      await adapter.deletePath('/delete_me.bin');

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'keep_me.bin'), isTrue);
      expect(files.any((f) => f['name'] == 'delete_me.bin'), isFalse);
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – multiple files', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('upload 5 files and list returns all 5', () async {
      for (int i = 0; i < 5; i++) {
        final data = _testData(128, seed: i);
        await adapter.uploadFile(data, 'file_$i.bin', '/');
      }

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      expect(files.length, equals(5));
    });

    test('each of 5 files has distinct content', () async {
      final originals = <String, Uint8List>{};
      for (int i = 0; i < 5; i++) {
        final data = _testData(256, seed: i * 7);
        originals['multi_$i.bin'] = data;
        await adapter.uploadFile(data, 'multi_$i.bin', '/');
      }

      for (final entry in originals.entries) {
        final downloaded =
            await adapter.downloadFileBytes('/${entry.key}');
        expect(downloaded, equals(entry.value),
            reason: 'Content mismatch for ${entry.key}');
      }
    });

    test('upload 5 files then delete 2, listing shows 3 remaining', () async {
      for (int i = 0; i < 5; i++) {
        await adapter.uploadFile(_testData(64), 'del_test_$i.bin', '/');
      }
      await adapter.deletePath('/del_test_0.bin');
      await adapter.deletePath('/del_test_4.bin');

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      expect(files.length, equals(3));
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – special characters in filenames', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('filename with spaces round-trips correctly', () async {
      final data = _testData(128);
      await adapter.uploadFile(data, 'my file.bin', '/');

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'my file.bin'), isTrue);

      final downloaded = await adapter.downloadFileBytes('/my file.bin');
      expect(downloaded, equals(data));
    });

    test('filename with unicode characters round-trips correctly', () async {
      final data = _testData(128);
      await adapter.uploadFile(data, 'файл.bin', '/');

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'файл.bin'), isTrue);

      final downloaded = await adapter.downloadFileBytes('/файл.bin');
      expect(downloaded, equals(data));
    });

    test('filename with hyphens and underscores round-trips', () async {
      final data = _testData(64);
      await adapter.uploadFile(data, 'my-file_name.bin', '/');

      final downloaded =
          await adapter.downloadFileBytes('/my-file_name.bin');
      expect(downloaded, equals(data));
    });

    test('filename with dots round-trips', () async {
      final data = _testData(64);
      await adapter.uploadFile(data, 'archive.tar.gz', '/');

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'archive.tar.gz'), isTrue);
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – large file', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('upload and download 100KB file preserves content', () async {
      final data = _testData(100 * 1024);
      await adapter.uploadFile(data, 'large.bin', '/');

      final downloaded = await adapter.downloadFileBytes('/large.bin');
      expect(downloaded.length, equals(100 * 1024));
      expect(downloaded, equals(data));
    });

    test('100KB file appears in listing with correct size', () async {
      final data = _testData(100 * 1024);
      await adapter.uploadFile(data, 'large_listed.bin', '/');

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      final entry =
          files.firstWhere((f) => f['name'] == 'large_listed.bin');
      expect(entry['size'], equals(100 * 1024));
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – movePath', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('movePath moves file to target folder', () async {
      final data = _testData(128);
      await adapter.uploadFile(data, 'movable.bin', '/');
      await adapter.createFolderPath('/target');

      await adapter.movePath('/movable.bin', '/target');

      final targetListing = await adapter.listPath('/target');
      final files = targetListing['files'] as List;
      expect(files.any((f) => f['name'] == 'movable.bin'), isTrue);
    });

    test('movePath removes file from source location', () async {
      final data = _testData(128);
      await adapter.uploadFile(data, 'move_src.bin', '/');
      await adapter.createFolderPath('/dest');

      await adapter.movePath('/move_src.bin', '/dest');

      // After move, source key must be gone from the root listing.
      final root = await adapter.listPath('/');
      final rootFiles = root['files'] as List;
      expect(rootFiles.any((f) => f['name'] == 'move_src.bin'), isFalse);
    });

    test('movePath makes file accessible at destination', () async {
      final data = _testData(128);
      await adapter.uploadFile(data, 'present.bin', '/');
      await adapter.createFolderPath('/arrived');

      await adapter.movePath('/present.bin', '/arrived');

      final destListing = await adapter.listPath('/arrived');
      final destFiles = destListing['files'] as List;
      expect(destFiles.any((f) => f['name'] == 'present.bin'), isTrue);
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – capability flags', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('supportsMultipart is true', () {
      expect(adapter.supportsMultipart, isTrue);
    });

    test('supportsStreaming is true', () {
      expect(adapter.supportsStreaming, isTrue);
    });

    test('supportsServerSideCopy is true', () {
      expect(adapter.supportsServerSideCopy, isTrue);
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – resolvePath', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('resolvePath("/") returns folder entry for root', () async {
      final result = await adapter.resolvePath('/');
      expect(result, isNotNull);
      expect(result!['type'], equals('folder'));
    });

    test('resolvePath for uploaded file returns file entry', () async {
      final data = _testData(64);
      await adapter.uploadFile(data, 'resolve_me.bin', '/');

      final result = await adapter.resolvePath('/resolve_me.bin');
      expect(result, isNotNull);
      expect(result!['type'], equals('file'));
    });

    test('resolvePath for non-existent key returns null', () async {
      final result = await adapter.resolvePath('/does_not_exist.bin');
      expect(result, isNull);
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – presigned URLs', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('generatePresignedUrl produces valid URL with correct path', () async {
      await adapter.uploadFile(_testData(128), 'share-me.bin', '/');

      final url = adapter.generatePresignedUrl('/share-me.bin');
      final parsed = Uri.parse(url);

      // URL should point to the mock server
      expect(parsed.host, equals('127.0.0.1'));
      expect(parsed.port, equals(server.port));
      // Path should include bucket and key
      expect(parsed.path, contains('test-bucket'));
      expect(parsed.path, contains('share-me.bin'));
      // Query should have SigV4 params
      expect(parsed.queryParameters['X-Amz-Algorithm'], equals('AWS4-HMAC-SHA256'));
      expect(parsed.queryParameters['X-Amz-Credential'], contains(_accessKey));
      expect(parsed.queryParameters['X-Amz-Signature'], isNotNull);
      expect(parsed.queryParameters['X-Amz-Signature']!.length, equals(64));
    });

    test('generatePresignedUrl with custom expiry sets correct X-Amz-Expires', () async {
      await adapter.uploadFile(_testData(64), 'expire-test.txt', '/');

      final url = adapter.generatePresignedUrl(
        '/expire-test.txt',
        expires: const Duration(minutes: 15),
      );
      final parsed = Uri.parse(url);
      expect(parsed.queryParameters['X-Amz-Expires'], equals('900'));
    });

    test('generatePresignedUploadUrl produces different signature than GET', () async {
      final getUrl = adapter.generatePresignedUrl('/test.txt');
      final putUrl = adapter.generatePresignedUploadUrl('/test.txt');

      final getSig = Uri.parse(getUrl).queryParameters['X-Amz-Signature'];
      final putSig = Uri.parse(putUrl).queryParameters['X-Amz-Signature'];

      expect(getSig, isNot(equals(putSig)),
          reason: 'GET and PUT presigned URLs should have different signatures');
    });

    test('presigned URL for different paths produces different signatures', () async {
      await adapter.uploadFile(_testData(32), 'a.txt', '/');
      await adapter.uploadFile(_testData(32), 'b.txt', '/');

      final urlA = adapter.generatePresignedUrl('/a.txt');
      final urlB = adapter.generatePresignedUrl('/b.txt');

      final sigA = Uri.parse(urlA).queryParameters['X-Amz-Signature'];
      final sigB = Uri.parse(urlB).queryParameters['X-Amz-Signature'];

      expect(sigA, isNot(equals(sigB)));
    });

    test('presigned URL for subfolder paths works correctly', () async {
      await adapter.createFolderPath('/photos');
      await adapter.uploadFile(_testData(64), 'cat.jpg', '/photos');

      final url = adapter.generatePresignedUrl('/photos/cat.jpg');
      final parsed = Uri.parse(url);

      expect(parsed.path, contains('photos'));
      expect(parsed.path, contains('cat.jpg'));
      expect(parsed.queryParameters['X-Amz-Algorithm'], equals('AWS4-HMAC-SHA256'));
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – server-side encryption', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('SSE-S3 encrypted upload still works (mock server ignores headers)', () async {
      adapter.encryption = S3Encryption.sseS3;

      final data = _testData(256);
      await adapter.uploadFile(data, 'encrypted.bin', '/');

      final downloaded = await adapter.downloadFileBytes('/encrypted.bin');
      expect(downloaded, equals(data));
    });

    test('SSE-KMS encrypted upload still works', () async {
      adapter.encryption = S3Encryption.sseKms;
      adapter.kmsKeyId = 'arn:aws:kms:us-east-1:123456:key/test-key-id';

      final data = _testData(512);
      await adapter.uploadFile(data, 'kms-file.bin', '/');

      final downloaded = await adapter.downloadFileBytes('/kms-file.bin');
      expect(downloaded, equals(data));
    });

    test('encryption setting persists through credential save/restore', () async {
      adapter.encryption = S3Encryption.sseKms;
      adapter.kmsKeyId = 'arn:aws:kms:us-east-1:123:key/abc';
      adapter.storageClass = S3StorageClass.standardIa;

      // Re-save credentials with the updated encryption/storage class settings
      await adapter.config.saveCredentials({
        'accessKey': _accessKey,
        'secretKey': _secretKey,
        'endpoint': server.baseUrl,
        'bucket': _bucket,
        'region': _region,
        'encryption': adapter.encryption.name,
        'kmsKeyId': adapter.kmsKeyId!,
        'storageClass': adapter.storageClass.headerValue,
      });

      // Create a new adapter sharing the same config service to restore
      final adapter2 = S3ClientAdapter(config: adapter.config);
      final restored = await adapter2.restoreCredentials();

      expect(restored, isTrue);
      expect(adapter2.encryption, equals(S3Encryption.sseKms));
      expect(adapter2.kmsKeyId, equals('arn:aws:kms:us-east-1:123:key/abc'));
      expect(adapter2.storageClass, equals(S3StorageClass.standardIa));
    });
  });

  // -------------------------------------------------------------------------

  group('S3ClientAdapter integration – storage classes', () {
    late MockS3Server server;
    late S3ClientAdapter adapter;

    setUp(() async {
      server = MockS3Server();
      await server.start();
      server.createBucket(_bucket);
      adapter = await _connect(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('upload with non-default storage class works', () async {
      adapter.storageClass = S3StorageClass.standardIa;

      final data = _testData(128);
      await adapter.uploadFile(data, 'ia-file.bin', '/');

      final downloaded = await adapter.downloadFileBytes('/ia-file.bin');
      expect(downloaded, equals(data));
    });

    test('upload with glacier storage class works', () async {
      adapter.storageClass = S3StorageClass.glacier;

      final data = _testData(64);
      await adapter.uploadFile(data, 'glacier-file.bin', '/');

      // File should be listed
      final listing = await adapter.listPath('/');
      final files = listing['files'] as List;
      final names = files.map((f) => f['name']).toList();
      expect(names, contains('glacier-file.bin'));
    });

    test('changing storage class between uploads applies to each file', () async {
      adapter.storageClass = S3StorageClass.standard;
      await adapter.uploadFile(_testData(32), 'standard.bin', '/');

      adapter.storageClass = S3StorageClass.intelligentTiering;
      await adapter.uploadFile(_testData(32), 'tiered.bin', '/');

      // Both files should exist
      final listing = await adapter.listPath('/');
      final files = listing['files'] as List;
      expect(files.length, equals(2));
    });
  });
}
