import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../models/archive_endpoint.dart';
import '../models/file_item.dart';
import 'archive_directory_snapshot.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';
import 'archive_workspace.dart';
import 'file_operation_backend.dart';
import 'file_operation_service.dart';

enum ArchiveDirectorySyncStatus {
  equal,
  sourceOnly,
  changed,
  archiveOnly,
  typeConflict,
}

class ArchiveDirectorySyncRow {
  const ArchiveDirectorySyncRow._(
    this.relativePath,
    this.source,
    this.archive,
    this.status,
    this.sourceSha256,
    this.archiveSha256,
  );
  final String relativePath;
  final FileItem? source;
  final FileItem? archive;
  final ArchiveDirectorySyncStatus status;
  final String? sourceSha256;
  final String? archiveSha256;
}

class ArchiveDirectorySyncPlan {
  ArchiveDirectorySyncPlan._(
    this._owner,
    this._snapshot,
    this._revision,
    List<ArchiveDirectorySyncRow> rows,
  ) : rows = List.unmodifiable(rows);
  final ArchiveDirectorySyncService _owner;
  final ArchiveDirectorySnapshot _snapshot;
  final int _revision;
  final List<ArchiveDirectorySyncRow> rows;
  final List<String> errors = const [];
  bool _consumed = false;
  bool get isConsumed => _consumed;
  bool get hasTypeConflicts =>
      rows.any((row) => row.status == ArchiveDirectorySyncStatus.typeConflict);
  bool get canStage => !_consumed && errors.isEmpty && !hasTypeConflicts;
}

class ArchiveDirectorySyncReview {
  ArchiveDirectorySyncReview._(
    this._owner,
    this._plan,
    this.archiveReview,
    List<String> copiedPaths,
    List<String> removedPaths,
  ) : copiedPaths = List.unmodifiable(copiedPaths),
      removedPaths = List.unmodifiable(removedPaths);
  final ArchiveDirectorySyncService _owner;
  final ArchiveDirectorySyncPlan _plan;
  final ArchiveWorkspaceReview archiveReview;
  final List<String> copiedPaths;
  final List<String> removedPaths;
}

class ArchiveDirectorySyncResult {
  ArchiveDirectorySyncResult._(
    this.receipt,
    this.copiedPaths,
    this.removedPaths,
  ) : warnings = List.unmodifiable([
        if (receipt.cleanupPending) 'The synchronized archive is published; a verified recovery file still needs cleanup.',
      ]);
  final ArchivePublicationReceipt receipt;
  final List<String> copiedPaths;
  final List<String> removedPaths;
  final List<String> warnings;
}

/// One native directory's contents update one existing archive directory.
/// Compare is read-only; selected rows become one private atomic draft, and
/// publication/recovery remain bound to the complete captured source tree.
/// The caller owns [destination] and closes it after this service is finished.
class ArchiveDirectorySyncService {
  ArchiveDirectorySyncService({
    required this.source,
    required this.sourceDirectory,
    required this.destination,
    this.destinationDirectory = '/',
  });
  final FileOperationBackend source;
  final String sourceDirectory;
  final ArchiveWorkspace destination;
  final String destinationDirectory;
  final Object _authority = Object();
  bool _closed = false;
  bool _busy = false;
  bool _staged = false;
  ArchiveDirectorySyncPlan? _plan;
  ArchiveDirectorySyncReview? _review;
  ArchiveDirectorySyncResult? _result;

  bool get isCurrent => !_closed && source.isCurrent && destination.isCurrent;
  String? get unsupportedReason {
    if (!isCurrent) return 'The captured synchronization locations changed.';
    if (destination.nestedMemberPaths.isNotEmpty) {
      return 'Directory synchronization currently requires a top-level archive.';
    }
    if (kIsWeb ||
        source is! LocalOperationBackend ||
        destination.source is! LocalOperationBackend ||
        source.storageReference?.persistent != true ||
        source.storageReference != destination.source.storageReference) {
      return 'Directory synchronization requires native local storage from the same installation.';
    }
    if (!destination.canSynchronizeDirectory) {
      return 'This archive profile cannot synchronize a directory. ${destination.updateSupport}';
    }
    return null;
  }

  void _check([FileOperationControl? control]) {
    if (unsupportedReason case final reason?) throw StateError(reason);
    if (control?.isCancelled ?? false) throw const FileOperationCancelled();
  }

  String _archivePath(String relative) => destinationDirectory == '/'
      ? '/$relative'
      : '$destinationDirectory/$relative';

