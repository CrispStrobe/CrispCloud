import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/archive_directory_sync_strings.dart';
import '../l10n/archive_endpoint_strings.dart';
import '../l10n/archive_transfer_strings.dart';
import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../services/archive_container_publisher.dart';
import '../services/archive_endpoint.dart';
import '../services/archive_publication_journal.dart';
import '../services/archive_service.dart';
import '../services/archive_workspace.dart';
import '../services/file_operation_service.dart';
import '../utils/formatters.dart';

Future<ArchiveEndpointTransferResult?> showArchiveEndpointImportDialog(
  BuildContext context, {
  required FileOperationBackend source,
  required List<FileItem> files,
  required FileOperationBackend containerBackend,
  required FileItem containerFile,
  List<String> nestedMembers = const [],
  String directory = '/',
  String? expectedOuterFingerprint,
  bool moveSources = false,
  ArchivePublicationJournal? journal,
}) => _showArchiveEndpointDialog(
  context,
  (onResult) => _ArchiveEndpointDialog(
    onResult: onResult,
    source: source,
    files: List.unmodifiable(files),
    containerBackend: containerBackend,
    containerFile: containerFile,
    nestedMembers: List.unmodifiable(nestedMembers),
    directory: directory,
    expectedOuterFingerprint: expectedOuterFingerprint,
    moveSources: moveSources,
    journal: journal ?? ArchivePublicationJournal(),
  ),
);

/// Copies members between two physical archives. Source and destination routes
/// are captured separately, including their independent nested passwords.
Future<ArchiveEndpointTransferResult?> showArchiveEndpointCopyDialog(
  BuildContext context, {
  required FileOperationBackend sourceContainerBackend,
  required FileItem sourceContainerFile,
  required List<FileItem> files,
  required FileOperationBackend containerBackend,
  required FileItem containerFile,
  List<String> sourceNestedMembers = const [],
  String? expectedSourceFingerprint,
  List<String> nestedMembers = const [],
  String directory = '/',
  String? expectedOuterFingerprint,
  ArchivePublicationJournal? journal,
}) => _showArchiveEndpointDialog(
  context,
  (onResult) => _ArchiveEndpointDialog(
    onResult: onResult,
    sourceContainerBackend: sourceContainerBackend,
    sourceContainerFile: sourceContainerFile,
    sourceNestedMembers: List.unmodifiable(sourceNestedMembers),
    expectedSourceFingerprint: expectedSourceFingerprint,
    files: List.unmodifiable(files),
    containerBackend: containerBackend,
    containerFile: containerFile,
    nestedMembers: List.unmodifiable(nestedMembers),
    directory: directory,
    expectedOuterFingerprint: expectedOuterFingerprint,
    journal: journal ?? ArchivePublicationJournal(),
  ),
);

/// Reviews both physical containers before copying and removing members. The
/// move result distinguishes a verified copy from verified source removal.
Future<ArchiveEndpointTransferResult?> showArchiveEndpointMoveDialog(
  BuildContext context, {
  required FileOperationBackend sourceContainerBackend,
  required FileItem sourceContainerFile,
  required List<FileItem> files,
  required FileOperationBackend containerBackend,
  required FileItem containerFile,
  List<String> sourceNestedMembers = const [],
  String? expectedSourceFingerprint,
  List<String> nestedMembers = const [],
  String directory = '/',
  String? expectedOuterFingerprint,
  ArchivePublicationJournal? journal,
}) => _showArchiveEndpointDialog(
  context,
  (onResult) => _ArchiveEndpointDialog(
    onResult: onResult,
    sourceContainerBackend: sourceContainerBackend,
    sourceContainerFile: sourceContainerFile,
    sourceNestedMembers: List.unmodifiable(sourceNestedMembers),
    expectedSourceFingerprint: expectedSourceFingerprint,
    files: List.unmodifiable(files),
    containerBackend: containerBackend,
    containerFile: containerFile,
    nestedMembers: List.unmodifiable(nestedMembers),
    directory: directory,
    expectedOuterFingerprint: expectedOuterFingerprint,
    moveSources: true,
    journal: journal ?? ArchivePublicationJournal(),
  ),
);

