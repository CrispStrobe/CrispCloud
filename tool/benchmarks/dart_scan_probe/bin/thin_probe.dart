import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class FileRecord {
  FileRecord(this.path, this.name, this.bytes, this.modifiedMicros);
  final String path;
  final String name;
  final int bytes;
  final int modifiedMicros;
}

class DirectoryRecord {
  DirectoryRecord(this.path, this.name, this.modifiedMicros, this.parent);
  final String path;
  final String name;
  final int modifiedMicros;
  final int parent;
  final children = <Object>[];
  int bytes = 0;
  int fileCount = 0;
  int folderCount = 0;
}

class ScanResult {
  final files = <FileRecord>[];
  final buckets = <int, List<FileRecord>>{};
  final directories = <DirectoryRecord>[];
  int folderCount = 0;
  int bytes = 0;

  void add(FileRecord entry) {
    files.add(entry);
    (buckets[entry.bytes] ??= <FileRecord>[]).add(entry);
    bytes += entry.bytes;
  }
}

String _cheapName(String path) =>
    path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);

FileRecord _file(String path, FileStat info, {bool packagePaths = false}) =>
    FileRecord(
      path,
      packagePaths ? p.basename(path) : _cheapName(path),
      info.size,
      info.modified.microsecondsSinceEpoch,
    );

ScanResult recursiveSync(String root, {bool packagePaths = false}) {
  final result = ScanResult();
  for (final entity in Directory(
    root,
  ).listSync(recursive: true, followLinks: false)) {
    if (entity is Directory) {
      result.folderCount++;
    } else if (entity is File) {
      final path = packagePaths ? p.normalize(entity.path) : entity.path;
      final info = FileStat.statSync(path);
      if (info.type != FileSystemEntityType.file)
        throw StateError('Not a regular file: $path');
      result.add(_file(path, info, packagePaths: packagePaths));
    }
  }
  return result;
}

ScanResult iterativeSync(String root, {bool packagePaths = false}) {
  final result = ScanResult();
  final pending = <String>[root];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    for (final entity in Directory(directory).listSync(followLinks: false)) {
      final path = packagePaths ? p.normalize(entity.path) : entity.path;
      if (entity is Directory) {
        result.folderCount++;
        pending.add(path);
      } else if (entity is File) {
        final info = FileStat.statSync(path);
        if (info.type != FileSystemEntityType.file)
          throw StateError('Not a regular file: $path');
        result.add(_file(path, info, packagePaths: packagePaths));
      }
    }
  }
  return result;
}

Future<ScanResult> recursiveAsync(
  String root, {
  required bool asyncStat,
}) async {
  final result = ScanResult();
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    if (entity is Directory) {
      result.folderCount++;
    } else if (entity is File) {
      final info = asyncStat
          ? await FileStat.stat(entity.path)
          : FileStat.statSync(entity.path);
      if (info.type != FileSystemEntityType.file)
        throw StateError('Not a regular file: ${entity.path}');
      result.add(_file(entity.path, info));
    }
  }
  return result;
}

/// A deliberately strict portable Dart prototype, still not the production
/// scanner. Retains directory nodes and byte/file/folder aggregates, checks
/// types without following links before/after each directory, stats every
/// entry, and rechecks its no-follow type after stat. Like the current reader,
/// these separate operations cannot close every adversarial rename race.
ScanResult checkedTree(
  String root, {
  bool packagePaths = false,
  bool validatePaths = false,
}) {
  final result = ScanResult();
  final rootInfo = FileStat.statSync(root);
  if (rootInfo.type != FileSystemEntityType.directory ||
      FileSystemEntity.typeSync(root, followLinks: false) !=
          FileSystemEntityType.directory) {
    throw StateError('Root is not a no-follow directory: $root');
  }
  result.directories.add(
    DirectoryRecord(
      root,
      _cheapName(root),
      rootInfo.modified.microsecondsSinceEpoch,
      -1,
    ),
  );
  final pending = <int>[0];
  final seen = <String>{root};
  while (pending.isNotEmpty) {
    final index = pending.removeLast();
    final parent = result.directories[index];
    if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Directory changed before listing: ${parent.path}');
    }
    for (final entity in Directory(parent.path).listSync(followLinks: false)) {
      if (entity is Link) continue;
      final path = packagePaths ? p.normalize(entity.path) : entity.path;
      final name = packagePaths ? p.basename(path) : _cheapName(path);
      final expectedType = entity is Directory
          ? FileSystemEntityType.directory
          : FileSystemEntityType.file;
      final info = FileStat.statSync(path);
      if (info.type != expectedType ||
          FileSystemEntity.typeSync(path, followLinks: false) != expectedType) {
        throw StateError('Entry changed while reading metadata: $path');
      }
      if (validatePaths &&
          (name.isEmpty ||
              name == '.' ||
              name == '..' ||
              name.contains('\u0000') ||
              path.contains('\u0000') ||
              !p.isAbsolute(path) ||
              p.normalize(path) != path ||
              !p.isWithin(root, path) ||
              p.normalize(p.dirname(path)) != p.normalize(parent.path) ||
              p.basename(path) != name ||
              !seen.add(p.normalize(path)))) {
        throw StateError('Invalid or duplicate child: $path');
      }
      if (expectedType == FileSystemEntityType.directory) {
        final child = DirectoryRecord(
          path,
          name,
          info.modified.microsecondsSinceEpoch,
          index,
        );
        parent.children.add(child);
        result.directories.add(child);
        pending.add(result.directories.length - 1);
        result.folderCount++;
      } else {
        final entry = FileRecord(
          path,
          name,
          info.size,
          info.modified.microsecondsSinceEpoch,
        );
        result.add(entry);
        parent.children.add(entry);
        parent.bytes += entry.bytes;
        parent.fileCount++;
      }
    }
    if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Directory changed during listing: ${parent.path}');
    }
  }
  for (var index = result.directories.length - 1; index > 0; index--) {
    final child = result.directories[index];
    final parent = result.directories[child.parent];
    parent.bytes += child.bytes;
    parent.fileCount += child.fileCount;
    parent.folderCount += child.folderCount + 1;
  }
  return result;
}

