import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/archive_endpoint.dart';
import '../models/file_item.dart';
import 'archive_container_publisher.dart';
import 'archive_output_spool.dart';
import 'archive_publication_journal.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';
import 'archive_workspace.dart';
import 'file_operation_backend.dart' show LocalOperationBackend;
import 'file_operation_service.dart';
import 'storage_transfer_contract.dart';
import 'archive_source_cleanup_stub.dart'
    if (dart.library.io) 'archive_source_cleanup_io.dart'
    as native;

export '../models/archive_endpoint.dart';

/// A physical publication, never the result of writing a virtual member.
class ArchiveEndpointTransferResult {
  const ArchiveEndpointTransferResult({
    required this.receipt,
    required this.publishedFiles,
    required this.removedSources,
    this.retainedSources = const [],
    this.warnings = const [],
  });
  final ArchivePublicationReceipt receipt;
  final int publishedFiles;
  final int removedSources;
  final List<String> retainedSources;
  final List<String> warnings;
}

enum ArchiveMovePhase { destinationPublication, sourcePublication }

enum ArchiveMoveDisposition { moved, destinationOnly, sourceRecoveryRequired }

/// A destination receipt is always present. Source removal is complete only
/// with its own receipt; interrupted removal retains its dependency-bound
/// publication record for explicit recovery.
class ArchiveEndpointMoveResult extends ArchiveEndpointTransferResult {
  const ArchiveEndpointMoveResult({
    required super.receipt,
    required super.publishedFiles,
    required super.removedSources,
    required this.disposition,
    this.sourceReceipt,
    this.sourceRecovery,
    super.retainedSources,
    super.warnings,
  });
  final ArchiveMoveDisposition disposition;
  final ArchivePublicationReceipt? sourceReceipt;
  final ArchivePublicationRecord? sourceRecovery;
}

class ArchiveEndpointMoveReview {
  ArchiveEndpointMoveReview._(
    this._owner,
    this.destinationReview,
    this.sourceReview,
    List<String> removedSourcePaths,
    List<String> retainedSourcePaths,
  ) : removedSourcePaths = List.unmodifiable(removedSourcePaths),
      retainedSourcePaths = List.unmodifiable(retainedSourcePaths);
  final ArchiveEndpoint _owner;
  final ArchiveWorkspaceReview destinationReview;
  final ArchiveWorkspaceReview sourceReview;
  final List<String> removedSourcePaths;
  final List<String> retainedSourcePaths;
}

class ArchiveEndpointImportEntry {
  const ArchiveEndpointImportEntry(
    this.source,
    this.destination,
    this.existing,
  );
  final FileItem source;
  final String destination;
  final FileItem? existing;
}

/// The operation engine and its writable destination remain private. Callers
/// cannot accidentally execute a generic move against staged archive members.
class ArchiveEndpointImportPlan {
  ArchiveEndpointImportPlan._(
    this._owner,
    this._plan,
    this.moveSources,
    this._nativeSnapshots,
    this._archiveSource,
  );
  final _ArchiveCopyWitness? _archiveSource;
  final Map<String, Object> _nativeSnapshots;
  final ArchiveEndpoint _owner;
  final FileOperationPlan _plan;
  final bool moveSources;
  bool _archiveMove = false;
  bool get isArchiveMove => _archiveMove;
  bool _consumed = false;
  List<String> get errors => List.unmodifiable(_plan.errors);
  bool get canStage => !_consumed && _plan.canExecute;
  List<ArchiveEndpointImportEntry> get entries => List.unmodifiable([
    for (final entry in _plan.entries)
      ArchiveEndpointImportEntry(
        entry.source,
        entry.destination,
        entry.existing,
      ),
  ]);
}

class ArchiveEndpoint {
  ArchiveEndpoint.fromWorkspace(
    this.workspace, {
    this.ownsWorkspace = false,
    Duration? importDeadline,
    this.readInactivity = const Duration(seconds: 30),
  }) : importDeadline = importDeadline ?? const Duration(minutes: 10),
       _scaleImportDeadline = importDeadline == null;
  final Duration importDeadline;
  final bool _scaleImportDeadline;
  final Duration readInactivity;
  final ArchiveWorkspace workspace;
  final bool ownsWorkspace;
  bool _closed = false, _busy = false;
  ArchiveEndpointImportPlan? _staged;
  ArchiveWorkspaceReview? _review;
  final _witnesses = <_ImportWitness>[];
  ArchiveWorkspace? _moveSource;
  ArchiveEndpointMoveReview? _moveReview;
  ArchiveEndpointTransferResult? _moveDestinationResult;
  ArchiveEndpointMoveResult? _moveResult;
  bool _moveCommitting = false;
  final Object _sourceRemovalAuthority = Object();

  static Future<ArchiveEndpoint> open({
    required FileOperationBackend containerBackend,
    required FileItem containerFile,
    List<String> nestedMembers = const [],
    List<String?>? passwords,
    String? expectedOuterFingerprint,
    ArchivePublicationJournal? journal,
  }) async => ArchiveEndpoint.fromWorkspace(
    await ArchiveWorkspace.openNested(
      containerBackend,
      containerFile,
      nestedMembers,
      passwords: passwords,
      expectedOuterFingerprint: expectedOuterFingerprint,
      journal: journal,
    ),
    ownsWorkspace: true,
  );

  bool get isCurrent => !_closed && workspace.isCurrent;

  Duration _importBudget(int bytes) =>
      _scaleImportDeadline && workspace.supportsLargeFiles
      ? _archiveReadBudget(importDeadline, bytes)
      : importDeadline;
  void _check() {
    if (!isCurrent) throw StateError('The captured archive endpoint changed.');
    if (!workspace.canUpdate) throw UnsupportedError(workspace.updateSupport);
  }

