import '../models/file_item.dart';
import 'file_operation_service.dart';
import 'storage_transfer_contract.dart';

/// Strict wall-clock input: Dart's DateTime constructor alone normalizes invalid
/// dates such as February 31, which must not silently become another edit.
DateTime? parseFileAttributeTime(String text, {required bool utc}) {
  final value = text.trim();
  if (value.isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$')
      .firstMatch(value);
  if (match == null) throw const FormatException('Use YYYY-MM-DD HH:mm:ss.');
  final parts = [
    for (var index = 1; index <= 6; index++) int.parse(match[index]!),
  ];
  final date = utc
      ? DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
      : DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  final actual = [
    date.year,
    date.month,
    date.day,
    date.hour,
    date.minute,
    date.second,
  ];
  if (parts.indexed.any((part) => part.$2 != actual[part.$1])) {
    throw const FormatException('The timestamp is not a valid date and time.');
  }
  return date;
}

/// A captured source, independent of panel position or the currently connected
/// account. The service never resolves a missing origin from a provider label.
class FileAttributesTarget {
  const FileAttributesTarget(this.backend, this.file);
  final FileOperationBackend backend;
  final FileItem file;
}

class FileAttributesPatch {
  const FileAttributesPatch({
    this.mode,
    this.owner,
    this.group,
    this.modified,
    this.accessed,
    this.created,
    this.windowsAttributes,
    this.windowsAttributesMask = 0x27,
  });

  final int? mode;
  final String? owner;
  final String? group;
  final DateTime? modified;
  final DateTime? accessed;
  final DateTime? created;
  final int? windowsAttributes;
  final int windowsAttributesMask;

  void validate() {
    if (mode == null &&
        owner == null &&
        group == null &&
        modified == null &&
        accessed == null &&
        created == null &&
        windowsAttributes == null) {
      throw const FormatException('Choose at least one attribute to change.');
    }
    if (mode != null && (mode! < 0 || mode! > 0xfff)) {
      throw const FormatException('Permissions must be 0000 through 7777.');
    }
    if (windowsAttributes != null &&
        (windowsAttributesMask <= 0 ||
            (windowsAttributesMask & ~0x27) != 0 ||
            windowsAttributes! < 0 ||
            (windowsAttributes! & ~windowsAttributesMask) != 0)) {
      throw const FormatException(
        'Windows flags require an explicit supported mask and value.',
      );
    }
    for (final value in [owner, group]) {
      if (value != null && (value.isEmpty || value.contains('\u0000'))) {
        throw const FormatException('An owner or group cannot be empty.');
      }
    }
  }

  TransferMetadata get metadata => TransferMetadata(
    mode: mode,
    owner: owner,
    group: group,
    modified: modified,
    accessed: accessed,
    created: created,
    windowsAttributes: windowsAttributes,
    windowsAttributesMask: windowsAttributesMask,
  );

  void requireSupported(FileOperationBackend backend) {
    final c = backend.capabilities;
    if ((mode != null && !c.permissions) ||
        ((owner != null || group != null) && !c.ownership) ||
        (modified != null && !c.setModifiedTime) ||
        (accessed != null && !c.setAccessedTime) ||
        (created != null && !c.setCreatedTime) ||
        (windowsAttributes != null && !c.windowsAttributes)) {
      throw UnsupportedError(
        'This source cannot change all the requested attributes.',
      );
    }
  }

  Future<TransferMetadata> read(FileOperationBackend backend, String path) =>
      backend.readMetadataFields(
        path,
        permissions: mode != null,
        ownership: owner != null || group != null,
        modified: modified != null,
        accessed: accessed != null,
        created: created != null,
        windowsAttributes: windowsAttributes != null,
        extendedAttributes: false,
        acl: false,
      );

  bool matches(TransferMetadata expected, TransferMetadata actual) =>
      (mode == null ||
          (expected.mode != null &&
              actual.mode != null &&
              (expected.mode! & 0xfff) == (actual.mode! & 0xfff))) &&
      (owner == null || expected.owner == actual.owner) &&
      (group == null || expected.group == actual.group) &&
      (modified == null || _sameTime(expected.modified, actual.modified)) &&
      (accessed == null || _sameTime(expected.accessed, actual.accessed)) &&
      (created == null || _sameTime(expected.created, actual.created)) &&
      (windowsAttributes == null ||
          (expected.windowsAttributes != null &&
              actual.windowsAttributes != null &&
              (expected.windowsAttributes! & windowsAttributesMask) ==
                  (actual.windowsAttributes! & windowsAttributesMask)));

  // SFTP v3 and several filesystems store timestamps with second precision.
  static bool _sameTime(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.toUtc().millisecondsSinceEpoch ~/ 1000 ==
          b.toUtc().millisecondsSinceEpoch ~/ 1000;
}

enum FileAttributesOutcome {
  ready,
  skipped,
  blocked,
  changed,
  failed,
  cancelled,
}

class FileAttributesEntry {
  FileAttributesEntry({
    required this.target,
    required this.depth,
    this.before,
    this.outcome = FileAttributesOutcome.ready,
    this.message,
  });
  final FileAttributesTarget target;
  final int depth;
  final TransferMetadata? before;
  FileAttributesOutcome outcome;
  String? message;
}

class FileAttributesPlan {
  FileAttributesPlan({required this.patch, required this.entries});
  final FileAttributesPatch patch;
  final List<FileAttributesEntry> entries;
  bool started = false;
  int get ready =>
      entries.where((e) => e.outcome == FileAttributesOutcome.ready).length;
  int get changed =>
      entries.where((e) => e.outcome == FileAttributesOutcome.changed).length;
}

class FileAttributesCancelled implements Exception {
  const FileAttributesCancelled();
}

/// Preview is read-only. Execution revisits the captured account and each
/// reviewed row, then verifies the fields written. Descendants are changed
/// before their parents so a restrictive parent mode cannot block the batch.
class FileAttributesService {
  const FileAttributesService({this.maximumEntries = 100000});
  final int maximumEntries;

  Future<FileAttributesPlan> preview({
    required List<FileAttributesTarget> targets,
    required FileAttributesPatch patch,
    bool recursive = false,
    bool includeFiles = true,
    bool includeFolders = true,
    bool Function()? isCancelled,
  }) async {
    patch.validate();
    if (!includeFiles && !includeFolders) {
      throw const FormatException('Include files, folders, or both.');
    }
    final entries = <FileAttributesEntry>[];
    final seen = <(Object, String)>{};
    var visited = 0;
    void check(FileOperationBackend backend) {
      if (isCancelled?.call() == true) throw const FileAttributesCancelled();
      if (!backend.isCurrent) {
        throw StateError('The captured source is unavailable.');
      }
    }

    Future<void> visit(FileAttributesTarget target, int depth) async {
      final backend = target.backend;
      check(backend);
      final path = target.file.path;
      if (path == null || path.isEmpty) {
        entries.add(
          FileAttributesEntry(
            target: target,
            depth: depth,
            outcome: FileAttributesOutcome.blocked,
            message: 'The original path is unavailable.',
          ),
        );
        return;
      }
      if (!seen.add((backend.identity, backend.pathKey(path)))) return;
      if (++visited > maximumEntries) {
        throw StateError(
          'The attributes preview exceeds $maximumEntries items.',
        );
      }
      FileItem? current;
      try {
        current = await backend.stat(path);
        check(backend);
        if (!_sameFile(target.file, current)) {
          throw StateError(
            'The listed item changed; refresh and preview again.',
          );
        }
        if (current!.isSymlink == true) {
          entries.add(
            FileAttributesEntry(
              target: target,
              depth: depth,
              outcome: FileAttributesOutcome.skipped,
              message: 'Symbolic links are not followed or changed.',
            ),
          );
          return;
        }
      } on FileAttributesCancelled {
        rethrow;
      } catch (error) {
        entries.add(
          FileAttributesEntry(
            target: target,
            depth: depth,
            outcome: FileAttributesOutcome.blocked,
            message: '$error',
          ),
        );
        return;
      }
      final captured = FileAttributesTarget(backend, current);
      int? attributesIndex;
      if (current.isFolder ? includeFolders : includeFiles) {
        try {
          patch.requireSupported(backend);
          final before = await patch.read(backend, path);
          check(backend);
          if ((patch.mode != null && before.mode == null) ||
              (patch.owner != null && before.owner == null) ||
              (patch.group != null && before.group == null) ||
              (patch.modified != null && before.modified == null) ||
              (patch.accessed != null && before.accessed == null) ||
              (patch.created != null && before.created == null) ||
              (patch.windowsAttributes != null &&
                  before.windowsAttributes == null)) {
            throw StateError('The requested attributes could not be read.');
          }
          if (!_sameFile(current, await backend.stat(path))) {
            throw StateError('The item changed while reading its attributes.');
          }
          check(backend);
          attributesIndex = entries.length;
          entries.add(
            FileAttributesEntry(target: captured, depth: depth, before: before),
          );
        } on FileAttributesCancelled {
          rethrow;
        } catch (error) {
          entries.add(
            FileAttributesEntry(
              target: captured,
              depth: depth,
              outcome: FileAttributesOutcome.blocked,
              message: '$error',
            ),
          );
        }
      }
      if (recursive && current.isFolder) {
        try {
          final children = await backend.list(path);
          check(backend);
          for (final child in children) {
            final childPath = child.path;
            if (childPath == null ||
                !backend.isWithin(path, childPath) ||
                !backend.samePath(backend.paths.dirname(childPath), path)) {
              throw StateError(
                'The directory listing contains an invalid child path.',
              );
            }
            await visit(FileAttributesTarget(backend, child), depth + 1);
          }
          if (patch.accessed != null && attributesIndex != null) {
            // Enumeration may update the directory's own access time. Capture
            // the reviewed value after our reads rather than rejecting them
            // later as an external change.
            final before = await patch.read(backend, path);
            check(backend);
            if (before.accessed == null) {
              throw StateError('The directory access time could not be read.');
            }
            entries[attributesIndex] = FileAttributesEntry(
              target: captured,
              depth: depth,
              before: before,
            );
          }
        } on FileAttributesCancelled {
          rethrow;
        } catch (error) {
          // A partially enumerated folder cannot be silently presented as a
          // complete recursive edit. Do not apply its restrictive attributes.
          final parentRows = entries.where(
            (entry) =>
                entry.target.backend.identity == backend.identity &&
                entry.target.file.path == path,
          );
          if (parentRows.isNotEmpty) {
            parentRows.first
              ..outcome = FileAttributesOutcome.blocked
              ..message = 'Directory enumeration failed: $error';
          } else {
            entries.add(
              FileAttributesEntry(
                target: captured,
                depth: depth,
                outcome: FileAttributesOutcome.blocked,
                message: 'Directory enumeration failed: $error',
              ),
            );
          }
        }
      }
    }

    for (final target in targets) {
      await visit(target, 0);
    }
    // Sorting by physical path depth also handles overlapping selected roots
    // encountered in a different order, rather than relying on traversal order.
    entries.sort(
      (a, b) => b.target.backend.paths
          .split(b.target.file.path ?? '')
          .length
          .compareTo(
            a.target.backend.paths.split(a.target.file.path ?? '').length,
          ),
    );
    return FileAttributesPlan(
      patch: patch,
      entries: List.unmodifiable(entries),
    );
  }

  Future<void> apply(
    FileAttributesPlan plan, {
    bool stopOnError = true,
    bool Function()? isCancelled,
    void Function()? onChanged,
  }) async {
    if (plan.started) {
      throw StateError('Preview again before applying another batch.');
    }
    plan.started = true;
    var stop = false;
    final failed = [
      for (final row in plan.entries)
        if (row.outcome == FileAttributesOutcome.blocked) row.target,
    ];
    for (final row in plan.entries) {
      if (row.outcome != FileAttributesOutcome.ready) continue;
      if (stop || isCancelled?.call() == true) {
        row.outcome = FileAttributesOutcome.cancelled;
        onChanged?.call();
        continue;
      }
      final backend = row.target.backend;
      final file = row.target.file;
      try {
        if (!backend.isCurrent) {
          throw StateError('The captured source is unavailable.');
        }
        if (file.isFolder &&
            failed.any(
              (child) =>
                  child.backend.identity == backend.identity &&
                  backend.isWithin(file.path!, child.file.path!),
            )) {
          throw StateError(
            'A child failed; parent attributes are retained for retry.',
          );
        }
        if (!_sameFile(file, await backend.stat(file.path!))) {
          throw StateError(
            'The item changed since preview; no attributes were written.',
          );
        }
        final before = await plan.patch.read(backend, file.path!);
        if (!plan.patch.matches(row.before!, before)) {
          throw StateError('The reviewed attributes changed; preview again.');
        }
        if (isCancelled?.call() == true) {
          row.outcome = FileAttributesOutcome.cancelled;
          onChanged?.call();
          continue;
        }
        if (!backend.isCurrent) {
          throw StateError('The captured source is unavailable.');
        }
        await backend.writeMetadata(file.path!, plan.patch.metadata);
        if (!backend.isCurrent) {
          throw StateError('The source changed before verification.');
        }
        final after = await plan.patch.read(backend, file.path!);
        if (!plan.patch.matches(plan.patch.metadata, after)) {
          throw StateError(
            'The source did not retain all requested attributes.',
          );
        }
        row.outcome = FileAttributesOutcome.changed;
      } catch (error) {
        row
          ..outcome = FileAttributesOutcome.failed
          ..message = '$error';
        failed.add(row.target);
        stop = stopOnError;
      }
      onChanged?.call();
    }
  }

  static bool _sameFile(FileItem before, FileItem? after) =>
      after != null &&
      before.isFolder == after.isFolder &&
      (before.isSymlink == true) == (after.isSymlink == true) &&
      (before.uuid == null || before.uuid == after.uuid) &&
      (before.size == null || before.isFolder || before.size == after.size) &&
      (before.updatedAt == null ||
          before.isFolder ||
          after.updatedAt?.isAtSameMomentAs(before.updatedAt!) == true) &&
      const [
        'version',
        'versionId',
        'eTag',
        'etag',
        'rev',
        'revision',
        'cTag',
      ].every((key) => before.metadata?[key] == after.metadata?[key]);
}
