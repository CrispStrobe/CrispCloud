import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as codec;
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_endpoint.dart';
import 'package:crisp_cloud/services/archive_publication_journal.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_workspace.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:crisp_cloud/services/archive_source_cleanup_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:koni_archive/koni_archive.dart' as koni;

import 'support/archive_endpoint_backend.dart';

Uint8List zip(Map<String, List<int>> files) {
  final archive = codec.Archive();
  for (final entry in files.entries) {
    archive.addFile(codec.ArchiveFile.bytes(entry.key, entry.value));
  }
  return Uint8List.fromList(codec.ZipEncoder().encode(archive));
}

Future<Uint8List> protected(
  koni.ArchiveWriteFormat format,
  Map<String, List<int>> files, {
  String? password,
  bool names = false,
}) async {
  final sink = koni.BytesBuilderSink();
  final writer = koni.Archive.create(
    sink,
    format: format,
    options: koni.ArchiveWriteOptions(password: password, encryptHeader: names),
  );
  for (final entry in files.entries) {
    await writer.addBytes(
      koni.ArchiveEntrySpec(path: entry.key),
      Uint8List.fromList(entry.value),
    );
  }
  await writer.close();
  await sink.close();
  return sink.takeBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ArchiveEndpointTestBackend backend;
  late ArchivePublicationJournal journal;
  late ArchiveEndpoint endpoint;
  final original = zip({
    'existing.txt': [1, 2],
  });
  setUp(() async {
    backend = ArchiveEndpointTestBackend()
      ..put('/out/work.zip', original)
      ..put('/input/new.txt', [3, 4, 5]);
    backend.modes['/input'] = 0x1ed;
    journal = ArchivePublicationJournal(storage: MemoryFileCollectionStorage());
    endpoint = await ArchiveEndpoint.open(
      containerBackend: backend,
      containerFile: (await backend.stat('/out/work.zip'))!,
      journal: journal,
    );
  });
  tearDown(() => endpoint.close());
  Future<ArchiveWorkspaceReview> stage({
    bool move = false,
    FileConflictPolicy conflict = FileConflictPolicy.keepBoth,
    List<FileItem>? files,
  }) async {
    final plan = await endpoint.prepareImport(
      source: backend,
      files: files ?? [(await backend.stat('/input/new.txt'))!],
      moveSources: move,
      conflict: conflict,
    );
    expect(plan.errors, isEmpty);
    expect(plan.canStage, isTrue);
    return endpoint.stageImport(plan, control: FileOperationControl());
  }

  Future<Map<String, List<int>>> published() async {
    final archive = await openViewerArchive(
      backend.files['/out/work.zip']!,
      name: 'work.zip',
    );
    try {
      return {
        for (final member in archive.members.where((member) => member.isFile))
          member.name: await archive.readMember(member),
      };
    } finally {
      await archive.close();
    }
  }

  test('private copy stages atomically and returns a physical receipt only after publication', () async {
    final review = await stage();
    expect(backend.files['/out/work.zip'], original);
    expect(backend.mutations, isEmpty);
    expect(review.changes.single.path, 'new.txt');
    final result = await endpoint.commit(reviewed: review);
    expect(result.publishedFiles, 1);
    expect(result.removedSources, 0);
    expect(result.receipt.cleanupPending, isFalse);
    expect(await published(), {
      'existing.txt': [1, 2],
      'new.txt': [3, 4, 5],
    });
    expect(backend.files['/input/new.txt'], [3, 4, 5]);
    expect(
      backend.files.keys.where((key) => key.contains('.crisp-archive-')),
      isEmpty,
    );
  });
  test('move source deletion follows durable verified publication', () async {
    final review = await stage(move: true);
    backend.before = (action, path, destination) {
      if (action == 'delete' && path == '/input/new.txt') {
        expect(journal.records.single.published, isNotNull);
        expect(journal.records.single.phase, ArchivePublicationPhase.complete);
        expect(backend.files['/out/work.zip'], isNot(original));
      }
    };
    final result = await endpoint.commit(reviewed: review);
    expect(result.removedSources, 1);
    expect(result.retainedSources, isEmpty);
    expect(backend.files.containsKey('/input/new.txt'), isFalse);
    expect((await published())['new.txt'], [3, 4, 5]);
  });
  test('changed source remains after verified publication with explicit partial move', () async {
    final review = await stage(move: true);
    backend.put('/input/new.txt', [9, 8, 7]);
    final result = await endpoint.commit(reviewed: review);
    expect(result.retainedSources, ['/input/new.txt']);
    expect(result.removedSources, 0);
    expect(backend.files['/input/new.txt'], [9, 8, 7]);
    expect((await published())['new.txt'], [3, 4, 5]);
  });
  test('same-length source mutation without a version update is caught by full hash', () async {
    final review = await stage(move: true);
    backend.put('/input/new.txt', [9, 8, 7], preserveVersion: true);
    final result = await endpoint.commit(reviewed: review);
    expect(result.retainedSources, ['/input/new.txt']);
    expect(result.removedSources, 0);
    expect(backend.files['/input/new.txt'], [9, 8, 7]);
  });
  test(
    'source revision changes at conditional deletion preserve changed source',
    () async {
      final review = await stage(move: true);
      backend.before = (action, path, destination) {
        if (action == 'delete' && path == '/input/new.txt') {
          backend.put(path, [8, 8, 8]);
        }
      };
      final result = await endpoint.commit(reviewed: review);
      expect(result.retainedSources, ['/input/new.txt']);
      expect(backend.files['/input/new.txt'], [8, 8, 8]);
    },
  );
  test(
    'source directories without stable identity remain after their files move',
    () async {
      final review = await stage(
        move: true,
        files: [(await backend.stat('/input'))!],
      );
      final result = await endpoint.commit(reviewed: review);
      expect(result.removedSources, 1);
      expect(result.retainedSources, ['/input']);
      expect(backend.directories, contains('/input'));
      expect((await published())['input/new.txt'], [3, 4, 5]);
    },
  );
  test('unsupported source conditional deletion reports retained source after copy', () async {
    final review = await stage(move: true);
    backend.conditionalCleanup = false;
    final result = await endpoint.commit(reviewed: review);
    expect(result.receipt.cleanupPending, isTrue);
    expect(result.retainedSources, ['/input/new.txt']);
    expect(backend.files['/input/new.txt'], [3, 4, 5]);
  });
  test(
    'changed outer container prevents publication and source deletion',
    () async {
      final review = await stage(move: true);
      final external = zip({
        'external': [7],
      });
      backend.put('/out/work.zip', external);
      await expectLater(endpoint.commit(reviewed: review), throwsA(anything));
      expect(backend.files['/out/work.zip'], external);
      expect(backend.files['/input/new.txt'], [3, 4, 5]);
      expect(backend.mutations, isEmpty);
    },
  );
  test('cancelled publication preserves original and source', () async {
    final review = await stage(move: true);
    await expectLater(
      endpoint.commit(reviewed: review, isCancelled: () => true),
      throwsA(anything),
    );
    expect(backend.files['/out/work.zip'], original);
    expect(backend.files['/input/new.txt'], [3, 4, 5]);
  });
  test('cancel after install returns receipt and retains source', () async {
    var cancelled = false;
    final review = await stage(move: true);
    backend.after = (action, path, destination) {
      if (action == 'move' && destination == '/out/work.zip') cancelled = true;
    };
    final result = await endpoint.commit(
      reviewed: review,
      isCancelled: () => cancelled,
    );
    expect(result.receipt, isNotNull);
    expect(result.retainedSources, ['/input/new.txt']);
    expect((await published())['new.txt'], [3, 4, 5]);
  });
  test(
    'source changes during staging leave the archive draft untouched',
    () async {
      var reads = 0;
      backend.after = (action, path, destination) {
        if (action == 'read' && path == '/input/new.txt' && ++reads == 1) {
          backend.put(path, [8, 8, 8]);
        }
      };
      final plan = await endpoint.prepareImport(
        source: backend,
        files: [(await backend.stat('/input/new.txt'))!],
      );
      await expectLater(
        endpoint.stageImport(plan, control: FileOperationControl()),
        throwsA(anything),
      );
      expect(endpoint.workspace.dirty, isFalse);
      expect(backend.files['/out/work.zip'], original);
      expect(backend.mutations, isEmpty);
    },
  );
  test(
    'closed endpoint invalidates prepared import without mutation',
    () async {
      final plan = await endpoint.prepareImport(
        source: backend,
        files: [(await backend.stat('/input/new.txt'))!],
      );
      await endpoint.close();
      await expectLater(
        endpoint.stageImport(plan, control: FileOperationControl()),
        throwsStateError,
      );
      expect(backend.mutations, isEmpty);
    },
  );
  test('changed draft invalidates a concrete publication review', () async {
    final review = await stage();
    endpoint.workspace.replace('/later.txt', Uint8List.fromList([8]));
    await expectLater(endpoint.commit(reviewed: review), throwsStateError);
    expect(backend.files['/out/work.zip'], original);
  });
  for (final conflict in [
    FileConflictPolicy.keepBoth,
    FileConflictPolicy.replace,
    FileConflictPolicy.skip,
  ]) {
    test(
      'explicit ${conflict.name} collision is enforced by copy planner',
      () async {
        backend.put('/input/existing.txt', [7]);
        final files = [
          (await backend.stat('/input/existing.txt'))!,
          (await backend.stat('/input/new.txt'))!,
        ];
        final review = await stage(files: files, conflict: conflict);
        await endpoint.commit(reviewed: review);
        final contents = await published();
        expect(
          contents['existing.txt'],
          conflict == FileConflictPolicy.replace ? [7] : [1, 2],
        );
        expect(contents['new.txt'], [3, 4, 5]);
        expect(
          contents.length,
          conflict == FileConflictPolicy.keepBoth ? 3 : 2,
        );
      },
    );
  }
  test(
    'empty folders and imported supported permissions survive verified packing',
    () async {
      backend.directories.add('/input/empty');
      backend.modes['/input/empty'] = 0x1c0;
      final review = await stage(
        files: [(await backend.stat('/input/empty'))!],
      );
      await endpoint.commit(reviewed: review);
      final archive = await openViewerArchive(
        backend.files['/out/work.zip']!,
        name: 'work.zip',
      );
      addTearDown(archive.close);
      final empty = archive.members.singleWhere(
        (member) => member.name == 'empty',
      );
      expect(empty.isFile, isFalse);
      expect(empty.posixMode! & 0xfff, 0x1c0);
    },
  );
  test(
    'archive sources and selected source ancestors of destination are refused',
    () async {
      await expectLater(
        endpoint.prepareImport(
          source: endpoint.workspace.backend,
          files: endpoint.workspace.list(),
        ),
        throwsUnsupportedError,
      );
      await expectLater(
        endpoint.prepareImport(
          source: backend,
          files: [(await backend.stat('/out'))!],
        ),
        throwsStateError,
      );
    },
  );
  test('large and symbolic sources are refused before staging', () async {
    final fake = FileItem(
      name: 'large',
      path: '/input/large',
      isFolder: false,
      size: 64 * 1024 * 1024 + 1,
    );
    final plan = await endpoint.prepareImport(source: backend, files: [fake]);
    expect(plan.errors, isNotEmpty);
    backend.links.add('/input/link');
    await expectLater(
      endpoint.prepareImport(
        source: backend,
        files: [(await backend.stat('/input/link'))!],
      ),
      throwsStateError,
    );
  });
  test(
    'unsupported publication capabilities still permit browsing but block edit',
    () async {
      backend.accessPolicySupported = false;
      expect(endpoint.workspace.list(), isNotEmpty);
      expect(endpoint.workspace.canUpdate, isFalse);
      await expectLater(
        endpoint.prepareImport(
          source: backend,
          files: [(await backend.stat('/input/new.txt'))!],
        ),
        throwsUnsupportedError,
      );
      expect(backend.mutations, isEmpty);
    },
  );
  test('import read inactivity closes the operation without adopting partial bytes', () async {
    final input = _StalledSource();
    final bounded = ArchiveEndpoint.fromWorkspace(
      endpoint.workspace,
      readInactivity: const Duration(milliseconds: 40),
    );
    final plan = await bounded.prepareImport(
      source: input,
      files: [input.file],
    );
    await expectLater(
      bounded.stageImport(plan, control: FileOperationControl()),
      throwsA(anything),
    );
    expect(input.cancelled, isTrue);
    expect(endpoint.workspace.dirty, isFalse);
    await bounded.close();
  });
  test(
    'whole import deadline stops a source that continues to drip bytes',
    () async {
      final input = _StalledSource(drip: true);
      final bounded = ArchiveEndpoint.fromWorkspace(
        endpoint.workspace,
        importDeadline: const Duration(milliseconds: 70),
        readInactivity: const Duration(seconds: 1),
      );
      final plan = await bounded.prepareImport(
        source: input,
        files: [input.file],
      );
      await expectLater(
        bounded.stageImport(plan, control: FileOperationControl()),
        throwsA(anything),
      );
      expect(input.cancelled, isTrue);
      expect(endpoint.workspace.dirty, isFalse);
      await bounded.close();
    },
  );
  test('a source versionId-only replacement is retained even with identical bytes and timestamps', () async {
    final source = _VersionOnlySource();
    final plan = await endpoint.prepareImport(
      source: source,
      files: [(await source.stat('/input/new.txt'))!],
      moveSources: true,
    );
    final review = await endpoint.stageImport(
      plan,
      control: FileOperationControl(),
    );
    source.revision = 'v2';
    final result = await endpoint.commit(reviewed: review);
    expect(result.retainedSources, ['/input/new.txt']);
    expect(source.deletes, 0);
  });
  test('post-publication source metadata timeout returns an explicit unconfirmed move', () async {
    final source = _VersionOnlySource();
    final bounded = ArchiveEndpoint.fromWorkspace(
      endpoint.workspace,
      readInactivity: const Duration(milliseconds: 50),
    );
    addTearDown(bounded.close);
    final plan = await bounded.prepareImport(
      source: source,
      files: [(await source.stat('/input/new.txt'))!],
      moveSources: true,
    );
    final review = await bounded.stageImport(
      plan,
      control: FileOperationControl(),
    );
    backend.after = (action, path, destination) {
      if (action == 'move' && destination == '/out/work.zip') {
        source.stall = true;
      }
    };
    final result = await bounded.commit(reviewed: review);
    expect(result.retainedSources, ['/input/new.txt']);
    expect(result.receipt, isNotNull);
    expect(source.deletes, 0);
    expect((await published())['new.txt'], [3, 4, 5]);
  });
  test('native source removal checks the publication and unlinks exactly one verified file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'crisp-archive-source-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'source.txt'));
    await file.writeAsBytes([1, 2, 3], flush: true);
    final local = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => true,
    );
    var receiptChecks = 0;
    expect(
      await deleteNativeArchiveImportSource(
        local,
        (await local.stat(file.path))!,
        sha256: sha256.convert([1, 2, 3]).toString(),
        capturedIdentity: await captureNativeArchiveImportSource(
          local,
          (await local.stat(file.path))!,
        ),
        checkpoint: () async {},
        verifyPublication: () async {
          receiptChecks++;
        },
      ),
      isTrue,
    );
    expect(receiptChecks, 1);
    expect(await file.exists(), isFalse);
  });
  test(
    'native source mutation during the final receipt check refuses unlink',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'crisp-archive-source-change-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(p.join(directory.path, 'source.txt'));
      await file.writeAsBytes([1, 2, 3], flush: true);
      final local = LocalOperationBackend(
        LocalFileService(),
        isCurrent: () => true,
      );
      await expectLater(
        deleteNativeArchiveImportSource(
          local,
          (await local.stat(file.path))!,
          sha256: sha256.convert([1, 2, 3]).toString(),
          capturedIdentity: await captureNativeArchiveImportSource(
            local,
            (await local.stat(file.path))!,
          ),
          checkpoint: () async {},
          verifyPublication: () async {
            await file.writeAsBytes([9, 9, 9], flush: true);
          },
        ),
        throwsStateError,
      );
      expect(await file.readAsBytes(), [9, 9, 9]);
    },
  );
  test('native source replacement preserving bytes and mtime is retained by captured change time', () async {
    final directory = await Directory.systemTemp.createTemp(
      'crisp-archive-original-identity-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'native.txt'));
    await file.writeAsBytes([3, 4, 5], flush: true);
    final local = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => true,
    );
    final plan = await endpoint.prepareImport(
      source: local,
      files: [(await local.stat(file.path))!],
      moveSources: true,
    );
    final review = await endpoint.stageImport(
      plan,
      control: FileOperationControl(),
    );
    final modified = (await file.stat()).modified;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await file.writeAsBytes([3, 4, 5], flush: true);
    await file.setLastModified(modified);
    final result = await endpoint.commit(reviewed: review);
    expect(result.retainedSources, [file.path]);
    expect(result.removedSources, 0);
    expect(await file.readAsBytes(), [3, 4, 5]);
  });
  test('native source permission change after preview invalidates the import before adoption', () async {
    final directory = await Directory.systemTemp.createTemp(
      'crisp-archive-original-mode-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'native.txt'));
    await file.writeAsBytes([3, 4, 5], flush: true);
    final local = LocalOperationBackend(
      LocalFileService(),
      isCurrent: () => true,
    );
    if (!local.capabilities.permissions) return;
    final plan = await endpoint.prepareImport(
      source: local,
      files: [(await local.stat(file.path))!],
    );
    await local.writeMetadata(file.path, const TransferMetadata(mode: 0x100));
    await expectLater(
      endpoint.stageImport(plan, control: FileOperationControl()),
      throwsStateError,
    );
    expect(endpoint.workspace.dirty, isFalse);
    expect(backend.files['/out/work.zip'], original);
  });
  test('a ZIP with signed negative UTC timestamps remains read-only with the pinned reader', () async {
    final file = codec.ArchiveFile.bytes('older', [1])..lastModTime = -1;
    backend.put(
      '/out/old.zip',
      codec.ZipEncoder().encode(codec.Archive()..addFile(file)),
    );
    final workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat('/out/old.zip'))!,
      journal: journal,
    );
    addTearDown(workspace.close);
    expect(workspace.canUpdate, isFalse);
    expect(workspace.updateSupport, contains('timestamp'));
  });
  test('directory merge preserves existing archive mode and time while importing child metadata', () async {
    final sink = koni.BytesBuilderSink();
    final writer = koni.Archive.create(
      sink,
      format: const koni.ZipWriteFormat(),
    );
    final originalTime = DateTime.utc(2025, 2, 3, 4, 5, 6);
    await writer.addEntry(
      koni.ArchiveEntrySpec(
        path: 'folder',
        type: koni.ArchiveEntryType.directory,
        modified: originalTime,
        posixMode: 0x1c0,
      ),
    );
    await writer.addBytes(
      koni.ArchiveEntrySpec(path: 'folder/old'),
      Uint8List.fromList([1]),
    );
    await writer.close();
    await sink.close();
    backend.put('/out/folders.zip', sink.takeBytes());
    backend.put('/input/folder/new', [2]);
    backend.modes['/input/folder'] = 0x1ff;
    final merged = await ArchiveEndpoint.open(
      containerBackend: backend,
      containerFile: (await backend.stat('/out/folders.zip'))!,
      journal: journal,
    );
    addTearDown(merged.close);
    final plan = await merged.prepareImport(
      source: backend,
      files: [(await backend.stat('/input/folder'))!],
    );
    final review = await merged.stageImport(
      plan,
      control: FileOperationControl(),
    );
    expect(review.changes.map((change) => change.path), ['folder/new']);
    await merged.commit(reviewed: review);
    final archive = await openViewerArchive(
      backend.files['/out/folders.zip']!,
      name: 'folders.zip',
    );
    addTearDown(archive.close);
    final folder = archive.members.singleWhere(
      (member) => member.name == 'folder',
    );
    expect(folder.modified, originalTime);
    expect(folder.posixMode! & 0xfff, 0x1c0);
    expect(
      await archive.readMember(
        archive.members.singleWhere((member) => member.name == 'folder/new'),
      ),
      [2],
    );
  });
  test('misnamed detected containers cannot silently change format', () async {
    backend.put(
      '/out/misnamed.zip',
      await protected(const koni.TarWriteFormat(), {
        'member': [1],
      }),
    );
    final workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat('/out/misnamed.zip'))!,
      journal: journal,
    );
    addTearDown(workspace.close);
    expect(workspace.canUpdate, isFalse);
    expect(workspace.updateSupport, contains('format'));
  });
  test(
    'nested archives accept distinct passwords and preserve both policies',
    () async {
      final inner = await protected(const koni.ZipWriteFormat(), {
        'inside': [1],
      }, password: 'inner-password');
      final outer = await protected(
        const koni.SevenZWriteFormat(),
        {'inner.zip': inner},
        password: 'outer-password',
        names: true,
      );
      backend.put('/out/protected.7z', outer);
      final file = (await backend.stat('/out/protected.7z'))!;
      await expectLater(
        ArchiveWorkspace.openNested(
          backend,
          file,
          ['inner.zip'],
          passwords: ['outer-password', null],
          journal: journal,
        ),
        throwsA(
          isA<ArchiveNestedPasswordRequiredException>().having(
            (error) => error.level,
            'level',
            1,
          ),
        ),
      );
      final nested = await ArchiveWorkspace.openNested(
        backend,
        file,
        ['inner.zip'],
        passwords: ['outer-password', 'inner-password'],
        journal: journal,
      );
      addTearDown(nested.close);
      nested.replace('/added', Uint8List.fromList([2]));
      final receipt = await nested.save();
      expect(receipt, isNotNull);
      expect(nested.isCurrent, isTrue);
      expect(nested.dirty, isFalse);
      final reopened = await ArchiveWorkspace.openNested(
        backend,
        (await backend.stat('/out/protected.7z'))!,
        ['inner.zip'],
        passwords: ['outer-password', 'inner-password'],
        journal: journal,
      );
      addTearDown(reopened.close);
      expect(await reopened.read('/added'), [2]);
      expect(reopened.encrypted, isTrue);
      expect(reopened.outermost.encryptNames, isTrue);
    },
  );
  test(
    'empty header-encrypted 7z remains protected after adding a member',
    () async {
      final bytes = await protected(
        const koni.SevenZWriteFormat(),
        {},
        password: 'empty-secret',
        names: true,
      );
      backend.put('/out/empty.7z', bytes);
      final workspace = await ArchiveWorkspace.open(
        backend,
        (await backend.stat('/out/empty.7z'))!,
        password: 'empty-secret',
        journal: journal,
      );
      addTearDown(workspace.close);
      expect(workspace.encrypted, isTrue);
      expect(workspace.encryptNames, isTrue);
      workspace.replace('/added', Uint8List.fromList([3]));
      await workspace.save();
      await expectLater(
        openViewerArchive(backend.files['/out/empty.7z']!, name: 'empty.7z'),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );
    },
  );
  test(
    'removing the final encrypted ZIP file refuses to discard protection',
    () async {
      backend.put(
        '/out/encrypted.zip',
        await protected(const koni.ZipWriteFormat(), {
          'only': [1],
        }, password: 'secret'),
      );
      final workspace = await ArchiveWorkspace.open(
        backend,
        (await backend.stat('/out/encrypted.zip'))!,
        password: 'secret',
        journal: journal,
      );
      addTearDown(workspace.close);
      workspace.remove(['/only']);
      await expectLater(workspace.review(), throwsStateError);
      expect(backend.mutations, isEmpty);
    },
  );
  test('empty unverified password policy is read-only rather than silently unencrypted', () async {
    backend.put('/out/empty.zip', zip({}));
    final workspace = await ArchiveWorkspace.open(
      backend,
      (await backend.stat('/out/empty.zip'))!,
      password: 'unknown',
      journal: journal,
    );
    addTearDown(workspace.close);
    expect(workspace.canUpdate, isFalse);
  });
}