  Future<ArchiveEndpointImportPlan> prepareImport({
    required FileOperationBackend source,
    required List<FileItem> files,
    String directory = '/',
    bool moveSources = false,
    FileConflictPolicy conflict = FileConflictPolicy.keepBoth,
    FileOperationControl? control,
  }) async {
    if (source is ArchiveOperationBackend) {
      throw UnsupportedError(
        'Archive members require the reviewed archive copy workflow; archive-to-archive moves are unavailable.',
      );
    }
    return _prepareImport(
      source: source,
      files: files,
      directory: directory,
      moveSources: moveSources,
      conflict: conflict,
      control: control,
    );
  }

  /// Copies original members from an independently captured archive. Source
  /// mutation is deliberately absent: publication of one destination is not a
  /// transaction authorizing a second physical archive rewrite.
  Future<ArchiveEndpointImportPlan> prepareArchiveCopy({
    required ArchiveWorkspace source,
    required List<FileItem> files,
    String directory = '/',
    FileConflictPolicy conflict = FileConflictPolicy.keepBoth,
    FileOperationControl? control,
  }) async {
    _check();
    final snapshot = source.captureCopySource();
    if (snapshot.sharesContainerWith(workspace) ||
        await native
            .sameNativeArchiveContainer(
              snapshot.containerBackend,
              snapshot.containerFile,
              workspace.outermost.source,
              workspace.outermost.file,
            )
            .timeout(readInactivity)) {
      throw UnsupportedError(
        'Copying between members of the same physical archive requires a single-container transaction.',
      );
    }
    final nativeSnapshot = await native
        .captureNativeArchiveImportSource(
          snapshot.containerBackend,
          snapshot.containerFile,
        )
        .timeout(readInactivity);
    snapshot.checkCurrent();
    return _prepareImport(
      source: snapshot.backend,
      files: files,
      directory: directory,
      moveSources: false,
      conflict: conflict,
      control: control,
      archiveSource: _ArchiveCopyWitness(snapshot, nativeSnapshot),
    );
  }

  /// The first move increment requires two distinct top-level local archives
  /// on the same persistent installation. Nested, browser and remote moves
  /// need their own source-publication dependency and recovery contracts.
  static String? archiveMoveUnsupportedReason(
    ArchiveWorkspace source,
    ArchiveWorkspace destination,
  ) {
    if (!source.isCurrent || !destination.isCurrent) {
      return 'The captured archive endpoints are no longer current.';
    }
    if (source.nestedMemberPaths.isNotEmpty ||
        destination.nestedMemberPaths.isNotEmpty) {
      return 'Moving between archives currently requires two top-level containers.';
    }
    if (source.source is! LocalOperationBackend ||
        destination.source is! LocalOperationBackend ||
        source.source.storageReference?.persistent != true ||
        source.source.storageReference != destination.source.storageReference) {
      return 'Moving between archives requires native local storage from the same installation.';
    }
    if (!source.canRemoveMembers) {
      return 'The source archive cannot remove transferred members. ${source.updateSupport}';
    }
    if (!destination.canUpdate) return destination.updateSupport;
    if (source.dirty ||
        destination.dirty ||
        source.pendingPublication != null ||
        destination.pendingPublication != null) {
      return 'Save, discard or recover both archive drafts before moving members.';
    }
    if (identical(source, destination) ||
        source.source.samePath(source.file.path!, destination.file.path!)) {
      return 'Use the single-workspace move action inside the same archive.';
    }
    return null;
  }

  Future<ArchiveEndpointImportPlan> prepareArchiveMove({
    required ArchiveWorkspace source,
    required List<FileItem> files,
    String directory = '/',
    FileConflictPolicy conflict = FileConflictPolicy.keepBoth,
    FileOperationControl? control,
  }) async {
    _check();
    if (archiveMoveUnsupportedReason(source, workspace)
        case final String reason) {
      throw UnsupportedError(reason);
    }
    final plan = await prepareArchiveCopy(
      source: source,
      files: files,
      directory: directory,
      conflict: conflict,
      control: control,
    );
    plan._archiveMove = true;
    return plan;
  }

  Future<ArchiveEndpointImportPlan> _prepareImport({
    required FileOperationBackend source,
    required List<FileItem> files,
    required String directory,
    required bool moveSources,
    required FileConflictPolicy conflict,
    FileOperationControl? control,
    _ArchiveCopyWitness? archiveSource,
  }) async {
    _check();
    if (_busy || _staged != null || workspace.pendingPublication != null) {
      throw StateError(
        'Finish the current archive transaction before importing again.',
      );
    }
    if (![
      FileConflictPolicy.keepBoth,
      FileConflictPolicy.skip,
      FileConflictPolicy.replace,
    ].contains(conflict)) {
      throw UnsupportedError(
        'This archive import requires an explicit collision policy.',
      );
    }
    final outer = workspace.outermost;
    final sameStorage =
        archiveSource == null &&
        (source.identity == outer.source.identity ||
            source.storageReference != null &&
                source.storageReference == outer.source.storageReference);
    for (final file in files) {
      if (file.path == null ||
          file.isSymlink == true ||
          !source.paths.isAbsolute(file.path!)) {
        throw StateError(
          'Import requires captured regular files or directories.',
        );
      }
      if (sameStorage &&
          (source.samePath(file.path!, outer.file.path!) ||
              file.isFolder && source.isWithin(file.path!, outer.file.path!))) {
        throw StateError('The import source contains the destination archive.');
      }
    }
    final overlay = _ArchiveImportOverlay(workspace, () => !_closed);
    final plan = await const FileOperationService().prepare(
      files: List.unmodifiable(files.map(_captureImportFile)),
      source: _ArchiveImportSource(source, readInactivity),
      destination: overlay,
      targetDirectory: directory,
      options: FileOperationOptions(
        kind: FileOperationKind.copy,
        fileConflict: conflict,
        verifyContents: true,
        preferNative: false,
        copyMethod: FileCopyMethod.stream,
      ),
      maxEntries: 200000,
      maxDepth: 200,
      control: control,
    );
    var bytes = 0;
    var projected = workspace.expandedBytes;
    final sourceStreams =
        source.capabilities.boundedDownload ||
        source is ArchiveOperationBackend &&
            source.workspace.supportsLargeFiles;
    final memberLimit = workspace.supportsLargeFiles && !sourceStreams
        ? kArchiveReadLimit
        : workspace.maxMemberBytes;
    for (final entry in plan.entries) {
      if (entry.outcome != FileOperationOutcome.pending) continue;
      if (entry.source.isSymlink == true ||
          !entry.source.isFolder &&
              (entry.source.size == null ||
                  entry.source.size! < 0 ||
                  entry.source.size! > memberLimit)) {
        plan.errors.add(
          'An import member has an unsupported type or exceeds ${_archiveLimitLabel(memberLimit)}: ${entry.source.path}',
        );
      }
      if (!entry.source.isFolder) {
        bytes += entry.source.size ?? 0;
        projected +=
            (entry.source.size ?? 0) -
            (entry.existing?.isFolder == false ? entry.existing?.size ?? 0 : 0);
      }
    }
    if (bytes > workspace.maxExpandedBytes ||
        projected > workspace.maxExpandedBytes) {
      plan.errors.add(
        'The selected import and retained archive contents exceed ${_archiveLimitLabel(workspace.maxExpandedBytes)}.',
      );
    }
    _check();
    final nativeSnapshots = <String, Object>{};
    for (final entry in plan.entries.where(
      (entry) =>
          !entry.source.isFolder &&
          entry.outcome == FileOperationOutcome.pending,
    )) {
      final snapshot = await native
          .captureNativeArchiveImportSource(source, entry.source)
          .timeout(readInactivity);
      if (snapshot != null) nativeSnapshots[entry.source.path!] = snapshot;
    }
    _check();
    archiveSource?.snapshot.checkCurrent();
    return ArchiveEndpointImportPlan._(
      this,
      plan,
      moveSources,
      Map.unmodifiable(nativeSnapshots),
      archiveSource,
    );
  }