Future<ArchivePublicationReceipt?> showArchiveWorkspacePublicationDialog(
  BuildContext context,
  ArchiveWorkspace workspace,
) async => (await _showArchiveEndpointDialog(
  context,
  (onResult) => _ArchiveEndpointDialog(
    onResult: onResult,
    workspace: workspace,
    containerBackend: workspace.outermost.source,
    containerFile: workspace.outermost.file,
    journal: workspace.journal,
  ),
))?.receipt;

/// Copies from a clean, unlocked workspace without taking ownership of it.
Future<ArchiveEndpointTransferResult?> showArchiveWorkspaceCopyDialog(
  BuildContext context,
  ArchiveWorkspace source, {
  required List<FileItem> files,
  required FileOperationBackend containerBackend,
  required FileItem containerFile,
  List<String> nestedMembers = const [],
  String directory = '/',
  String? expectedOuterFingerprint,
  bool Function()? isCopyCurrent,
  VoidCallback? onSourceInvalidated,
  ArchivePublicationJournal? journal,
}) => _showArchiveWorkspaceTransferDialog(
  context,
  source,
  files: files,
  containerBackend: containerBackend,
  containerFile: containerFile,
  nestedMembers: nestedMembers,
  directory: directory,
  expectedOuterFingerprint: expectedOuterFingerprint,
  isCopyCurrent: isCopyCurrent,
  onSourceInvalidated: onSourceInvalidated,
  journal: journal,
);

/// Borrows the clean source only for reading. The move service owns a separate
/// removal candidate; cancelling review never changes the borrowed draft.
Future<ArchiveEndpointTransferResult?> showArchiveWorkspaceMoveDialog(
  BuildContext context,
  ArchiveWorkspace source, {
  required List<FileItem> files,
  required FileOperationBackend containerBackend,
  required FileItem containerFile,
  List<String> nestedMembers = const [],
  String directory = '/',
  String? expectedOuterFingerprint,
  bool Function()? isCopyCurrent,
  VoidCallback? onSourceInvalidated,
  ArchivePublicationJournal? journal,
}) => _showArchiveWorkspaceTransferDialog(
  context,
  source,
  files: files,
  containerBackend: containerBackend,
  containerFile: containerFile,
  nestedMembers: nestedMembers,
  directory: directory,
  expectedOuterFingerprint: expectedOuterFingerprint,
  isCopyCurrent: isCopyCurrent,
  onSourceInvalidated: onSourceInvalidated,
  moveSources: true,
  journal: journal,
);

Future<ArchiveEndpointTransferResult?> _showArchiveWorkspaceTransferDialog(
  BuildContext context,
  ArchiveWorkspace source, {
  required List<FileItem> files,
  required FileOperationBackend containerBackend,
  required FileItem containerFile,
  required List<String> nestedMembers,
  required String directory,
  String? expectedOuterFingerprint,
  bool Function()? isCopyCurrent,
  VoidCallback? onSourceInvalidated,
  bool moveSources = false,
  ArchivePublicationJournal? journal,
}) {
  final snapshot = source.captureCopySource();
  final selected = List<FileItem>.unmodifiable(files);
  final sourceRoute = source.nestedMemberPaths;
  final destinationRoute = List<String>.unmodifiable(nestedMembers);
  var lost = false;
  bool current() {
    if (!lost) {
      lost = !snapshot.isCurrent || isCopyCurrent?.call() == false;
    }
    return !lost;
  }

  return _showArchiveEndpointDialog(
    context,
    (onResult) => _ArchiveEndpointDialog(
      onResult: onResult,
      sourceWorkspace: source,
      sourceContainerBackend: snapshot.containerBackend,
      sourceContainerFile: snapshot.containerFile,
      sourceNestedMembers: sourceRoute,
      files: selected,
      containerBackend: containerBackend,
      containerFile: containerFile,
      nestedMembers: destinationRoute,
      directory: directory,
      expectedOuterFingerprint: expectedOuterFingerprint,
      isCopyCurrent: current,
      onSourceInvalidated: onSourceInvalidated,
      moveSources: moveSources,
      journal: journal ?? ArchivePublicationJournal(),
    ),
  );
}

