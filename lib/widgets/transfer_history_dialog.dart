import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../models/storage_reference.dart';
import '../models/transfer_job.dart';
import '../providers/core_providers.dart';
import '../providers/panel_provider.dart';
import '../providers/transfer_provider.dart';
import '../services/file_operation_backend.dart';
import '../services/file_operation_service.dart';
import '../services/transfer_recovery_service.dart';
import '../utils/formatters.dart' show formatBytes;
import 'file_operation_conflict_dialog.dart';

Future<void> showTransferHistoryDialog(
  BuildContext context,
  WidgetRef ref, {
  String? jobId,
  bool reviewOnOpen = false,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) =>
      TransferHistoryDialog(jobId: jobId, reviewOnOpen: reviewOnOpen),
);

/// Review saved intents before reattaching live accounts. Opening this dialog
/// or starting the app never automatically resumes a destructive operation.
class TransferHistoryDialog extends ConsumerStatefulWidget {
  const TransferHistoryDialog({
    super.key,
    this.jobId,
    this.reviewOnOpen = false,
  });
  final String? jobId;
  final bool reviewOnOpen;

  @override
  ConsumerState<TransferHistoryDialog> createState() => _TransferHistoryState();
}

class _TransferHistoryState extends ConsumerState<TransferHistoryDialog> {
  String? _selected;
  TransferRecoveryMode _mode = TransferRecoveryMode.retryRemaining;
  TransferRecoveryPreview? _preview;
  PanelFileOrigin? _sourceOrigin;
  FileOperationBackend? _destination;
  FileOperationControl _control = FileOperationControl();
  final Set<int> _excluded = {};
  bool _busy = false;
  bool _running = false;
  int _checked = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.jobId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final transfers = ref.read(transferProvider);
      await transfers.refreshBackgroundRecovery();
      if (!mounted || !widget.reviewOnOpen || widget.jobId == null) return;
      final job = transfers.savedJob(widget.jobId!);
      if (job != null &&
          job.canRecover &&
          job.ready &&
          !job.isFinished &&
          !transfers.isJobLive(job.id)) {
        await _review(job);
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
      _preview = null;
      _sourceOrigin = null;
      _destination = null;
      _control = FileOperationControl();
      _excluded.clear();
      _error = null;
      _checked = 0;
    });
  }

  PanelFileOrigin _origin(StorageReference? storage, String path) {
    if (storage == null) {
      throw StateError(
        'This source is available only in its original session.',
      );
    }
    final origin = ref
        .read(panelProvider(PanelSide.local))
        .resolveStorageReference(storage, path);
    if (origin == null) {
      throw StateError(
        'Reconnect the original ${storage.isLocal ? 'local storage' : storage.provider} account and try again.',
      );
    }
    return origin;
  }

  FileOperationBackend _backend(PanelFileOrigin origin) => fileOperationBackend(
    source: origin.source,
    local: ref.read(localFileServiceProvider),
    isCurrent: () => origin.isCurrent,
  );

  Future<void> _review(TransferJobRecord job) async {
    if (_busy) return;
    _control = FileOperationControl();
    setState(() {
      _selected = job.id;
      _busy = true;
      _preview = null;
      _error = null;
      _checked = 0;
      _excluded.clear();
    });
    try {
      await ref.read(transferProvider).ready;
      _destination = _backend(_origin(job.destination, job.targetDirectory));
      final firstPath = job.entries.isEmpty
          ? job.targetDirectory
          : job.entries.first.source.path!;
      final source = _origin(job.source, firstPath);
      _sourceOrigin = source;
      final preview = await const TransferRecoveryService().prepare(
        job,
        source: _backend(source),
        destination: _destination!,
        control: _control,
        mode: _mode,
        onProgress: (count, _) {
          if (mounted) setState(() => _checked = count);
        },
      );
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<FileConflictResolution> _resolve(
    FileOperationEntry entry,
    FileItem existing,
  ) async {
    if (!mounted || _preview == null) {
      return const FileConflictResolution(FileConflictDecision.cancel);
    }
    return showFileOperationConflict(
      context,
      entry: entry,
      existing: existing,
      source: _preview!.plan.source,
      destination: _preview!.plan.destination,
    );
  }

  Future<void> _run(TransferJobRecord job) async {
    final preview = _preview;
    final origin = _sourceOrigin;
    if (_busy || preview == null || origin == null) return;
    final plan = preview.excluding(_excluded);
    if (plan.errors.isNotEmpty) return;
    setState(() {
      _busy = true;
      _running = true;
      _error = null;
    });
    try {
      await ref
          .read(transferProvider)
          .runFileOperation(
            plan,
            recoveryJobId: job.id,
            control: _control,
            resolveDetailedConflict: _resolve,
            onEntryComplete: (entry) {
              if (entry.outcome == FileOperationOutcome.moved) {
                for (final side in PanelSide.values) {
                  ref.read(panelProvider(side)).applyFileListChanges({
                    entry.source.path!: null,
                  }, origin: origin);
                }
              }
              if (mounted) setState(() {});
            },
          );
      if (mounted) {
        for (final side in PanelSide.values) {
          await ref.read(panelProvider(side)).refresh();
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _running = false;
          _preview = null;
        });
      }
    }
  }

  Future<void> _restoreBackup(TransferJobRecord job, int index) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final destination =
          _destination ??
          _backend(_origin(job.destination, job.targetDirectory));
      await ref
          .read(transferProvider)
          .restoreSavedBackup(
            job.id,
            index,
            destination,
            FileOperationControl(),
          );
      if (mounted) setState(() => _preview = null);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(TransferJobRecord job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.commanderTr("Remove saved transfer?")),
        content: Text(
          context.commanderTr(
            "This removes its recovery instructions and history. Files and saved staging or backup copies stay where they are.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.commanderTr("Keep history")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.commanderTr("Remove history entry")),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(transferProvider).dismissSavedJob(job.id);
      if (mounted) _select(null);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final transfers = ref.watch(transferProvider);
    final jobs = transfers.savedJobs;
    final chosen = jobs.where((job) => job.id == _selected).firstOrNull;
    final job =
        chosen ??
        jobs.where((job) => job.needsReview).firstOrNull ??
        jobs.firstOrNull;
    final live = job != null && transfers.isJobLive(job.id);
    final preview = _preview;
    final remainingIssues =
        preview?.issues.keys
            .where((index) => !_excluded.contains(index))
            .length ??
        0;
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: SizedBox(
          width: math.min(1080, size.width - 40),
          height: math.min(800, size.height - 56),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.commanderTr("Transfer history and recovery"),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      tooltip: context.commanderTr("Close"),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (transfers.recoveryError != null)
                  _notice(transfers.recoveryError!, error: true),
                if (transfers.recoveryWarnings.isNotEmpty)
                  Tooltip(
                    message: transfers.recoveryWarnings.join('\n'),
                    child: Text(
                      context.commanderTr(
                        "History recovered an incomplete last checkpoint. The previous journal was retained.",
                      ),
                    ),
                  ),
                if (jobs.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        context.commanderTr(
                          "Reviewed copy and move jobs appear here, including every file and its result.",
                        ),
                      ),
                    ),
                  ),
                if (job != null) ...[
                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        SliverList.list(
                          children: [
                            DropdownButtonFormField<String>(
                              key: ValueKey(job.id),
                              initialValue: job.id,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: context.commanderTr(
                                  "Saved transfer",
                                ),
                              ),
                              items: jobs
                                  .map(
                                    (saved) => DropdownMenuItem(
                                      value: saved.id,
                                      child: Text(
                                        '${saved.created.toLocal().toString().split('.').first} · ${context.commanderEnum(saved.options.kind)} · ${saved.sourceLabel} → ${saved.destinationLabel} · ${context.commanderTr(transferStatusLabel(saved.status))}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _busy ? null : _select,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              context.commanderTr(
                                "{0} of {1} items saved · {2}",
                                [
                                  job.entries.length,
                                  job.expectedEntries,
                                  context.commanderTr(
                                    transferStatusLabel(job.status),
                                  ),
                                ],
                              ),
                            ),
                            SelectableText(
                              '${job.sourceLabel} → ${job.destinationLabel}: ${job.targetDirectory}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (!job.canRecover)
                              _notice(
                                'This transfer used a temporary source or browser handle. Reopen that source to create a new plan; its saved results remain available below.',
                              ),
                            if (!job.ready)
                              _notice(
                                'Saving this plan was interrupted before any queued file actions started. Create a new plan from the selected sources.',
                              ),
                            if (live && !_running)
                              _notice(
                                'This transfer is active in the queue. Pause or cancel it in the operations panel before reviewing recovery.',
                              ),
                            if (job.message != null)
                              Text(
                                job.message!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (job.canRecover &&
                                job.ready &&
                                !job.isFinished &&
                                !live) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SizedBox(
                                    width: math.min(430, size.width - 128),
                                    child:
                                        DropdownButtonFormField<
                                          TransferRecoveryMode
                                        >(
                                          initialValue: _mode,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            labelText: context.commanderTr(
                                              "Recovery action",
                                            ),
                                          ),
                                          items: [
                                            DropdownMenuItem(
                                              value: TransferRecoveryMode
                                                  .retryRemaining,
                                              child: Text(
                                                context.commanderTr(
                                                  "Resume / retry remaining",
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: TransferRecoveryMode
                                                  .restartIncomplete,
                                              child: Text(
                                                context.commanderTr(
                                                  "Restart incomplete",
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                          onChanged: _busy
                                              ? null
                                              : (value) {
                                                  if (value == null) return;
                                                  _select(job.id);
                                                  setState(() => _mode = value);
                                                },
                                        ),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: _busy
                                        ? null
                                        : () => _review(job),
                                    icon: const Icon(Icons.fact_check_outlined),
                                    label: Text(
                                      context.commanderTr("Review saved plan"),
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _mode == TransferRecoveryMode.retryRemaining
                                      ? context.commanderTr(
                                          "Verify original accounts and file contents, reuse confirmed copies, and resume matching staged bytes.",
                                        )
                                      : context.commanderTr(
                                          "Keep completed items. Re-copy incomplete items and ask again before replacing an occupied destination.",
                                        ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                            if (_busy) ...[
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: !_running && job.expectedEntries > 0
                                    ? _checked / job.expectedEntries
                                    : null,
                              ),
                              Text(
                                _running
                                    ? context.commanderTr(
                                        "Running the reviewed transfer…",
                                      )
                                    : context.commanderTr(
                                        "Checking {0} of {1} items…",
                                        [_checked, job.expectedEntries],
                                      ),
                              ),
                            ],
                            if (_error != null) _notice(_error!, error: true),
                            if (remainingIssues > 0)
                              _notice(
                                '$remainingIssues item(s) need attention. Resolve the changes and review again, or explicitly exclude those items below.',
                                error: true,
                              ),
                            const SizedBox(height: 8),
                            const Divider(height: 1),
                          ],
                        ),
                        SliverList.builder(
                          itemCount: job.entries.length,
                          itemBuilder: (context, index) =>
                              _row(job, index, live),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _busy || live ? null : () => _remove(job),
                        child: Text(
                          context.commanderTr("Remove history entry"),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                try {
                                  await transfers.clearSavedCompleted();
                                  if (mounted) _select(null);
                                } catch (error) {
                                  if (mounted) {
                                    setState(() => _error = '$error');
                                  }
                                }
                              },
                        child: Text(
                          context.commanderTr("Clear completed history"),
                        ),
                      ),
                      if (_busy)
                        OutlinedButton(
                          onPressed: _control.cancel,
                          child: Text(context.commanderTr("Stop")),
                        ),
                      if (preview != null && !_busy && !live)
                        FilledButton.icon(
                          onPressed: remainingIssues == 0
                              ? () => _run(job)
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            preview
                                    .excluding(_excluded)
                                    .entries
                                    .any(
                                      (entry) =>
                                          entry.outcome ==
                                          FileOperationOutcome.pending,
                                    )
                                ? context.commanderTr(
                                    job.status ==
                                            TransferJobStatus.waitingForDecision
                                        ? "Resolve conflicts and continue"
                                        : "Run reviewed remaining items",
                                  )
                                : context.commanderTr(
                                    "Record recovered completion",
                                  ),
                          ),
                        ),
                      TextButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: Text(context.commanderTr("Close")),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(String message, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      message,
      style: TextStyle(
        color: error ? Theme.of(context).colorScheme.error : null,
      ),
    ),
  );

  Widget _row(TransferJobRecord job, int index, bool live) {
    final saved = job.entries[index];
    final preview = _preview;
    final row = preview?.plan.entries[index];
    final issue = preview?.issues[index];
    final excluded = _excluded.contains(index);
    final backup =
        saved.recovery['backupPath'] ?? saved.recovery['renamedExistingPath'];
    final staged = saved.recovery['stagedPath'];
    final action =
        preview?.actions[index] ??
        saved.message ??
        context.commanderEnum(saved.outcome);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preview != null && !_running)
            Checkbox(
              value: excluded,
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      if (value == true) {
                        _excluded.add(index);
                      } else {
                        _excluded.remove(index);
                      }
                    }),
              semanticLabel: context.commanderTr("Exclude {0} from recovery", [
                saved.source.name,
              ]),
            )
          else
            Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                saved.source.isFolder
                    ? Icons.folder_outlined
                    : Icons.insert_drive_file_outlined,
                size: 20,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  '${saved.source.path} → ${row?.destination ?? saved.destination}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  excluded
                      ? context.commanderTr("Excluded from this recovery")
                      : issue ?? action,
                  style: TextStyle(
                    color: issue != null && !excluded
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
                if (saved.source.size != null)
                  Text(
                    formatBytes(saved.source.size!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (staged != null)
                  SelectableText(
                    context.commanderTr("Saved staging file: {0}", [staged]),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (backup != null)
                  SelectableText(
                    context.commanderTr("Recovery copy: {0}", [backup]),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (backup != null &&
              saved.recovery['backupSha256'] != null &&
              saved.phase != 'backupRestored')
            TextButton(
              onPressed: _busy || live
                  ? null
                  : () => _restoreBackup(job, index),
              child: Text(context.commanderTr("Restore backup")),
            ),
        ],
      ),
    );
  }
}
