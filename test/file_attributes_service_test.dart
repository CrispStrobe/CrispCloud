import 'dart:typed_data';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_attributes_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/storage_transfer_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const service = FileAttributesService();
  late _Backend backend;
  setUp(() => backend = _Backend());
  Future<FileAttributesPlan> preview({
    bool recursive = false,
    FileAttributesPatch patch = const FileAttributesPatch(mode: 0x1a0),
    List<FileAttributesTarget>? targets,
  }) => service.preview(
    targets:
        targets ?? [FileAttributesTarget(backend, backend.items['/root']!)],
    patch: patch,
    recursive: recursive,
  );

  test(
    'preview is read-only and recursive changes run deepest first',
    () async {
      final plan = await preview(recursive: true);
      expect(backend.writes, isEmpty);
      expect(plan.ready, 3);
      expect(
        plan.entries.where((e) => e.outcome == FileAttributesOutcome.skipped),
        hasLength(1),
      );
      await service.apply(plan);
      expect(backend.writes, ['/root/sub/file', '/root/sub', '/root']);
      expect(plan.changed, 3);
      expect(backend.writes, isNot(contains('/root/link')));
    },
  );

  test(
    'overlapping selected roots are deduplicated and ordered by actual depth',
    () async {
      final plan = await preview(
        recursive: true,
        targets: [
          FileAttributesTarget(backend, backend.items['/root/sub']!),
          FileAttributesTarget(backend, backend.items['/root']!),
        ],
      );
      await service.apply(plan);
      expect(backend.writes, ['/root/sub/file', '/root/sub', '/root']);
    },
  );

  test(
    'a disconnected captured account cannot write to its replacement',
    () async {
      final plan = await preview();
      backend.current = false;
      await service.apply(plan);
      expect(plan.entries.single.outcome, FileAttributesOutcome.failed);
      expect(backend.writes, isEmpty);
    },
  );

  test('same-size version edits after preview are rejected', () async {
    final original = backend.items['/root/sub/file']!;
    final plan = await preview(
      targets: [FileAttributesTarget(backend, original)],
    );
    backend.items[original.path!] = original.copyWith(
      metadata: {'etag': 'changed'},
    );
    await service.apply(plan);
    expect(backend.writes, isEmpty);
    expect(plan.entries.single.message, contains('changed since preview'));
  });

  test('provider revision changes invalidate a reviewed file', () async {
    final original = backend.items['/root/sub/file']!.copyWith(
      metadata: {'revision': 'one'},
    );
    backend.items[original.path!] = original;
    final plan = await preview(
      targets: [FileAttributesTarget(backend, original)],
    );
    backend.items[original.path!] = original.copyWith(
      metadata: {'revision': 'two'},
    );
    await service.apply(plan);
    expect(backend.writes, isEmpty);
    expect(plan.entries.single.outcome, FileAttributesOutcome.failed);
  });

  test('replacement during the apply metadata read cannot receive reviewed attributes', () async {
    final original = backend.items['/root/sub/file']!;
    final plan = await preview(
      targets: [FileAttributesTarget(backend, original)],
    );
    backend.onRead = (path) async {
      backend.onRead = null;
      backend.items[path] = original.copyWith(
        metadata: {'etag': 'replacement'},
      );
    };
    await service.apply(plan);
    expect(backend.writes, isEmpty);
    expect(plan.entries.single.outcome, FileAttributesOutcome.failed);
    expect(
      plan.entries.single.message,
      contains('while reading its attributes'),
    );
  });

  test(
    'recursive listing captures directory access times after its own reads',
    () async {
      backend.touchAccessedOnList = true;
      final requested = DateTime.utc(2023, 7, 8);
      final plan = await preview(
        recursive: true,
        patch: FileAttributesPatch(accessed: requested),
      );
      expect(plan.ready, 3);
      expect(
        plan.entries
            .firstWhere((e) => e.target.file.path == '/root')
            .before!
            .accessed,
        DateTime.utc(2026),
      );
      await service.apply(plan);
      expect(plan.changed, 3);
      expect(backend.writes, ['/root/sub/file', '/root/sub', '/root']);
      for (final path in backend.writes) {
        expect(backend.metadata[path]!.accessed, requested);
      }
    },
  );

  test(
    'Windows edits change only their selected flags and support creation time',
    () async {
      backend = _Backend(supportsWindows: true);
      final created = DateTime.utc(2022, 3, 4);
      final plan = await preview(
        patch: FileAttributesPatch(
          windowsAttributes: 2,
          windowsAttributesMask: 3,
          created: created,
        ),
      );
      await service.apply(plan);
      expect(plan.changed, 1);
      expect(backend.metadata['/root']!.windowsAttributes, 0x26);
      expect(backend.metadata['/root']!.created, created);
      expect(backend.metadata['/root']!.modified, DateTime.utc(2024));
    },
  );

  test('unrequested Windows flags can change without stale selected flags being ignored', () async {
    backend = _Backend(supportsWindows: true);
    final plan = await preview(
      patch: const FileAttributesPatch(
        windowsAttributes: 2,
        windowsAttributesMask: 2,
      ),
    );
    backend.metadata['/root'] = const TransferMetadata(windowsAttributes: 0x21);
    await service.apply(plan);
    expect(plan.changed, 1);
    expect(backend.metadata['/root']!.windowsAttributes, 0x23);
  });

  test(
    'creation time and Windows attributes are blocked when unsupported',
    () async {
      for (final patch in [
        FileAttributesPatch(created: DateTime.utc(2024)),
        const FileAttributesPatch(
          windowsAttributes: 2,
          windowsAttributesMask: 2,
        ),
      ]) {
        final plan = await preview(patch: patch);
        expect(plan.ready, 0);
        expect(plan.entries.single.outcome, FileAttributesOutcome.blocked);
      }
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'changes to reviewed attributes do not get silently overwritten',
    () async {
      final plan = await preview();
      backend.metadata['/root'] = const TransferMetadata(mode: 0x1ff);
      await service.apply(plan);
      expect(backend.writes, isEmpty);
      expect(plan.entries.single.message, contains('attributes changed'));
    },
  );

  test(
    'a failed descendant retains parent permissions even when continuing',
    () async {
      final plan = await preview(recursive: true);
      backend.failPath = '/root/sub/file';
      await service.apply(plan, stopOnError: false);
      expect(backend.writes, ['/root/sub/file']);
      expect(plan.changed, 0);
      expect(
        plan.entries.where((e) => e.outcome == FileAttributesOutcome.failed),
        hasLength(3),
      );
    },
  );

  test(
    'cancellation between review and write leaves every item untouched',
    () async {
      final plan = await preview(recursive: true);
      await service.apply(plan, isCancelled: () => true);
      expect(backend.writes, isEmpty);
      expect(
        plan.entries.where((e) => e.outcome == FileAttributesOutcome.cancelled),
        hasLength(3),
      );
    },
  );

  test('unsafe child paths cannot escape a recursive selection', () async {
    backend.badChild = FileItem(
      name: 'outside',
      path: '/elsewhere',
      isFolder: false,
    );
    final plan = await preview(recursive: true);
    expect(
      plan.entries.firstWhere((e) => e.target.file.path == '/root').outcome,
      FileAttributesOutcome.blocked,
    );
    expect(
      plan.entries.any((e) => e.target.file.path == '/elsewhere'),
      isFalse,
    );
  });

  test(
    'mixed source selection reports unsupported rows independently',
    () async {
      final other = _Backend(supportsMode: false);
      final plan = await preview(
        targets: [
          FileAttributesTarget(backend, backend.items['/root']!),
          FileAttributesTarget(other, other.items['/root']!),
        ],
      );
      expect(plan.ready, 1);
      expect(
        plan.entries.where((e) => e.outcome == FileAttributesOutcome.blocked),
        hasLength(1),
      );
      await service.apply(plan);
      expect(backend.writes, ['/root']);
      expect(other.writes, isEmpty);
    },
  );

  test(
    'only requested fields are read and successfully written values verified',
    () async {
      final modified = DateTime.utc(2024, 1, 2, 3, 4, 5);
      final plan = await preview(
        patch: FileAttributesPatch(modified: modified),
      );
      expect(
        backend.readFields,
        everyElement([false, true, false, false, false, false, false, false]),
      );
      await service.apply(plan);
      expect(plan.changed, 1);
      expect(backend.metadata['/root']!.modified, modified);
      expect(backend.metadata['/root']!.mode, 0x1ed);
    },
  );

  test(
    'a provider that ignores the requested values is reported as failed',
    () async {
      final plan = await preview();
      backend.ignoreWrites = true;
      await service.apply(plan);
      expect(plan.changed, 0);
      expect(plan.entries.single.message, contains('did not retain'));
    },
  );

  test(
    'a completed plan cannot be replayed after its review became stale',
    () async {
      final plan = await preview();
      await service.apply(plan);
      await expectLater(service.apply(plan), throwsStateError);
      expect(backend.writes, hasLength(1));
    },
  );

  test(
    'empty patches and invalid octal permission values cannot be previewed',
    () async {
      await expectLater(
        preview(patch: const FileAttributesPatch()),
        throwsFormatException,
      );
      await expectLater(
        preview(patch: const FileAttributesPatch(mode: 0x1000)),
        throwsFormatException,
      );
      for (final patch in [
        const FileAttributesPatch(
          windowsAttributes: 2,
          windowsAttributesMask: 1,
        ),
        const FileAttributesPatch(
          windowsAttributes: 0,
          windowsAttributesMask: 0x80,
        ),
      ]) {
        await expectLater(preview(patch: patch), throwsFormatException);
      }
    },
  );
}

