// test/integration/webdav_flow_test.dart
//
// Full user-flow integration tests for WebDavClientAdapter using MockWebDavServer.
// Each test group starts a real HTTP server on port 0 and makes real I/O
// requests through the adapter.
//
// Run in isolation:
//   flutter test test/integration/webdav_flow_test.dart --tags integration
@Tags(['integration'])

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/services/webdav_client_adapter.dart';
import 'package:crisp_cloud/services/webdav_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';

import '../mock_server/mock_webdav_server.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _user = 'testuser';
const _password = 'testpass';

/// Build a fresh adapter already logged in to [server].
Future<WebDavClientAdapter> _login(MockWebDavServer server) async {
  final config = WebDavConfigService(
    configPath: '/tmp/webdav_integration_test',
    secureStorage: InMemorySecureStorage(),
  );
  final adapter = WebDavClientAdapter(config: config);

  // Login identity format: user@serverURL
  final identity = '$_user@${server.baseUrl}';
  await adapter.login(identity, _password);
  return adapter;
}

/// Generate deterministic test data of [length] bytes.
Uint8List _testData(int length, {int seed = 0xCD}) {
  return Uint8List.fromList(
    List.generate(length, (i) => (i + seed) & 0xFF),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('WebDavClientAdapter integration – basic lifecycle', () {
    late MockWebDavServer server;
    late WebDavClientAdapter adapter;

    setUp(() async {
      server = MockWebDavServer();
      await server.start();
      adapter = await _login(server);
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

    test('userId equals the username after login', () {
      expect(adapter.userId, equals(_user));
    });

    test('logout sets isAuthenticated to false', () async {
      await adapter.logout();
      expect(adapter.isAuthenticated, isFalse);
    });

    test('providerName is WebDAV', () {
      expect(adapter.providerName, equals('WebDAV'));
    });

    test('rootPath is /', () {
      expect(adapter.rootPath, equals('/'));
    });
  });

  // -------------------------------------------------------------------------

  group('WebDavClientAdapter integration – empty root listing', () {
    late MockWebDavServer server;
    late WebDavClientAdapter adapter;

    setUp(() async {
      server = MockWebDavServer();
      await server.start();
      adapter = await _login(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('listPath("/") returns empty folders and files on fresh server', () async {
      final result = await adapter.listPath('/');
      expect(result['folders'], isEmpty);
      expect(result['files'], isEmpty);
    });

    test('listPath result contains folders and files keys', () async {
      final result = await adapter.listPath('/');
      expect(result, containsPair('folders', isA<List>()));
      expect(result, containsPair('files', isA<List>()));
    });
  });

  // -------------------------------------------------------------------------

  group('WebDavClientAdapter integration – folder creation', () {
    late MockWebDavServer server;
    late WebDavClientAdapter adapter;

    setUp(() async {
      server = MockWebDavServer();
      await server.start();
      adapter = await _login(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('createFolderPath creates folder in root listing', () async {
      await adapter.createFolderPath('/documents');

      final result = await adapter.listPath('/');
      final folders = result['folders'] as List;
      expect(folders.any((f) => f['name'] == 'documents'), isTrue);
    });

    test('creating two folders both appear in root listing', () async {
      await adapter.createFolderPath('/photos');
      await adapter.createFolderPath('/videos');

      final result = await adapter.listPath('/');
      final folders = result['folders'] as List;
      final names = folders.map((f) => f['name']).toList();
      expect(names, containsAll(['photos', 'videos']));
    });

    test('folder type is "folder" in listing', () async {
      await adapter.createFolderPath('/music');

      final result = await adapter.listPath('/');
      final folders = result['folders'] as List;
      final entry = folders.firstWhere((f) => f['name'] == 'music');
      expect(entry['type'], equals('folder'));
    });
  });

  // -------------------------------------------------------------------------

  group('WebDavClientAdapter integration – single file upload and download', () {
    late MockWebDavServer server;
    late WebDavClientAdapter adapter;

    setUp(() async {
      server = MockWebDavServer();
      await server.start();
      adapter = await _login(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('uploadFile inside folder shows in folder listing', () async {
      await adapter.createFolderPath('/docs');
      final data = _testData(1024);
      await adapter.uploadFile(data, 'readme.bin', '/docs');

      final result = await adapter.listPath('/docs');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'readme.bin'), isTrue);
    });

    test('downloadFileBytes returns exact uploaded content', () async {
      await adapter.createFolderPath('/data');
      final data = _testData(512);
      await adapter.uploadFile(data, 'roundtrip.bin', '/data');

      final downloaded =
          await adapter.downloadFileBytes('/data/roundtrip.bin');
      expect(downloaded, equals(data));
    });

    test('downloadFileBytes returns correct length', () async {
      await adapter.createFolderPath('/store');
      final data = _testData(256);
      await adapter.uploadFile(data, 'sized.bin', '/store');

      final downloaded =
          await adapter.downloadFileBytes('/store/sized.bin');
      expect(downloaded.length, equals(256));
    });

    test('file type is "file" in listing', () async {
      await adapter.createFolderPath('/items');
      final data = _testData(64);
      await adapter.uploadFile(data, 'item.bin', '/items');

      final result = await adapter.listPath('/items');
      final files = result['files'] as List;
      final entry = files.firstWhere((f) => f['name'] == 'item.bin');
      expect(entry['type'], equals('file'));
    });

    test('uploadFile with progress callback invokes callback', () async {
      await adapter.createFolderPath('/prog');
      final data = _testData(128);
      int? calledLoaded;
      int? calledTotal;

      await adapter.uploadFile(
        data,
        'prog.bin',
        '/prog',
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

  group('WebDavClientAdapter integration – rename', () {
    late MockWebDavServer server;
    late WebDavClientAdapter adapter;

    setUp(() async {
      server = MockWebDavServer();
      await server.start();
      adapter = await _login(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('renamePath moves file to new name in same directory', () async {
      await adapter.createFolderPath('/rename_dir');
      final data = _testData(256);
      await adapter.uploadFile(data, 'original.bin', '/rename_dir');

      await adapter.renamePath('/rename_dir/original.bin', 'renamed.bin');

      final result = await adapter.listPath('/rename_dir');
      final files = result['files'] as List;
      final names = files.map((f) => f['name']).toList();
      expect(names, contains('renamed.bin'));
      expect(names, isNot(contains('original.bin')));
    });

    test('renamePath preserves file content after rename', () async {
      await adapter.createFolderPath('/ren_content');
      final data = _testData(512);
      await adapter.uploadFile(data, 'before.bin', '/ren_content');

      await adapter.renamePath('/ren_content/before.bin', 'after.bin');

      final downloaded =
          await adapter.downloadFileBytes('/ren_content/after.bin');
      expect(downloaded, equals(data));
    });

    test('renaming a folder updates its name in parent listing', () async {
      await adapter.createFolderPath('/old_folder');

      await adapter.renamePath('/old_folder', 'new_folder');

      final result = await adapter.listPath('/');
      final folders = result['folders'] as List;
      final names = folders.map((f) => f['name']).toList();
      expect(names, contains('new_folder'));
      expect(names, isNot(contains('old_folder')));
    });
  });

  // -------------------------------------------------------------------------

  group('WebDavClientAdapter integration – delete', () {
    late MockWebDavServer server;
    late WebDavClientAdapter adapter;

    setUp(() async {
      server = MockWebDavServer();
      await server.start();
      adapter = await _login(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('deletePath removes file from listing', () async {
      await adapter.createFolderPath('/del_dir');
      await adapter.uploadFile(_testData(128), 'to_delete.bin', '/del_dir');

      await adapter.deletePath('/del_dir/to_delete.bin');

      final result = await adapter.listPath('/del_dir');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'to_delete.bin'), isFalse);
    });

    test('deletePath removes folder from listing', () async {
      await adapter.createFolderPath('/removable');

      await adapter.deletePath('/removable');

      final result = await adapter.listPath('/');
      final folders = result['folders'] as List;
      expect(folders.any((f) => f['name'] == 'removable'), isFalse);
    });

    test('deleting folder also removes its contents', () async {
      await adapter.createFolderPath('/parent');
      await adapter.uploadFile(_testData(64), 'child.bin', '/parent');

      await adapter.deletePath('/parent');

      final result = await adapter.listPath('/');
      final folders = result['folders'] as List;
      expect(folders.any((f) => f['name'] == 'parent'), isFalse);
    });

    test('deleting one file leaves sibling file in place', () async {
      await adapter.createFolderPath('/siblings');
      await adapter.uploadFile(_testData(64), 'keep.bin', '/siblings');
      await adapter.uploadFile(_testData(64), 'remove.bin', '/siblings');

      await adapter.deletePath('/siblings/remove.bin');

      final result = await adapter.listPath('/siblings');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'keep.bin'), isTrue);
      expect(files.any((f) => f['name'] == 'remove.bin'), isFalse);
    });
  });

  // -------------------------------------------------------------------------

  group('WebDavClientAdapter integration – multiple files and folders', () {
    late MockWebDavServer server;
    late WebDavClientAdapter adapter;

    setUp(() async {
      server = MockWebDavServer();
      await server.start();
      adapter = await _login(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('upload 5 files and list returns all 5', () async {
      await adapter.createFolderPath('/multi');
      for (int i = 0; i < 5; i++) {
        await adapter.uploadFile(_testData(128, seed: i), 'file_$i.bin', '/multi');
      }

      final result = await adapter.listPath('/multi');
      final files = result['files'] as List;
      expect(files.length, equals(5));
    });

    test('each of 5 files has correct independent content', () async {
      await adapter.createFolderPath('/content_check');
      final originals = <String, Uint8List>{};
      for (int i = 0; i < 5; i++) {
        final data = _testData(256, seed: i * 11);
        originals['c_$i.bin'] = data;
        await adapter.uploadFile(data, 'c_$i.bin', '/content_check');
      }

      for (final entry in originals.entries) {
        final downloaded =
            await adapter.downloadFileBytes('/content_check/${entry.key}');
        expect(downloaded, equals(entry.value),
            reason: 'Content mismatch for ${entry.key}');
      }
    });

    test('create 3 folders and all appear in root listing', () async {
      await adapter.createFolderPath('/folder_a');
      await adapter.createFolderPath('/folder_b');
      await adapter.createFolderPath('/folder_c');

      final result = await adapter.listPath('/');
      final folders = result['folders'] as List;
      final names = folders.map((f) => f['name']).toList();
      expect(names, containsAll(['folder_a', 'folder_b', 'folder_c']));
    });

    test('upload 3 files in root listing', () async {
      for (int i = 0; i < 3; i++) {
        await adapter.uploadFile(_testData(64), 'root_$i.bin', '/');
      }

      final result = await adapter.listPath('/');
      final files = result['files'] as List;
      expect(files.length, greaterThanOrEqualTo(3));
    });
  });

  // -------------------------------------------------------------------------

  group('WebDavClientAdapter integration – nested folders (3 levels deep)', () {
    late MockWebDavServer server;
    late WebDavClientAdapter adapter;

    setUp(() async {
      server = MockWebDavServer();
      await server.start();
      adapter = await _login(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('create 3-level deep folder structure', () async {
      await adapter.createFolderPath('/level1');
      await adapter.createFolderPath('/level1/level2');
      await adapter.createFolderPath('/level1/level2/level3');

      final result = await adapter.listPath('/level1/level2');
      final folders = result['folders'] as List;
      expect(folders.any((f) => f['name'] == 'level3'), isTrue);
    });

    test('upload file at 3rd nesting level and download it', () async {
      await adapter.createFolderPath('/a');
      await adapter.createFolderPath('/a/b');
      await adapter.createFolderPath('/a/b/c');

      final data = _testData(128);
      await adapter.uploadFile(data, 'deep.bin', '/a/b/c');

      final downloaded = await adapter.downloadFileBytes('/a/b/c/deep.bin');
      expect(downloaded, equals(data));
    });

    test('file at deep level appears in its immediate parent listing', () async {
      await adapter.createFolderPath('/x');
      await adapter.createFolderPath('/x/y');
      await adapter.createFolderPath('/x/y/z');
      await adapter.uploadFile(_testData(64), 'leaf.bin', '/x/y/z');

      final result = await adapter.listPath('/x/y/z');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'leaf.bin'), isTrue);
    });

    test('file at deep level does not appear in top-level listing', () async {
      await adapter.createFolderPath('/top');
      await adapter.createFolderPath('/top/mid');
      await adapter.createFolderPath('/top/mid/bot');
      await adapter.uploadFile(_testData(64), 'hidden.bin', '/top/mid/bot');

      final root = await adapter.listPath('/');
      final rootFiles = root['files'] as List;
      expect(rootFiles.any((f) => f['name'] == 'hidden.bin'), isFalse);
    });

    test('intermediate folder appears in its parent listing', () async {
      await adapter.createFolderPath('/p1');
      await adapter.createFolderPath('/p1/p2');
      await adapter.createFolderPath('/p1/p2/p3');

      final p1Listing = await adapter.listPath('/p1');
      final p1Folders = p1Listing['folders'] as List;
      expect(p1Folders.any((f) => f['name'] == 'p2'), isTrue);
    });
  });

  // -------------------------------------------------------------------------

  group('WebDavClientAdapter integration – special characters in filenames', () {
    late MockWebDavServer server;
    late WebDavClientAdapter adapter;

    setUp(() async {
      server = MockWebDavServer();
      await server.start();
      adapter = await _login(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('filename with spaces round-trips correctly', () async {
      await adapter.createFolderPath('/sp');
      final data = _testData(128);
      await adapter.uploadFile(data, 'my file.bin', '/sp');

      final result = await adapter.listPath('/sp');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'my file.bin'), isTrue);

      final downloaded = await adapter.downloadFileBytes('/sp/my file.bin');
      expect(downloaded, equals(data));
    });

    test('filename with unicode characters round-trips correctly', () async {
      await adapter.createFolderPath('/uni');
      final data = _testData(128);
      await adapter.uploadFile(data, 'документ.bin', '/uni');

      final result = await adapter.listPath('/uni');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'документ.bin'), isTrue);
    });

    test('filename with hyphens and underscores round-trips', () async {
      await adapter.createFolderPath('/hyp');
      final data = _testData(64);
      await adapter.uploadFile(data, 'my-file_name.bin', '/hyp');

      final downloaded =
          await adapter.downloadFileBytes('/hyp/my-file_name.bin');
      expect(downloaded, equals(data));
    });

    test('filename with multiple extensions round-trips', () async {
      await adapter.createFolderPath('/ext');
      final data = _testData(64);
      await adapter.uploadFile(data, 'archive.tar.gz', '/ext');

      final result = await adapter.listPath('/ext');
      final files = result['files'] as List;
      expect(files.any((f) => f['name'] == 'archive.tar.gz'), isTrue);
    });
  });

  // -------------------------------------------------------------------------

  group('WebDavClientAdapter integration – movePath', () {
    late MockWebDavServer server;
    late WebDavClientAdapter adapter;

    setUp(() async {
      server = MockWebDavServer();
      await server.start();
      adapter = await _login(server);
    });

    tearDown(() async {
      await adapter.logout();
      await server.stop();
    });

    test('movePath moves file from source to target folder', () async {
      await adapter.createFolderPath('/src_dir');
      await adapter.createFolderPath('/tgt_dir');
      final data = _testData(128);
      await adapter.uploadFile(data, 'moveme.bin', '/src_dir');

      await adapter.movePath('/src_dir/moveme.bin', '/tgt_dir/moveme.bin');

      final tgt = await adapter.listPath('/tgt_dir');
      final tgtFiles = tgt['files'] as List;
      expect(tgtFiles.any((f) => f['name'] == 'moveme.bin'), isTrue);
    });

    test('movePath removes file from source listing', () async {
      await adapter.createFolderPath('/from_dir');
      await adapter.createFolderPath('/to_dir');
      await adapter.uploadFile(_testData(128), 'gone.bin', '/from_dir');

      await adapter.movePath('/from_dir/gone.bin', '/to_dir/gone.bin');

      final src = await adapter.listPath('/from_dir');
      final srcFiles = src['files'] as List;
      expect(srcFiles.any((f) => f['name'] == 'gone.bin'), isFalse);
    });

    test('moved file content is preserved', () async {
      await adapter.createFolderPath('/mv_src');
      await adapter.createFolderPath('/mv_dst');
      final data = _testData(256);
      await adapter.uploadFile(data, 'preserve.bin', '/mv_src');

      await adapter.movePath('/mv_src/preserve.bin', '/mv_dst/preserve.bin');

      final downloaded =
          await adapter.downloadFileBytes('/mv_dst/preserve.bin');
      expect(downloaded, equals(data));
    });
  });
}