  /// All bytes and source snapshots are verified before this single draft edit.
  /// A later review is required before any container publication.
  Future<ArchiveWorkspaceReview> stageImport(
    ArchiveEndpointImportPlan import, {
    required FileOperationControl control,
  }) {
    if (import.isArchiveMove) {
      throw StateError('A move requires review of both archive candidates.');
    }
    return _stageImport(import, control: control);
  }

  Future<ArchiveWorkspaceReview> _stageImport(
    ArchiveEndpointImportPlan import, {
    required FileOperationControl control,
  }) async {
    _check();
    if (_busy ||
        _staged != null ||
        !identical(import._owner, this) ||
        !import.canStage) {
      throw StateError('The archive import preview is no longer available.');
    }
    _busy = true;
    import._consumed = true;
    final plan = import._plan;
    final overlay = plan.destination as _ArchiveImportOverlay;
    final witnesses = <_ImportWitness>[];
    (plan.source as _ArchiveImportSource).control = control;
    final deadline = Timer(
      _importBudget(
        plan.entries.fold<int>(
          workspace.expandedBytes,
          (sum, entry) =>
              sum + (entry.source.isFolder ? 0 : entry.source.size ?? 0),
        ),
      ),
      control.cancel,
    );
    try {
      await _verifyArchiveSource(import._archiveSource, control: control);
      for (final entry in plan.entries.where(
        (entry) => import._nativeSnapshots.containsKey(entry.source.path),
      )) {
        await native
            .verifyNativeArchiveImportSource(
              (plan.source as _ArchiveImportSource).input,
              entry.source,
              import._nativeSnapshots[entry.source.path],
            )
            .timeout(readInactivity);
      }
      await const FileOperationService().execute(plan, control: control);
      if (plan.entries.any(
        (entry) =>
            entry.failed ||
            entry.outcome == FileOperationOutcome.cancelled ||
            entry.outcome == FileOperationOutcome.needsDecision,
      )) {
        throw StateError(
          plan.entries
              .where((entry) => entry.message != null)
              .map((entry) => entry.message)
              .join('\n'),
        );
      }
      for (final entry in plan.entries.where((entry) => entry.completed)) {
        await control.checkpoint();
        _check();
        final current = await plan.source.stat(entry.source.path!);
        if (current == null || !sameArchiveFile(entry.source, current)) {
          throw StateError('Import source changed: ${entry.source.path}');
        }
        String? digest;
        if (!current.isFolder) {
          digest = await _digest(
            plan.source,
            current,
            control.checkpoint,
            control: control,
            inactivity: readInactivity,
            maxBytes: workspace.maxMemberBytes,
          );
          if (digest != overlay._hashes[overlay._path(entry.destination)]) {
            throw StateError(
              'Import source bytes changed: ${entry.source.path}',
            );
          }
        }
        int? mode;
        if (plan.source.capabilities.permissions ||
            import._archiveSource != null) {
          mode = (await plan.source.readMetadataFields(
            current.path!,
            modified: false,
            accessed: false,
            created: false,
            ownership: false,
            extendedAttributes: false,
            acl: false,
            windowsAttributes: false,
          )).mode;
          if (mode == null && import._archiveSource == null) {
            throw StateError(
              'Source permissions could not be read: ${current.path}',
            );
          }
          if ((mode ?? 0) & 0xc00 != 0) {
            throw const ArchiveViewException(
              'Importing setuid or setgid entries requires an ownership-preserving workflow. Source ownership is not captured by this importer.',
            );
          }
        }
        if (!sameArchiveFile(current, await plan.source.stat(current.path!))) {
          throw StateError('Import source changed while reading metadata.');
        }
        final nativeSnapshot = import._nativeSnapshots[current.path];
        await native
            .verifyNativeArchiveImportSource(
              (plan.source as _ArchiveImportSource).input,
              current,
              nativeSnapshot,
            )
            .timeout(readInactivity);
        witnesses.add(
          _ImportWitness(
            current,
            overlay._path(entry.destination),
            digest,
            mode,
            nativeSnapshot,
          ),
        );
      }
      await control.checkpoint();
      overlay._check();
      import._archiveSource?.snapshot.checkCurrent();
      if (witnesses.isEmpty) {
        throw StateError(
          'No archive members were selected after collision handling.',
        );
      }
      workspace.applyImport([
        for (final witness in witnesses)
          ArchiveWorkspaceImport(
            witness.destination,
            isFolder: witness.source.isFolder,
            bytes: witness.source.isFolder
                ? null
                : overlay._bytes[witness.destination],
            spool: witness.source.isFolder
                ? null
                : overlay._spools[witness.destination],
            contentSha256: witness.sha256,
            modified: witness.source.updatedAt,
            mode: witness.mode,
          ),
      ], expectedRevision: overlay.revision);
      // applyImport has adopted the complete set. A failed later review keeps
      // the draft and its spools with the workspace until discard or close.
      overlay._releaseSpoolOwnership();
      _witnesses.addAll(witnesses);
      _staged = import;
      _review = await workspace.review(
        isCancelled: () {
          import._archiveSource?.snapshot.checkCurrent();
          return control.isCancelled || _closed;
        },
      );
      return _review!;
    } finally {
      deadline.cancel();
      try {
        await overlay._dispose();
      } finally {
        _busy = false;
      }
    }
  }