class _StalledSource extends ArchiveEndpointTestBackend {
  _StalledSource({this.drip = false}) {
    put('/input/drip', List.filled(100, 1));
  }
  final bool drip;
  bool cancelled = false;
  final file = FileItem(
    name: 'drip',
    path: '/input/drip',
    isFolder: false,
    size: 100,
  );
  @override
  Future<FileItem?> stat(String path) async =>
      path == file.path ? file : super.stat(path);
  @override
  Stream<List<int>> readFile(FileItem file) {
    Timer? timer;
    late StreamController<List<int>> controller;
    controller = StreamController(
      onListen: () {
        if (drip) {
          timer = Timer.periodic(
            const Duration(milliseconds: 10),
            (_) => controller.add([1]),
          );
        }
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );
    return controller.stream;
  }
}

class _VersionOnlySource extends ArchiveEndpointTestBackend {
  _VersionOnlySource() {
    put('/input/new.txt', [3, 4, 5]);
  }
  String revision = 'v1';
  bool stall = false;
  int deletes = 0;
  @override
  Future<FileItem?> stat(String path) async {
    if (path != '/input/new.txt') return super.stat(path);
    if (stall) return Completer<FileItem?>().future;
    if (!files.containsKey(path)) return null;
    return FileItem(
      name: 'new.txt',
      path: path,
      isFolder: false,
      size: 3,
      uuid: 'stable-key',
      updatedAt: DateTime.utc(2026),
      metadata: {'versionId': revision},
    );
  }

  @override
  Future<void> deleteFile(FileItem file) async {
    if (file.metadata?['versionId'] != revision) {
      throw StateError('Revision changed.');
    }
    deletes++;
    files.remove(file.path!);
  }
}
