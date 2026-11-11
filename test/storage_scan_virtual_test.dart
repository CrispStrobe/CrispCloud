import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _VirtualLocal extends Fake
    implements
        LocalFileService,
        LocalFileSourceIdentity,
        LocalDirectorySnapshotReader {
  Object grant = Object();
  final foreignGrants = <String, Object>{};
  final directories = <String, List<FileSystemEntity>?>{};
  final metadata = <String, Map<String, dynamic>>{};
  final snapshotReads = <String>[];
  final metadataReads = <String>[];
  Completer<void>? snapshotStarted;
  Completer<void>? releaseSnapshot;
  bool deny = false;
  int interactiveReads = 0;
  int cacheWrites = 0;
  int accessRequests = 0;
  String cacheMarker = 'original browsing state';

  @override
  String currentPath = '/Selected/visible';
  @override
  String get grantedBasePath => '/Selected';
  @override
  Object? sourceIdentityForPath(String path) {
    if (foreignGrants.containsKey(path)) return foreignGrants[path];
    final normalized = p.posix.normalize(path);
    return normalized == '/Selected' ||
            p.posix.isWithin('/Selected', normalized)
        ? grant
        : null;
  }

  @override
  Future<List<FileSystemEntity>?> listDirectorySnapshot(String path) async {
    snapshotReads.add(path);
    if (deny || !directories.containsKey(path)) {
      throw PathAccessException(path, const OSError('Access denied', 13));
    }
    final entries = directories[path];
    final captured = entries == null
        ? null
        : List<FileSystemEntity>.of(entries);
    if (snapshotStarted?.isCompleted == false) snapshotStarted!.complete();
    await releaseSnapshot?.future;
    return captured;
  }

  @override
  Map<String, dynamic> getWebMetadata(String path) {
    metadataReads.add(path);
    return metadata[path] ?? {};
  }

  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    interactiveReads++;
    cacheWrites++;
    cacheMarker = 'interactive listing replaced the cache';
    currentPath = path;
    throw StateError('Background scans must not populate the browsing cache.');
  }

  @override
  Future<bool> ensureAccess(String path) async {
    accessRequests++;
    throw StateError('Background scans must not request a grant.');
  }

  @override
  Future<String?> requestDirectoryAccess({String? initialDirectory}) async {
    accessRequests++;
    throw StateError('Background scans must not open a picker.');
  }
}

class _LegacyVirtual extends Fake
    implements LocalFileService, LocalFileSourceIdentity {
  final grant = Object();
  int interactiveReads = 0;
  @override
  Object? sourceIdentityForPath(String path) => grant;
  @override
  Future<List<FileSystemEntity>?> listDirectory(String path) async {
    interactiveReads++;
    return [];
  }
}