  /// Builds both candidates before either original is published. The source
  /// copy witness remains a clean workspace; removal is staged in a separately
  /// opened workspace bound to that exact physical fingerprint and password.
  Future<ArchiveEndpointMoveReview> stageArchiveMove(
    ArchiveEndpointImportPlan import, {
    required FileOperationControl control,
    int? maxCandidateBytes,
  }) async {
    _check();
    if (!import.isArchiveMove ||
        !identical(import._owner, this) ||
        _moveReview != null ||
        _moveSource != null ||
        _moveCommitting) {
      throw StateError('This preview is not an available archive move.');
    }
    final snapshot = import._archiveSource!.snapshot;
    final combinedLimit =
        workspace.supportsLargeFiles || snapshot.workspace.supportsLargeFiles
        ? workspace.maxContainerBytes + snapshot.workspace.maxContainerBytes
        : ArchiveService.maxArchiveBytes;
    final candidateLimit = maxCandidateBytes ?? combinedLimit;
    if (candidateLimit <= 0 || candidateLimit > combinedLimit) {
      throw ArgumentError.value(maxCandidateBytes, 'maxCandidateBytes');
    }
    if (archiveMoveUnsupportedReason(snapshot.workspace, workspace)
        case final String reason) {
      throw UnsupportedError(reason);
    }
    final originalRevision = workspace.revision;
    ArchiveWorkspace? shadow;
    final deadline = Timer(
      _importBudget(workspace.expandedBytes + snapshot.workspace.expandedBytes),
      control.cancel,
    );
    try {
      final destinationReview = await _stageImport(import, control: control);
      _busy = true;
      await control.checkpoint();
      snapshot.checkCurrent();
      shadow = await ArchiveWorkspace.open(
        snapshot.containerBackend,
        snapshot.containerFile,
        password: snapshot.workspace.password,
        expectedFingerprint: snapshot.fingerprint,
        journal: workspace.journal,
      );
      await control.checkpoint();
      snapshot.checkCurrent();
      final removed = await shadow.stageVerifiedMemberRemoval(
        [
          for (final witness in _witnesses)
            ArchiveWorkspaceRemoval(
              path: witness.source.path!,
              isDirectory: witness.source.isFolder,
              size: witness.source.isFolder ? 0 : witness.source.size!,
              sha256: witness.sha256,
            ),
        ],
        expectedRevision: shadow.revision,
        publicationAuthority: _sourceRemovalAuthority,
        isCancelled: () =>
            _closed || control.isCancelled || !snapshot.isCurrent,
      );
      final sourceReview = await shadow.review(
        isCancelled: () =>
            _closed || control.isCancelled || !snapshot.isCurrent,
      );
      if (removed.isEmpty || sourceReview.changes.isEmpty) {
        throw StateError(
          'No successfully copied source members can be removed.',
        );
      }
      if (sourceReview.packedBytes + destinationReview.packedBytes >
          candidateLimit) {
        throw const ArchiveViewException(
          'The two reviewed archive candidates exceed the combined move limit.',
        );
      }
      await control.checkpoint();
      _check();
      snapshot.checkCurrent();
      if (!sourceReview.isCurrent || !destinationReview.isCurrent) {
        throw StateError(
          'An archive candidate changed while preparing the move.',
        );
      }
      final removedSet = removed.toSet();
      final retained = <String>{
        for (final entry in import._plan.entries)
          if (!removedSet.contains(entry.source.path!)) entry.source.path!,
      };
      final review = ArchiveEndpointMoveReview._(
        this,
        destinationReview,
        sourceReview,
        removed,
        retained.toList()..sort(),
      );
      _moveSource = shadow;
      _moveReview = review;
      shadow = null;
      return review;
    } catch (_) {
      // Move preparation starts from a clean destination. Revert only our one
      // still-current import mutation; an unrelated newer draft is retained.
      if (identical(_staged, import) &&
          workspace.isCurrent &&
          workspace.pendingPublication == null &&
          workspace.revision == originalRevision + 1) {
        workspace.discardDraft();
        _staged = null;
        _review = null;
        _witnesses.clear();
      }
      rethrow;
    } finally {
      deadline.cancel();
      await shadow?.close();
      _busy = false;
    }
  }

