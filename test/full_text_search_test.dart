import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/gdrive_client_adapter.dart';
import 'package:crisp_cloud/services/dropbox_client_adapter.dart';
import 'package:crisp_cloud/services/onedrive_client_adapter.dart';
import 'package:crisp_cloud/services/s3_client_adapter.dart';
import 'package:crisp_cloud/services/sftp_client_adapter.dart';
import 'package:crisp_cloud/services/ftp_client_adapter.dart';

// ---------------------------------------------------------------------------
// Fake client for testing the default fullTextSearch fallback
// ---------------------------------------------------------------------------

class _FakeStorageClient extends CloudStorageClient {
  final Map<String, String> fakeFiles; // path -> content
  final List<Map<String, dynamic>> fakeFileList;

  _FakeStorageClient({required this.fakeFiles, required this.fakeFileList});

  @override
  String get providerName => 'FakeProvider';
  @override
  String get rootPath => '/';
  @override
  bool get isAuthenticated => true;
  @override
  String? get userId => 'test-user';
  @override
  String? get bucketId => null;

  @override
  Future<void> login(String email, String password, {String? twoFactorCode}) async {}
  @override
  Future<bool> is2faNeeded(String email) async => false;
  @override
  Future<void> logout() async {}
  @override
  Future<Map<String, dynamic>?> resolvePath(String path) async => {'path': path};
  @override
  Future<void> uploadFile(List<int> fileData, String fileName, String targetPath, {Function(int, int)? onProgress}) async {}
  @override
  Future<void> downloadFileByPath(String remotePath, String localPath, {Function(int, int)? onProgress}) async {}
  @override
  Future<void> createFolderPath(String path) async {}
  @override
  Future<void> deletePath(String path) async {}
  @override
  Future<void> movePath(String sourcePath, String targetPath) async {}
  @override
  Future<void> renamePath(String path, String newName) async {}

  @override
  Future<Map<String, dynamic>> listPath(String path) async {
    return {
      'folders': <Map<String, dynamic>>[],
      'files': fakeFileList,
    };
  }

  @override
  Future<Uint8List> downloadFileBytes(String remotePath, {Function(int, int)? onProgress}) async {
    final fileName = remotePath.split('/').last;
    final content = fakeFiles[fileName];
    if (content == null) throw Exception('File not found: $remotePath');
    return Uint8List.fromList(content.codeUnits);
  }
}

void main() {
  group('CloudStorageClient.supportsFullTextSearch', () {
    test('GDrive supports full-text search', () {
      final client = GDriveClientAdapter(config: null);
      expect(client.supportsFullTextSearch, isTrue);
    });

    test('Dropbox supports full-text search', () {
      final client = DropboxClientAdapter(config: null);
      expect(client.supportsFullTextSearch, isTrue);
    });

    test('OneDrive supports full-text search', () {
      final client = OneDriveClientAdapter(config: null);
      expect(client.supportsFullTextSearch, isTrue);
    });

    test('S3 does not support full-text search', () {
      final client = S3ClientAdapter(config: null);
      expect(client.supportsFullTextSearch, isFalse);
    });

    test('SFTP does not support full-text search', () {
      final client = SFTPClientAdapter(config: null);
      expect(client.supportsFullTextSearch, isFalse);
    });

    test('FTP does not support full-text search', () {
      final client = FTPClientAdapter(config: null);
      expect(client.supportsFullTextSearch, isFalse);
    });
  });

  group('Default fullTextSearch fallback', () {
    test('finds matching content in text files', () async {
      final client = _FakeStorageClient(
        fakeFiles: {
          'readme.txt': 'Hello world, this is a test file with important data.',
          'notes.md': 'Some notes about flutter development.',
          'config.json': '{"key": "value", "important": true}',
        },
        fakeFileList: [
          {'name': 'readme.txt', 'uuid': '1', 'size': 50},
          {'name': 'notes.md', 'uuid': '2', 'size': 40},
          {'name': 'config.json', 'uuid': '3', 'size': 35},
          {'name': 'image.png', 'uuid': '4', 'size': 1000},
        ],
      );

      final results = await client.fullTextSearch('important', '/');
      expect(results.length, 2); // readme.txt and config.json
      final names = results.map((r) => r['name']).toSet();
      expect(names, contains('readme.txt'));
      expect(names, contains('config.json'));
    });

    test('returns empty list when no matches found', () async {
      final client = _FakeStorageClient(
        fakeFiles: {
          'readme.txt': 'Hello world.',
        },
        fakeFileList: [
          {'name': 'readme.txt', 'uuid': '1', 'size': 12},
        ],
      );

      final results = await client.fullTextSearch('nonexistent_term_xyz', '/');
      expect(results, isEmpty);
    });

    test('skips non-text files', () async {
      final client = _FakeStorageClient(
        fakeFiles: {
          'photo.png': 'binary data here with search term',
        },
        fakeFileList: [
          {'name': 'photo.png', 'uuid': '1', 'size': 30},
        ],
      );

      // .png is not a text extension, so it should be skipped
      final results = await client.fullTextSearch('search term', '/');
      expect(results, isEmpty);
    });

    test('skips files larger than 1 MB', () async {
      final client = _FakeStorageClient(
        fakeFiles: {
          'huge.txt': 'some content with keyword',
        },
        fakeFileList: [
          {'name': 'huge.txt', 'uuid': '1', 'size': 2 * 1024 * 1024},
        ],
      );

      final results = await client.fullTextSearch('keyword', '/');
      expect(results, isEmpty);
    });

    test('search is case-insensitive', () async {
      final client = _FakeStorageClient(
        fakeFiles: {
          'readme.txt': 'Hello WORLD.',
        },
        fakeFileList: [
          {'name': 'readme.txt', 'uuid': '1', 'size': 12},
        ],
      );

      final results = await client.fullTextSearch('hello world', '/');
      expect(results.length, 1);
    });

    test('results include snippet with context', () async {
      final client = _FakeStorageClient(
        fakeFiles: {
          'readme.txt': 'First line. The important keyword is here. Last line.',
        },
        fakeFileList: [
          {'name': 'readme.txt', 'uuid': '1', 'size': 50},
        ],
      );

      final results = await client.fullTextSearch('keyword', '/');
      expect(results.length, 1);
      expect(results.first['snippet'], isA<String>());
      expect((results.first['snippet'] as String).contains('keyword'), isTrue);
    });
  });

  group('GDrive fullTextSearch query format', () {
    test('GDriveClientAdapter has fullTextSearch method', () {
      // Verify the method exists and has the correct signature
      final client = GDriveClientAdapter(config: null);
      expect(client.supportsFullTextSearch, isTrue);
      // The method exists — calling it without auth would throw, but it's there
      expect(
        () => client.fullTextSearch('test', '/'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
