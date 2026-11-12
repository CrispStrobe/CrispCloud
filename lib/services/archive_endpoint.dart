import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/archive_endpoint.dart';
import '../models/file_item.dart';
import 'archive_container_publisher.dart';
import 'archive_publication_journal.dart';
import 'archive_service.dart';
import 'archive_viewer_service.dart';
import 'archive_workspace.dart';
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
  );
  final Map<String, Object> _nativeSnapshots;
  final ArchiveEndpoint _owner;
  final FileOperationPlan _plan;
  final bool moveSources;
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
    this.importDeadline = const Duration(minutes: 10),
    this.readInactivity = const Duration(seconds: 30),
  });
  final Duration importDeadline;
  final Duration readInactivity;
  final ArchiveWorkspace workspace;
  final bool ownsWorkspace;
  bool _closed = false, _busy = false;
  ArchiveEndpointImportPlan? _staged;
  ArchiveWorkspaceReview? _review;
  final _witnesses = <_ImportWitness>[];

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
    _check();
    if (_busy || _staged != null || workspace.pendingPublication != null) {
      throw StateError(
        'Finish the current archive transaction before importing again.',
      );
    }
    if (source is ArchiveOperationBackend) {
      throw UnsupportedError(
        'Archive-to-archive imports require a separate transaction workflow.',
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
        source.identity == outer.source.identity ||
        source.storageReference != null &&
            source.storageReference == outer.source.storageReference;
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
    for (final entry in plan.entries) {
      if (entry.source.isSymlink == true ||
          !entry.source.isFolder &&
              (entry.source.size == null ||
                  entry.source.size! < 0 ||
                  entry.source.size! > kArchiveReadLimit)) {
        plan.errors.add(
          'An import member has an unsupported type or exceeds 64 MiB: ${entry.source.path}',
        );
      }
      if (!entry.source.isFolder) bytes += entry.source.size ?? 0;
    }
    if (bytes > ArchiveService.maxExtractedBytes) {
      plan.errors.add('The selected import exceeds 256 MiB.');
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
    return ArchiveEndpointImportPlan._(
      this,
      plan,
      moveSources,
      Map.unmodifiable(nativeSnapshots),
    );
  }

  /// All bytes and source snapshots are verified before this single draft edit.
  /// A later review is required before any container publication.
  Future<ArchiveWorkspaceReview> stageImport(
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
    final deadline = Timer(importDeadline, control.cancel);
    try {
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
          );
          final imported = overlay._bytes[entry.destination];
          if (imported == null ||
              digest != sha256.convert(imported).toString()) {
            throw StateError(
              'Import source bytes changed: ${entry.source.path}',
            );
          }
        }
        int? mode;
        if (plan.source.capabilities.permissions) {
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
          if (mode == null) {
            throw StateError(
              'Source permissions could not be read: ${current.path}',
            );
          }
          if (mode & 0xc00 != 0) {
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
            entry.destination,
            digest,
            mode,
            nativeSnapshot,
          ),
        );
      }
      await control.checkpoint();
      overlay._check();
      workspace.applyImport([
        for (final witness in witnesses)
          ArchiveWorkspaceImport(
            witness.destination,
            isFolder: witness.source.isFolder,
            bytes: witness.source.isFolder
                ? null
                : overlay._bytes[witness.destination],
            modified: witness.source.updatedAt,
            mode: witness.mode,
          ),
      ], expectedRevision: overlay.revision);
      if (witnesses.isEmpty) {
        throw StateError(
          'No archive members were selected after collision handling.',
        );
      }
      _witnesses.addAll(witnesses);
      _staged = import;
      _review = await workspace.review(
        isCancelled: () => control.isCancelled || _closed,
      );
      return _review!;
    } finally {
      deadline.cancel();
      overlay._bytes.clear();
      _busy = false;
    }
  }

  Future<ArchiveWorkspaceReview> review({bool Function()? isCancelled}) async {
    _check();
    return _review = await workspace.review(isCancelled: isCancelled);
  }

  Future<ArchiveEndpointTransferResult> commit({
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
      final receipt = await workspace.save(
        reviewed: reviewed,
        isCancelled: () => _closed || (isCancelled?.call() ?? false),
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
        final cleanupDeadline = Timer(importDeadline, cleanupControl.cancel);
        Future<T> bounded<T>(Future<T> operation) => operation.timeout(
          readInactivity,
          onTimeout: () {
            cleanupControl.cancel();
            throw TimeoutException('Source cleanup acknowledgement timed out.');
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
              await bounded(publisher.verifyReceipt(receipt));
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
                if (sha256
                            .convert(await workspace.read(witness.destination))
                            .toString() !=
                        witness.sha256 ||
                    await _digest(
                          input,
                          now,
                          () async => current(),
                          control: cleanupControl,
                          inactivity: readInactivity,
                        ) !=
                        witness.sha256) {
                  throw StateError(
                    'The original source or published member changed.',
                  );
                }
                await bounded(publisher.verifyReceipt(receipt));
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
                      await bounded(publisher.verifyReceipt(receipt));
                      current();
                    },
                  ),
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

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (ownsWorkspace) await workspace.close();
  }
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

Future<String> _digest(
  FileOperationBackend source,
  FileItem expected,
  TransferCheckpoint checkpoint, {
  FileOperationControl? control,
  Duration inactivity = const Duration(seconds: 30),
}) async {
  if (expected.size == null ||
      expected.size! > kArchiveReadLimit ||
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
  final deadline = Timer(const Duration(minutes: 5), readControl.cancel);
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
    : revision = workspace.revision;
  final ArchiveWorkspace workspace;
  final bool Function() current;
  final int revision;
  final _bytes = <String, Uint8List>{};
  final _directories = <String>{};
  void _check() {
    if (!isCurrent) {
      throw StateError('The archive draft changed during import.');
    }
  }

  String _path(String path) {
    if (path == '/') return path;
    return '/${ArchiveService.safeMemberPath(path.replaceFirst(RegExp(r'^/+'), ''))}';
  }

  @override
  Object get identity => this;
  @override
  String get label => workspace.file.name;
  @override
  p.Context get paths => p.posix;
  @override
  bool get isCurrent =>
      current() && workspace.isCurrent && workspace.revision == revision;
  @override
  bool get supportsStagedVerification => true;
  @override
  Future<FileItem?> stat(String path) async {
    _check();
    path = _path(path);
    if (path == '/' || _directories.contains(path)) {
      return FileItem(name: paths.basename(path), path: path, isFolder: true);
    }
    if (_bytes.containsKey(path)) {
      return FileItem(
        name: paths.basename(path),
        path: path,
        isFolder: false,
        size: _bytes[path]!.length,
        metadata: {'version': sha256.convert(_bytes[path]!).toString()},
      );
    }
    return workspace.backend.stat(path);
  }

  @override
  Future<List<FileItem>> list(String path) async {
    _check();
    path = _path(path);
    final items = {for (final item in workspace.list(path)) item.path!: item};
    for (final entry in {..._directories, ..._bytes.keys}) {
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
    yield _bytes[file.path!] ?? await workspace.read(file.path!);
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
    final builder = BytesBuilder(copy: false);
    await for (final chunk in data) {
      _check();
      if (builder.length + chunk.length > kArchiveReadLimit) {
        throw StateError('Imported member exceeds 64 MiB.');
      }
      builder.add(chunk);
    }
    _check();
    if (length == null || builder.length != length) {
      throw StateError('Imported member length changed.');
    }
    final bytes = builder.takeBytes();
    if (_bytes.values.fold<int>(0, (sum, item) => sum + item.length) -
            (_bytes[path]?.length ?? 0) +
            bytes.length >
        ArchiveService.maxExtractedBytes) {
      throw StateError('Private archive import exceeds 256 MiB.');
    }
    _bytes[path] = bytes;
    await verifyStaged?.call((await stat(path))!);
    _check();
  }

  @override
  Future<void> deleteFile(FileItem file) async =>
      throw UnsupportedError('Private archive import is copy-only.');
  @override
  Future<void> deleteEmptyDirectory(String path) async =>
      throw UnsupportedError('Private archive import is copy-only.');
}