  /// Publishes the verified destination first. The source-removal publication
  /// is independently reviewed and durably depends on that exact destination
  /// receipt. After destination success, cancellation/failure returns an
  /// explicit partial result instead of misreporting the entire move as failed.
  Future<ArchiveEndpointMoveResult> commitArchiveMove({
    required ArchiveEndpointMoveReview reviewed,
    bool Function()? isCancelled,
    void Function(ArchiveMovePhase)? onPhase,
  }) async {
    _check();
    if (_busy ||
        _moveCommitting ||
        _moveResult != null ||
        !identical(reviewed._owner, this) ||
        !identical(_moveReview, reviewed) ||
        !identical(_review, reviewed.destinationReview) ||
        _moveSource == null ||
        !reviewed.sourceReview.isCurrent ||
        !reviewed.destinationReview.isCurrent) {
      throw StateError(
        'Review both current archive candidates before moving members.',
      );
    }
    final source = _moveSource!;
    final snapshot = _staged!._archiveSource!.snapshot;
    snapshot.checkCurrent();
    _moveCommitting = true;
    try {
      onPhase?.call(ArchiveMovePhase.destinationPublication);
      final destination = _moveDestinationResult ??= await _commit(
        reviewed: reviewed.destinationReview,
        isCancelled: isCancelled,
      );
      ArchivePublicationReceipt? sourceReceipt;
      String? sourceIssue;
      try {
        if (_closed || (isCancelled?.call() ?? false)) {
          throw const FileOperationCancelled();
        }
        snapshot.checkCurrent();
        if (!reviewed.sourceReview.isCurrent) {
          throw StateError('The reviewed source-removal candidate changed.');
        }
        onPhase?.call(ArchiveMovePhase.sourcePublication);
        // Destination publication may take long enough for the separate
        // physical source to change. Recheck the original native identity and
        // complete content witness before beginning any source publication.
        await _verifyArchiveSource(
          _staged!._archiveSource,
          isCancelled: () => _closed || (isCancelled?.call() ?? false),
        );
        sourceReceipt = await source.save(
          reviewed: reviewed.sourceReview,
          isCancelled: () =>
              _closed || !snapshot.isCurrent || (isCancelled?.call() ?? false),
          dependency: ArchivePublicationDependency.fromReceipt(
            destination.receipt,
          ),
          sourceRemovalAuthority: _sourceRemovalAuthority,
        );
        if (sourceReceipt == null) {
          throw StateError('The source-removal publication was not confirmed.');
        }
      } catch (error) {
        sourceIssue = '$error';
      }
      final recovery = source.pendingPublication;
      final disposition = sourceReceipt != null
          ? ArchiveMoveDisposition.moved
          : recovery != null
          ? ArchiveMoveDisposition.sourceRecoveryRequired
          : ArchiveMoveDisposition.destinationOnly;
      final result = ArchiveEndpointMoveResult(
        receipt: destination.receipt,
        publishedFiles: destination.publishedFiles,
        removedSources: sourceReceipt == null
            ? 0
            : _witnesses.where((item) => !item.source.isFolder).length,
        disposition: disposition,
        sourceReceipt: sourceReceipt,
        sourceRecovery: recovery,
        retainedSources:
            disposition == ArchiveMoveDisposition.sourceRecoveryRequired
            ? const []
            : sourceReceipt == null
            ? List.unmodifiable({
                for (final entry in _staged!._plan.entries) entry.source.path!,
              })
            : reviewed.retainedSourcePaths,
        warnings: List.unmodifiable([
          ...destination.warnings,
          if (sourceIssue != null) sourceIssue,
          if (sourceReceipt?.cleanupPending == true) 'Source removal is published; its verified recovery backup still needs cleanup.',
        ]),
      );
      return _moveResult = result;
    } finally {
      _moveCommitting = false;
    }
  }

  Future<ArchiveWorkspaceReview> review({bool Function()? isCancelled}) async {
    _check();
    if (_staged?.isArchiveMove == true) {
      throw StateError(
        'Review both archive candidates through the move workflow.',
      );
    }
    final source = _staged?._archiveSource;
    source?.snapshot.checkCurrent();
    return _review = await workspace.review(
      isCancelled: () {
        source?.snapshot.checkCurrent();
        return isCancelled?.call() ?? false;
      },
    );
  }

  Future<ArchiveEndpointTransferResult> commit({
    required ArchiveWorkspaceReview reviewed,
    bool Function()? isCancelled,
    void Function(ArchivePublicationPhase)? onPhase,
  }) {
    if (_staged?.isArchiveMove == true) {
      throw StateError(
        'A move requires the reviewed two-container publication workflow.',
      );
    }
    return _commit(
      reviewed: reviewed,
      isCancelled: isCancelled,
      onPhase: onPhase,
    );
  }