/// Preserve a physical outcome even when Back, Escape or an external
/// Navigator.pop closes the route without supplying its result.
Future<ArchiveEndpointTransferResult?> _showArchiveEndpointDialog(
  BuildContext context,
  Widget Function(ValueChanged<ArchiveEndpointTransferResult>) builder,
) async {
  ArchiveEndpointTransferResult? completed;
  final dismissed = await showDialog<ArchiveEndpointTransferResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => builder((result) => completed = result),
  );
  return dismissed ?? completed;
}

class _ArchiveEndpointDialog extends StatefulWidget {
  const _ArchiveEndpointDialog({
    required this.containerBackend,
    required this.containerFile,
    required this.journal,
    required this.onResult,
    this.source,
    this.files = const [],
    this.nestedMembers = const [],
    this.directory = '/',
    this.expectedOuterFingerprint,
    this.moveSources = false,
    this.workspace,
    this.sourceContainerBackend,
    this.sourceContainerFile,
    this.sourceNestedMembers = const [],
    this.expectedSourceFingerprint,
    this.sourceWorkspace,
    this.isCopyCurrent,
    this.onSourceInvalidated,
  });
  final FileOperationBackend containerBackend;
  final FileItem containerFile;
  final ArchivePublicationJournal journal;
  final ValueChanged<ArchiveEndpointTransferResult> onResult;
  final FileOperationBackend? source;
  final List<FileItem> files;
  final List<String> nestedMembers;
  final String directory;
  final String? expectedOuterFingerprint;
  final bool moveSources;
  final ArchiveWorkspace? workspace;
  final FileOperationBackend? sourceContainerBackend;
  final FileItem? sourceContainerFile;
  final List<String> sourceNestedMembers;
  final String? expectedSourceFingerprint;
  final ArchiveWorkspace? sourceWorkspace;
  final bool Function()? isCopyCurrent;
  final VoidCallback? onSourceInvalidated;
  bool get isArchiveCopy => sourceContainerBackend != null;
  bool get isArchiveMove => isArchiveCopy && moveSources;
  @override
  State<_ArchiveEndpointDialog> createState() => _ArchiveEndpointDialogState();
}

