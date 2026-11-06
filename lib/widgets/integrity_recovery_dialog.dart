import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/integrity_recovery.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../models/transfer_job.dart';
import '../providers/core_providers.dart';
import '../providers/panel_provider.dart';
import '../providers/transfer_provider.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/integrity_recovery_service.dart';
import '../services/transfer_journal.dart';
import '../utils/formatters.dart';
import 'commander_review_dialog.dart';

Future<void> showIntegrityRecoveryDialog(
  BuildContext context,
  WidgetRef ref, {
  String? jobId,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => IntegrityRecoveryDialog(jobId: jobId),
);

class IntegrityRecoveryDialog extends ConsumerStatefulWidget {
  const IntegrityRecoveryDialog({super.key, this.jobId});
  final String? jobId;
  @override
  ConsumerState<IntegrityRecoveryDialog> createState() =>
      _IntegrityRecoveryState();
}

class _IntegrityRecoveryState extends ConsumerState<IntegrityRecoveryDialog> {
  String? _selected;
  IntegrityRecoveryReview? _review;
  FileOperationBackend? _source;
  FileOperationBackend? _destination;
  FileOperationControl _control = FileOperationControl();
  bool _loading = true;
  bool _busy = false;
  bool _executing = false;
  String? _error;
  int _bytes = 0;
  int _total = 0;
  IntegrityRecoveryService get _service =>
      IntegrityRecoveryService(ref.read(transferJournalProvider));

  @override
  void initState() {
    super.initState();
    _selected = widget.jobId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(transferProvider).refreshIntegrityHistory();
      } catch (error) {
        if (mounted) setState(() => _error = '$error');
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _control.cancel();
    super.dispose();
  }

  void _select(String? id) {
    if (_busy) return;
    _control.cancel();
    setState(() {
      _selected = id;
      _review = null;
      _source = null;
      _destination = null;
      _error = null;
      _bytes = _total = 0;
    });
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
      isCurrent: () => mounted && origin.isCurrent,
    );
  }

  void _progress(String _, int bytes, int total) {
    if (mounted) {
      setState(() {
        _bytes = bytes;
        _total = total;
      });
    }
  }

  Future<void> _refreshHistory() async {
    if (!mounted) return;
    try {
      await ref.read(transferProvider).refreshIntegrityHistory();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _inspect(TransferJobRecord job) async {
    if (_busy || _loading) return;
    _control = FileOperationControl();
    setState(() {
      _selected = job.id;
      _busy = true;
      _executing = false;
      _error = null;
      _review = null;
      _bytes = _total = 0;
    });
    try {
      _source = _backend(job.source, job.entries.first.source.path!);
      _destination = _backend(job.destination, job.targetDirectory);
      final review = await _service.review(
        job.id,
        source: _source!,
        destination: _destination!,
        control: _control,
        onProgress: _progress,
      );
      if (mounted) setState(() => _review = review);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continue() async {
    final review = _review;
    final source = _source;
    final destination = _destination;
    if (review == null ||
        source == null ||
        destination == null ||
        _busy ||
        _loading) {
      return;
    }
    _control = FileOperationControl();
    setState(() {
      _busy = true;
      _executing = true;
      _error = null;
      _bytes = _total = 0;
    });
    var completed = false;
    try {
      final running = _service.resume(
        review,
        source: source,
        destination: destination,
        control: _control,
        onProgress: _progress,
      );
      unawaited(_refreshHistory());
      await running;
      completed = true;
      if (mounted) {
        setState(() => _review = null);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _review = null;
        });
      }
    } finally {
      await _refreshHistory();
      if (mounted) {
        setState(() {
          _busy = false;
          _executing = false;
        });
      }
    }
    if (completed && mounted) {
      // Listing failures cannot turn a verified, durably completed operation
      // into a failed job. Release the dialog controls before refreshing.
      for (final side in PanelSide.values) {
        if (!mounted) break;
        try {
          await ref.read(panelProvider(side)).refresh();
        } catch (error) {
          if (mounted) {
            setState(() {
              _error = context.commanderTr(
                'Recovery completed, but a file panel could not be refreshed: {0}',
                ['$error'],
              );
            });
          }
        }
      }
    }
  }

  Future<void> _forget(TransferJobRecord job) async {
    if (_busy || _loading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.commanderTr('Forget integrity recovery?')),
        content: Text(
          context.commanderTr(
            'Only the saved recovery instructions are removed. Original files, parts, manifests, output and staging files are kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.commanderTr('Keep history')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.commanderTr('Forget recovery, keep files')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.forget(job.id);
      if (mounted) {
        _select(null);
        await _refreshHistory();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  String _resumeLabel(IntegrityRecoveryReview review) {
    if (review.definition.kind == IntegrityOperationKind.split) {
      return context.commanderTr('Resume missing split parts');
    }
    if (review.reconcilesOutput) {
      return context.commanderTr('Record verified completion');
    }
    return context.commanderTr('Restart combine from verified inputs');
  }

  @override
  Widget build(BuildContext context) {
    final transfers = ref.watch(transferProvider);
    final jobs = ref
        .read(transferJournalProvider)
        .jobs
        .where(IntegrityRecoveryService.isIntegrityJob)
        .toList();
    final job =
        jobs.where((job) => job.id == _selected).firstOrNull ??
        jobs.where((job) => job.needsReview).firstOrNull ??
        jobs.firstOrNull;
    final active = job != null && transfers.isJobLive(job.id);
    final review = _review?.jobId == job?.id ? _review : null;
    return PopScope(
      canPop: !_busy,
      child: CommanderReviewDialog(
        title: context.commanderTr('Split/combine recovery'),
        width: 720,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.commanderTr(
                    'Recovery checks the original accounts, source bytes, manifests and outputs before writing.',
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator(),
                if (transfers.recoveryError != null)
                  Text(
                    transfers.recoveryError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (transfers.recoveryWarnings.isNotEmpty)
                  Tooltip(
                    message: transfers.recoveryWarnings.join('\n'),
                    child: Text(
                      context.commanderTr(
                        'History recovered an incomplete last checkpoint. The previous journal was retained.',
                      ),
                    ),
                  ),
                if (!_loading &&
                    jobs.isEmpty &&
                    transfers.recoveryError == null &&
                    _error == null)
                  Text(
                    context.commanderTr(
                      'No saved split or combine operations.',
                    ),
                  ),
                if (job != null) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(job.id),
                    initialValue: job.id,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.commanderTr('Saved operation'),
                    ),
                    items: [
                      for (final saved in jobs)
                        DropdownMenuItem(
                          value: saved.id,
                          child: Text(
                            '${saved.sourceLabel} → ${saved.destinationLabel} · '
                            '${saved.entries.firstOrNull?.destination ?? saved.targetDirectory}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy ? null : _select,
                  ),
                  const SizedBox(height: 10),
                  Text(context.commanderTr(transferStatusLabel(job.status))),
                  SelectableText(
                    '${job.sourceLabel} → ${job.destinationLabel}: ${job.targetDirectory}',
                  ),
                  if (!job.ready)
                    Text(
                      context.commanderTr(
                        'Saving the recovery plan was interrupted before output writes. Start a new reviewed operation.',
                      ),
                    ),
                  if (!job.canRecover)
                    Text(
                      context.commanderTr(
                        'The original storage cannot be restored after restart. Files were retained.',
                      ),
                    ),
                  if (active && !_busy)
                    Text(
                      context.commanderTr('This operation is already active.'),
                    ),
                  if (job.message != null) SelectableText(job.message!),
                  if (review != null) ...[
                    const Divider(),
                    if (review.definition.kind == IntegrityOperationKind.split)
                      Text(
                        context.commanderTr(
                          '{0} of {1} parts verified. Only missing parts will be written.',
                          [
                            review.verifiedParts,
                            review.definition.parts.length,
                          ],
                        ),
                      )
                    else if (review.reconcilesOutput)
                      Text(
                        context.commanderTr(
                          'A matching completed output was found. Its completion can be recorded without another copy.',
                        ),
                      )
                    else
                      Text(
                        context.commanderTr(
                          'The output is absent. Unfinished combination will restart from verified inputs; retained stages stay untouched.',
                        ),
                      ),
                    if (review.retainedPaths.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(context.commanderTr('Retained recovery files')),
                      SizedBox(
                        height: math.min(
                          160,
                          review.retainedPaths.length * 32.0,
                        ),
                        child: ListView.builder(
                          itemCount: review.retainedPaths.length,
                          itemBuilder: (_, index) =>
                              SelectableText(review.retainedPaths[index]),
                        ),
                      ),
                    ],
                  ],
                ],
                if (_busy) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _total > 0
                        ? (_bytes / _total).clamp(0.0, 1.0)
                        : null,
                  ),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _executing
                          ? context.commanderTr(
                              'Running reviewed recovery… {0} / {1}',
                              [formatBytes(_bytes), formatBytes(_total)],
                            )
                          : context.commanderTr(
                              'Verifying recovery… {0} / {1}',
                              [formatBytes(_bytes), formatBytes(_total)],
                            ),
                    ),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  context.commanderTr(
                    'Unverified existing files are preserved. To restart with a new destination or name, open Split or Combine again.',
                  ),
                ),
              ],
            ),
          ),
        ],
        actions: [
          if (_busy)
            TextButton(
              onPressed: _control.cancel,
              child: Text(context.commanderTr('Cancel operation')),
            )
          else ...[
            if (job != null)
              TextButton(
                onPressed: active ? null : () => _forget(job),
                child: Text(context.commanderTr('Forget recovery, keep files')),
              ),
            if (job != null && job.ready && job.canRecover && !job.isFinished)
              OutlinedButton(
                onPressed: active ? null : () => _inspect(job),
                child: Text(context.commanderTr('Review integrity recovery')),
              ),
            if (review != null && job != null && !job.isFinished)
              FilledButton(
                onPressed: active ? null : _continue,
                child: Text(_resumeLabel(review)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.commanderTr('Close')),
            ),
          ],
        ],
      ),
    );
  }
}
