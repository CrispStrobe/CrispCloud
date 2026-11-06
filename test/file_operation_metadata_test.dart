import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/services/transfer_recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const service = FileOperationService();
  const permissions = FileOperationOptions(preservePermissions: true);

  Future<FileOperationPlan> prepare(
    _MetadataBackend source,
    _MetadataBackend target, {
    String root = '/tree',
    FileOperationOptions options = permissions,
  }) => service.prepare(
    files: [source.item(root)],
    source: source,
    destination: target,
    targetDirectory: '/target',
    options: options,
  );

  _MetadataBackend tree() => _MetadataBackend('source')
    ..directory('/tree', mode: 0x1c0)
    ..directory('/tree/nested', mode: 0x1e8)
    ..file('/tree/nested/data.txt', 'copied bytes', mode: 0x1a0);

  test(
    'all requested directory metadata is applied after child writes',
    () async {
      final source = tree();
      final target = _MetadataBackend('target');
      final modified = DateTime.utc(2024, 6, 7, 8, 9, 10);
      source.metadata['/tree'] = TransferMetadata(
        mode: 0x1c0,
        owner: '1001',
        group: '1002',
        modified: modified,
        extendedAttributes: {
          'user.note': Uint8List.fromList([1, 2, 3]),
        },
        acl: 'owner:rwx;group:r-x',
      );
      final plan = await prepare(
        source,
        target,
        options: const FileOperationOptions(
          preserveModified: true,
          preservePermissions: true,
          preserveOwnership: true,
          preserveExtendedAttributes: true,
          preserveAcl: true,
        ),
      );
      expect(plan.errors, isEmpty);
      await service.execute(plan, control: FileOperationControl());

      final root = target.metadata['/target/tree']!;
      expect(root.mode, 0x1c0);
      expect(root.owner, '1001');
      expect(root.group, '1002');
      expect(root.modified, modified);
      expect(root.extendedAttributes['user.note'], [1, 2, 3]);
      expect(root.acl, 'owner:rwx;group:r-x');
      expect(target.metadata['/target/tree/nested']!.mode, 0x1e8);
      expect(
        target.events.where((event) => event.startsWith('metadata:')).toList(),
        [
          'metadata:/target/tree/nested/data.txt',
          'metadata:/target/tree/nested',
          'metadata:/target/tree',
        ],
      );
      expect(
        target.events.indexOf('write:/target/tree/nested/data.txt'),
        lessThan(target.events.indexOf('metadata:/target/tree/nested')),
      );
      expect(plan.entries.every((entry) => entry.completed), isTrue);
      for (final entry in plan.entries.where(
        (entry) => entry.source.isFolder,
      )) {
        expect(entry.recovery?['directoryMetadataApplied'], isTrue);
      }
    },
  );

  test('failed child data defers restrictive directory metadata', () async {
    final source = tree();
    final target = _MetadataBackend('target')
      ..writeFailures.add('/target/tree/nested/data.txt');
    final plan = await prepare(source, target);
    await service.execute(plan, control: FileOperationControl());

    expect(plan.entries.last.outcome, FileOperationOutcome.failed);
    expect(
      target.events.where((event) => event.startsWith('metadata:')),
      isEmpty,
    );
    expect(target.metadata['/target/tree']!.mode, 0x1ff);
    expect(target.metadata['/target/tree/nested']!.mode, 0x1ff);
    expect(source.bytes['/tree/nested/data.txt'], utf8.encode('copied bytes'));
  });

  test(
    'failed directory metadata is durable and retry does not recopy moved data',
    () async {
      final source = tree();
      final target = _MetadataBackend('target')
        ..metadataFailures.add('/target/tree/nested');
      final storage = MemoryTransferJournalStorage();
      final journal = TransferJournal(storage);
      final plan = await prepare(
        source,
        target,
        options: const FileOperationOptions(
          kind: FileOperationKind.move,
          preservePermissions: true,
        ),
      );
      await journal.create('directory-metadata', plan);
      await JournaledTransferRunner(journal)
          .execute('directory-metadata', plan, control: FileOperationControl());

      expect(
        journal.job('directory-metadata')!.status,
        TransferJobStatus.failed,
      );
      expect(plan.entries[1].outcome, FileOperationOutcome.metadataFailed);
      expect(plan.entries[1].message, contains('Source directory retained'));
      expect(source.directories, containsAll(['/tree', '/tree/nested']));
      expect(source.bytes.containsKey('/tree/nested/data.txt'), isFalse);
      expect(target.writes, 1);
      expect(target.metadata['/target/tree']!.mode, 0x1ff);

      final restarted = TransferJournal(storage);
      await restarted.initialize();
      final saved = restarted.job('directory-metadata')!;
      expect(saved.entries[1].outcome, FileOperationOutcome.metadataFailed);
      target.metadataFailures.clear();
      final preview = await const TransferRecoveryService().prepare(
        saved,
        source: source,
        destination: target,
        control: FileOperationControl(),
      );
      expect(preview.issues, isEmpty);
      await JournaledTransferRunner(restarted)
          .execute(saved.id, preview.plan, control: FileOperationControl());
      expect(restarted.job(saved.id)!.status, TransferJobStatus.completed);
      expect(target.writes, 1);
      expect(target.metadata['/target/tree/nested']!.mode, 0x1e8);
      expect(target.metadata['/target/tree']!.mode, 0x1c0);
      expect(source.directories, isNot(contains('/tree/nested')));
      expect(source.directories, isNot(contains('/tree')));
    },
  );

  test('cancellation during post-order metadata retains remaining source directories', () async {
    final source = tree();
    final target = _MetadataBackend('target');
    final control = FileOperationControl();
    target.afterMetadata = (path) {
      if (path == '/target/tree/nested') control.cancel();
    };
    final plan = await prepare(
      source,
      target,
      options: const FileOperationOptions(
        kind: FileOperationKind.move,
        preservePermissions: true,
      ),
    );
    await service.execute(plan, control: control);
    expect(control.isCancelled, isTrue);
    expect(plan.entries.where((entry) => entry.failed), isEmpty);
    expect(source.directories, containsAll(['/tree', '/tree/nested']));
    expect(plan.entries.first.recovery?['directoryMetadataApplied'], isFalse);
    expect(target.metadata['/target/tree']!.mode, 0x1ff);
  });

  test('explicit preservation cannot consume a native-move source before metadata succeeds', () async {
    final storage = _MetadataBackend('same-volume')
      ..file('/file.txt', 'source', mode: 0x1a0)
      ..metadataFailures.add('/target/file.txt');
    final plan = await prepare(
      storage,
      storage,
      root: '/file.txt',
      options: const FileOperationOptions(
        kind: FileOperationKind.move,
        preservePermissions: true,
      ),
    );
    await service.execute(plan, control: FileOperationControl());
    expect(storage.nativeMoves, 0);
    expect(plan.entries.single.outcome, FileOperationOutcome.metadataFailed);
    expect(storage.bytes['/file.txt'], utf8.encode('source'));
    expect(storage.bytes['/target/file.txt'], utf8.encode('source'));
  });

  test('ordinary native moves retain their fast path', () async {
    final storage = _MetadataBackend('same-volume')
      ..file('/file.txt', 'source', mode: 0x1a0);
    final plan = await prepare(
      storage,
      storage,
      root: '/file.txt',
      options: const FileOperationOptions(kind: FileOperationKind.move),
    );
    await service.execute(plan, control: FileOperationControl());
    expect(storage.nativeMoves, 1);
    expect(storage.writes, 0);
    expect(plan.entries.single.outcome, FileOperationOutcome.moved);
    expect(storage.bytes.containsKey('/file.txt'), isFalse);
    expect(storage.metadata['/target/file.txt']!.mode, 0x1a0);
  });

  test(
    'child moves may change directory revisions without losing its identity',
    () async {
      final source = tree();
      final target = _MetadataBackend('target');
      source.afterDelete = (_) {
        source.revisions['/tree'] = 'after-child-move';
        source.revisions['/tree/nested'] = 'after-child-move';
      };
      final plan = await prepare(
        source,
        target,
        options: const FileOperationOptions(
          kind: FileOperationKind.move,
          preservePermissions: true,
        ),
      );
      await service.execute(plan, control: FileOperationControl());
      expect(
        plan.entries.every(
          (entry) => entry.outcome == FileOperationOutcome.moved,
        ),
        isTrue,
      );
      expect(target.metadata['/target/tree']!.mode, 0x1c0);
    },
  );

  test(
    'a replaced destination directory does not receive captured metadata',
    () async {
      final source = tree();
      final target = _MetadataBackend('target');
      target.afterMetadata = (path) {
        if (path == '/target/tree/nested/data.txt') {
          target.objectIds['/target/tree'] = 'replacement-directory';
        }
      };
      final plan = await prepare(source, target);
      await service.execute(plan, control: FileOperationControl());
      expect(plan.entries.first.outcome, FileOperationOutcome.metadataFailed);
      expect(plan.entries.first.message, contains('directory changed'));
      expect(target.metadata['/target/tree']!.mode, 0x1ff);
    },
  );

  for (final requirement in [
    ('permissions', const FileOperationOptions(preservePermissions: true)),
    ('ownership', const FileOperationOptions(preserveOwnership: true)),
    ('access control list', const FileOperationOptions(preserveAcl: true)),
  ]) {
    test('missing requested ${requirement.$1} is a metadata failure', () async {
      final source = _MetadataBackend('source')..file('/file.txt', 'source');
      source.metadata['/file.txt'] = const TransferMetadata();
      final target = _MetadataBackend('target');
      final plan = await prepare(
        source,
        target,
        root: '/file.txt',
        options: requirement.$2,
      );
      await service.execute(plan, control: FileOperationControl());
      expect(plan.entries.single.outcome, FileOperationOutcome.metadataFailed);
      expect(plan.entries.single.message, contains(requirement.$1));
      expect(source.bytes['/file.txt'], utf8.encode('source'));
      expect(target.bytes['/target/file.txt'], utf8.encode('source'));
      expect(
        target.events.where((event) => event.startsWith('metadata:')),
        isEmpty,
      );
    });
  }

  for (final folder in [false, true]) {
    test(
      'missing ${folder ? 'directory' : 'file'} timestamp retains a move source',
      () async {
        final source = _MetadataBackend('source');
        if (folder) {
          source.directory('/item');
        } else {
          source.file('/item', 'retain');
        }
        source.metadata['/item'] = const TransferMetadata();
        final target = _MetadataBackend('target');
        final plan = await prepare(
          source,
          target,
          root: '/item',
          options: const FileOperationOptions(
            kind: FileOperationKind.move,
            preserveModified: true,
          ),
        );
        await service.execute(plan, control: FileOperationControl());
        expect(
          plan.entries.single.outcome,
          FileOperationOutcome.metadataFailed,
        );
        expect(plan.entries.single.message, contains('modification timestamp'));
        expect(await source.stat('/item'), isNotNull);
        expect(await target.stat('/target/item'), isNotNull);
        if (!folder) {
          expect(source.bytes['/item'], target.bytes['/target/item']);
        }
      },
    );
  }

  test(
    'permissions-only preservation does not probe unrelated metadata',
    () async {
      final source = _SelectiveMetadataBackend()
        ..file('/file.txt', 'source', mode: 0x180);
      final target = _MetadataBackend('target');
      final plan = await prepare(source, target, root: '/file.txt');
      await service.execute(plan, control: FileOperationControl());
      expect(plan.entries.single.outcome, FileOperationOutcome.copied);
      expect(target.metadata['/target/file.txt']!.mode, 0x180);
      expect(source.requested, {
        'permissions': true,
        'modified': false,
        'accessed': false,
        'ownership': false,
        'extendedAttributes': false,
        'acl': false,
      });
    },
  );

  test(
    'an empty source extended-attribute map is supported metadata',
    () async {
      final source = _MetadataBackend('source')..file('/file.txt', 'source');
      final target = _MetadataBackend('target');
      final plan = await prepare(
        source,
        target,
        root: '/file.txt',
        options: const FileOperationOptions(preserveExtendedAttributes: true),
      );
      await service.execute(plan, control: FileOperationControl());
      expect(plan.entries.single.outcome, FileOperationOutcome.copied);
    },
  );
}

