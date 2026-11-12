import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/archive_directory_sync_strings.dart';
import '../l10n/archive_endpoint_strings.dart';
import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/archive_directory_sync_service.dart';
import '../services/archive_endpoint.dart';
import '../services/archive_publication_journal.dart';
import '../services/archive_workspace.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/local_file_service.dart';
import '../utils/formatters.dart';
import 'archive_endpoint_actions.dart';
import 'archive_endpoint_dialog.dart';
import 'commander_review_dialog.dart';

/// Captures both panes before opening any dialog. The real directory supplies
/// its contents, regardless of which pane holds the archive destination.
Future<void> showCurrentArchiveDirectorySyncDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  CapturedArchiveImportDestination? destination;
  try {
    final left = ref.read(panelProvider(PanelSide.local));
    final right = ref.read(panelProvider(PanelSide.remote));
    if (kIsWeb || left.isInArchive == right.isInArchive) {
      throw UnsupportedError(archiveDirectorySyncText(context, 'scope'));
    }
    final sourcePanel = left.isInArchive ? right : left;
    if (!sourcePanel.hasVerifiedDirectoryListing) {
      throw StateError(archiveDirectorySyncText(context, 'capturedChanged'));
    }
    final sourceOrigin = sourcePanel.captureCurrentOrigin();
    final sourceDirectory = sourcePanel.currentPath;
    final sourceSession = sourcePanel.captureOperationSession();
    final sourceNavigation = sourcePanel.navigationIntentRevision;
    final local = ref.read(localFileServiceProvider);
    final identities = local is LocalFileSourceIdentity
        ? local as LocalFileSourceIdentity
        : null;
    final grant = identities?.sourceIdentityForPath(sourceDirectory);
    destination = CapturedArchiveImportDestination.capture(
      ref,
      left.isInArchive ? PanelSide.local : PanelSide.remote,
    );
    final capturedDestination = destination;
    var lost = false;
    bool current() {
      if (!lost) {
        lost =
            !context.mounted ||
            !sourceSession() ||
            !sourceOrigin.isCurrent ||
            sourcePanel.navigationIntentRevision != sourceNavigation ||
            !capturedDestination.isCurrent ||
            identities != null &&
                !identical(
                  identities.sourceIdentityForPath(sourceDirectory),
                  grant,
                );
      }
      return !lost;
    }

    final source = fileOperationBackend(
      source: sourceOrigin.source,
      local: local,
      isCurrent: current,
    );
    final backend = fileOperationBackend(
      source: destination.origin.source,
      local: local,
      isCurrent: current,
    );
    if (!sourceOrigin.source.isLocal ||
        !destination.origin.source.isLocal ||
        identities != null && grant == null ||
        destination.location.nestedMembers.isNotEmpty ||
        source.storageReference?.persistent != true ||
        source.storageReference != backend.storageReference ||
        !source.canRecover ||
        !backend.canRecover) {
      throw UnsupportedError(archiveDirectorySyncText(context, 'scope'));
    }
    await showArchiveDirectorySyncDialog(
      context,
      source: source,
      sourceDirectory: sourceDirectory,
      containerBackend: backend,
      containerFile: destination.location.file,
      destinationDirectory: destination.directory,
      expectedOuterFingerprint: destination.location.fingerprint,
      isCaptureCurrent: current,
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  } finally {
    // Recovery can alter the physical archive without returning a new receipt.
    // Refresh only the captured destination; navigation never redirects it.
    if (context.mounted && destination?.isCurrent == true) {
      await destination!.panel.refresh();
    }
  }
}

/// The result survives every dismissal route. A forced external pop waits for
/// any in-flight publication to settle before its caller refreshes the pane.
Future<ArchiveDirectorySyncResult?> showArchiveDirectorySyncDialog(
  BuildContext context, {
  required FileOperationBackend source,
  required String sourceDirectory,
  required FileOperationBackend containerBackend,
  required FileItem containerFile,
  String destinationDirectory = '/',
  String? expectedOuterFingerprint,
  bool Function()? isCaptureCurrent,
  ArchivePublicationJournal? journal,
}) async {
  ArchiveDirectorySyncResult? completed;
  Future<void>? pending;
  final dismissed = await showDialog<ArchiveDirectorySyncResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ArchiveDirectorySyncDialog(
      source: source,
      sourceDirectory: sourceDirectory,
      containerBackend: containerBackend,
      containerFile: containerFile,
      destinationDirectory: destinationDirectory,
      expectedOuterFingerprint: expectedOuterFingerprint,
      isCaptureCurrent: isCaptureCurrent,
      journal: journal ?? ArchivePublicationJournal(),
      onResult: (result) => completed = result,
      onOperation: (operation) => pending = operation,
    ),
  );
  await pending;
  return dismissed ?? completed;
}