class _ArchiveEndpointDialogState extends State<_ArchiveEndpointDialog> {
  ArchiveEndpoint? _endpoint;
  ArchiveWorkspace? _sourceWorkspace;
  List<FileItem>? _sourceMembers;
  bool _ownsSourceWorkspace = false;
  ArchiveEndpointImportPlan? _plan;
  ArchiveWorkspaceReview? _review;
  ArchiveEndpointMoveReview? _moveReview;
  ArchiveEndpointTransferResult? _result;
  FileConflictPolicy _conflict = FileConflictPolicy.keepBoth;
  FileOperationControl _control = FileOperationControl();
  bool _busy = true, _cancelled = false;
  String? _error;
  String _activity = 'preparing';
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _cancelled = true;
    _control.cancel();
    unawaited(_endpoint?.close());
    if (_ownsSourceWorkspace) unawaited(_sourceWorkspace?.close());
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String activity) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _cancelled = false;
      _activity = activity;
    });
    _control = FileOperationControl();
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() => _run(() async {
    if (widget.workspace != null) {
      _endpoint = ArchiveEndpoint.fromWorkspace(widget.workspace!);
      _review = await _endpoint!.review(
        isCancelled: () => _cancelled || !mounted,
      );
      return;
    }
    if (widget.isArchiveMove) {
      final sourceStorage = widget.sourceContainerBackend!.storageReference;
      final destinationStorage = widget.containerBackend.storageReference;
      if (widget.sourceNestedMembers.isNotEmpty ||
          widget.nestedMembers.isNotEmpty ||
          sourceStorage?.isLocal != true ||
          sourceStorage?.persistent != true ||
          destinationStorage?.persistent != true ||
          sourceStorage != destinationStorage ||
          !widget.sourceContainerBackend!.canRecover ||
          !widget.containerBackend.canRecover) {
        throw UnsupportedError(archiveTransferText(context, 'scope'));
      }
    }
    await widget.journal.initialize();
    final pending = widget.journal.records.where(
      (record) =>
          !record.isFinished &&
          record.storage == widget.containerBackend.storageReference &&
          record.original.path == widget.containerFile.path,
    );
    if (pending.isNotEmpty) {
      if (!mounted) return;
      await showArchivePublicationRecoveryDialog(
        context,
        backend: widget.containerBackend,
        journal: widget.journal,
        containerPath: widget.containerFile.path,
      );
      if (!mounted) return;
      throw StateError(archiveEndpointText(context, 'reopen'));
    }
    if (widget.isArchiveMove &&
        widget.journal.records.any(
          (record) =>
              !record.isFinished &&
              record.storage ==
                  widget.sourceContainerBackend!.storageReference &&
              record.original.path == widget.sourceContainerFile!.path,
        )) {
      // A pending source record makes the borrowed view ambiguous, including
      // when recovery is dismissed without taking an action.
      widget.onSourceInvalidated?.call();
      if (!mounted) return;
      await showArchivePublicationRecoveryDialog(
        context,
        backend: widget.sourceContainerBackend!,
        journal: widget.journal,
        containerPath: widget.sourceContainerFile!.path,
      );
      if (!mounted) return;
      throw StateError(archiveEndpointText(context, 'reopen'));
    }
    if (widget.isArchiveCopy) {
      await _openCopySource();
      if (!mounted || _cancelled || _sourceWorkspace == null) return;
    }
    final passwords = List<String?>.filled(
      widget.nestedMembers.length + 1,
      null,
    );
    while (mounted && !_cancelled) {
      try {
        final endpoint = await ArchiveEndpoint.open(
          containerBackend: widget.containerBackend,
          containerFile: widget.containerFile,
          nestedMembers: widget.nestedMembers,
          passwords: passwords,
          expectedOuterFingerprint: widget.expectedOuterFingerprint,
          journal: widget.journal,
        );
        if (!mounted || _cancelled) {
          await endpoint.close();
          return;
        }
        _endpoint = endpoint;
        break;
      } on ArchiveNestedPasswordRequiredException catch (error) {
        if (!mounted || _cancelled) return;
        final password = await _password(
          context,
          error.containerName,
          error.wrongPassword,
          role: widget.isArchiveCopy ? 'destinationPassword' : null,
        );
        if (password == null) {
          _cancelled = true;
          return;
        }
        passwords[error.level] = password;
      }
    }
    if (_endpoint != null) await _prepare();
  }, 'preparing');

  void _checkCopyCurrent() {
    if (widget.isCopyCurrent?.call() == false) {
      throw StateError(archiveEndpointText(context, 'sourceChanged'));
    }
  }

  Future<void> _captureCopyMembers(ArchiveWorkspace workspace) async {
    final members = <FileItem>[];
    for (final selected in widget.files) {
      final raw = selected.path;
      if (raw == null || selected.name == '..') {
        throw StateError(archiveEndpointText(context, 'sourceChanged'));
      }
      final path =
          '/${ArchiveService.safeMemberPath(raw.replaceAll(RegExp(r'^/+|/+$'), ''))}';
      final member = await workspace.backend.stat(path);
      if (!mounted || _cancelled) return;
      _checkCopyCurrent();
      if (member == null ||
          member.isFolder != selected.isFolder ||
          (!member.isFolder &&
              selected.size != null &&
              selected.size != member.size)) {
        throw StateError(archiveEndpointText(context, 'sourceChanged'));
      }
      members.add(member);
    }
    _sourceMembers = List.unmodifiable(members);
  }

  Future<void> _openCopySource() async {
    _checkCopyCurrent();
    final borrowed = widget.sourceWorkspace;
    if (borrowed != null) {
      if (borrowed.dirty || borrowed.pendingPublication != null) {
        throw StateError(
          widget.isArchiveMove
              ? archiveTransferText(context, 'sourceDraft')
              : archiveEndpointText(context, 'sourceDraft'),
        );
      }
      borrowed.captureCopySource().checkCurrent();
      _sourceWorkspace = borrowed;
      await _captureCopyMembers(borrowed);
      return;
    }
    final passwords = List<String?>.filled(
      widget.sourceNestedMembers.length + 1,
      null,
    );
    while (mounted && !_cancelled) {
      try {
        final workspace = await ArchiveWorkspace.openNested(
          widget.sourceContainerBackend!,
          widget.sourceContainerFile!,
          widget.sourceNestedMembers,
          passwords: passwords,
          expectedOuterFingerprint: widget.expectedSourceFingerprint,
          journal: widget.journal,
        );
        if (!mounted || _cancelled) {
          await workspace.close();
          return;
        }
        _sourceWorkspace = workspace;
        _ownsSourceWorkspace = true;
        await _captureCopyMembers(workspace);
        return;
      } on ArchiveNestedPasswordRequiredException catch (error) {
        if (!mounted || _cancelled) return;
        final password = await _password(
          context,
          error.containerName,
          error.wrongPassword,
          role: 'sourcePassword',
        );
        if (password == null) {
          _cancelled = true;
          return;
        }
        passwords[error.level] = password;
      }
    }
  }

  Future<void> _prepare() async {
    _plan = null;
    _checkCopyCurrent();
    if (widget.isArchiveMove) {
      final reason = ArchiveEndpoint.archiveMoveUnsupportedReason(
        _sourceWorkspace!,
        _endpoint!.workspace,
      );
      if (reason != null) {
        throw UnsupportedError(
          '${archiveTransferText(context, 'scope')}\n$reason',
        );
      }
      _plan = await _endpoint!.prepareArchiveMove(
        source: _sourceWorkspace!,
        files: _sourceMembers!,
        directory: widget.directory,
        conflict: _conflict,
        control: _control,
      );
      return;
    }
    _plan = widget.isArchiveCopy
        ? await _endpoint!.prepareArchiveCopy(
            source: _sourceWorkspace!,
            files: _sourceMembers!,
            directory: widget.directory,
            conflict: _conflict,
            control: _control,
          )
        : await _endpoint!.prepareImport(
            source: widget.source!,
            files: widget.files,
            directory: widget.directory,
            moveSources: widget.moveSources,
            conflict: _conflict,
            control: _control,
          );
  }

  Future<void> _stage() => _run(() async {
    _checkCopyCurrent();
    if (widget.isArchiveMove) {
      final review = await _endpoint!.stageArchiveMove(
        _plan!,
        control: _control,
      );
      _moveReview = review;
      _review = review.destinationReview;
    } else {
      _review = await _endpoint!.stageImport(_plan!, control: _control);
    }
  }, 'preparing');
  Future<void> _reviewAgain() => _run(() async {
    _checkCopyCurrent();
    _review = await _endpoint!.review(
      isCancelled: () => _cancelled || !mounted,
    );
  }, 'preparing');
  Future<void> _publish() => _run(() async {
    _checkCopyCurrent();
    bool cancelled() =>
        _cancelled || !mounted || widget.isCopyCurrent?.call() == false;
    if (widget.isArchiveMove) {
      _result = await _endpoint!.commitArchiveMove(
        reviewed: _moveReview!,
        isCancelled: cancelled,
        onPhase: (phase) {
          if (phase == ArchiveMovePhase.sourcePublication) {
            // Record this before the first source publication await. An
            // external Navigator.pop can bypass a busy route's PopScope.
            widget.onSourceInvalidated?.call();
          }
          if (!mounted) return;
          setState(
            () => _activity = switch (phase) {
              ArchiveMovePhase.destinationPublication =>
                'destinationPublishing',
              ArchiveMovePhase.sourcePublication => 'sourcePublishing',
            },
          );
        },
      );
    } else {
      _result = await _endpoint!.commit(
        reviewed: _review!,
        isCancelled: cancelled,
      );
    }
    widget.onResult(_result!);
  }, 'publishing');
  void _close() => Navigator.pop(context, _result);

  @override
  Widget build(BuildContext context) {
    String t(String key, [List<Object?> values = const []]) =>
        archiveEndpointText(context, key, values);
    String m(String key, [List<Object?> values = const []]) =>
        archiveTransferText(context, key, values);
    final workspace = _endpoint?.workspace;
    final moveResult = _result is ArchiveEndpointMoveResult
        ? _result! as ArchiveEndpointMoveResult
        : null;
    Widget reviewSummary(
      ArchiveWorkspaceReview review, {
      String? title,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
        Text(t('packed', [formatBytes(review.packedBytes)])),
        Text(t('entries', [review.changes.length])),
        for (final change in review.changes.take(100))
          Text(
            '${t(change.kind.name)}: ${change.from == null ? '' : '${change.from} → '}${change.path}',
          ),
        if (review.changes.length > 100)
          Text(t('moreEntries', [review.changes.length - 100])),
      ],
    );
    return PopScope<ArchiveEndpointTransferResult>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _close();
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              if (!_busy) _close();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: AlertDialog(
            title: Text(
              widget.isArchiveMove
                  ? m(_moveReview != null ? 'review' : 'title')
                  : t(
                      _review != null
                          ? 'reviewTitle'
                          : widget.isArchiveCopy
                          ? 'copyTitle'
                          : 'importTitle',
                    ),
            ),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isArchiveCopy) ...[
                      Text(t('sourceArchive')),
                      SelectableText(
                        [
                          widget.sourceContainerFile!.path,
                          ...widget.sourceNestedMembers,
                        ].join('!/'),
                      ),
                      const SizedBox(height: 8),
                      Text(t('destinationArchive')),
                    ],
                    SelectableText(
                      [
                        widget.containerFile.path,
                        ...widget.nestedMembers,
                      ].join('!/'),
                    ),
                    if (widget.source != null)
                      Text('${widget.source!.label} → ${widget.directory}'),
                    if (widget.isArchiveCopy) Text('→ ${widget.directory}'),
                    const SizedBox(height: 12),
                    if (_busy) ...[
                      const LinearProgressIndicator(),
                      Text(
                        _activity == 'destinationPublishing' ||
                                _activity == 'sourcePublishing'
                            ? m(_activity)
                            : t(_activity),
                      ),
                    ],
                    if (_error != null)
                      SelectableText(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_result != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          moveResult == null
                              ? t('published')
                              : m(switch (moveResult.disposition) {
                                  ArchiveMoveDisposition.moved => 'published',
                                  ArchiveMoveDisposition.destinationOnly =>
                                    'retained',
                                  ArchiveMoveDisposition
                                      .sourceRecoveryRequired =>
                                    'recovery',
                                }),
                        ),
                      ),
                      if (moveResult != null) ...[
                        if (moveResult.sourceReceipt != null)
                          Text(
                            m('removedCount', [
                              _moveReview!.removedSourcePaths.length,
                            ]),
                          ),
                        if (moveResult.disposition !=
                            ArchiveMoveDisposition.moved)
                          Text(m('recoveryDetail')),
                      ],
                      if (_result!.receipt.cleanupPending ||
                          moveResult?.sourceReceipt?.cleanupPending == true)
                        Text(t('cleanupPending')),
                      if (_result!.retainedSources.isNotEmpty &&
                          moveResult?.disposition !=
                              ArchiveMoveDisposition.sourceRecoveryRequired)
                        Text(
                          moveResult == null
                              ? t('retained', [_result!.retainedSources.length])
                              : m('retainedCount', [
                                  _result!.retainedSources.length,
                                ]),
                        ),
                      for (final warning in _result!.warnings)
                        SelectableText(warning),
                    ] else ...[
                      if (workspace != null && !workspace.canUpdate)
                        Text(workspace.updateSupport),
                      if (workspace != null) ...[
                        Text(
                          t('protection', [
                            workspace.encrypted
                                ? t(
                                    workspace.encryptNames
                                        ? 'namesProtected'
                                        : 'dataProtected',
                                  )
                                : t('unencrypted'),
                          ]),
                        ),
                        Text(t('metadata')),
                      ],
                      Text(t('publicationSafety')),
                      if (widget.isArchiveCopy) ...[
                        if (widget.isArchiveMove) ...[
                          Text(m('scope')),
                          Text(m('policy')),
                          Text(m('skipped')),
                        ] else
                          Text(t('archiveCopySnapshot')),
                        Text(t('archiveCopyProtection')),
                        Text(t('archiveCopyMetadata')),
                      ] else
                        Text(
                          t(widget.moveSources ? 'movePolicy' : 'copyPolicy'),
                        ),
                      if (widget.moveSources && !widget.isArchiveMove)
                        Text(t('directoriesRemain')),
                      if (workspace?.pendingPublication != null)
                        Text(t('recoveryClose')),
                      Text(
                        t(
                          workspace?.supportsLargeFiles == true
                              ? 'streamedBounds'
                              : 'bounds',
                        ),
                      ),
                      if (_review == null &&
                          (widget.source != null || widget.isArchiveCopy) &&
                          _endpoint != null) ...[
                        DropdownButtonFormField<FileConflictPolicy>(
                          initialValue: _conflict,
                          isExpanded: true,
                          itemHeight: null,
                          decoration: InputDecoration(
                            labelText: t('collision'),
                          ),
                          items: [
                            for (final value in [
                              FileConflictPolicy.keepBoth,
                              FileConflictPolicy.skip,
                              FileConflictPolicy.replace,
                            ])
                              DropdownMenuItem(
                                value: value,
                                child: Text(
                                  t(value.name),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _conflict = value);
                                    unawaited(_run(_prepare, 'preparing'));
                                  }
                                },
                        ),
                        if (_plan != null) ...[
                          for (final error in _plan!.errors)
                            Text(
                              error,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          Text(t('entries', [_plan!.entries.length])),
                          for (final entry in _plan!.entries.take(100))
                            Text(
                              '${entry.source.path} → ${entry.destination}${entry.existing == null ? '' : ' • ${t('collision')}'}',
                            ),
                        ],
                      ],
                      if (_review != null) ...[
                        reviewSummary(
                          _review!,
                          title: widget.isArchiveMove
                              ? m('destinationReview')
                              : null,
                        ),
                        if (_moveReview != null) ...[
                          reviewSummary(
                            _moveReview!.sourceReview,
                            title: m('sourceReview'),
                          ),
                          if (_moveReview!.retainedSourcePaths.isNotEmpty) ...[
                            Text(
                              m('retainedCount', [
                                _moveReview!.retainedSourcePaths.length,
                              ]),
                            ),
                            for (final path
                                in _moveReview!.retainedSourcePaths.take(100))
                              Text(path),
                            if (_moveReview!.retainedSourcePaths.length > 100)
                              Text(
                                t('moreEntries', [
                                  _moveReview!.retainedSourcePaths.length - 100,
                                ]),
                              ),
                          ],
                        ],
                      ],
                      Text(
                        widget.isArchiveMove ? m('draftOnly') : t('draftOnly'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (_busy)
                TextButton(
                  onPressed: () {
                    setState(() => _cancelled = true);
                    _control.cancel();
                  },
                  child: Text(context.commanderTr('Cancel')),
                ),
              if (!_busy)
                TextButton(
                  onPressed: _close,
                  child: Text(context.commanderTr('Close')),
                ),
              if (!_busy &&
                  _result == null &&
                  _review == null &&
                  !widget.isArchiveMove &&
                  _endpoint?.workspace.dirty == true)
                TextButton(
                  onPressed: _reviewAgain,
                  child: Text(t('reviewTitle')),
                ),
              if (!_busy &&
                  _result == null &&
                  _review == null &&
                  _plan?.canStage == true)
                FilledButton(
                  onPressed: _stage,
                  child: Text(widget.isArchiveMove ? m('stage') : t('stage')),
                ),
              if (!_busy &&
                  _result == null &&
                  _review != null &&
                  (!widget.isArchiveMove || _moveReview != null))
                FilledButton(
                  onPressed: _publish,
                  child: Text(
                    widget.isArchiveMove ? m('publish') : t('publish'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Requests a container password without retaining it beyond its owning route.
Future<String?> requestArchiveEndpointPassword(
  BuildContext context,
  String name,
  bool wrong, {
  String? role,
}) => _password(context, name, wrong, role: role);

Future<String?> _password(
  BuildContext context,
  String name,
  bool wrong, {
  String? role,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      _ArchiveEndpointPasswordDialog(name: name, wrong: wrong, role: role),
);

/// Own the controller for the complete route lifetime. A popped prompt can
/// still be animating while the next nested password is requested.
class _ArchiveEndpointPasswordDialog extends StatefulWidget {
  const _ArchiveEndpointPasswordDialog({
    required this.name,
    required this.wrong,
    this.role,
  });
  final String name;
  final bool wrong;
  final String? role;
  @override
  State<_ArchiveEndpointPasswordDialog> createState() =>
      _ArchiveEndpointPasswordDialogState();
}

class _ArchiveEndpointPasswordDialogState
    extends State<_ArchiveEndpointPasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.wrong
          ? context.commanderTr('Incorrect password. Try again')
          : widget.role == null
          ? context.commanderTr('Archive password')
          : archiveEndpointText(context, widget.role!),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.wrong && widget.role != null)
          Text(archiveEndpointText(context, widget.role!)),
        TextField(
          controller: _controller,
          obscureText: true,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: widget.name),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.commanderTr('Cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(context.commanderTr('Continue')),
      ),
    ],
  );
}

/// Recovery is scoped to one already captured account. A true result means an
/// explicit recovery action was attempted; callers should refresh and recapture
/// the container before a new edit, even if the path now exists again.
Future<bool> showArchivePublicationRecoveryDialog(
  BuildContext context, {
  required FileOperationBackend backend,
  ArchivePublicationJournal? journal,
  String? containerPath,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ArchiveRecoveryDialog(
        backend: backend,
        journal: journal ?? ArchivePublicationJournal(),
        containerPath: containerPath,
      ),
    ) ??
    false;

class _ArchiveRecoveryDialog extends StatefulWidget {
  const _ArchiveRecoveryDialog({
    required this.backend,
    required this.journal,
    this.containerPath,
  });
  final FileOperationBackend backend;
  final ArchivePublicationJournal journal;
  final String? containerPath;
  @override
  State<_ArchiveRecoveryDialog> createState() => _ArchiveRecoveryDialogState();
}

class _ArchiveRecoveryDialogState extends State<_ArchiveRecoveryDialog> {
  List<ArchiveRecoveryInspection> _records = [];
  bool _busy = true, _changed = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.journal.initialize();
      final publisher = ArchiveContainerPublisher(
        widget.backend,
        widget.journal,
      );
      final records = <ArchiveRecoveryInspection>[];
      for (final record in widget.journal.records.where(
        (record) =>
            !record.isFinished &&
            record.storage == widget.backend.storageReference &&
            (widget.containerPath == null ||
                record.original.path == widget.containerPath),
      )) {
        if (!mounted) return;
        try {
          records.add(
            await publisher.inspect(record, isCancelled: () => !mounted),
          );
        } catch (error) {
          records.add(
            ArchiveRecoveryInspection(
              record: record,
              canFinish: false,
              canRestore: false,
              message: '$error',
            ),
          );
        }
      }
      if (mounted) setState(() => _records = records);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover(
    ArchiveRecoveryInspection item,
    ArchiveRecoveryAction action,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
      _changed = true;
    });
    try {
      await ArchiveContainerPublisher(
        widget.backend,
        widget.journal,
      ).recover(item.record, action, isCancelled: () => !mounted);
      if (mounted) await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => archiveEndpointText(context, key);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(t('recoveryTitle')),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('recoveryDetail')),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) SelectableText(_error!),
                if (!_busy && _records.isEmpty) Text(t('noRecovery')),
                for (final item in _records)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.record.dependency != null)
                            Text(t('sourceArchive')),
                          if (item.record.directoryDependency != null)
                            Text(t('destinationArchive')),
                          SelectableText(item.record.original.path!),
                          if (item.record.dependency
                              case final dependency?) ...[
                            Text(t('destinationArchive')),
                            SelectableText(dependency.file.path!),
                          ],
                          if (item.record.directoryDependency
                              case final directoryDependency?) ...[
                            Text(
                              archiveDirectorySyncText(
                                context,
                                'sourceDirectory',
                              ),
                            ),
                            SelectableText(directoryDependency.directory.path!),
                          ],
                          Text(item.message),
                          SelectableText(
                            item.record.candidatePath(widget.backend.paths),
                          ),
                          SelectableText(
                            item.record.backupPath(widget.backend.paths),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: !_busy && item.canFinish
                                    ? () => _recover(
                                        item,
                                        ArchiveRecoveryAction.finishPublication,
                                      )
                                    : null,
                                child: Text(t('finish')),
                              ),
                              TextButton(
                                onPressed: !_busy && item.canRestore
                                    ? () => _recover(
                                        item,
                                        ArchiveRecoveryAction.restoreOriginal,
                                      )
                                    : null,
                                child: Text(t('restore')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _reload,
            child: Text(t('recheck')),
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, _changed),
            child: Text(context.commanderTr('Close')),
          ),
        ],
      ),
    );
  }
}