class _MetadataBackend extends FileOperationBackend {
  _MetadataBackend(this.label) {
    directory('/');
    directory('/target');
  }

  @override
  final String label;
  @override
  StorageReference get storageReference => StorageReference(
    kind: 'remote',
    provider: 'metadata-test',
    accountKey: label,
  );
  @override
  Object get identity => storageReference.id;
  @override
  bool get isCurrent => true;
  @override
  bool get canRecover => true;
  @override
  p.Context get paths => p.posix;
  @override
  bool get supportsModifiedTime => true;
  @override
  StorageTransferCapabilities get capabilities =>
      const StorageTransferCapabilities(
        permissions: true,
        ownership: true,
        extendedAttributes: true,
        accessControlLists: true,
        setModifiedTime: true,
      );

  final directories = <String>{};
  final bytes = <String, List<int>>{};
  final metadata = <String, TransferMetadata>{};
  final revisions = <String, String>{};
  final objectIds = <String, String>{};
  final events = <String>[];
  final metadataFailures = <String>{};
  final writeFailures = <String>{};
  FutureOr<void> Function(String)? afterMetadata;
  FutureOr<void> Function(String)? afterDelete;
  int nativeMoves = 0;
  int writes = 0;

  void directory(String path, {int mode = 0x1ff}) {
    final parent = paths.dirname(path);
    if (parent != path && !directories.contains(parent)) directory(parent);
    directories.add(path);
    metadata[path] = TransferMetadata(
      mode: mode,
      modified: DateTime.utc(2024),
      owner: '1000',
      group: '1000',
      acl: 'owner:rwx;group:r-x',
    );
  }

