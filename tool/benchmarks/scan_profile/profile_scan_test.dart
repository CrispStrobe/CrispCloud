// Run against the pinned baseline checkout described in README.md.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_scan_backend.dart';
import 'package:crisp_cloud/services/storage_scan_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'profiled_native_read.dart';
import 'profiled_scan_service.dart';
import 'scan_profile.dart';
import '../../../test/support/workflow_fake_client.dart';

final fixture =
    Platform.environment['SCAN_PROFILE_FIXTURE'] ??
    (throw StateError(
      'Set SCAN_PROFILE_FIXTURE to the generated 24,000-file fixture.',
    ));

class _MeasuredNative extends LocalOperationBackend
    implements StorageScanDirectoryReader {
  _MeasuredNative(super.service, this.profile) : super(isCurrent: () => true);
  final ScanProfile profile;
  @override
  String pathKey(String path) => paths.normalize(path);
  @override
  Future<StorageScanDirectory> listForStorageScan(String path) async {
    if (!isCurrent) throw StateError('Source changed');
    final result = await service.withFileOperationAccess(path, () async {
      if (!isCurrent) throw StateError('Source changed');
      final start = profile.mark();
      final (listing, workerTicks) = await readProfiledNativeDirectory(path);
      profile.record('native_spawn_worker_handoff', start);
      profile.add('native_worker', workerTicks);
      if (!isCurrent) throw StateError('Source changed');
      return listing;
    });
    if (!isCurrent) throw StateError('Source changed');
    return result;
  }
}

