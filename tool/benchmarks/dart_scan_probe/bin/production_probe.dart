import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../../lib/models/file_item.dart';
import '../../../../lib/models/storage_reference.dart';
import '../../../../lib/services/storage_scan_native_io.dart';
import '../../../../lib/services/storage_scan_service.dart';

/// The filesystem adapter is intentionally small; traversal, limits, progress,
/// cancellation, path checks, immutable nodes and worker code are imported from
/// production. This does not pretend to benchmark Flutter/plugin access scopes.
abstract class NativeProbeSource implements StorageScanSource {
  bool current = true;
  String installationKey = 'installation:00000000-0000-4000-8000-000000000000';
  int statCalls = 0;
  int listingCalls = 0;
  int workerStarts = 0;
  int workerCloses = 0;

  @override
  Object get identity => StorageReference(
    kind: 'local',
    provider: Platform.operatingSystem,
    accountKey: installationKey,
  ).id;

  @override
  bool get isCurrent => current;
  @override
  bool get supportsSymbolicLinks => true;
  @override
  p.Context get paths => p.context;
  @override
  String pathKey(String path) => paths.normalize(path);
  @override
  bool samePath(String first, String second) =>
      pathKey(first) == pathKey(second);
  @override
  bool isWithin(String parent, String child) =>
      paths.isWithin(pathKey(parent), pathKey(child));

  void check() {
    if (!isCurrent) throw StateError('The selected local folder changed.');
  }

  Future<T> withAccess<T>(String path, Future<T> Function() action) async =>
      action();

  bool _missing(FileSystemException error) =>
      error.osError?.errorCode == 2 ||
      (Platform.isWindows && error.osError?.errorCode == 3);

  Future<bool> _confirmMissing(String path) async {
    try {
      await File(path).resolveSymbolicLinks();
    } on FileSystemException catch (error) {
      if (_missing(error)) return true;
      rethrow;
    }
    return false;
  }

  Future<FileItem?> _nativeItemOrNull(String path) async {
    var type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      if (await _confirmMissing(path)) return null;
      type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound)
        throw FileSystemException('Cannot inspect the requested item.', path);
    }
    if (type == FileSystemEntityType.link) {
      return FileItem(
        name: paths.basename(path),
        path: path,
        isFolder: false,
        isSymlink: true,
        symlinkTarget: await Link(path).target(),
      );
    }
    final info = await FileStat.stat(path);
    if (info.type == FileSystemEntityType.notFound) {
      if (await _confirmMissing(path)) return null;
      throw FileSystemException(
        'Cannot read the requested item metadata.',
        path,
      );
    }
    if (info.type != type ||
        await FileSystemEntity.type(path, followLinks: false) != type) {
      throw FileSystemException(
        'Item changed while it was being inspected.',
        path,
      );
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
  Future<FileItem?> stat(String path) async {
    statCalls++;
    check();
    path = paths.normalize(path);
    final parent = paths.dirname(path);
    // Mirror the normal existing-parent local stat path, including both parent
    // checks. Plugin/security-scope behavior is measured by the separate real
    // Flutter-backend benchmark; this harness only reads the supplied fixture.
    if (parent != path &&
        await FileSystemEntity.type(parent, followLinks: false) ==
            FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Benchmark fixture parent is unavailable.',
        parent,
      );
    }
    return withAccess(path, () async {
      check();
      if (parent != path) {
        final type = await FileSystemEntity.type(parent, followLinks: false);
        if (type == FileSystemEntityType.link ||
            (type != FileSystemEntityType.directory &&
                type != FileSystemEntityType.notFound)) {
          throw FileSystemException(
            'The parent is not a regular directory.',
            parent,
          );
        }
      }
      final item = await _nativeItemOrNull(path);
      check();
      return item;
    });
  }
}

class PerDirectorySource extends NativeProbeSource
    implements StorageScanDirectoryReader, StorageScanDirectoryGuard {
  @override
  bool get verifiesStorageScanDirectoryType => true;

  @override
  Future<List<FileItem>> list(String path) async =>
      (await listForStorageScan(path)).entries;

  @override
  Future<StorageScanDirectory> listForStorageScan(String path) async {
    listingCalls++;
    check();
    final result = await withAccess(path, () async {
      check();
      final listing = await readNativeStorageScanDirectory(path);
      check();
      return listing;
    });
    check();
    return result;
  }
}

