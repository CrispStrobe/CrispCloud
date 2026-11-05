import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/workflow_fake_client.dart';

class _RacingArchiveClient extends WorkflowFakeClient {
  void Function()? beforeStageUpload;
  @override
  Future<void> uploadFile(
    List<int> bytes,
    String name,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    if (name.startsWith('.crisp-transfer-')) {
      final change = beforeStageUpload;
      beforeStageUpload = null;
      change?.call();
    }
    await super.uploadFile(bytes, name, targetPath, onProgress: onProgress);
  }
}

Future<Uint8List> _archive(
  koni.ArchiveWriteFormat format, {
  String? password,
}) async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: format,
    options: koni.ArchiveWriteOptions(
      password: password,
      encryptHeader: password != null,
    ),
  );
  await writer.addBytes(
    koni.ArchiveEntrySpec(
      path: 'folder/original.txt',
      modified: DateTime.utc(2025, 2, 3),
      posixMode: 0x1a4,
    ),
    Uint8List.fromList(utf8.encode('original')),
  );
  await writer.addBytes(
    koni.ArchiveEntrySpec(path: 'remove.txt'),
    Uint8List.fromList([1, 2]),
  );
  await writer.addEntry(
    koni.ArchiveEntrySpec(path: 'empty', type: koni.ArchiveEntryType.directory),
  );
  await writer.close();
  await sink.close();
  return sink.takeBytes();
}