void main() {
  const scanner = StorageScanService();
  late _VirtualLocal local;

  setUp(() {
    local = _VirtualLocal();
    local.directories['/Selected'] = [
      File('/Selected/known.bin'),
      File('/Selected/.hidden'),
      Directory('/Selected/nested'),
      Link('/Selected/outside-link'),
    ];
    local.directories['/Selected/nested'] = [File('/Selected/nested/new.bin')];
    local.metadata['/Selected/known.bin'] = {'size': 4};
    local.metadata['/Selected/.hidden'] = {'size': 2};
  });

  VirtualLocalStorageScanBackend source({String root = '/Selected'}) =>
      VirtualLocalStorageScanBackend(
        local,
        scanRoot: root,
        isCurrent: () => true,
      );

  void expectUnchangedBrowsingState() {
    expect(local.currentPath, '/Selected/visible');
    expect(local.grantedBasePath, '/Selected');
    expect(local.interactiveReads, 0);
    expect(local.cacheWrites, 0);
    expect(local.accessRequests, 0);
  }

  test(
    'virtual scans preserve browsing state and exact snapshot entry kinds',
    () async {
      final result = await scanner.scan(source(), '/Selected');
      expect(result.isComplete, isFalse);
      expect(result.root.bytes, 6);
      expect(result.root.fileCount, 3);
      expect(result.root.folderCount, 1);
      expect(result.root.unknownSizeCount, 1);
      expect(result.root.skippedLinkCount, 1);
      expect(
        result.root.children.any((entry) => entry.name == '.hidden'),
        isTrue,
      );
      expect(local.snapshotReads, ['/Selected', '/Selected/nested']);
      expect(local.metadataReads, [
        '/Selected/known.bin',
        '/Selected/.hidden',
        '/Selected/nested/new.bin',
      ]);
      expect(local.cacheMarker, 'original browsing state');
      expectUnchangedBrowsingState();
    },
  );

  test('grant replacement during a snapshot rejects late data without cache writes', () async {
    final original = local.grant;
    local.snapshotStarted = Completer<void>();
    local.releaseSnapshot = Completer<void>();
    final backend = source();
    final pending = scanner.scan(backend, '/Selected');
    await local.snapshotStarted!.future;
    local.grant = Object();
    local.cacheMarker = 'replacement grant browsing state';
    local.releaseSnapshot!.complete();
    final result = await pending;
    expect(result.sourceChanged, isTrue);
    expect(result.isComplete, isFalse);
    expect(result.root.bytes, 0);
    expect(result.root.children, isEmpty);
    expect(local.metadataReads, isEmpty);
    expect(local.cacheMarker, 'replacement grant browsing state');
    expect(backend.isCurrent, isFalse);
    local.grant = original;
    expect(backend.isCurrent, isFalse);
    expectUnchangedBrowsingState();
  });

  test(
    'canonical scan path owns the grant instead of its literal alias',
    () async {
      const alias = '/Other/../Selected';
      local.foreignGrants[alias] = Object();
      final backend = source(root: alias);
      expect(backend.scanRoot, '/Selected');
      expect((await scanner.scan(backend, alias)).root.bytes, 6);
      local.grant = Object();
      expect(backend.isCurrent, isFalse);
      expectUnchangedBrowsingState();
    },
  );

  test('virtual stat maps snapshot records without following links or reading contents', () async {
    final backend = source();
    final folder = await backend.stat('/Selected/nested');
    final file = await backend.stat('/Selected/known.bin');
    final link = await backend.stat('/Selected/outside-link');
    expect(folder?.isFolder, isTrue);
    expect(file?.isFolder, isFalse);
    expect(file?.size, 4);
    expect(link?.isSymlink, isTrue);
    expect(link?.isFolder, isFalse);
    expect(await backend.stat('/Selected/missing'), isNull);
    expect(local.snapshotReads.every((path) => path == '/Selected'), isTrue);
    expectUnchangedBrowsingState();
  });

  test('malformed and foreign-grant entries never read metadata or become scan children', () async {
    local.directories['/Selected']!.addAll([
      File('/Other/private.bin'),
      File('/Selected/nested/descendant.bin'),
      File('/Selected/alias/../known.bin'),
      Directory('/Selected/foreign'),
      File('/Selected/ambiguous.bin'),
      File('/Selected/ambiguous.bin'),
    ]);
    local.metadata['/Selected/ambiguous.bin'] = {'size': 999};
    local.foreignGrants['/Selected/foreign'] = Object();
    final result = await scanner.scan(source(), '/Selected');
    expect(result.root.bytes, 6);
    expect(result.root.fileCount, 3);
    expect(result.root.folderCount, 1);
    expect(
      result.issues.where(
        (issue) => issue.code == StorageScanIssueCode.invalidEntry,
      ),
      hasLength(6),
    );
    expect(local.metadataReads, [
      '/Selected/known.bin',
      '/Selected/.hidden',
      '/Selected/nested/new.bin',
    ]);
    expect(local.snapshotReads, ['/Selected', '/Selected/nested']);
    expectUnchangedBrowsingState();
  });

  test('ungranted namespace and out-of-root reads fail without interactive fallback', () async {
    expect(() => source(root: '/'), throwsUnsupportedError);
    final backend = source();
    await expectLater(
      backend.list('/Other'),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      backend.stat('/Selected/../Other'),
      throwsA(isA<FileSystemException>()),
    );
    expect(local.snapshotReads, isEmpty);
    expectUnchangedBrowsingState();
  });

  test(
    'denied and missing snapshots stay failed without invented empty totals',
    () async {
      for (final denied in [true, false]) {
        local.deny = denied;
        if (!denied) local.directories['/Selected'] = null;
        final result = await scanner.scan(source(), '/Selected');
        expect(result.isComplete, isFalse);
        expect(result.root.bytes, 0);
        expect(result.issues.single.code, StorageScanIssueCode.rootUnavailable);
      }
      expectUnchangedBrowsingState();
    },
  );

  test('a legacy virtual service cannot substitute a mutating listing for a snapshot', () {
    final legacy = _LegacyVirtual();
    expect(
      () => VirtualLocalStorageScanBackend(
        legacy,
        scanRoot: '/Selected',
        isCurrent: () => true,
      ),
      throwsUnsupportedError,
    );
    expect(legacy.interactiveReads, 0);
  });
}