class Variant {
  const Variant(this.name, this.description, this.run);
  final String name;
  final String description;
  final FutureOr<ScanResult> Function(String) run;
}

final variants = <Variant>[
  Variant(
    'recursive_sync_flat',
    'Directory.listSync(recursive:true, followLinks:false); FileStat.statSync per file; flat entries and size buckets; returned paths.',
    recursiveSync,
  ),
  Variant(
    'iterative_sync_flat',
    'Iterative per-directory listSync(followLinks:false); FileStat.statSync per file; flat entries and size buckets; returned paths.',
    iterativeSync,
  ),
  Variant(
    'iterative_sync_flat_path',
    'Thin iterative scan plus package:path normalize and basename for each file.',
    (root) => iterativeSync(root, packagePaths: true),
  ),
  Variant(
    'recursive_async_sync_stat_flat',
    'Directory.list(recursive:true, followLinks:false) stream; synchronous FileStat.statSync per file; flat entries and buckets.',
    (root) => recursiveAsync(root, asyncStat: false),
  ),
  Variant(
    'recursive_async_stat_flat',
    'Directory.list(recursive:true, followLinks:false) stream; await FileStat.stat per file; flat entries and buckets.',
    (root) => recursiveAsync(root, asyncStat: true),
  ),
  Variant(
    'iterative_sync_checked_tree',
    'Whole iterative sync traversal; stat files/directories; post-stat no-follow type checks; before/after directory checks; tree and size buckets; postorder totals; returned paths.',
    checkedTree,
  ),
  Variant(
    'iterative_sync_checked_tree_path',
    'Checked tree plus package:path normalize/basename for each entry.',
    (root) => checkedTree(root, packagePaths: true),
  ),
  Variant(
    'iterative_sync_checked_tree_validated',
    'Checked tree plus normalize/basename and production-like lexical containment/parent/duplicate checks.',
    (root) => checkedTree(root, packagePaths: true, validatePaths: true),
  ),
  Variant(
    'whole_isolate_checked_tree',
    'Checked tree in one Isolate.run per whole scan (including worker creation and result delivery); no per-directory spawn.',
    (root) => Isolate.run(() => checkedTree(root)),
  ),
];