class _MeasuredPaths implements p.Context {
  _MeasuredPaths(this.delegate, this.profile);
  final p.Context delegate;
  final ScanProfile profile;
  @override
  String normalize(String path) =>
      profile.sync('paths_normalize', () => delegate.normalize(path));
  @override
  bool isAbsolute(String path) =>
      profile.sync('paths_isAbsolute', () => delegate.isAbsolute(path));
  @override
  String dirname(String path) =>
      profile.sync('paths_dirname', () => delegate.dirname(path));
  @override
  String basename(String path) =>
      profile.sync('paths_basename', () => delegate.basename(path));
  @override
  // Context exposes an internal subtype; infer it without importing path/src.
  // ignore: always_declare_return_types
  get style => delegate.style;
  @override
  String get current => delegate.current;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _MeasuredBackend extends FileOperationBackend
    implements StorageScanDirectoryReader {
  _MeasuredBackend(this.delegate, this.profile)
    : _paths = _MeasuredPaths(delegate.paths, profile);
  final FileOperationBackend delegate;
  final ScanProfile profile;
  final p.Context _paths;
  @override
  Object get identity =>
      profile.sync('source_identity', () => delegate.identity);
  @override
  bool get isCurrent =>
      profile.sync('source_isCurrent', () => delegate.isCurrent);
  @override
  p.Context get paths => _paths;
  @override
  String get label => delegate.label;
  @override
  bool get supportsSymbolicLinks => delegate.supportsSymbolicLinks;
  @override
  String pathKey(String path) =>
      profile.sync('pathKey', () => delegate.pathKey(path));
  @override
  bool samePath(String first, String second) =>
      profile.sync('samePath', () => delegate.samePath(first, second));
  @override
  bool isWithin(String parent, String child) =>
      profile.sync('isWithin', () => delegate.isWithin(parent, child));
  @override
  Future<FileItem?> stat(String path) =>
      profile.async('source_stat', () => delegate.stat(path));
  @override
  Future<StorageScanDirectory> listForStorageScan(String path) => profile.async(
    'source_listing',
    () => (delegate as StorageScanDirectoryReader).listForStorageScan(path),
  );
  @override
  Future<List<FileItem>> list(String path) async =>
      (await listForStorageScan(path)).entries;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _CachedBackend extends FileOperationBackend
    implements StorageScanDirectoryReader {
  _CachedBackend(
    this.original,
    StorageScanResult result, {
    this.cheapIdentity = false,
    this.cheapPath = false,
  }) {
    final pending = [result.root];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      items[node.path] = node.item;
      if (node.isFolder) {
        directories[node.path] = StorageScanDirectory(
          entries: node.children.map((child) => child.item).toList(),
        );
      }
      pending.addAll(node.children);
    }
  }
  final FileOperationBackend original;
  final bool cheapIdentity;
  final bool cheapPath;
  final items = <String, FileItem>{};
  final directories = <String, StorageScanDirectory>{};
  @override
  Object get identity => cheapIdentity ? 'stable-cached' : original.identity;
  @override
  bool get isCurrent => cheapIdentity ? true : original.isCurrent;
  @override
  String get label => 'Cached validated fixture';
  @override
  p.Context get paths => original.paths;
  @override
  bool get supportsSymbolicLinks => true;
  // Cheap paths are a lower-bound experiment over already validated cached
  // fixture entries, NOT a suggested bypass for untrusted production entries.
  @override
  String pathKey(String path) => cheapPath ? path : original.pathKey(path);
  @override
  bool samePath(String a, String b) =>
      cheapPath ? a == b : original.samePath(a, b);
  @override
  bool isWithin(String a, String b) => cheapPath
      ? b.startsWith(a.endsWith('/') ? a : '$a/')
      : original.isWithin(a, b);
  @override
  Future<FileItem?> stat(String path) async => items[path];
  @override
  Future<StorageScanDirectory> listForStorageScan(String path) async =>
      directories[path]!;
  @override
  Future<List<FileItem>> list(String path) async => directories[path]!.entries;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

String digest(StorageScanResult result) {
  expect(result.isComplete, isTrue);
  expect(result.root.fileCount, 24000);
  expect(result.root.folderCount, 460);
  expect(result.root.bytes, 359116800);
  final pending = [result.root];
  final rows = <List<Object>>[];
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    pending.addAll(node.children);
    rows.add([
      node.path,
      node.isFolder,
      node.bytes,
      node.fileCount,
      node.folderCount,
      node.unknownSizeCount,
      node.skippedLinkCount,
      node.isComplete,
    ]);
  }
  rows.sort((a, b) => (a[0] as String).compareTo(b[0] as String));
  return sha256.convert(utf8.encode(jsonEncode(rows))).toString();
}

Future<Map<String, Object>> singleWorkerReadAll(String root) async {
  return Isolate.run(() {
    final watch = Stopwatch()..start();
    final pending = [root];
    var files = 0;
    var directories = 0;
    var bytes = 0;
    final listings = <StorageScanDirectory>[];
    while (pending.isNotEmpty) {
      final listing = readProfiledNativeDirectoryInline(pending.removeLast());
      listings.add(listing);
      for (final item in listing.entries) {
        if (item.isFolder) {
          directories++;
          pending.add(item.path!);
        } else {
          files++;
          bytes += item.size ?? 0;
        }
      }
    }
    watch.stop();
    return {
      'worker_ms': watch.elapsedMicroseconds / 1000,
      'files': files,
      'folders': directories,
      'bytes': bytes,
      'listings': listings.length,
    };
  });
}

class _InlineNativeBackend extends FileOperationBackend
    implements StorageScanDirectoryReader {
  @override
  Object get identity => 'immutable-fixture';
  @override
  bool get isCurrent => true;
  @override
  String get label => 'single-worker immutable fixture';
  @override
  p.Context get paths => p.context;
  @override
  bool get supportsSymbolicLinks => true;
  @override
  Future<FileItem?> stat(String path) async {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type == FileSystemEntityType.link) {
      return FileItem(
        name: paths.basename(path),
        path: path,
        isFolder: false,
        isSymlink: true,
      );
    }
    final info = FileStat.statSync(path);
    if (info.type != type ||
        FileSystemEntity.typeSync(path, followLinks: false) != type) {
      throw StateError('Entry changed');
    }
    return FileItem(
      name: paths.basename(path),
      path: path,
      isFolder: type == FileSystemEntityType.directory,
      isSymlink: false,
      size: type == FileSystemEntityType.file ? info.size : null,
      updatedAt: info.modified,
    );
  }

