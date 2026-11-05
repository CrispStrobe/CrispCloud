import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import 'file_selection_pattern.dart';

enum FileOperationKind { copy, move }

enum FileConflictPolicy { ask, skip, replace, replaceIfNewer, keepBoth }

enum DirectoryConflictPolicy { ask, merge, skip }

enum FileOperationOutcome {
  pending,
  copied,
  moved,
  directoryCreated,
  skipped,
  filtered,
  cancelled,
  failed,
}

/// Options are immutable so changing the dialog cannot change a running job.
class FileOperationOptions {
  const FileOperationOptions({
    this.kind = FileOperationKind.copy,
    this.fileConflict = FileConflictPolicy.ask,
    this.directoryConflict = DirectoryConflictPolicy.merge,
    this.recursive = true,
    this.preserveRelativePaths = false,
    this.relativeBase,
    this.preserveModified = false,
    this.verifyContents = false,
    this.stopOnError = true,
    this.copySymbolicLinks = false,
    this.pattern,
  });

  final FileOperationKind kind;
  final FileConflictPolicy fileConflict;
  final DirectoryConflictPolicy directoryConflict;
  final bool recursive;
  final bool preserveRelativePaths;
  final String? relativeBase;
  final bool preserveModified;
  final bool verifyContents;
  final bool stopOnError;
  final bool copySymbolicLinks;
  final FileSelectionPattern? pattern;
}

/// Storage adapter whose identity and authentication are captured before work.
/// [stat] and [list] must propagate access/network errors, never report them as
/// missing files. writeFile must not delete an existing destination on failure.
abstract class FileOperationBackend {
  Object get identity;
  String get label;
  p.Context get paths;
  String pathKey(String path) => paths.normalize(path);
  bool samePath(String first, String second) => pathKey(first) == pathKey(second);
  bool isWithin(String parent, String child) =>
      paths.isWithin(pathKey(parent), pathKey(child));
  bool get isCurrent;
  bool get supportsModifiedTime => false;
  bool get supportsSymbolicLinks => false;
  Future<FileItem?> stat(String path);
  Future<List<FileItem>> list(String path);
  Future<void> createDirectory(String path);
  Stream<List<int>> readFile(FileItem file);
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  });
  Future<void> deleteFile(FileItem file);
  Future<void> deleteEmptyDirectory(String path);
  Future<void> setModified(String path, DateTime modified) async =>
      throw UnsupportedError(
        'This storage cannot preserve modification times.',
      );
  Future<void> copySymbolicLink(
    FileItem source,
    String destination, {
    required bool replace,
  }) async =>
      throw UnsupportedError('This storage cannot create symbolic links.');
}

class FileOperationEntry {
  FileOperationEntry(this.source, this.destination, {this.existing});
  final FileItem source;
  String destination;
  FileItem? existing;
  FileOperationOutcome outcome = FileOperationOutcome.pending;
  String? message;
  bool get failed => outcome == FileOperationOutcome.failed;
  bool get completed =>
      outcome == FileOperationOutcome.copied ||
      outcome == FileOperationOutcome.moved ||
      outcome == FileOperationOutcome.directoryCreated;
}

class FileOperationPlan {
  FileOperationPlan({
    required this.source,
    required this.destination,
    required this.targetDirectory,
    required this.options,
    required this.entries,
    required this.errors,
  });
  final FileOperationBackend source;
  final FileOperationBackend destination;
  final String targetDirectory;
  final FileOperationOptions options;
  final List<FileOperationEntry> entries;
  final List<String> errors;
  bool get canExecute =>
      errors.isEmpty &&
      entries.any((entry) => entry.outcome == FileOperationOutcome.pending);
  int get fileCount => entries
      .where(
        (entry) =>
            !entry.source.isFolder &&
            entry.outcome == FileOperationOutcome.pending,
      )
      .length;
  int get totalBytes => entries
      .where(
        (entry) =>
            !entry.source.isFolder &&
            entry.outcome == FileOperationOutcome.pending,
      )
      .fold(0, (sum, entry) => sum + (entry.source.size ?? 0));
}

class FileOperationControl {
  bool _cancelled = false;
  Completer<void>? _paused;
  bool get isCancelled => _cancelled;
  bool get isPaused => _paused != null;
  void cancel() {
    _cancelled = true;
    resume();
  }