  Future<ArchiveDirectorySyncPlan> compare({
    required FileOperationControl control,
    void Function(int entries, String path)? onProgress,
  }) async {
    _check(control);
    if (_busy ||
        _staged ||
        destination.dirty ||
        destination.pendingPublication != null) {
      throw StateError('Open a clean archive before comparing directories.');
    }
    if (!p.posix.isAbsolute(destinationDirectory) ||
        p.posix.normalize(destinationDirectory) != destinationDirectory ||
        destinationDirectory != '/' &&
            destinationDirectory !=
                '/${ArchiveService.safeMemberPath(destinationDirectory.substring(1))}') {
      throw StateError('The archive synchronization directory is invalid.');
    }
    final revision = destination.revision;
    void check() {
      _check(control);
      if (destination.revision != revision || destination.dirty) {
        throw StateError('The archive changed during comparison.');
      }
    }

    _busy = true;
    try {
      final root = await destination.backend.stat(destinationDirectory);
      check();
      if (root == null || !root.isFolder) {
        throw StateError(
          'The archive destination is not an existing directory.',
        );
      }
      final archiveRoot = root.path!;
      final archiveBackend = destination.backend;
      String destinationKey(String relative) =>
          archiveBackend.pathKey(_archivePath(relative));
      final snapshot = await captureArchiveDirectorySnapshot(
        source,
        sourceDirectory,
        isCancelled: () =>
            _closed || control.isCancelled || !destination.isCurrent,
        onProgress: onProgress,
        forbiddenContainer: destination.file,
      );
      check();
      // A source may distinguish names that this archive represents as one
      // member (for example NFC/NFD spellings in HFSX). Preserve the captured
      // source paths, but reject ambiguous destination identities up front.
      final sourceByDestination = <String, ArchiveDirectorySnapshotEntry>{};
      for (final entry in snapshot.entries.values) {
        final key = destinationKey(entry.relativePath);
        if (sourceByDestination.containsKey(key)) {
          throw StateError(
            'Source names collide in the destination archive: '
            '${sourceByDestination[key]!.relativePath} and ${entry.relativePath}',
          );
        }
        sourceByDestination[key] = entry;
      }
      final archive = <String, FileItem>{};
      final archivePaths = <String, String>{};
      final hashes = <String, String>{};
      var total = 0;
      Future<void> walk(String path, int depth) async {
        await control.checkpoint();
        check();
        if (depth > 200) {
          throw StateError(
            'The archive comparison exceeds its traversal bounds.',
          );
        }
        for (final child in destination.list(path)) {
          check();
          // Implicit directories also become comparison rows, so count each
          // row rather than relying only on the workspace's stored-member cap.
          if (archive.length >= 200000) {
            throw StateError(
              'The archive comparison exceeds its traversal bounds.',
            );
          }
          final relative = p.posix.relative(child.path!, from: archiveRoot);
          final key = destinationKey(relative);
          if (ArchiveService.safeMemberPath(relative) != relative ||
              archive.containsKey(key)) {
            throw StateError('The archive comparison namespace is ambiguous.');
          }
          archive[key] = child;
          archivePaths[key] = relative;
          if (child.isFolder) {
            await walk(child.path!, depth + 1);
          } else {
            final bytes = await destination.read(child.path!);
            check();
            total += bytes.length;
            if (bytes.length > kArchiveReadLimit ||
                total > ArchiveService.maxExtractedBytes) {
              throw StateError(
                'The archive comparison exceeds its content bounds.',
              );
            }
            hashes[key] = crypto.sha256.convert(bytes).toString();
          }
        }
      }

      await walk(archiveRoot, 0);
      check();
      final keys = {...sourceByDestination.keys, ...archive.keys};
      final rows = <ArchiveDirectorySyncRow>[];
      for (final key in keys) {
        final first = sourceByDestination[key];
        final second = archive[key];
        final status = first == null
            ? ArchiveDirectorySyncStatus.archiveOnly
            : second == null
            ? ArchiveDirectorySyncStatus.sourceOnly
            : first.file.isFolder != second.isFolder
            ? ArchiveDirectorySyncStatus.typeConflict
            : first.file.isFolder || first.sha256 == hashes[key]
            ? ArchiveDirectorySyncStatus.equal
            : ArchiveDirectorySyncStatus.changed;
        rows.add(
          ArchiveDirectorySyncRow._(
            first?.relativePath ?? archivePaths[key]!,
            first?.file,
            second,
            status,
            first?.sha256,
            hashes[key],
          ),
        );
      }
      rows.sort(
        (first, second) => first.relativePath.compareTo(second.relativePath),
      );
      // The archive reads above can take time. Revalidate the source's complete
      // namespace, including entries whose action will be Keep or Equal.
      await verifyArchiveDirectoryDependency(
        source,
        snapshot.dependency,
        isCancelled: () =>
            _closed || control.isCancelled || !destination.isCurrent,
      );
      check();
      return _plan = ArchiveDirectorySyncPlan._(this, snapshot, revision, rows);
    } finally {
      _busy = false;
    }
  }