  void file(String path, String contents, {int mode = 0x1b6}) {
    final parent = paths.dirname(path);
    if (!directories.contains(parent)) directory(parent);
    bytes[path] = utf8.encode(contents);
    metadata[path] = TransferMetadata(
      mode: mode,
      modified: DateTime.utc(2024),
      owner: '1000',
      group: '1000',
      acl: 'owner:rw-;group:r--',
    );
  }

  FileItem item(String path) => FileItem(
    path: path,
    uuid: objectIds[path] ?? 'node:$path',
    name: paths.basename(path),
    isFolder: directories.contains(path),
    isSymlink: false,
    size: bytes[path]?.length,
    updatedAt: metadata[path]?.modified,
    metadata: {if (revisions[path] != null) 'version': revisions[path]},
  );

  @override
  Future<FileItem?> stat(String path) async =>
      directories.contains(path) || bytes.containsKey(path) ? item(path) : null;
  @override
  Future<List<FileItem>> list(String path) async => [
    for (final candidate in {...directories, ...bytes.keys})
      if (candidate != path && paths.dirname(candidate) == path)
        item(candidate),
  ];
  @override
  Future<void> createDirectory(String path) async => directory(path);
  @override
  Stream<List<int>> readFile(FileItem file) => Stream.value(bytes[file.path!]!);
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async {
    if (writeFailures.contains(path)) throw StateError('Write denied');
    final contents = await data.fold(
      <int>[],
      (value, part) => value..addAll(part),
    );
    if (length != null && contents.length != length) {
      throw StateError('Length changed');
    }
    writes++;
    events.add('write:$path');
    bytes[path] = contents;
    metadata[path] = const TransferMetadata(mode: 0x1b6);
  }