  @override
  Future<StorageScanDirectory> listForStorageScan(String path) async =>
      readProfiledNativeDirectoryInline(path);
  @override
  Future<List<FileItem>> list(String path) async =>
      (await listForStorageScan(path)).entries;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

// Research-only whole-worker bound: same scanner validation/aggregation and
// no-follow metadata reader, but fixture identity is constant and there is no
// scope/cancellation/progress bridge. This is not a production implementation.
Future<(StorageScanResult, int)> singleWorkerFullScan(String root) =>
    Isolate.run(() async {
      final watch = Stopwatch()..start();
      final result = await const StorageScanService().scan(
        _InlineNativeBackend(),
        root,
      );
      watch.stop();
      return (result, watch.elapsedTicks);
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('profile current analyzer cost components', () async {
    if (Platform.environment['SCAN_PROFILE_PREPARE_ONLY'] == '1') return;
    final records = <Map<String, Object?>>[];
    final original = storageScanBackend(
      source: LocalPanelSource(fixture),
      local: LocalFileService(),
      isCurrent: () => true,
    );
    final baseline = await const StorageScanService().scan(original, fixture);
    final expectedDigest = digest(baseline);
    final cloud = WorkflowFakeClient();
    final cloudReference = storageReferenceForClient(cloud);
    // Match the real remote-origin guard's repeated namespace hash, without
    // adding unrelated provider/Riverpod work or any real credentials.
    final cloudBackend = CloudOperationBackend(
      cloud,
      isCurrent: () => storageReferenceForClient(cloud) == cloudReference,
    );
    final modes = [
      'original',
      'native_instrumented',
      'cached',
      'cached_cheap_identity',
      'cached_cheap_path',
      'cached_cloud_guard',
      'single_worker_read_only',
      'single_worker_full_scan',
    ];
    for (final mode in modes) {
      for (var run = 0; run < 4; run++) {
        final profile = ScanProfile();
        final FileOperationBackend? input = mode == 'native_instrumented'
            ? _MeasuredNative(LocalFileService(), profile)
            : mode.startsWith('cached')
            ? _CachedBackend(
                mode == 'cached_cloud_guard' ? cloudBackend : original,
                baseline,
                cheapIdentity:
                    mode == 'cached_cheap_identity' ||
                    mode == 'cached_cheap_path',
                cheapPath: mode == 'cached_cheap_path',
              )
            : null;
        final watch = Stopwatch()..start();
        String? resultDigest;
        Map<String, Object>? worker;
        if (mode == 'single_worker_read_only') {
          worker = await singleWorkerReadAll(fixture);
          watch.stop();
          expect(worker['files'], 24000);
          expect(worker['folders'], 460);
          expect(worker['bytes'], 359116800);
        } else if (mode == 'single_worker_full_scan') {
          final (result, ticks) = await singleWorkerFullScan(fixture);
          watch.stop();
          profile.add('whole_worker_core', ticks);
          resultDigest = digest(result);
        } else if (mode == 'original') {
          final result = await const StorageScanService().scan(
            original,
            fixture,
          );
          watch.stop();
          resultDigest = digest(result);
        } else {
          final result = await ProfiledStorageScanService(profile)
              .scan(_MeasuredBackend(input!, profile), fixture);
          watch.stop();
          resultDigest = digest(result);
        }
        watch.stop();
        if (resultDigest != null) expect(resultDigest, expectedDigest);
        final record = <String, Object?>{
          'mode': mode,
          'run': run,
          'warmup': run == 0,
          'wall_ms': watch.elapsedMicroseconds / 1000,
          'profile': profile.json(),
          'worker': worker,
          'tree_digest': resultDigest,
        };
        records.add(record);
        // This benchmark emits a machine-readable record after timing stops.
        // ignore: avoid_print
        print('PROFILE ${jsonEncode(record)}');
      }
    }
    final output = File(
      Platform.environment['SCAN_PROFILE_OUTPUT'] ??
          p.join('build', 'scan-profile', 'results.json'),
    );
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(records),
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