  void pause() {
    if (!_cancelled) _paused ??= Completer<void>();
  }

  void resume() {
    final pause = _paused;
    _paused = null;
    pause?.complete();
  }

  Future<void> checkpoint() async {
    if (_cancelled) throw const FileOperationCancelled();
    await _paused?.future;
    if (_cancelled) throw const FileOperationCancelled();
  }
}

class FileOperationCancelled implements Exception {
  const FileOperationCancelled();
  @override
  String toString() => 'Cancelled';
}

/// Decisions returned by the conflict UI. Cancel stops the entire job.
enum FileConflictDecision { skip, replace, keepBoth, merge, cancel }

typedef FileConflictResolver = Future<FileConflictDecision> Function(
  FileOperationEntry entry,
  FileItem existing,
);

/// Previews all paths, then executes in order. Directory moves are file-by-file:
/// only empty source directories are removed, so filters/skips never lose data.
class FileOperationService {
  const FileOperationService();

  void _checkSources(FileOperationBackend source, FileOperationBackend target) {
    if (!source.isCurrent || !target.isCurrent) {
      throw StateError('The storage account changed. Reopen the operation.');
    }
  }

  Future<FileOperationPlan> prepare({
    required List<FileItem> files,
    required FileOperationBackend source,
    required FileOperationBackend destination,
    required String targetDirectory,
    FileOperationOptions options = const FileOperationOptions(),
    FileOperationControl? control,
  }) async {
    final entries = <FileOperationEntry>[];
    final errors = <String>[];
    final target = destination.paths.normalize(targetDirectory.trim());
    final plan = FileOperationPlan(
      source: source,
      destination: destination,
      targetDirectory: target,
      options: options,
      entries: entries,
      errors: errors,
    );
    _checkSources(source, destination);
    if (targetDirectory.trim().isEmpty ||
        !destination.paths.isAbsolute(target)) {
      errors.add('Choose an absolute destination directory.');
      return plan;
    }
    if (options.preserveModified && !destination.supportsModifiedTime) {
      errors.add('The destination cannot preserve modification times.');
    }
    if (options.copySymbolicLinks &&
        (!source.supportsSymbolicLinks || !destination.supportsSymbolicLinks)) {
      errors.add('Copying symbolic links requires two local filesystems.');
    }
    final base = options.relativeBase;
    if (options.preserveRelativePaths &&
        (base == null || !source.paths.isAbsolute(base))) {
      errors.add('Choose an absolute source base for relative paths.');
      return plan;
    }
    final roots = <String, FileItem>{};
    for (final file in files) {
      if (file.name == '..') continue;
      final path = file.path;
      if (path == null || !source.paths.isAbsolute(path)) {
        errors.add('No absolute source path for ${file.name}.');
        continue;
      }
      roots.putIfAbsent(source.paths.normalize(path), () => file);
    }
    // Selecting a folder and a child must process the child only once.
    final unique = roots.entries
        .where(
          (candidate) => !roots.entries.any(
            (parent) =>
                options.recursive &&
                parent.value.isFolder &&
                parent.value.isSymlink != true &&
                parent.key != candidate.key &&
                source.isWithin(parent.key, candidate.key),
          ),
        )
        .toList();
    final destinations = <String, FileOperationEntry>{};
    final visited = <String>{};

    Future<void> walk(FileItem listed, String output) async {
      await control?.checkpoint();
      _checkSources(source, destination);
      final path = source.paths.normalize(listed.path!);
      if (!visited.add(source.pathKey(path))) return;
      final current = await source.stat(path);
      _checkSources(source, destination);
      if (current == null) {
        errors.add('Source no longer exists: $path');
        return;
      }
      final file = current.copyWith(path: path);
      if (identical(source.identity, destination.identity) &&
          source.samePath(path, output) &&
          !file.isFolder &&
          options.kind == FileOperationKind.copy &&
          options.fileConflict == FileConflictPolicy.keepBoth) {
        output = await _availableName(output, destination,
            reserved: destinations.keys.toSet());
      }
      if (identical(source.identity, destination.identity) &&
          (source.samePath(path, output) ||
              (file.isFolder && source.isWithin(path, output)))) {
        errors.add('Cannot copy or move an item into itself: $path');
        return;
      }
      final entry = FileOperationEntry(file, output);
      entries.add(entry);
      if (file.isSymlink == true && !options.copySymbolicLinks) {
        entry.outcome = FileOperationOutcome.skipped;
        entry.message = 'Symbolic link skipped (links are never followed).';
        return;
      }
      if (file.isFolder && !options.recursive) {
        entry.outcome = FileOperationOutcome.skipped;
        entry.message = 'Folder skipped: recursion is off.';
        return;
      }
      if (!file.isFolder && !(options.pattern?.matches(file) ?? true)) {
        entry.outcome = FileOperationOutcome.filtered;
        entry.message = 'Excluded by the file filter.';
        return;
      }
      final previous = destinations[destination.pathKey(output)];
      if (previous != null && !(previous.source.isFolder && file.isFolder)) {
        if (options.fileConflict == FileConflictPolicy.keepBoth &&
            !file.isFolder) {
          output = await _availableName(
            output,
            destination,
            reserved: destinations.keys.toSet(),
          );
          entry.destination = output;
        } else {
          errors.add(
            'Several source items target $output. Use Keep both or preserve relative paths.',
          );
        }
      }
      destinations[destination.pathKey(output)] = entry;
      entry.existing = await destination.stat(output);
      _checkSources(source, destination);
      if (entry.existing != null &&
          (entry.existing!.isFolder != file.isFolder ||
              entry.existing!.isSymlink == true)) {
        errors.add(
          'Destination has an incompatible type or is a symbolic link: $output',
        );
      }
      if (file.isFolder && file.isSymlink != true) {
        final children = await source.list(path);
        children.sort((a, b) => a.name.compareTo(b.name));
        for (final child in children) {
          if (child.path == null ||
              child.name == '.' ||
              child.name == '..' ||
              source.paths.dirname(source.paths.normalize(child.path!)) !=
                  path ||
              source.paths.basename(child.path!) != child.name ||
              child.name.contains('/') ||
              child.name.contains('\\')) {
            errors.add(
              'Invalid child path returned by ${source.label}: ${child.path}',
            );
            continue;
          }
          await walk(child, destination.paths.join(output, child.name));
        }
      }
    }

    for (final root in unique) {
      String relative = source.paths.basename(root.key);
      if (options.preserveRelativePaths) {
        if (!source.isWithin(base!, root.key)) {
          errors.add('Source is outside the relative base: ${root.key}');
          continue;
        }
        relative = source.paths.relative(root.key, from: base);
      }
      final components = source.paths.split(relative);
      final output = destination.paths.joinAll([target, ...components]);
      if (!destination.isWithin(target, output)) {
        errors.add('Destination would escape the selected directory: $output');
        continue;
      }
      await walk(root.value.copyWith(path: root.key), output);
    }
    // Check destination ancestors, including links, before any writes.
    final checked = <String>{};
    for (final entry in entries.where(
      (entry) => entry.outcome == FileOperationOutcome.pending,
    )) {
      var parent = destination.paths.dirname(entry.destination);
      while (checked.add(parent)) {
        final existing = await destination.stat(parent);
        if (existing != null &&
            (!existing.isFolder || existing.isSymlink == true)) {
          errors.add('Destination parent is not a regular directory: $parent');
          break;
        }
        final next = destination.paths.dirname(parent);
        if (next == parent) break;
        parent = next;
      }
    }
    _checkSources(source, destination);
    return plan;
  }