String verify(ScanResult result, Map<String, dynamic> manifest) {
  final root = manifest['root'] as String;
  final prefix = '$root${Platform.pathSeparator}';
  final expected = <String, List<dynamic>>{
    for (final row in manifest['records'] as List)
      (row as List)[0] as String: row,
  };
  if (result.files.length != manifest['files'] ||
      result.bytes != manifest['logicalBytes'] ||
      result.folderCount != manifest['foldersExcludingRoot']) {
    throw StateError(
      'Count/byte mismatch: ${result.files.length}/${result.folderCount}/${result.bytes}',
    );
  }
  final seen = <String>{};
  final records = <List<Object>>[];
  for (final file in result.files) {
    if (!file.path.startsWith(prefix))
      throw StateError('Out-of-root file: ${file.path}');
    final relative = file.path
        .substring(prefix.length)
        .split(Platform.pathSeparator)
        .join('/');
    if (!seen.add(relative)) throw StateError('Duplicate file: $relative');
    final wanted = expected[relative];
    if (wanted == null ||
        wanted[1] != file.bytes ||
        wanted[2] != file.modifiedMicros ||
        file.name != relative.split('/').last) {
      throw StateError(
        'Path/size/microsecond mtime mismatch: $relative; actual ${file.bytes}/${file.modifiedMicros}, expected $wanted',
      );
    }
    records.add([relative, file.bytes, file.modifiedMicros]);
  }
  final indexed = <FileRecord>{};
  for (final bucket in result.buckets.entries) {
    for (final entry in bucket.value) {
      if (entry.bytes != bucket.key || !indexed.add(entry))
        throw StateError('Invalid size bucket');
    }
  }
  if (indexed.length != result.files.length ||
      !indexed.containsAll(result.files))
    throw StateError('Incomplete size buckets');
  if (result.directories.isNotEmpty) {
    final directories = <String, int>{
      for (final row in manifest['directories'] as List)
        (row as List)[0] as String: row[1] as int,
    };
    final totals = manifest['directoryTotals'] as Map<String, dynamic>;
    if (result.directories.length != directories.length)
      throw StateError('Directory count mismatch');
    final found = <String>{};
    for (final directory in result.directories) {
      final relative = directory.path == root
          ? ''
          : directory.path
                .substring(prefix.length)
                .split(Platform.pathSeparator)
                .join('/');
      final wanted = totals[relative] as List?;
      if (!found.add(relative) ||
          directories[relative] != directory.modifiedMicros ||
          wanted == null ||
          wanted[0] != directory.bytes ||
          wanted[1] != directory.fileCount ||
          wanted[2] != directory.folderCount) {
        throw StateError('Directory metadata or aggregate mismatch: $relative');
      }
    }
  }
  records.sort((a, b) => (a[0] as String).compareTo(b[0] as String));
  final digest = sha256.convert(utf8.encode(jsonEncode(records))).toString();
  if (digest != manifest['filesSizeMtimeDigest'])
    throw StateError('Manifest digest mismatch: $digest');
  return digest;
}

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (final arg in args) {
    if (!arg.startsWith('--') || !arg.contains('='))
      throw ArgumentError('Use --key=value arguments');
    final split = arg.indexOf('=');
    options[arg.substring(2, split)] = arg.substring(split + 1);
  }
  final manifestFile = options['manifest'];
  if (manifestFile == null)
    throw ArgumentError('--manifest=/absolute/expected.json is required');
  final manifest =
      jsonDecode(File(manifestFile).readAsStringSync()) as Map<String, dynamic>;
  final root = manifest['root'] as String;
  final runs = int.parse(options['runs'] ?? '5');
  if (runs < 1) throw ArgumentError('--runs must be positive');
  final requested = options['variants']?.split(',').toSet();
  final results = <Map<String, Object>>[];
  for (final variant in variants) {
    if (requested != null && !requested.contains(variant.name)) continue;
    final measured = <double>[];
    String? digest;
    double? warmup;
    for (var iteration = 0; iteration <= runs; iteration++) {
      final watch = Stopwatch()..start();
      final result = await variant.run(root);
      watch.stop();
      // All correctness work is outside the stopwatch, against Python truth.
      digest = verify(result, manifest);
      final ms = watch.elapsedMicroseconds / 1000;
      if (iteration == 0) {
        warmup = ms;
      } else {
        measured.add(ms);
      }
    }
    final sorted = [...measured]..sort();
    final median = sorted.length.isOdd
        ? sorted[sorted.length ~/ 2]
        : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
    results.add({
      'variant': variant.name,
      'description': variant.description,
      'warmupMilliseconds': warmup!,
      'milliseconds': measured,
      'medianMilliseconds': median,
      'minimumMilliseconds': sorted.first,
      'maximumMilliseconds': sorted.last,
      'filesPerSecond': (manifest['files'] as int) / median * 1000,
      'validated': true,
      'filesSizeMtimeDigest': digest!,
    });
    stderr.writeln(
      '${variant.name}: ${median.toStringAsFixed(3)} ms, verified',
    );
  }
  final output = {
    'prototype': true,
    'runtimeMode': options['mode'] ?? 'unspecified',
    'runtime': Platform.version,
    'os': Platform.operatingSystemVersion,
    'cpusReported': Platform.numberOfProcessors,
    'root': root,
    'files': manifest['files'],
    'foldersExcludingRoot': manifest['foldersExcludingRoot'],
    'logicalBytes': manifest['logicalBytes'],
    'filesSizeMtimeDigest': manifest['filesSizeMtimeDigest'],
    'mtimeUnit': manifest['mtimeUnit'],
    'protocol':
        'One unmeasured warmup and $runs measured scans per variant. Process/runtime startup, compilation, independent manifest read, full path/size/microsecond-mtime and tree verification, and digest hashing excluded. No content reads. Warm synthetic filesystem fixture. No production edits. No security-scope, source-identity, cancellation/progress, limits or issue retention implemented in prototypes.',
    'results': results,
  };
  final json = '${const JsonEncoder.withIndent('  ').convert(output)}\n';
  if (options['output'] case final String path)
    File(path).writeAsStringSync(json);
  stdout.write(json);
}