class _Backend extends FileOperationBackend {
  _Backend({this.supportsMode = true, this.supportsWindows = false}) {
    for (final item in [
      FileItem(name: 'root', path: '/root', isFolder: true),
      FileItem(name: 'sub', path: '/root/sub', isFolder: true),
      FileItem(
        name: 'file',
        path: '/root/sub/file',
        isFolder: false,
        size: 4,
        updatedAt: DateTime.utc(2024),
        metadata: {'etag': 'original'},
      ),
      FileItem(
        name: 'link',
        path: '/root/link',
        isFolder: false,
        isSymlink: true,
      ),
    ]) {
      items[item.path!] = item;
      metadata[item.path!] = TransferMetadata(
        mode: 0x1ed,
        owner: '1000',
        group: '1000',
        modified: DateTime.utc(2024),
        accessed: DateTime.utc(2024),
        created: DateTime.utc(2020),
        windowsAttributes: 0x25,
      );
    }
  }
  final bool supportsMode;
  final bool supportsWindows;
  bool touchAccessedOnList = false;
  bool current = true;
  bool ignoreWrites = false;
  String? failPath;
  FileItem? badChild;
  final items = <String, FileItem>{};
  final metadata = <String, TransferMetadata>{};
  final writes = <String>[];
  final readFields = <List<bool>>[];
  Future<void> Function(String path)? onRead;
  @override
  Object get identity => this;
  @override
  String get label => 'Captured test account';
  @override
  bool get isCurrent => current;
  @override
  p.Context get paths => p.posix;
  @override
  StorageTransferCapabilities get capabilities => StorageTransferCapabilities(
    permissions: supportsMode,
    ownership: true,
    setModifiedTime: true,
    setAccessedTime: true,
    setCreatedTime: supportsWindows,
    windowsAttributes: supportsWindows,
  );
  @override
  Future<FileItem?> stat(String path) async => items[path];
  @override
  Future<List<FileItem>> list(String path) async {
    if (touchAccessedOnList) {
      final old = metadata[path]!;
      metadata[path] = TransferMetadata(
        mode: old.mode,
        owner: old.owner,
        group: old.group,
        modified: old.modified,
        accessed: DateTime.utc(2026),
        created: old.created,
        windowsAttributes: old.windowsAttributes,
      );
    }
    return [
      for (final item in items.values)
        if (p.posix.dirname(item.path!) == path && item.path != path) item,
      if (path == '/root' && badChild != null) badChild!,
    ];
  }