  Future<void> execute(
    FileOperationPlan plan, {
    required FileOperationControl control,
    FileConflictResolver? resolveConflict,
    void Function(FileOperationEntry entry, int transferred, int? total)?
    onProgress,
    void Function(FileOperationEntry entry)? onEntryComplete,
  }) async {
    if (!plan.canExecute) throw StateError(plan.errors.join('\n'));
    final source = plan.source;
    final target = plan.destination;
    final options = plan.options;
    final skippedDirectories = <String>[];
    final reserved = plan.entries.map((entry) => target.pathKey(entry.destination)).toSet();
    var stopped = false;
    for (final entry in plan.entries) {
      if (entry.outcome != FileOperationOutcome.pending) continue;
      if (stopped || control.isCancelled) {
        entry.outcome = FileOperationOutcome.cancelled;
        entry.message = stopped
            ? 'Not started after an earlier error.'
            : 'Cancelled before starting.';
        onEntryComplete?.call(entry);
        continue;
      }
      if (skippedDirectories.any(
        (path) => target.isWithin(path, entry.destination),
      )) {
        entry.outcome = FileOperationOutcome.skipped;
        entry.message = 'Parent directory was skipped.';
        onEntryComplete?.call(entry);
        continue;
      }
      try {
        await control.checkpoint();
        _checkSources(source, target);
        final currentSource = await source.stat(entry.source.path!);
        if (currentSource == null ||
            !_sameVersion(entry.source, currentSource)) {
          throw StateError(
            'Source changed after preview: ${entry.source.path}',
          );
        }
        var existing = await target.stat(entry.destination);
        _checkSources(source, target);
        var replace = false;
        if (existing != null) {
          if (existing.isFolder != entry.source.isFolder ||
              existing.isSymlink == true) {
            throw StateError(
              'Destination has an incompatible type or is a symbolic link.',
            );
          }
          final decision = await _decision(
            entry,
            existing,
            options,
            resolveConflict,
          );
          await control.checkpoint();
          _checkSources(source, target);
          if (decision == FileConflictDecision.cancel) {
            control.cancel();
            throw const FileOperationCancelled();
          }
          if (decision == FileConflictDecision.skip) {
            entry.outcome = FileOperationOutcome.skipped;
            entry.message = 'Destination exists; skipped.';
            if (entry.source.isFolder)
              skippedDirectories.add(entry.destination);
            onEntryComplete?.call(entry);
            continue;
          }
          if (decision == FileConflictDecision.keepBoth) {
            entry.destination = await _availableName(
              entry.destination,
              target,
              reserved: reserved,
            );
            reserved.add(target.pathKey(entry.destination));
            existing = null;
          } else if (!entry.source.isFolder) {
            replace = true;
          }
        }
        await control.checkpoint();
        _checkSources(source, target);
        await _ensureDirectory(target, target.paths.dirname(entry.destination));
        if (entry.source.isFolder && entry.source.isSymlink != true) {
          await _ensureDirectory(target, entry.destination);
          entry.outcome = FileOperationOutcome.directoryCreated;
          entry.message = existing == null
              ? 'Directory created.'
              : 'Merged into existing directory.';
        } else {
          if (entry.source.isSymlink == true) {
            await target.copySymbolicLink(
              entry.source,
              entry.destination,
              replace: replace,
            );
          } else {
            var sent = 0;
            final stream = source.readFile(entry.source).asyncMap((
              chunk,
            ) async {
              await control.checkpoint();
              _checkSources(source, target);
              sent += chunk.length;
              onProgress?.call(entry, sent, entry.source.size);
              return chunk;
            });
            await target.writeFile(
              entry.destination,
              stream,
              entry.source.size,
              replace: replace,
            );
            if (entry.source.size != null && sent != entry.source.size) {
              throw StateError(
                'Source length changed while copying; source retained.',
              );
            }
            await control.checkpoint();
            _checkSources(source, target);
            final written = await target.stat(entry.destination);
            if (written == null ||
                written.isFolder ||
                (written.size != null && written.size != sent)) {
              throw StateError(
                'Destination could not be verified; source retained.',
              );
            }
            if (options.verifyContents) {
              final before = await _digest(
                source,
                entry.source,
                control,
                target,
              );
              final after = await _digest(target, written, control, source);
              if (before != after)
                throw StateError(
                  'SHA-256 verification failed; source retained.',
                );
            }
            if (options.preserveModified && entry.source.updatedAt != null) {
              await target.setModified(
                entry.destination,
                entry.source.updatedAt!,
              );
            }
          }
          if (options.kind == FileOperationKind.move) {
            await control.checkpoint();
            _checkSources(source, target);
            final latest = await source.stat(entry.source.path!);
            if (latest == null || !_sameVersion(entry.source, latest)) {
              throw StateError('Source changed during copy; source retained.');
            }
            await source.deleteFile(entry.source);
            entry.outcome = FileOperationOutcome.moved;
          } else {
            entry.outcome = FileOperationOutcome.copied;
          }
        }
      } on FileOperationCancelled {
        entry.outcome = FileOperationOutcome.cancelled;
        entry.message = 'Cancelled; source retained.';
      } catch (error) {
        entry.outcome = FileOperationOutcome.failed;
        entry.message = error.toString();
        stopped = options.stopOnError;
      }
      onEntryComplete?.call(entry);
    }
    if (options.kind == FileOperationKind.move && !control.isCancelled) {
      for (final entry in plan.entries.reversed.where(
        (entry) =>
            entry.source.isFolder &&
            entry.outcome == FileOperationOutcome.directoryCreated,
      )) {
        try {
          await control.checkpoint();
          _checkSources(source, target);
          // No recursive deletion: excluded/skipped/new files keep their parent.
          if ((await source.list(entry.source.path!)).isEmpty) {
            await source.deleteEmptyDirectory(entry.source.path!);
            entry.outcome = FileOperationOutcome.moved;
            entry.message = 'Empty source directory removed.';
          } else {
            entry.message =
                'Source directory retained because it still contains items.';
          }
        } catch (error) {
          entry.message = 'Source directory retained: $error';
        }
        onEntryComplete?.call(entry);
      }
    }
  }