class PersistentSource extends PerDirectorySource
    implements StorageScanSessionFactory {
  @override
  Future<StorageScanSession?> openStorageScanSession() async {
    check();
    workerStarts++;
    final worker = await NativeStorageScanWorker.start();
    if (!isCurrent) {
      await worker.close();
      throw StateError('The selected local folder changed.');
    }
    return _Session(this, worker);
  }
}

class _Session implements StorageScanSession, StorageScanDirectoryGuard {
  _Session(this.source, this.worker);
  final NativeProbeSource source;
  final NativeStorageScanWorker worker;
  @override
  bool get verifiesStorageScanDirectoryType => true;

  @override
  Future<StorageScanDirectory> listForStorageScan(String path) async {
    source.listingCalls++;
    source.check();
    final result = await source.withAccess(path, () async {
      source.check();
      final listing = await worker.readDirectory(path);
      source.check();
      return listing;
    });
    source.check();
    return result;
  }

  @override
  Future<void> close() async {
    await worker.close();
    source.workerCloses++;
  }
}

class Oracle {
  Oracle(this.data)
    : files = {
        for (final row in data['records'] as List)
          (row as List)[0] as String: row,
      },
      directories = {
        for (final row in data['directories'] as List)
          (row as List)[0] as String: row[1] as int,
      };
  final Map<String, dynamic> data;
  final Map<String, List<dynamic>> files;
  final Map<String, int> directories;
  String get root => data['root'] as String;

