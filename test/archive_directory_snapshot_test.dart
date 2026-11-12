import 'dart:io';

import 'package:crisp_cloud/models/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_directory_snapshot.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/installation_identity.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/archive_directory_sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await InstallationIdentityService.instance.initialize();
  });
  late Directory temp;
  late String root;
  late ArchiveDirectoryTestBackend backend;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('archive-directory-snapshot-');
    root = '${temp.path}/source';
    await Directory(root).create();
    backend = ArchiveDirectoryTestBackend();
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('complete snapshot includes hashes, nested paths, empty dirs and reloadable native evidence', () async {
    await writeDirectorySyncSource(root, 'nested/a.txt', [1, 2, 3]);
    await writeDirectorySyncSource(root, '.hidden', [4]);
    await Directory('$root/empty').create();
    final snapshot = await captureArchiveDirectorySnapshot(backend, root);
    expect(snapshot.entries.keys, [
      '.hidden',
      'empty',
      'nested',
      'nested/a.txt',
    ]);
    expect(snapshot.dependency.entryCount, 4);
    expect(snapshot.dependency.totalBytes, 4);
    expect(snapshot.entries['empty']!.sha256, isNull);
    expect(
      snapshot.entries['nested/a.txt']!.sha256,
      sha256.convert([1, 2, 3]).toString(),
    );
    expect(() => snapshot.entries.clear(), throwsUnsupportedError);
    final persisted = ArchivePublicationDirectoryDependency.fromJson(
      snapshot.dependency.toJson(),
    );
    await verifyArchiveDirectoryDependency(backend, persisted);
    expect(
      await readArchiveDirectorySnapshotFile(
        backend,
        snapshot.entries['nested/a.txt']!,
      ),
      [1, 2, 3],
    );
    expect(
      (await captureArchiveDirectorySnapshot(backend, root)).dependency.sha256,
      snapshot.dependency.sha256,
    );
  });

  test('an empty source directory is a complete witnessed namespace', () async {
    final snapshot = await captureArchiveDirectorySnapshot(backend, root);
    expect(snapshot.entries, isEmpty);
    expect(snapshot.dependency.entryCount, 0);
    expect(snapshot.dependency.totalBytes, 0);
    await verifyArchiveDirectoryDependency(backend, snapshot.dependency);
  });

  for (final change in ['addition', 'removal', 'bytes', 'empty directory']) {
    test('$change invalidates the complete tree', () async {
      final file = await writeDirectorySyncSource(root, 'a', [1, 2, 3]);
      final snapshot = await captureArchiveDirectorySnapshot(backend, root);
      switch (change) {
        case 'addition':
          await writeDirectorySyncSource(root, 'new', [9]);
        case 'removal':
          await file.delete();
        case 'bytes':
          final modified = await file.lastModified();
          await file.writeAsBytes([3, 2, 1], flush: true);
          await file.setLastModified(modified);
        case 'empty directory':
          await Directory('$root/new-empty').create();
      }
      await expectLater(
        verifyArchiveDirectoryDependency(backend, snapshot.dependency),
        throwsStateError,
      );
    });
  }

  test('mode-only changes invalidate identical content', () async {
    final file = await writeDirectorySyncSource(root, 'a', [1]);
    final snapshot = await captureArchiveDirectorySnapshot(backend, root);
    final result = await Process.run('chmod', ['700', file.path]);
    expect(result.exitCode, 0);
    await expectLater(
      verifyArchiveDirectoryDependency(backend, snapshot.dependency),
      throwsStateError,
    );
  }, skip: !Platform.isLinux && !Platform.isMacOS);

  test(
    'a source addition during the final relist cannot become absence evidence',
    () async {
      await writeDirectorySyncSource(root, 'a', [1]);
      var lists = 0;
      backend.afterList = (path, _) async {
        if (path == root && ++lists == 2) {
          await writeDirectorySyncSource(root, 'appeared', [9]);
        }
      };
      await expectLater(
        captureArchiveDirectorySnapshot(backend, root),
        throwsStateError,
      );
      expect(lists, 2);
    },
  );

  test('changed file after its read is detected before a complete snapshot returns', () async {
    final first = await writeDirectorySyncSource(root, 'a', [1]);
    await writeDirectorySyncSource(root, 'z', [2]);
    backend.beforeRead = (file) async {
      if (file.path == '$root/z') {
        await first.writeAsBytes([9], flush: true);
      }
    };
    await expectLater(
      captureArchiveDirectorySnapshot(backend, root),
      throwsStateError,
    );
  });

  for (final directory in [false, true]) {
    test(
      'symbolic ${directory ? 'directory' : 'file'} prevents complete comparison',
      () async {
        final target = directory
            ? '${temp.path}/outside-dir'
            : '${temp.path}/outside-file';
        if (directory) {
          await Directory(target).create();
        } else {
          await File(target).writeAsBytes([1]);
        }
        await Link('$root/link').create(target);
        await expectLater(
          captureArchiveDirectorySnapshot(backend, root),
          throwsUnsupportedError,
        );
      },
      skip: Platform.isWindows,
    );
  }

  test('special source entries are rejected before reading', () async {
    final result = await Process.run('mkfifo', ['$root/pipe']);
    expect(result.exitCode, 0);
    await expectLater(
      captureArchiveDirectorySnapshot(backend, root),
      throwsA(anyOf(isA<UnsupportedError>(), isA<StateError>())),
    );
  }, skip: !Platform.isLinux && !Platform.isMacOS);

  test(
    'names requiring normalization are not silently mapped into aliases',
    () async {
      await writeDirectorySyncSource(root, r'a\b', [1]);
      await expectLater(
        captureArchiveDirectorySnapshot(backend, root),
        throwsStateError,
      );
    },
    skip: Platform.isWindows,
  );

  test(
    'source cannot contain the destination or its hard-link alias',
    () async {
      final target = await writeDirectorySyncSource(root, 'target.zip', [1]);
      await expectLater(
        captureArchiveDirectorySnapshot(
          backend,
          root,
          forbiddenContainer: await backend.stat(target.path),
        ),
        throwsStateError,
      );
      final outside = File('${temp.path}/target.zip');
      await target.rename(outside.path);
      final link = await Process.run('ln', [outside.path, '$root/alias.zip']);
      expect(link.exitCode, 0);
      await expectLater(
        captureArchiveDirectorySnapshot(
          backend,
          root,
          forbiddenContainer: await backend.stat(outside.path),
        ),
        throwsStateError,
      );
    },
    skip: !Platform.isLinux && !Platform.isMacOS,
  );

  test('oversized file and cancellation cannot produce a partial complete dependency', () async {
    final file = await File('$root/large').open(mode: FileMode.write);
    await file.truncate(64 * 1024 * 1024 + 1);
    await file.close();
    await expectLater(
      captureArchiveDirectorySnapshot(backend, root),
      throwsStateError,
    );
    await expectLater(
      captureArchiveDirectorySnapshot(backend, root, isCancelled: () => true),
      throwsA(isA<FileOperationCancelled>()),
    );
  });
}