  bool _sameVersion(FileItem before, FileItem after) =>
      before.isFolder == after.isFolder &&
      before.isSymlink == after.isSymlink &&
      before.symlinkTarget == after.symlinkTarget &&
      (before.uuid == null || before.uuid == after.uuid) &&
      (before.isFolder ||
          ((before.size == null || before.size == after.size) &&
              (before.updatedAt == null ||
                  before.updatedAt == after.updatedAt)));

  Future<String> _digest(
    FileOperationBackend backend,
    FileItem file,
    FileOperationControl control,
    FileOperationBackend other,
  ) async {
    final hash = await sha256
        .bind(
          backend.readFile(file).asyncMap((chunk) async {
            await control.checkpoint();
            _checkSources(backend, other);
            return chunk;
          }),
        )
        .first;
    return hash.toString();
  }

  Future<FileConflictDecision> _decision(
    FileOperationEntry entry,
    FileItem existing,
    FileOperationOptions options,
    FileConflictResolver? resolver,
  ) async {
    if (entry.source.isFolder) {
      switch (options.directoryConflict) {
        case DirectoryConflictPolicy.merge:
          return FileConflictDecision.merge;
        case DirectoryConflictPolicy.skip:
          return FileConflictDecision.skip;
        case DirectoryConflictPolicy.ask:
          return resolver == null
              ? FileConflictDecision.skip
              : await resolver(entry, existing);
      }
    }
    switch (options.fileConflict) {
      case FileConflictPolicy.skip:
        return FileConflictDecision.skip;
      case FileConflictPolicy.replace:
        return FileConflictDecision.replace;
      case FileConflictPolicy.keepBoth:
        return FileConflictDecision.keepBoth;
      case FileConflictPolicy.replaceIfNewer:
        // Unknown timestamps never authorize an overwrite.
        return entry.source.updatedAt != null &&
                existing.updatedAt != null &&
                entry.source.updatedAt!.isAfter(existing.updatedAt!)
            ? FileConflictDecision.replace
            : FileConflictDecision.skip;
      case FileConflictPolicy.ask:
        return resolver == null
            ? FileConflictDecision.skip
            : await resolver(entry, existing);
    }
  }

  Future<String> _availableName(
    String original,
    FileOperationBackend backend, {
    Set<String> reserved = const {},
  }) async {
    final name = backend.paths.basename(original);
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    for (var index = 1; index < 100000; index++) {
      final candidate = backend.paths.join(
        backend.paths.dirname(original),
        '$stem ($index)$extension',
      );
      if (!reserved.contains(backend.pathKey(candidate)) &&
          await backend.stat(candidate) == null)
        return candidate;
    }
    throw StateError('Cannot find a free filename for $original');
  }

  Future<void> _ensureDirectory(
    FileOperationBackend backend,
    String path,
  ) async {
    if (!backend.isCurrent) throw StateError('The storage account changed.');
    final existing = await backend.stat(path);
    if (existing != null) {
      if (!existing.isFolder || existing.isSymlink == true) {
        throw StateError(
          'Destination parent is not a regular directory: $path',
        );
      }
      return;
    }
    final parent = backend.paths.dirname(path);
    if (parent == path)
      throw StateError('Destination root is unavailable: $path');
    await _ensureDirectory(backend, parent);
    if (!backend.isCurrent) throw StateError('The storage account changed.');
    await backend.createDirectory(path);
  }
}