  Future<ArchiveEndpointTransferResult> _commit({
    required ArchiveWorkspaceReview reviewed,
    bool Function()? isCancelled,
    void Function(ArchivePublicationPhase)? onPhase,
  }) async {
    _check();
    if (_busy || !identical(_review, reviewed)) {
      throw StateError('Review this archive transaction before publishing.');
    }
    _busy = true;
    try {
      final source = _staged?._archiveSource;
      source?.snapshot.checkCurrent();
      final receipt = await workspace.save(
        reviewed: reviewed,
        isCancelled: () {
          source?.snapshot.checkCurrent();
          return _closed || (isCancelled?.call() ?? false);
        },
        beforePublication: source == null
            ? null
            : () => _verifyArchiveSource(source, isCancelled: isCancelled),
        onPhase: onPhase,
      );
      if (receipt == null) {
        throw StateError(
          'The archive transaction did not publish a changed container.',
        );
      }
      final retained = <String>[];
      final warnings = <String>[
        if (receipt.cleanupPending) 'The archive is published; a verified recovery file still needs cleanup.',
      ];
      var removed = 0;
      final import = _staged;
      if (import?.moveSources == true) {
        final input = (import!._plan.source as _ArchiveImportSource).input;
        final ordered = _witnesses.toList()
          ..sort((a, b) {
            if (a.source.isFolder != b.source.isFolder) {
              return a.source.isFolder ? 1 : -1;
            }
            return b.source.path!.length.compareTo(a.source.path!.length);
          });
        final publisher = ArchiveContainerPublisher(
          workspace.outermost.source,
          workspace.journal,
        );
        final cleanupControl = FileOperationControl();
        final cleanupDeadline = Timer(
          _importBudget(
            _witnesses.fold<int>(
              workspace.outermost.file.size ?? 0,
              (sum, item) =>
                  sum + (item.source.isFolder ? 0 : item.source.size ?? 0),
            ),
          ),
          cleanupControl.cancel,
        );
        Future<T> bounded<T>(Future<T> operation, {int? workBytes}) =>
            operation.timeout(
              workBytes == null ? readInactivity : _importBudget(workBytes),
              onTimeout: () {
                cleanupControl.cancel();
                throw TimeoutException(
                  'Source cleanup acknowledgement timed out.',
                );
              },
            );
        try {
          for (final witness in ordered) {
            final file = witness.source;
            try {
              void current() {
                _check();
                if (!input.isCurrent ||
                    cleanupControl.isCancelled ||
                    (isCancelled?.call() ?? false)) {
                  throw const FileOperationCancelled();
                }
              }

              current();
              await bounded(
                publisher.verifyReceipt(receipt),
                workBytes: receipt.file.size,
              );
              current();
              final observed = await bounded(input.stat(file.path!));
              final now = observed == null
                  ? null
                  : _captureImportFile(observed);
              if (now == null ||
                  now.isSymlink == true ||
                  (file.isFolder
                      ? !now.isFolder || file.uuid != now.uuid
                      : !sameArchiveFile(file, now))) {
                throw StateError('The original source identity changed.');
              }
              if (file.isFolder) {
                throw UnsupportedError(
                  'Source directories remain: this operation has no exact identity-guarded directory deletion contract.',
                );
              } else {
                if (await _digest(
                          workspace.backend,
                          (await workspace.backend.stat(witness.destination))!,
                          () async => current(),
                          control: cleanupControl,
                          inactivity: readInactivity,
                          maxBytes: workspace.maxMemberBytes,
                        ) !=
                        witness.sha256 ||
                    await _digest(
                          input,
                          now,
                          () async => current(),
                          control: cleanupControl,
                          inactivity: readInactivity,
                          maxBytes: workspace.maxMemberBytes,
                        ) !=
                        witness.sha256) {
                  throw StateError(
                    'The original source or published member changed.',
                  );
                }
                await bounded(
                  publisher.verifyReceipt(receipt),
                  workBytes: receipt.file.size,
                );
                current();
                if (!await bounded(
                  native.deleteNativeArchiveImportSource(
                    input,
                    now,
                    sha256: witness.sha256!,
                    capturedIdentity: witness.nativeSnapshot,
                    checkpoint: () async {
                      current();
                    },
                    verifyPublication: () async {
                      await bounded(
                        publisher.verifyReceipt(receipt),
                        workBytes: receipt.file.size,
                      );
                      current();
                    },
                  ),
                  workBytes: now.size! + receipt.file.size!,
                )) {
                  if (!input.capabilities.conditionalDelete ||
                      !_hasVersion(now)) {
                    throw UnsupportedError(
                      'The source does not support exact version-guarded deletion.',
                    );
                  }
                  final checked = await bounded(input.stat(now.path!));
                  current();
                  if (!sameArchiveFile(now, checked)) {
                    throw StateError(
                      'The original source changed before deletion.',
                    );
                  }
                  await bounded(input.deleteFile(now));
                }
              }
              current();
              if (await bounded(input.stat(file.path!)) != null) {
                throw StateError('Source removal was not confirmed.');
              }
              removed++;
            } catch (error) {
              retained.add(file.path!);
              if (warnings.length < 100) warnings.add('${file.path}: $error');
            }
          }
        } finally {
          cleanupDeadline.cancel();
        }
      }
      return ArchiveEndpointTransferResult(
        receipt: receipt,
        publishedFiles: _witnesses
            .where((item) => !item.source.isFolder)
            .length,
        removedSources: removed,
        retainedSources: List.unmodifiable(retained),
        warnings: List.unmodifiable(warnings),
      );
    } finally {
      _busy = false;
    }
  }

  static bool _hasVersion(FileItem file) {
    // Same precedence as CloudOperationBackend._fileVersion. An empty or
    // malformed earlier field must never shadow a usable later revision and
    // silently turn a provider's conditional removal into an unguarded one.
    var found = false;
    for (final key in ['version', 'versionId', 'eTag', 'etag', 'rev', 'cTag']) {
      final value = file.metadata?[key];
      if (value == null) continue;
      if (value is! String || value.trim().isEmpty) return false;
      found = true;
    }
    return found;
  }

  Future<void> _verifyArchiveSource(
    _ArchiveCopyWitness? witness, {
    FileOperationControl? control,
    bool Function()? isCancelled,
  }) async {
    if (witness == null) return;
    final snapshot = witness.snapshot;
    Future<void> checkpoint() async {
      _check();
      snapshot.checkCurrent();
      await control?.checkpoint();
      if (isCancelled?.call() ?? false) throw const FileOperationCancelled();
    }

    await checkpoint();
    await native
        .verifyNativeArchiveImportSource(
          snapshot.containerBackend,
          snapshot.containerFile,
          witness.nativeSnapshot,
        )
        .timeout(readInactivity);
    final hash = await _digest(
      snapshot.containerBackend,
      snapshot.containerFile,
      checkpoint,
      control: control,
      inactivity: readInactivity,
      maxBytes: snapshot.workspace.outermost.maxContainerBytes,
    );
    if (hash != snapshot.fingerprint) {
      throw StateError(
        'The source archive contents changed. Reopen the copy preview.',
      );
    }
    await native
        .verifyNativeArchiveImportSource(
          snapshot.containerBackend,
          snapshot.containerFile,
          witness.nativeSnapshot,
        )
        .timeout(readInactivity);
    await checkpoint();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _moveSource?.close();
    if (ownsWorkspace) await workspace.close();
  }
}

class _ArchiveCopyWitness {
  const _ArchiveCopyWitness(this.snapshot, this.nativeSnapshot);
  final ArchiveWorkspaceSourceSnapshot snapshot;
  final Object? nativeSnapshot;
}

class _ImportWitness {
  const _ImportWitness(
    this.source,
    this.destination,
    this.sha256,
    this.mode,
    this.nativeSnapshot,
  );
  final Object? nativeSnapshot;
  final FileItem source;
  final String destination;
  final String? sha256;
  final int? mode;
}

