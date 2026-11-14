import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/archive_creation_strings.dart';
import '../l10n/archive_zip_recovery_strings.dart';
import '../l10n/archive_endpoint_strings.dart';
import '../l10n/commander_strings.dart';
import '../models/archive_job.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../models/transfer_job.dart';
import '../providers/providers.dart';
import '../services/archive_creation_service.dart';
import '../services/archive_job_recovery_service.dart';
import '../services/archive_workspace.dart';
import '../services/archive_writer_worker.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import 'archive_endpoint_dialog.dart';

Future<void> showArchiveJobRecoveryDialog(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ArchiveJobRecoveryDialog(jobId: jobId),
);

/// Archive recipes always use archive recovery. They must never enter the
/// generic copy/move recovery path, even if a recipe is incomplete or invalid.
class ArchiveJobRecoveryDialog extends ConsumerStatefulWidget {
  const ArchiveJobRecoveryDialog({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<ArchiveJobRecoveryDialog> createState() =>
      _ArchiveJobRecoveryDialogState();
}

class _ArchiveJobRecoveryDialogState
    extends ConsumerState<ArchiveJobRecoveryDialog> {
  final _password = TextEditingController();
  FileOperationControl _control = FileOperationControl();
  ArchiveCreationRecoveryReview? _creationReview;
  bool _busy = false;
  bool _admitting = false;
  String? _error;

  @override
  void dispose() {
    // This control belongs only to the read-only recovery inspection. Any
    // admitted archive job owns a different control and outlives this view.
    _control.cancel();
    _password.dispose();
    super.dispose();
  }

  FileOperationBackend _backend(StorageReference? storage, String path) {
    if (storage == null) {
      throw StateError(
        context.commanderTr(
          'The original storage cannot be restored after restart. Files were retained.',
        ),
      );
    }
    final origin = ref
        .read(panelProvider(PanelSide.local))
        .resolveStorageReference(storage, path);
    if (origin == null) {
      throw StateError(
        context.commanderTr(
          'Reconnect the exact original source and destination accounts to recover this operation.',
        ),
      );
    }
    return fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => origin.isCurrent,
    );
  }

  Future<void> _inspectCreation(TransferJobRecord job) async {
    if (_busy) return;
    _control = FileOperationControl();
    setState(() {
      _busy = true;
      _error = null;
      _creationReview = null;
    });
    try {
      final definition = ArchiveCreationJobDefinition.fromJob(job);
      final source = _backend(job.source, definition.files.first.path!);
      final destination = _backend(
        job.destination,
        definition.destinationDirectory,
      );
      final review = await const ArchiveJobRecoveryService().prepareCreation(
        job,
        source: source,
        destination: destination,
        control: _control,
      );
      if (mounted) setState(() => _creationReview = review);
    } catch (error) {
      if (mounted) {
        setState(() => _error = archiveCreationError(context, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restartCreation(TransferJobRecord job) async {
    final review = _creationReview;
    if (_busy || review == null) return;
    final transfers = ref.read(transferProvider);
    setState(() {
      _busy = true;
      _admitting = true;
      _error = null;
    });
    try {
      if (review.alreadyPublished) {
        await transfers.confirmRecoveredArchiveCreation(
          job: job,
          review: review,
        );
      } else {
        final definition = review.definition;
        await transfers.enqueueArchiveCreation(
          source: review.source,
          destination: review.destination,
          files: definition.files,
          destinationDirectory: definition.destinationDirectory,
          options: definition.options(password: _password.text),
          recoveryJobId: job.id,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _error = archiveCreationError(context, error));
      }
    } finally {
      if (mounted) {
        _password.clear();
        setState(() {
          _busy = false;
          _admitting = false;
        });
      }
    }
  }

  Future<void> _restartWorkspace(
    TransferJobRecord job,
    ArchiveWorkspace workspace,
  ) async {
    if (_busy) return;
    final transfers = ref.read(transferProvider);
    setState(() {
      _busy = true;
      _admitting = true;
      _error = null;
    });
    try {
      await transfers.enqueueArchiveWorkspace(workspace, recoveryJobId: job.id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _admitting = false;
        });
      }
    }
  }

  Future<void> _reviewPublication(
    TransferJobRecord job,
    ArchiveWorkspace? workspace,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path =
          workspace?.outermost.file.path ??
          job.entries.firstOrNull?.source.path;
      if (path == null) {
        throw const FormatException('Invalid saved archive path.');
      }
      final backend =
          workspace?.outermost.source ?? _backend(job.destination, path);
      await showArchivePublicationRecoveryDialog(
        context,
        backend: backend,
        journal: workspace?.journal,
        containerPath: path,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String tr(String value) => context.commanderTr(value);
    final transfers = ref.watch(transferProvider);
    final job = transfers.savedJob(widget.jobId);
    final live = job != null && transfers.isJobLive(job.id);
    final kind = job?.entries.firstOrNull?.recovery['archiveKind'];
    final workspace = kind == 'workspace'
        ? transfers.archiveWorkspaceForJob(widget.jobId)
        : null;
    ArchiveCreationJobDefinition? definition;
    Object? recipeError;
    if (job != null && kind == 'create') {
      try {
        definition = ArchiveCreationJobDefinition.fromJob(job);
      } catch (error) {
        recipeError = error;
      }
    }
    final canReview =
        job != null && job.ready && !job.isFinished && !live && !_busy;
    final canSaveDraft =
        supportsArchiveWriterWorker &&
        canReview &&
        workspace != null &&
        workspace.isCurrent &&
        workspace.dirty &&
        workspace.pendingPublication == null;
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: SizedBox(
          width: math.min(680, size.width - 32),
          height: math.min(720, size.height - 48),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Archive job recovery'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      if (job == null || !isArchiveTransferJob(job))
                        Text(tr('This saved archive job is unavailable.'))
                      else ...[
                        Text(tr(transferStatusLabel(job.status))),
                        SelectableText(
                          '${job.sourceLabel} → ${job.destinationLabel}',
                        ),
                        SelectableText(job.targetDirectory),
                        const SizedBox(height: 12),
                        if (live)
                          Text(
                            tr(
                              'This archive is active in the operation queue. Use its pause or stop controls there.',
                            ),
                          ),
                        if (kind == 'create' && definition != null) ...[
                          SelectableText(definition.outputPath),
                          Text(
                            archiveCreationText(
                              context,
                              definition.format.label,
                            ),
                          ),
                          Text(
                            '${archiveCreationText(context, 'Compression')}: '
                            '${archiveCreationText(context, switch (definition.compression) {
                              ArchiveCreationCompression.none => 'Store (no compression)',
                              ArchiveCreationCompression.fast => 'Fast',
                              ArchiveCreationCompression.normal => 'Normal',
                              ArchiveCreationCompression.maximum => 'Maximum',
                              ArchiveCreationCompression.deflate => 'Deflate',
                              ArchiveCreationCompression.lzma2 => 'LZMA2',
                            })}',
                          ),
                          if (definition.encryptNames)
                            Text(
                              archiveCreationText(context, 'Hide filenames'),
                            ),
                          Text(
                            archiveCreationText(
                              context,
                              'Selected items: {0}',
                              [definition.files.length],
                            ),
                          ),
                          for (final file in definition.files)
                            Text(file.path ?? file.name),
                          const SizedBox(height: 12),
                          Text(
                            tr(
                              'Restarting packs a new private candidate from the original selection. An existing output is never replaced.',
                            ),
                          ),
                          if (_creationReview?.alreadyPublished == true) ...[
                            const SizedBox(height: 12),
                            Text(
                              tr(
                                'The published archive matches the saved receipt. Confirming completion verifies it again in the queue.',
                              ),
                            ),
                          ] else if (definition.passwordRequired) ...[
                            const SizedBox(height: 12),
                            Text(
                              tr(
                                'Passwords are not saved with queued jobs. Enter the original password again.',
                              ),
                            ),
                            TextField(
                              key: const ValueKey('archive-recovery-password'),
                              controller: _password,
                              enabled: !_busy && !live,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: archiveCreationText(
                                  context,
                                  'Password',
                                ),
                              ),
                            ),
                          ],
                        ] else if (kind == 'zipRecovery') ...[
                          Text(
                            archiveZipRecoveryText(
                              context,
                              'Scan the original ZIP again after restart. Saved digests and output receipts remain available in this job.',
                            ),
                          ),
                          SelectableText(job.entries.first.source.path ?? ''),
                          SelectableText(job.entries.first.destination),
                          SelectableText(
                            'Source SHA-256: ${job.entries.first.recovery['sourceSha256'] ?? ''}',
                          ),
                          if (job.entries.first.recovery['archivePublication']
                              case final Map receipt)
                            SelectableText(
                              'Output SHA-256: ${receipt['packedSha256'] ?? ''}\nPhase: ${receipt['phase'] ?? ''}',
                            ),
                        ] else if (kind == 'workspace') ...[
                          Text(
                            tr(
                              'Only publication recovery survives an app restart. Reopen the archive to create a new draft.',
                            ),
                          ),
                          if (workspace?.isCurrent == true) ...[
                            const SizedBox(height: 12),
                            Text(
                              tr(
                                'This session still has the unsaved draft. Review its changes before saving it in the background.',
                              ),
                            ),
                            SelectableText(
                              workspace!.outermost.file.path ??
                                  workspace.outermost.file.name,
                            ),
                            for (final change in workspace.draftChanges)
                              Text(
                                '${archiveEndpointText(context, change.kind.name)}: '
                                '${change.from == null ? '' : '${change.from} → '}${change.path}',
                              ),
                            const SizedBox(height: 12),
                            Text(
                              context.commanderTr(
                                'Publish these draft changes to {0} in the background? The original archive will be replaced only after packing and verification succeed.',
                                [
                                  workspace.outermost.file.path ??
                                      workspace.outermost.file.name,
                                ],
                              ),
                            ),
                          ],
                        ] else if (recipeError == null)
                          Text(
                            tr(
                              'This saved archive recipe is incomplete. Reopen its original sources.',
                            ),
                          ),
                        if (job.message != null) Text(job.message!),
                      ],
                      if (recipeError != null) Text('$recipeError'),
                      if (_busy) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        Text(
                          tr(
                            _admitting
                                ? archiveCreationText(
                                    context,
                                    'Queueing archive…',
                                  )
                                : _control.isCancelled
                                ? 'Cancelling'
                                : _control.isPaused
                                ? 'Paused'
                                : 'Checking original sources and destination…',
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          key: const ValueKey('archive-recovery-error'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (_busy && !_admitting && kind == 'create') ...[
                      TextButton(
                        onPressed: _control.isCancelled
                            ? null
                            : () => setState(() {
                                if (_control.isPaused) {
                                  _control.resume();
                                } else {
                                  _control.pause();
                                }
                              }),
                        child: Text(tr(_control.isPaused ? 'Resume' : 'Pause')),
                      ),
                      TextButton(
                        onPressed: _control.isCancelled
                            ? null
                            : () => setState(_control.cancel),
                        child: Text(tr('Stop')),
                      ),
                    ],
                    if (definition != null && canReview)
                      OutlinedButton(
                        key: const ValueKey('archive-recovery-inspect'),
                        onPressed: () => unawaited(_inspectCreation(job)),
                        child: Text(tr('Review original sources')),
                      ),
                    if ((supportsArchiveWriterWorker ||
                            _creationReview?.alreadyPublished == true) &&
                        canReview &&
                        _creationReview != null &&
                        kind == 'create')
                      FilledButton(
                        key: const ValueKey('archive-recovery-restart'),
                        onPressed: () => unawaited(_restartCreation(job)),
                        child: Text(
                          tr(
                            _creationReview!.alreadyPublished
                                ? 'Record recovered completion'
                                : 'Restart archive in background',
                          ),
                        ),
                      ),
                    if (canReview && kind == 'workspace')
                      OutlinedButton(
                        key: const ValueKey('archive-recovery-publication'),
                        onPressed: () =>
                            unawaited(_reviewPublication(job, workspace)),
                        child: Text(tr('Review publication recovery')),
                      ),
                    if (canSaveDraft)
                      FilledButton(
                        key: const ValueKey('archive-recovery-save-draft'),
                        onPressed: () =>
                            unawaited(_restartWorkspace(job, workspace)),
                        child: Text(tr('Save reviewed draft in background')),
                      ),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: Text(tr('Close')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