  String verify(StorageScanResult result) {
    if (!result.isComplete ||
        result.issues.isNotEmpty ||
        result.suppressedIssueCount != 0 ||
        result.root.fileCount != data['files'] ||
        result.root.folderCount != data['foldersExcludingRoot'] ||
        result.root.bytes != data['logicalBytes']) {
      throw StateError(
        'Incomplete or incorrect production result: ${result.root.fileCount}/${result.root.folderCount}/${result.root.bytes}; ${result.issues.map((i) => '${i.code}:${i.path}:${i.message}').join('; ')}',
      );
    }
    final prefix = '$root${Platform.pathSeparator}';
    final seenFiles = <String>{};
    final seenDirectories = <String>{};
    final records = <List<Object>>[];
    final pending = <StorageNode>[result.root];
    final totals = data['directoryTotals'] as Map<String, dynamic>;
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (!node.isComplete ||
          node.unknownSizeCount != 0 ||
          node.skippedLinkCount != 0 ||
          node.item.isSymlink == true)
        throw StateError('Unexpected partial/link node: ${node.path}');
      if (node.path != root && !node.path.startsWith(prefix))
        throw StateError('Out-of-root node: ${node.path}');
      final relative = node.path == root
          ? ''
          : node.path
                .substring(prefix.length)
                .split(Platform.pathSeparator)
                .join('/');
      if (node.isFolder) {
        final wanted = totals[relative] as List?;
        if (!seenDirectories.add(relative) ||
            directories[relative] !=
                node.item.updatedAt?.microsecondsSinceEpoch ||
            wanted == null ||
            wanted[0] != node.bytes ||
            wanted[1] != node.fileCount ||
            wanted[2] != node.folderCount) {
          throw StateError(
            'Directory path/mtime/aggregate mismatch: $relative',
          );
        }
        pending.addAll(node.children);
        for (var index = 1; index < node.children.length; index++) {
          final before = node.children[index - 1];
          final after = node.children[index];
          if (before.bytes < after.bytes ||
              (before.bytes == after.bytes &&
                  before.path.compareTo(after.path) > 0))
            throw StateError('Incorrect sorted children: $relative');
        }
      } else {
        final wanted = files[relative];
        final modified = node.item.updatedAt?.microsecondsSinceEpoch;
        if (!seenFiles.add(relative) ||
            wanted == null ||
            wanted[1] != node.bytes ||
            node.item.size != node.bytes ||
            wanted[2] != modified ||
            node.name != relative.split('/').last ||
            node.fileCount != 1 ||
            node.folderCount != 0 ||
            node.children.isNotEmpty) {
          throw StateError('File path/size/mtime mismatch: $relative');
        }
        records.add([relative, node.bytes, modified!]);
      }
    }
    if (seenFiles.length != files.length ||
        seenDirectories.length != directories.length)
      throw StateError('Missing file or directory nodes');
    records.sort((a, b) => (a[0] as String).compareTo(b[0] as String));
    final digest = sha256.convert(utf8.encode(jsonEncode(records))).toString();
    if (digest != data['filesSizeMtimeDigest'])
      throw StateError('Oracle digest mismatch: $digest');
    return digest;
  }
}

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--') || !arg.contains('='))
      throw ArgumentError('Use --key=value arguments');
    final split = arg.indexOf('=');
    options[arg.substring(2, split)] = arg.substring(split + 1);
  }
  if (options['oracle'] == null)
    throw ArgumentError('--oracle=/absolute/expected.json is required');
  final oracle = Oracle(
    jsonDecode(File(options['oracle']!).readAsStringSync())
        as Map<String, dynamic>,
  );
  final runs = int.parse(options['runs'] ?? '5');
  if (runs < 1) throw ArgumentError('--runs must be positive');
  final requested = options['variants']?.split(',').toSet();
  final variants = <String, NativeProbeSource Function()>{
    'production_per_directory_guarded': PerDirectorySource.new,
    'production_persistent_guarded': PersistentSource.new,
  };
  final output = <Map<String, Object>>[];
  for (final entry in variants.entries) {
    if (requested != null && !requested.contains(entry.key)) continue;
    final timings = <double>[];
    final progressCounts = <int>[];
    double? warmup;
    String? digest;
    Map<String, int>? sourceCounts;
    for (var iteration = 0; iteration <= runs; iteration++) {
      final source = entry.value();
      var progressCount = 0;
      StorageScanProgress? finalProgress;
      final cancelled = <bool>[false];
      final watch = Stopwatch()..start();
      final result = await const StorageScanService().scan(
        source,
        oracle.root,
        isCancelled: () => cancelled.single,
        onProgress: (progress) {
          progressCount++;
          finalProgress = progress;
        },
      );
      watch.stop();
      digest = oracle.verify(result);
      if (source.statCalls != 1 ||
          source.listingCalls != oracle.directories.length ||
          source.workerStarts != source.workerCloses ||
          progressCount < 2 ||
          finalProgress?.files != oracle.files.length ||
          finalProgress?.folders != oracle.directories.length - 1 ||
          finalProgress?.bytes != oracle.data['logicalBytes']) {
        throw StateError(
          'Source lifecycle/progress mismatch: ${source.statCalls}/${source.listingCalls}/${source.workerStarts}/${source.workerCloses}/$progressCount',
        );
      }
      sourceCounts = {
        'statCalls': source.statCalls,
        'listingCalls': source.listingCalls,
        'sessionWorkersStarted': source.workerStarts,
        'sessionWorkersClosed': source.workerCloses,
      };
      final ms = watch.elapsedMicroseconds / 1000;
      if (iteration == 0) {
        warmup = ms;
      } else {
        timings.add(ms);
        progressCounts.add(progressCount);
      }
    }
    final sorted = [...timings]..sort();
    final median = sorted.length.isOdd
        ? sorted[sorted.length ~/ 2]
        : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
    output.add({
      'variant': entry.key,
      'warmupMilliseconds': warmup!,
      'milliseconds': timings,
      'medianMilliseconds': median,
      'minimumMilliseconds': sorted.first,
      'maximumMilliseconds': sorted.last,
      'filesPerSecond': oracle.files.length / median * 1000,
      'filesSizeMtimeDigest': digest!,
      'validated': true,
      'sourceCallsPerScan': sourceCounts!,
      'progressCallbacks': progressCounts,
    });
    stderr.writeln(
      '${entry.key}: ${median.toStringAsFixed(3)} ms, full tree verified',
    );
  }
  final report = <String, Object?>{
    'benchmark': 'actual_production_storage_scan_service',
    'runtimeMode': options['mode'] ?? 'unspecified',
    'runtime': Platform.version,
    'os': Platform.operatingSystemVersion,
    'root': oracle.root,
    'files': oracle.data['files'],
    'foldersExcludingRoot': oracle.data['foldersExcludingRoot'],
    'logicalBytes': oracle.data['logicalBytes'],
    'filesSizeMtimeDigest': oracle.data['filesSizeMtimeDigest'],
    'protocol':
        'One unmeasured warmup and $runs measured scans per variant. Exact repository scanner/native helper/models. Default scanner limits, yielding, path checks, immutable sorted aggregation, progress/cancel callbacks and awaited worker cleanup retained. Watch includes worker creation and shutdown. Independent full file path/size/microsecond-mtime plus all folder metadata/aggregate verification outside watch. Source adapter mirrors local identity/path semantics and normal stat checks; platform access-scope/plugin work is omitted and belongs to the separate genuine Flutter-backend benchmark.',
    if (options['build-metadata'] case final String path)
      'build': jsonDecode(File(path).readAsStringSync()),
    'results': output,
  };
  final json = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
  if (options['output'] case final String path)
    File(path).writeAsStringSync(json);
  stdout.write(json);
}