// FileItem fields are final, but provider-owned metadata maps need their own
// copy. In particular, a later provider read must not rewrite captured String
// revisions in place and authorize deletion of a replacement source.
FileItem _captureImportFile(FileItem file) => file.metadata == null
    ? file
    : file.copyWith(
        metadata: Map.unmodifiable(Map<String, dynamic>.of(file.metadata!)),
      );

Duration _archiveReadBudget(Duration base, int bytes) {
  const bufferedLimit = 256 * 1024 * 1024;
  final excess = bytes > bufferedLimit ? bytes - bufferedLimit : 0;
  return base + Duration(seconds: (excess + 1024 * 1024 - 1) ~/ (1024 * 1024));
}

String _archiveLimitLabel(int bytes) => bytes % (1024 * 1024 * 1024) == 0
    ? '${bytes ~/ (1024 * 1024 * 1024)} GiB'
    : '${bytes ~/ (1024 * 1024)} MiB';

Future<String> _digest(
  FileOperationBackend source,
  FileItem expected,
  TransferCheckpoint checkpoint, {
  FileOperationControl? control,
  Duration inactivity = const Duration(seconds: 30),
  int maxBytes = kArchiveReadLimit,
}) async {
  if (expected.size == null ||
      expected.size! > maxBytes ||
      expected.size! < 0 ||
      expected.isFolder ||
      expected.isSymlink == true) {
    throw StateError('Import verification requires a bounded regular file.');
  }
  if (!source.isCurrent ||
      !sameArchiveFile(
        expected,
        await source.stat(expected.path!).timeout(inactivity),
      )) {
    throw StateError('Import source identity changed.');
  }
  var count = 0;
  final readControl = FileOperationControl();
  final deadline = Timer(
    _archiveReadBudget(const Duration(minutes: 5), expected.size!),
    readControl.cancel,
  );
  try {
    var stream = readControl
        .bind(source.readFile(expected))
        .timeout(inactivity);
    if (control != null) stream = control.bind(stream);
    final result = await sha256
        .bind(
          stream.asyncMap((bytes) async {
            await checkpoint();
            if (!source.isCurrent || (count += bytes.length) > expected.size!) {
              throw StateError('Import source grew while reading.');
            }
            return bytes;
          }),
        )
        .first;
    await checkpoint();
    if (!source.isCurrent ||
        count != expected.size ||
        !sameArchiveFile(
          expected,
          await source.stat(expected.path!).timeout(inactivity),
        )) {
      throw StateError('Import source changed while reading.');
    }
    return result.toString();
  } finally {
    deadline.cancel();
  }
}

/// Deadline/cancellation ownership stays with this one import. Provider reads
/// cannot keep the private copy alive indefinitely after a stalled connection.
class _ArchiveImportSource extends FileOperationBackend {
  _ArchiveImportSource(this.input, this.inactivity);
  final FileOperationBackend input;
  final Duration inactivity;
  FileOperationControl? control;
  @override
  Object get identity => input.identity;
  @override
  String get label => input.label;
  @override
  p.Context get paths => input.paths;
  @override
  String pathKey(String path) => input.pathKey(path);
  @override
  bool get isCurrent => input.isCurrent && !(control?.isCancelled ?? false);
  @override
  StorageTransferCapabilities get capabilities => input.capabilities;
  @override
  Future<FileItem?> stat(String path) async {
    final file = await input.stat(path).timeout(inactivity);
    return file == null ? null : _captureImportFile(file);
  }

  @override
  Future<List<FileItem>> list(String path) async => [
    for (final file in await input.list(path).timeout(inactivity))
      _captureImportFile(file),
  ];
  @override
  Stream<List<int>> readFile(FileItem file) =>
      (control?.bind(input.readFile(file)) ?? input.readFile(file)).timeout(
        inactivity,
      );
  @override
  Future<TransferMetadata> readMetadataFields(
    String path, {
    bool permissions = true,
    bool modified = true,
    bool accessed = true,
    bool created = true,
    bool ownership = true,
    bool extendedAttributes = true,
    bool acl = true,
    bool windowsAttributes = true,
  }) => input
      .readMetadataFields(
        path,
        permissions: permissions,
        modified: modified,
        accessed: accessed,
        created: created,
        ownership: ownership,
        extendedAttributes: extendedAttributes,
        acl: acl,
        windowsAttributes: windowsAttributes,
      )
      .timeout(inactivity);
  @override
  Future<void> createDirectory(String path) async =>
      throw UnsupportedError('Import source is read-only.');
  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) async => throw UnsupportedError('Import source is read-only.');
  @override
  Future<void> deleteFile(FileItem file) async =>
      throw UnsupportedError('Staging cannot delete import sources.');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('Staging cannot delete import sources.');
}

class _ArchiveImportOverlay extends FileOperationBackend {
  _ArchiveImportOverlay(this.workspace, this.current)
    : revision = workspace.revision,
      _projectedBytes = workspace.expandedBytes;
  final ArchiveWorkspace workspace;
  final bool Function() current;
  final int revision;
  final _bytes = <String, Uint8List>{};
  final _spools = <String, ArchiveOutputSpool>{};
  final _retiredSpools = <ArchiveOutputSpool>{};
  final _hashes = <String, String>{};
  final _directories = <String>{};
  int _projectedBytes;
  bool _disposed = false;
  void _check() {
    if (!isCurrent) {
      throw StateError('The archive draft changed during import.');
    }
  }

  String _path(String path) {
    if (path == '/') return path;
    final safe =
        '/${ArchiveService.safeMemberPath(path.replaceFirst(RegExp(r'^/+'), ''))}';
    return workspace.backend.pathKey(safe);
  }