  @override
  Future<void> deleteFile(FileItem file) async {
    bytes.remove(file.path);
    metadata.remove(file.path);
    await afterDelete?.call(file.path!);
  }

  @override
  Future<void> deleteEmptyDirectory(String path) async {
    if ((await list(path)).isNotEmpty) {
      throw StateError('Directory is not empty');
    }
    directories.remove(path);
    metadata.remove(path);
  }

  @override
  Future<TransferMetadata> readMetadata(String path) async => metadata[path]!;
  @override
  Future<void> writeMetadata(String path, TransferMetadata value) async {
    if (metadataFailures.contains(path)) throw StateError('Metadata denied');
    final existing = metadata[path]!;
    metadata[path] = TransferMetadata(
      mode: value.mode ?? existing.mode,
      owner: value.owner ?? existing.owner,
      group: value.group ?? existing.group,
      modified: value.modified ?? existing.modified,
      extendedAttributes: value.extendedAttributes.isEmpty
          ? existing.extendedAttributes
          : value.extendedAttributes,
      acl: value.acl ?? existing.acl,
    );
    events.add('metadata:$path');
    await afterMetadata?.call(path);
  }

  @override
  Future<void> setModified(String path, DateTime modified) async {
    if (metadataFailures.contains(path)) throw StateError('Metadata denied');
    final existing = metadata[path]!;
    metadata[path] = TransferMetadata(
      modified: modified,
      mode: existing.mode,
      owner: existing.owner,
      group: existing.group,
      extendedAttributes: existing.extendedAttributes,
      acl: existing.acl,
    );
  }

  @override
  Future<bool> moveNoReplace(FileItem file, String destination) async {
    if (await stat(destination) != null) throw StateError('Destination exists');
    nativeMoves++;
    bytes[destination] = bytes.remove(file.path)!;
    metadata[destination] = metadata.remove(file.path)!;
    return true;
  }
}

class _SelectiveMetadataBackend extends _MetadataBackend {
  _SelectiveMetadataBackend() : super('selective');
  Map<String, bool>? requested;

  @override
  Future<TransferMetadata> readMetadata(String path) async =>
      throw UnsupportedError('The filesystem cannot read ACLs.');

  @override
  Future<TransferMetadata> readMetadataFields(
    String path, {
    bool permissions = true,
    bool modified = true,
    bool accessed = true,
    bool ownership = true,
    bool extendedAttributes = true,
    bool acl = true,
  }) async {
    requested = {
      'permissions': permissions,
      'modified': modified,
      'accessed': accessed,
      'ownership': ownership,
      'extendedAttributes': extendedAttributes,
      'acl': acl,
    };
    if (modified || accessed || ownership || extendedAttributes || acl) {
      throw UnsupportedError('Only POSIX mode is available.');
    }
    return TransferMetadata(mode: metadata[path]!.mode);
  }
}