class _ArchiveDirectorySyncDialog extends StatefulWidget {
  const _ArchiveDirectorySyncDialog({
    required this.source,
    required this.sourceDirectory,
    required this.containerBackend,
    required this.containerFile,
    required this.destinationDirectory,
    required this.journal,
    required this.onResult,
    required this.onOperation,
    this.expectedOuterFingerprint,
    this.isCaptureCurrent,
  });

  final FileOperationBackend source, containerBackend;
  final String sourceDirectory, destinationDirectory;
  final FileItem containerFile;
  final String? expectedOuterFingerprint;
  final bool Function()? isCaptureCurrent;
  final ArchivePublicationJournal journal;
  final void Function(ArchiveDirectorySyncResult) onResult;
  final void Function(Future<void>) onOperation;

  @override
  State<_ArchiveDirectorySyncDialog> createState() =>
      _ArchiveDirectorySyncDialogState();
}

class _ArchiveDirectorySyncDialogState
    extends State<_ArchiveDirectorySyncDialog> {
  ArchiveEndpoint? _endpoint;
  ArchiveDirectorySyncService? _service;
  ArchiveDirectorySyncPlan? _plan;
  ArchiveDirectorySyncReview? _review;
  ArchiveDirectorySyncResult? _result;
  final _copyPaths = <String>{};
  final _removePaths = <String>{};
  FileOperationControl _control = FileOperationControl();
  Future<void>? _operation;
  bool _busy = true,
      _cancelled = false,
      _allowRemovals = false,
      _showEqual = false,
      _captureLost = false;
  String? _error;
  String _activity = 'comparing';

  @override
  void initState() {
    super.initState();
    unawaited(_run(_open, 'comparing'));
  }

  @override
  void dispose() {
    _cancelled = true;
    _control.cancel();
    // A direct Navigator.pop can bypass PopScope. Keep the transaction's
    // workspace alive until its cancellation/publication has settled.
    unawaited(() async {
      await _operation;
      await _service?.close();
      await _endpoint?.close();
    }());
    super.dispose();
  }

  bool _current() {
    if (!_captureLost) {
      _captureLost =
          !widget.source.isCurrent ||
          !widget.containerBackend.isCurrent ||
          widget.isCaptureCurrent?.call() == false;
    }
    return !_captureLost;
  }

  void _check() {
    if (!mounted) throw StateError('Archive synchronization cancelled.');
    if (!_current()) {
      throw StateError(archiveDirectorySyncText(context, 'capturedChanged'));
    }
    if (_cancelled) {
      throw StateError(archiveDirectorySyncText(context, 'cancelled'));
    }
  }

  Future<void> _run(Future<void> Function() action, String activity) {
    if (!mounted) return Future.value();
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _activity = activity;
    });
    _control = FileOperationControl();
    final operation = () async {
      try {
        _check();
        await action();
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }();
    _operation = operation;
    widget.onOperation(operation);
    return operation;
  }

  Future<void> _open() async {
    if (kIsWeb ||
        widget.source is! LocalOperationBackend ||
        widget.containerBackend is! LocalOperationBackend ||
        widget.source.storageReference?.persistent != true ||
        widget.source.storageReference !=
            widget.containerBackend.storageReference ||
        !widget.source.canRecover ||
        !widget.containerBackend.canRecover) {
      throw UnsupportedError(archiveDirectorySyncText(context, 'scope'));
    }
    await widget.journal.initialize();
    if (!mounted) return;
    _check();
    if (widget.journal.records.any(
      (record) =>
          !record.isFinished &&
          record.storage == widget.containerBackend.storageReference &&
          record.original.path == widget.containerFile.path,
    )) {
      await showArchivePublicationRecoveryDialog(
        context,
        backend: widget.containerBackend,
        journal: widget.journal,
        containerPath: widget.containerFile.path,
      );
      if (!mounted) return;
      throw StateError(archiveEndpointText(context, 'reopen'));
    }
    String? password;
    while (mounted && !_cancelled) {
      _check();
      try {
        final endpoint = await ArchiveEndpoint.open(
          containerBackend: widget.containerBackend,
          containerFile: widget.containerFile,
          passwords: [password],
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
        password = await requestArchiveEndpointPassword(
          context,
          error.containerName,
          error.wrongPassword,
          role: 'destinationPassword',
        );
        if (password == null) {
          _cancelled = true;
          return;
        }
      }
    }
    _check();
    _service = ArchiveDirectorySyncService(
      source: widget.source,
      sourceDirectory: widget.sourceDirectory,
      destination: _endpoint!.workspace,
      destinationDirectory: widget.destinationDirectory,
    );
    if (_service!.unsupportedReason case final reason?) {
      throw UnsupportedError(reason);
    }
    await _compare();
  }

  Future<void> _compare() async {
    _check();
    _plan = null;
    _copyPaths.clear();
    _removePaths.clear();
    _allowRemovals = false;
    final plan = await _service!.compare(control: _control);
    if (!mounted) return;
    _check();
    _plan = plan;
  }

  Future<void> _stage() => _run(() async {
    _review = await _service!.stage(
      _plan!,
      copyPaths: Set.unmodifiable(_copyPaths),
      removePaths: Set.unmodifiable(_removePaths),
      allowRemovals: _allowRemovals,
      control: _control,
    );
  }, 'staging');

  Future<void> _publish() => _run(() async {
    final result = await _service!.commit(
      reviewed: _review!,
      isCancelled: () => _cancelled || !mounted || !_current(),
    );
    _result = result;
    widget.onResult(result);
  }, 'publishing');

  void _close() => Navigator.pop(context, _result);

  @override
  Widget build(BuildContext context) {
    String t(String key, [List<Object?> values = const []]) =>
        archiveDirectorySyncText(context, key, values);
    String a(String key, [List<Object?> values = const []]) =>
        archiveEndpointText(context, key, values);
    final workspace = _endpoint?.workspace;
    final selecting =
        !_busy &&
        _review == null &&
        _plan?.canStage == true &&
        _plan?.isConsumed == false &&
        !_captureLost;
    final rows =
        _plan?.rows
            .where(
              (row) =>
                  _showEqual || row.status != ArchiveDirectorySyncStatus.equal,
            )
            .toList() ??
        [];
    final review = _review?.archiveReview;
    final changes = review?.changes ?? [];
    return PopScope<ArchiveDirectorySyncResult>(
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
          child: CommanderReviewDialog(
            title: t(review == null ? 'title' : 'review'),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('sourceDirectory')),
                    SelectableText(widget.sourceDirectory),
                    const SizedBox(height: 8),
                    Text(a('destinationArchive')),
                    SelectableText(widget.containerFile.path!),
                    Text(t('archiveDirectory')),
                    SelectableText(widget.destinationDirectory),
                    const SizedBox(height: 12),
                    if (_result case final result?) ...[
                      Text(
                        t('complete'),
                        key: const ValueKey('archive-sync-complete'),
                      ),
                      SelectableText('SHA-256: ${result.receipt.sha256}'),
                      for (final warning in result.warnings)
                        SelectableText(warning),
                      if (result.receipt.cleanupPending)
                        Text(a('cleanupPending')),
                    ] else ...[
                      Text(t('policy')),
                      if (workspace != null) ...[
                        Text(
                          a('protection', [
                            workspace.encrypted
                                ? a(
                                    workspace.encryptNames
                                        ? 'namesProtected'
                                        : 'dataProtected',
                                  )
                                : a('unencrypted'),
                          ]),
                        ),
                        Text(a('metadata')),
                      ],
                      Text(t('sourceGuard')),
                      if (_busy) ...[
                        Semantics(liveRegion: true, child: Text(t(_activity))),
                        const LinearProgressIndicator(),
                      ],
                      if (_error != null) SelectableText(_error!),
                      if (_cancelled &&
                          !_busy &&
                          _error == null &&
                          workspace?.pendingPublication == null)
                        Text(t('cancelled')),
                      if (workspace?.pendingPublication != null)
                        Text(a('recoveryClose')),
                      if (_plan case final plan?)
                        for (final error in plan.errors) SelectableText(error),
                      if (_plan?.hasTypeConflicts == true)
                        Text(t('conflictsBlock')),
                      if (_plan != null && review == null) ...[
                        Text(
                          t('compared', [
                            _plan!.rows.length,
                            _copyPaths.length + _removePaths.length,
                          ]),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton(
                              key: const ValueKey(
                                'archive-sync-select-updates',
                              ),
                              onPressed: !selecting
                                  ? null
                                  : () => setState(() {
                                      for (final row in _plan!.rows) {
                                        if (row.status ==
                                                ArchiveDirectorySyncStatus
                                                    .sourceOnly ||
                                            row.status ==
                                                ArchiveDirectorySyncStatus
                                                    .changed) {
                                          _copyPaths.add(row.relativePath);
                                        }
                                      }
                                    }),
                              child: Text(t('selectUpdates')),
                            ),
                            TextButton(
                              onPressed: !selecting
                                  ? null
                                  : () => setState(() {
                                      _copyPaths.clear();
                                      _removePaths.clear();
                                    }),
                              child: Text(t('clear')),
                            ),
                            FilterChip(
                              label: Text(t('showEqual')),
                              selected: _showEqual,
                              onSelected: (value) =>
                                  setState(() => _showEqual = value),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          key: const ValueKey('archive-sync-allow-removals'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(t('allowRemovals')),
                          value: _allowRemovals,
                          onChanged: !selecting
                              ? null
                              : (value) => setState(() {
                                  _allowRemovals = value;
                                  if (!value) _removePaths.clear();
                                }),
                        ),
                        Text(t('removalPolicy')),
                        if (_allowRemovals)
                          TextButton(
                            key: const ValueKey('archive-sync-select-removals'),
                            onPressed: !selecting
                                ? null
                                : () => setState(() {
                                    _removePaths.addAll(
                                      _plan!.rows
                                          .where(
                                            (row) =>
                                                row.status ==
                                                ArchiveDirectorySyncStatus
                                                    .archiveOnly,
                                          )
                                          .map((row) => row.relativePath),
                                    );
                                  }),
                            child: Text(t('selectRemovals')),
                          ),
                      ],
                      if (review != null) ...[
                        Text(a('packed', [formatBytes(review.packedBytes)])),
                        Text(a('entries', [review.changes.length])),
                        Text(a('publicationSafety')),
                      ],
                    ],
                  ],
                ),
              ),
              if (_result == null && review == null)
                SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final status = row.status;
                    final copy =
                        status == ArchiveDirectorySyncStatus.sourceOnly ||
                        status == ArchiveDirectorySyncStatus.changed;
                    final remove =
                        status == ArchiveDirectorySyncStatus.archiveOnly;
                    final enabled =
                        selecting && (copy || remove && _allowRemovals);
                    final selected = copy
                        ? _copyPaths.contains(row.relativePath)
                        : _removePaths.contains(row.relativePath);
                    final label = switch (status) {
                      ArchiveDirectorySyncStatus.sourceOnly => 'new',
                      ArchiveDirectorySyncStatus.changed => 'changed',
                      ArchiveDirectorySyncStatus.equal => 'equal',
                      ArchiveDirectorySyncStatus.archiveOnly => 'archiveOnly',
                      ArchiveDirectorySyncStatus.typeConflict => 'typeConflict',
                    };
                    final action = selected
                        ? copy
                              ? status == ArchiveDirectorySyncStatus.sourceOnly
                                    ? 'add'
                                    : 'update'
                              : 'remove'
                        : 'keep';
                    return Card(
                      child: CheckboxListTile(
                        key: ValueKey('archive-sync-row-${row.relativePath}'),
                        value: selected,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          row.relativePath,
                          textDirection: TextDirection.ltr,
                        ),
                        subtitle: Text('${t(label)}\n${t(action)}'),
                        onChanged: !enabled
                            ? null
                            : (value) => setState(() {
                                final paths = copy ? _copyPaths : _removePaths;
                                value == true
                                    ? paths.add(row.relativePath)
                                    : paths.remove(row.relativePath);
                              }),
                      ),
                    );
                  },
                ),
              if (_result == null && review != null)
                SliverList.builder(
                  itemCount: changes.length,
                  itemBuilder: (context, index) {
                    final change = changes[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '${a(change.kind.name)}: ${change.path}',
                          key: ValueKey('archive-sync-change-${change.path}'),
                        ),
                      ),
                    );
                  },
                ),
            ],
            actions: [
              if (_busy)
                TextButton(
                  onPressed: () => setState(() {
                    _cancelled = true;
                    _control.cancel();
                  }),
                  child: Text(context.commanderTr('Stop')),
                ),
              TextButton(
                key: const ValueKey('archive-sync-close'),
                onPressed: _busy ? null : _close,
                child: Text(
                  context.commanderTr(_result == null ? 'Cancel' : 'Close'),
                ),
              ),
              if (_result == null && review == null && _service != null)
                TextButton(
                  onPressed: _busy || _captureLost || _plan?.isConsumed == true
                      ? null
                      : () => _run(_compare, 'comparing'),
                  child: Text(t('compare')),
                ),
              if (_result == null && review == null)
                FilledButton(
                  key: const ValueKey('archive-sync-stage'),
                  onPressed:
                      selecting &&
                          (_copyPaths.isNotEmpty || _removePaths.isNotEmpty)
                      ? _stage
                      : null,
                  child: Text(t('stage')),
                ),
              if (_result == null && review != null)
                FilledButton(
                  key: const ValueKey('archive-sync-publish'),
                  onPressed:
                      _busy ||
                          !review.isCurrent ||
                          _captureLost ||
                          workspace?.pendingPublication != null
                      ? null
                      : _publish,
                  child: Text(t('publish')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