  @override
  Object get identity => this;
  @override
  String get label => workspace.file.name;
  @override
  p.Context get paths => p.posix;
  @override
  String pathKey(String path) => workspace.backend.pathKey(path);
  @override
  String destinationPathKey(String path) =>
      workspace.backend.destinationPathKey(path);
  @override
  bool get isCurrent =>
      !_disposed &&
      current() &&
      workspace.isCurrent &&
      workspace.revision == revision;
  @override
  bool get supportsStagedVerification => true;
  @override
  Future<FileItem?> stat(String path) async {
    _check();
    path = _path(path);
    if (path == '/' || _directories.contains(path)) {
      return FileItem(name: paths.basename(path), path: path, isFolder: true);
    }
    if (_bytes.containsKey(path) || _spools.containsKey(path)) {
      return FileItem(
        name: paths.basename(path),
        path: path,
        isFolder: false,
        size: _spools[path]?.length ?? _bytes[path]!.length,
        metadata: {'version': _hashes[path]},
      );
    }
    return workspace.backend.stat(path);
  }

  @override
  Future<List<FileItem>> list(String path) async {
    _check();
    path = _path(path);
    final items = {for (final item in workspace.list(path)) item.path!: item};
    for (final entry in {..._directories, ..._bytes.keys, ..._spools.keys}) {
      if (paths.dirname(entry) == path) items[entry] = (await stat(entry))!;
    }
    return items.values.toList();
  }

  @override
  Future<void> createDirectory(String path) async {
    _check();
    path = _path(path);
    if ((await stat(path))?.isFolder == false) {
      throw StateError('An archive file occupies this directory.');
    }
    _directories.add(path);
  }

  @override
  Stream<List<int>> readFile(FileItem file) async* {
    _check();
    final path = _path(file.path!);
    final spool = _spools[path];
    final bytes = _bytes[path];
    if (spool != null) {
      await for (final chunk in spool.openRead()) {
        _check();
        yield chunk;
      }
    } else if (bytes != null) {
      yield bytes;
    } else {
      await for (final chunk in workspace.openRead(path)) {
        _check();
        yield chunk;
      }
    }
    _check();
  }

  @override
  Future<void> writeFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
  }) => writePreparedFile(path, data, length, replace: replace);
  @override
  Future<void> writePreparedFile(
    String path,
    Stream<List<int>> data,
    int? length, {
    required bool replace,
    Future<void> Function(FileItem)? verifyStaged,
    Future<void> Function(Map<String, dynamic>)? checkpoint,
  }) async {
    _check();
    path = _path(path);
    final old = await stat(path);
    if (old?.isFolder == true || old != null && !replace) {
      throw StateError('Archive member conflict.');
    }
    if (length == null || length < 0 || length > workspace.maxMemberBytes) {
      throw StateError(
        'Imported member exceeds ${_archiveLimitLabel(workspace.maxMemberBytes)} or has no captured length.',
      );
    }
    final projected = _projectedBytes - (old?.size ?? 0) + length;
    if (projected > workspace.maxExpandedBytes) {
      throw StateError(
        'Private import and retained archive contents exceed ${_archiveLimitLabel(workspace.maxExpandedBytes)}.',
      );
    }
    final builder = workspace.supportsLargeFiles
        ? null
        : BytesBuilder(copy: false);
    final spool = workspace.supportsLargeFiles
        ? await ArchiveOutputSpool.create(maxBytes: workspace.maxMemberBytes)
        : null;
    final digest = _ArchiveImportDigest();
    final hash = sha256.startChunkedConversion(digest);
    var hashClosed = false;
    var adopted = false;
    var received = 0;
    final previousBytes = _bytes[path];
    final previousSpool = _spools[path];
    final previousHash = _hashes[path];
    final previousProjected = _projectedBytes;
    try {
      _check();
      await for (final chunk in data) {
        _check();
        if (chunk.length > length - received) {
          throw StateError('Imported member grew while copying.');
        }
        if (chunk is! Uint8List &&
            chunk.any((byte) => byte < 0 || byte > 255)) {
          throw StateError('Imported member contains invalid bytes.');
        }
        received += chunk.length;
        if (spool == null) {
          // The buffered fallback must also own buffers from reusable providers.
          final copy = Uint8List.fromList(chunk);
          hash.add(copy);
          builder!.add(copy);
        } else {
          // File writes and hashes consume bounded owned chunks. No complete
          // source member or compressed container is retained in Dart memory.
          for (var offset = 0; offset < chunk.length; offset += 256 * 1024) {
            _check();
            final end = offset + 256 * 1024 < chunk.length
                ? offset + 256 * 1024
                : chunk.length;
            final copy = Uint8List.fromList(chunk.sublist(offset, end));
            hash.add(copy);
            await spool.write(copy);
          }
        }
      }
      _check();
      if (received != length) {
        throw StateError('Imported member length changed.');
      }
      hash.close();
      hashClosed = true;
      await spool?.finish();
      _check();
      if (spool != null) {
        _spools[path] = spool;
        _bytes.remove(path);
      } else {
        _bytes[path] = builder!.takeBytes();
        _spools.remove(path);
      }
      _hashes[path] = digest.value!.toString();
      _projectedBytes = projected;
      await verifyStaged?.call((await stat(path))!);
      _check();
      adopted = true;
      if (previousSpool != null) _retiredSpools.add(previousSpool);
    } finally {
      if (!hashClosed) hash.close();
      if (!adopted) {
        if (previousBytes == null) {
          _bytes.remove(path);
        } else {
          _bytes[path] = previousBytes;
        }
        if (previousSpool == null) {
          _spools.remove(path);
        } else {
          _spools[path] = previousSpool;
        }
        if (previousHash == null) {
          _hashes.remove(path);
        } else {
          _hashes[path] = previousHash;
        }
        _projectedBytes = previousProjected;
        await spool?.dispose();
      }
    }
  }

  void _releaseSpoolOwnership() => _spools.clear();

  Future<void> _dispose() async {
    _disposed = true;
    Object? error;
    for (final spool in {..._spools.values, ..._retiredSpools}) {
      try {
        await spool.dispose();
      } catch (failure) {
        error ??= failure;
      }
    }
    _spools.clear();
    _retiredSpools.clear();
    _bytes.clear();
    _hashes.clear();
    if (error != null) throw error;
  }

  @override
  Future<void> deleteFile(FileItem file) async =>
      throw UnsupportedError('Private archive import is copy-only.');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('Private archive import is copy-only.');
}

class _ArchiveImportDigest implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