  Future<ArchiveDirectorySyncReview> stage(
    ArchiveDirectorySyncPlan plan, {
    required Set<String> copyPaths,
    Set<String> removePaths = const {},
    bool allowRemovals = false,
    required FileOperationControl control,
  }) async {
    _check(control);
    if (_busy ||
        _staged ||
        !identical(plan._owner, this) ||
        !identical(_plan, plan) ||
        !plan.canStage ||
        destination.revision != plan._revision ||
        destination.dirty ||
        destination.pendingPublication != null) {
      throw StateError(
        'Compare the current directory and archive before staging.',
      );
    }
    final copies = copyPaths.toList()..sort();
    final removals = removePaths.toList()..sort();
    final rows = {for (final row in plan.rows) row.relativePath: row};
    if (copies.isEmpty && removals.isEmpty) {
      throw StateError('Select at least one synchronization action.');
    }
    if (removals.isNotEmpty && !allowRemovals) {
      throw StateError('Explicitly allow selected archive-only removals.');
    }
    for (final path in copies) {
      if (!const {
        ArchiveDirectorySyncStatus.sourceOnly,
        ArchiveDirectorySyncStatus.changed,
      }.contains(rows[path]?.status)) {
        throw StateError(
          'Only new or changed source rows can be copied: $path',
        );
      }
    }
    for (final path in removals) {
      if (rows[path]?.status != ArchiveDirectorySyncStatus.archiveOnly) {
        throw StateError('Only archive-only rows can be removed: $path');
      }
    }
    void check() {
      _check(control);
      if (destination.revision != plan._revision || destination.dirty) {
        throw StateError('The archive changed after comparison.');
      }
    }

    _busy = true;
    try {
      final imports = <ArchiveWorkspaceImport>[];
      for (final path in copies) {
        await control.checkpoint();
        check();
        final entry = plan._snapshot.entries[path]!;
        Uint8List? bytes;
        if (!entry.file.isFolder) {
          bytes = await readArchiveDirectorySnapshotFile(
            source,
            entry,
            isCancelled: () =>
                _closed || control.isCancelled || !destination.isCurrent,
          );
        }
        imports.add(
          ArchiveWorkspaceImport(
            rows[path]!.archive?.path ?? _archivePath(path),
            isFolder: entry.file.isFolder,
            bytes: bytes,
            modified: entry.file.updatedAt,
            mode: entry.mode,
          ),
        );
      }
      await verifyArchiveDirectoryDependency(
        source,
        plan._snapshot.dependency,
        isCancelled: () =>
            _closed || control.isCancelled || !destination.isCurrent,
      );
      check();
      destination.applyDirectorySync(
        imports: imports,
        removals: {for (final path in removals) rows[path]!.archive!.path!},
        directory: destinationDirectory,
        expectedRevision: plan._revision,
        publicationAuthority: _authority,
        dependency: plan._snapshot.dependency,
      );
      plan._consumed = true;
      _staged = true;
      final review = await destination.review(
        isCancelled: () => _closed || control.isCancelled || !source.isCurrent,
      );
      _check(control);
      if (!review.isCurrent) {
        throw StateError('The synchronization draft changed.');
      }
      return _review = ArchiveDirectorySyncReview._(
        this,
        plan,
        review,
        copies,
        removals,
      );
    } catch (_) {
      if (plan.isConsumed &&
          destination.isCurrent &&
          destination.revision == plan._revision + 1 &&
          destination.pendingPublication == null) {
        destination.discardDraft();
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<ArchiveDirectorySyncResult> commit({
    required ArchiveDirectorySyncReview reviewed,
    bool Function()? isCancelled,
    void Function(ArchivePublicationPhase)? onPhase,
  }) async {
    _check();
    if (_busy ||
        _result != null ||
        !identical(reviewed._owner, this) ||
        !identical(reviewed, _review) ||
        !reviewed.archiveReview.isCurrent) {
      throw StateError(
        'Review the current synchronization candidate before publishing.',
      );
    }
    bool cancelled() =>
        _closed || !source.isCurrent || (isCancelled?.call() ?? false);
    _busy = true;
    try {
      final dependency = reviewed._plan._snapshot.dependency;
      await verifyArchiveDirectoryDependency(
        source,
        dependency,
        isCancelled: cancelled,
      );
      final receipt = await destination.save(
        reviewed: reviewed.archiveReview,
        isCancelled: cancelled,
        onPhase: onPhase,
        directoryDependency: dependency,
        directorySyncAuthority: _authority,
      );
      if (receipt == null) {
        throw StateError(
          'The synchronized archive was not physically published.',
        );
      }
      return _result = ArchiveDirectorySyncResult._(
        receipt,
        reviewed.copiedPaths,
        reviewed.removedPaths,
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> close() async {
    _closed = true;
  }
}