  @override
  Future<TransferMetadata> readMetadataFields(
    String path, {
    bool permissions = true,
    bool modified = true,
    bool accessed = true,
    bool created = true,
    bool windowsAttributes = true,
    bool ownership = true,
    bool extendedAttributes = true,
    bool acl = true,
  }) async {
    await onRead?.call(path);
    readFields.add([
      permissions,
      modified,
      accessed,
      ownership,
      extendedAttributes,
      acl,
      created,
      windowsAttributes,
    ]);
    final m = metadata[path]!;
    return TransferMetadata(
      mode: permissions ? m.mode : null,
      modified: modified ? m.modified : null,
      accessed: accessed ? m.accessed : null,
      owner: ownership ? m.owner : null,
      group: ownership ? m.group : null,
      created: created ? m.created : null,
      windowsAttributes: windowsAttributes ? m.windowsAttributes : null,
    );
  }

  @override
  Future<void> writeMetadata(String path, TransferMetadata m) async {
    writes.add(path);
    if (path == failPath) throw StateError('Permission denied');
    if (ignoreWrites) return;
    final old = metadata[path]!;
    metadata[path] = TransferMetadata(
      mode: m.mode ?? old.mode,
      owner: m.owner ?? old.owner,
      group: m.group ?? old.group,
      modified: m.modified ?? old.modified,
      accessed: m.accessed ?? old.accessed,
      created: m.created ?? old.created,
      windowsAttributes: m.windowsAttributes == null
          ? old.windowsAttributes
          : ((old.windowsAttributes! & ~m.windowsAttributesMask) |
                m.windowsAttributes!),
    );
  }

  @override
  Future<void> createDirectory(String path) => throw UnimplementedError();
  @override
  Future<void> deleteEmptyDirectory(String path) => throw UnimplementedError();
  @override
  Future<void> deleteFile(FileItem file) => throw UnimplementedError();
  @override
  Stream<Uint8List> readFile(FileItem file) => throw UnimplementedError();
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) => throw UnimplementedError();
}