void main() {
  test(
    'external archive change during upload is caught before staged replacement',
    () async {
      final original = await _archive(const koni.ZipWriteFormat());
      final external = await _archive(const koni.TarWriteFormat());
      final client = _RacingArchiveClient()..put('/work.zip', original);
      final backend = CloudOperationBackend(client, isCurrent: () => true);
      final workspace = await ArchiveWorkspace.open(
        backend,
        (await backend.stat('/work.zip'))!,
      );
      addTearDown(workspace.close);
      workspace.replace('/added.txt', Uint8List.fromList([7]));
      client.beforeStageUpload = () => client.put('/work.zip', external);
      await expectLater(workspace.save(), throwsStateError);
      expect(client.files['/work.zip'], external);
      expect(workspace.dirty, isTrue);
    },
  );

  test('adding recursive files keeps empty directories and refuses duplicate member replacement by default', () async {
    final client = WorkflowFakeClient()
      ..put('/work.zip', await _archive(const koni.ZipWriteFormat()))
      ..put('/input/folder/new.txt', [3, 4]);
    client.directories.add('/input/folder/empty');
    final backend = CloudOperationBackend(client, isCurrent: () => true);
    final workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat('/work.zip'))!,
    );
    addTearDown(workspace.close);
    await workspace.addFiles(backend, [(await backend.stat('/input/folder'))!]);
    expect(workspace.list('/folder').map((item) => item.name).toSet(), {
      'empty',
      'new.txt',
      'original.txt',
    });
    client.put('/input/folder/new.txt', [8]);
    await expectLater(
      workspace.addFiles(backend, [
        (await backend.stat('/input/folder/new.txt'))!,
      ], directory: '/folder'),
      throwsStateError,
    );
    expect(await workspace.read('/folder/new.txt'), [3, 4]);
    await workspace.addFiles(
      backend,
      [(await backend.stat('/input/folder/new.txt'))!],
      directory: '/folder',
      replaceExisting: true,
    );
    expect(await workspace.read('/folder/new.txt'), [8]);
  });

  test('captured account loss refuses repacking and extracting', () async {
    final client = WorkflowFakeClient()
      ..put('/work.zip', await _archive(const koni.ZipWriteFormat()));
    var current = true;
    final backend = CloudOperationBackend(client, isCurrent: () => current);
    final workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat('/work.zip'))!,
    );
    addTearDown(workspace.close);
    workspace.replace('/added.txt', Uint8List.fromList([1]));
    current = false;
    await expectLater(workspace.save(), throwsStateError);
    await expectLater(workspace.read('/added.txt'), throwsStateError);
    expect(client.writes, isEmpty);
  });

  for (final kind in <(String, koni.ArchiveWriteFormat)>[
    ('zip', const koni.ZipWriteFormat()),
    ('7z', const koni.SevenZWriteFormat()),
    ('tar', const koni.TarWriteFormat()),
  ]) {
    test(
      '${kind.$1} edit/add/rename/delete repacks all selected changes and empty directories',
      () async {
        final client = WorkflowFakeClient()
          ..put('/work.${kind.$1}', await _archive(kind.$2));
        final backend = CloudOperationBackend(client, isCurrent: () => true);
        final workspace = await ArchiveWorkspace.open(
          backend,
          (await backend.stat('/work.${kind.$1}'))!,
        );
        addTearDown(workspace.close);
        expect(
          workspace
              .list()
              .where((item) => item.isFolder)
              .map((item) => item.name),
          ['empty', 'folder'],
        );
        workspace.rename('/folder', 'renamed');
        workspace.replace(
          '/renamed/original.txt',
          Uint8List.fromList(utf8.encode('edited')),
        );
        workspace.replace('/added.txt', Uint8List.fromList([4, 5]));
        workspace.remove(['/remove.txt']);
        expect(
          client.writes,
          isEmpty,
          reason: 'working changes must not touch the original',
        );
        await workspace.save();
        expect(workspace.dirty, isFalse);
        final saved = await openViewerArchive(
          client.files['/work.${kind.$1}']!,
          name: 'work.${kind.$1}',
        );
        addTearDown(saved.close);
        expect(saved.members.map((member) => member.name).toSet(), {
          'empty',
          'renamed/original.txt',
          'added.txt',
        });
        expect(
          utf8.decode(
            await saved.readMember(
              saved.members.singleWhere(
                (member) => member.name == 'renamed/original.txt',
              ),
            ),
          ),
          'edited',
        );
        expect(
          saved.members.singleWhere((member) => member.name == 'empty').isFile,
          isFalse,
        );
      },
    );
  }

  test('encrypted archive requires the original password and preserves encryption after repacking', () async {
    final client = WorkflowFakeClient()
      ..put(
        '/protected.zip',
        await _archive(const koni.ZipWriteFormat(), password: 'secret'),
      );
    final backend = CloudOperationBackend(client, isCurrent: () => true);
    final file = (await backend.stat('/protected.zip'))!;
    await expectLater(
      ArchiveWorkspace.open(backend, file),
      throwsA(isA<ArchivePasswordRequiredException>()),
    );
    await expectLater(
      ArchiveWorkspace.open(backend, file, password: 'wrong'),
      throwsA(isA<ArchivePasswordRequiredException>()),
    );
    final workspace = await ArchiveWorkspace.open(
      backend,
      file,
      password: 'secret',
    );
    addTearDown(workspace.close);
    workspace.replace('/added.txt', Uint8List.fromList([7]));
    await workspace.save();
    final saved = await openViewerArchive(
      client.files['/protected.zip']!,
      name: 'protected.zip',
      password: 'secret',
    );
    addTearDown(saved.close);
    expect(
      saved.members
          .where((member) => member.isFile)
          .every((member) => member.isEncrypted),
      isTrue,
    );
    expect(
      await saved.readMember(
        saved.members.singleWhere((member) => member.name == 'added.txt'),
      ),
      [7],
    );
  });

  test(
    'external modification and cancellation retain the original archive',
    () async {
      final original = await _archive(const koni.ZipWriteFormat());
      final client = WorkflowFakeClient()..put('/work.zip', original);
      final backend = CloudOperationBackend(client, isCurrent: () => true);
      final workspace = await ArchiveWorkspace.open(
        backend,
        (await backend.stat('/work.zip'))!,
      );
      addTearDown(workspace.close);
      workspace.replace('/added.txt', Uint8List.fromList([7]));
      await expectLater(
        workspace.save(isCancelled: () => true),
        throwsStateError,
      );
      expect(client.files['/work.zip'], original);
      final external = await _archive(const koni.TarWriteFormat());
      client.put('/work.zip', external);
      await expectLater(workspace.save(), throwsStateError);
      expect(client.files['/work.zip'], external);
      expect(client.writes, isEmpty);
      expect(workspace.dirty, isTrue);
    },
  );

  test('read-only archive source copies selected members through the normal conflict engine', () async {
    final client = WorkflowFakeClient()
      ..put('/work.zip', await _archive(const koni.ZipWriteFormat()))
      ..put('/out/original.txt', utf8.encode('existing'));
    final backend = CloudOperationBackend(client, isCurrent: () => true);
    final workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat('/work.zip'))!,
    );
    addTearDown(workspace.close);
    final member = workspace.list('/folder').single;
    final plan = await const FileOperationService().prepare(
      files: [member],
      source: workspace.backend,
      destination: backend,
      targetDirectory: '/out',
      options: const FileOperationOptions(
        fileConflict: FileConflictPolicy.keepBoth,
        verifyContents: true,
      ),
    );
    expect(plan.canExecute, isTrue);
    await const FileOperationService().execute(
      plan,
      control: FileOperationControl(),
    );
    expect(
      plan.entries.single.failed,
      isFalse,
      reason: plan.entries.single.message,
    );
    expect(client.files['/out/original.txt'], utf8.encode('existing'));
    expect(
      client.files[plan.entries.single.destination],
      utf8.encode('original'),
    );
    expect(workspace.dirty, isFalse);
    final archiveBeforeMove = Uint8List.fromList(client.files['/work.zip']!);
    expect(await workspace.stageCopiedMemberRemoval(plan), 1);
    expect(workspace.list('/folder'), isEmpty);
    expect(workspace.dirty, isTrue);
    expect(
      client.files['/work.zip'],
      archiveBeforeMove,
      reason: 'Member removal is staged until the user saves the archive.',
    );
    expect(await workspace.read('/remove.txt'), [1, 2]);
  });

  test('archive move-out retains skipped members and refuses changed destinations atomically', () async {
    final client = WorkflowFakeClient()
      ..put('/work.zip', await _archive(const koni.ZipWriteFormat()))
      ..put('/out/remove.txt', [9]);
    final backend = CloudOperationBackend(client, isCurrent: () => true);
    final workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat('/work.zip'))!,
    );
    addTearDown(workspace.close);
    final plan = await const FileOperationService().prepare(
      files: workspace.list(),
      source: workspace.backend,
      destination: backend,
      targetDirectory: '/out',
      options: const FileOperationOptions(
        fileConflict: FileConflictPolicy.skip,
      ),
    );
    await const FileOperationService().execute(
      plan,
      control: FileOperationControl(),
    );
    client.put('/out/folder/original.txt', 'changed'.codeUnits);
    await expectLater(
      workspace.stageCopiedMemberRemoval(plan),
      throwsStateError,
    );
    expect(workspace.dirty, false);
    expect(
      await workspace.read('/folder/original.txt'),
      utf8.encode('original'),
    );
    client.put('/out/folder/original.txt', utf8.encode('original'));
    await workspace.stageCopiedMemberRemoval(plan);
    expect(await workspace.read('/remove.txt'), [1, 2]);
    expect(workspace.list().map((file) => file.name), ['remove.txt']);
  });

  test('unsafe hierarchy changes are rejected atomically', () async {
    final client = WorkflowFakeClient()
      ..put('/work.zip', await _archive(const koni.ZipWriteFormat()));
    final backend = CloudOperationBackend(client, isCurrent: () => true);
    final workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat('/work.zip'))!,
    );
    addTearDown(workspace.close);
    expect(
      () => workspace.replace('/folder', Uint8List.fromList([1])),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(
      () => workspace.rename('/folder', '../escape'),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(
      () => workspace.remove(['/remove.txt', '../escape']),
      throwsA(isA<ArchiveViewException>()),
    );
    expect(workspace.dirty, isFalse);
    expect(await workspace.read('/remove.txt'), [1, 2]);
  });

  test(
    'RAR remains available for extraction and refuses unsupported repacking',
    () async {
      final client = WorkflowFakeClient()
        ..put(
          '/work.rar',
          await File('test/fixtures/archives/sample.rar').readAsBytes(),
        );
      final backend = CloudOperationBackend(client, isCurrent: () => true);
      final workspace = await ArchiveWorkspace.open(
        backend,
        (await backend.stat('/work.rar'))!,
      );
      addTearDown(workspace.close);
      expect(workspace.canUpdate, isFalse);
      expect(workspace.list(), isNotEmpty);
      expect(
        () => workspace.replace('/added.txt', Uint8List.fromList([1])),
        throwsUnsupportedError,
      );
      expect(client.writes, isEmpty);
    },
  );
}
