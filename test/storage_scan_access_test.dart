import 'dart:async';
import 'dart:io';

import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Exercises the native worker through the real scan adapter. A fake access
/// lease supplies deterministic boundaries without relying on OS permissions
/// (tests may run as root) or races with filesystem changes.
class _ScopedLocal extends Fake
    implements LocalFileService, ScopedLocalFileOperations {
  bool denyAccess = false;
  int requests = 0;
  int actionCalls = 0;
  int activeScopes = 0;
  int releasedScopes = 0;
  final listingResults = <StorageScanDirectory>[];
  final activeAtListingCompletion = <int>[];
  Completer<StorageScanDirectory>? listingCompleted;
  Completer<void>? allowScopeRelease;
  void Function(Object? result)? onScopeReleased;

  @override
  Future<bool> hasAccessToPath(String path) async => !denyAccess;

  @override
  Future<T> withFileOperationAccess<T>(
    String path,
    Future<T> Function() action,
  ) async {
    requests++;
    if (denyAccess) {
      throw FileSystemException('Test directory grant was denied.', path);
    }
    activeScopes++;
    Object? completedResult;
    try {
      actionCalls++;
      final result = await action();
      completedResult = result;
      if (result is StorageScanDirectory) {
        listingResults.add(result);
        activeAtListingCompletion.add(activeScopes);
        listingCompleted?.complete(result);
        final release = allowScopeRelease;
        if (release != null) await release.future;
      }
      return result;
    } finally {
      activeScopes--;
      releasedScopes++;
      onScopeReleased?.call(completedResult);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp(
      'crisp-scan-access-',
    );
    root = Directory(await temporary.resolveSymbolicLinks());
    await File(p.join(root.path, 'payload.bin')).writeAsBytes([1, 2, 3, 4]);
  });

  tearDown(() async => root.delete(recursive: true));

  test(
    'native listing completes inside its access scope and awaits release',
    () async {
      final local = _ScopedLocal()
        ..listingCompleted = Completer<StorageScanDirectory>()
        ..allowScopeRelease = Completer<void>();
      final source = storageScanBackend(
        source: LocalPanelSource(root.path),
        local: local,
        isCurrent: () => true,
      );
      final reader = source as StorageScanDirectoryReader;
      var returnedToCaller = false;
      final pending = reader.listForStorageScan(root.path).then((result) {
        returnedToCaller = true;
        return result;
      });

      try {
        final workerResult = await local.listingCompleted!.future;
        expect(workerResult.isComplete, isTrue);
        expect(workerResult.entries.single.name, 'payload.bin');
        expect(workerResult.entries.single.size, 4);
        expect(local.activeAtListingCompletion, [1]);
        expect(local.activeScopes, 1);
        expect(local.releasedScopes, 0);
        expect(returnedToCaller, isFalse);
      } finally {
        local.allowScopeRelease!.complete();
      }

      final result = await pending;
      expect(result, same(local.listingResults.single));
      expect(returnedToCaller, isTrue);
      expect(local.requests, 1);
      expect(local.activeScopes, 0);
      expect(local.releasedScopes, 1);
    },
  );

  test(
    'source invalidation during scope release discards the finished listing',
    () async {
      var current = true;
      final local = _ScopedLocal()
        ..onScopeReleased = (result) {
          // Root stat also uses a scope. Disconnect only after the native
          // directory worker has returned its real result to the lease owner.
          if (result is StorageScanDirectory) current = false;
        };
      final source = storageScanBackend(
        source: LocalPanelSource(root.path),
        local: local,
        isCurrent: () => current,
      );

      final result = await const StorageScanService().scan(source, root.path);

      expect(local.listingResults.single.entries.single.size, 4);
      expect(local.activeAtListingCompletion, [1]);
      expect(local.activeScopes, 0);
      expect(result.sourceChanged, isTrue);
      expect(result.isComplete, isFalse);
      expect(result.root.fileCount, 0);
      expect(result.root.bytes, 0);
      expect(result.root.children, isEmpty);
      expect(result.issues.single.code, StorageScanIssueCode.sourceChanged);
    },
  );

  test(
    'denied access never invokes the scan action or publishes file data',
    () async {
      final local = _ScopedLocal()..denyAccess = true;
      final source = storageScanBackend(
        source: LocalPanelSource(root.path),
        local: local,
        isCurrent: () => true,
      );

      final result = await const StorageScanService().scan(source, root.path);

      expect(local.requests, 1);
      expect(local.actionCalls, 0);
      expect(local.listingResults, isEmpty);
      expect(local.activeScopes, 0);
      expect(result.isComplete, isFalse);
      expect(result.root.fileCount, 0);
      expect(result.root.bytes, 0);
      expect(result.root.children, isEmpty);
      expect(result.issues.single.code, StorageScanIssueCode.rootUnavailable);
    },
  );

  test('native worker errors release the access scope', () async {
    final local = _ScopedLocal();
    final source = storageScanBackend(
      source: LocalPanelSource(root.path),
      local: local,
      isCurrent: () => true,
    );
    final reader = source as StorageScanDirectoryReader;

    await expectLater(
      reader.listForStorageScan(p.join(root.path, 'missing-directory')),
      throwsA(isA<FileSystemException>()),
    );

    expect(local.requests, 1);
    expect(local.actionCalls, 1);
    expect(local.activeScopes, 0);
    expect(local.releasedScopes, 1);
    expect(local.listingResults, isEmpty);
  });

  test('a FIFO remains unknown while readable siblings are retained', () async {
    String? mkfifo;
    for (final directory in (Platform.environment['PATH'] ?? '').split(':')) {
      final candidate = p.join(directory, 'mkfifo');
      if (File(candidate).existsSync()) {
        mkfifo = candidate;
        break;
      }
    }
    if (mkfifo == null) {
      markTestSkipped('Requires the POSIX mkfifo utility on PATH.');
      return;
    }
    final fifoPath = p.join(root.path, 'entry.fifo');
    final creation = await Process.run(mkfifo, [fifoPath]);
    expect(creation.exitCode, 0, reason: creation.stderr.toString());
    expect(
      FileSystemEntity.typeSync(fifoPath, followLinks: false),
      FileSystemEntityType.pipe,
    );
    final local = _ScopedLocal();
    final source = storageScanBackend(
      source: LocalPanelSource(root.path),
      local: local,
      isCurrent: () => true,
    );

    final result = await const StorageScanService().scan(source, root.path);

    expect(result.isComplete, isFalse);
    expect(result.root.fileCount, 2);
    expect(result.root.bytes, 4);
    expect(result.root.unknownSizeCount, 1);
    final payload = result.root.children.singleWhere(
      (node) => node.name == 'payload.bin',
    );
    expect(payload.bytes, 4);
    expect(payload.isComplete, isTrue);
    final unknown = result.root.children.singleWhere(
      (node) => node.path == fifoPath,
    );
    expect(unknown.item.size, isNull);
    expect(unknown.isComplete, isFalse);
    expect(
      result.issues.any(
        (issue) =>
            issue.path == fifoPath &&
            issue.code == StorageScanIssueCode.invalidEntry,
      ),
      isTrue,
    );
    expect(local.activeScopes, 0);
  }, skip: Platform.isWindows ? 'Requires a POSIX FIFO.' : false);
}
