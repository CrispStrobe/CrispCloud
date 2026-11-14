import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../l10n/archive_creation_strings.dart';
import '../l10n/archive_zip_recovery_strings.dart';
import '../l10n/transfer_error_strings.dart';
import '../models/archive_job.dart';
import '../models/operation_progress.dart';
import '../models/transfer_job.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart' show formatBytes, formatSpeed;
import 'transfer_history_dialog.dart';
import 'archive_job_recovery_dialog.dart';
import 'transfer_file_details.dart';
import 'transfer_schedule_dialog.dart';
import 'transfer_bandwidth_dialog.dart';

enum _QueueFilter { active, queued, attention, finished, all }

enum _JobState {
  running,
  queued,
  scheduled,
  paused,
  cancelling,
  waiting,
  needsReview,
  completed,
  cancelled,
}

/// Progress can be queued without active I/O; restored rows require review.
_JobState _stateOf(
  OperationProgress operation,
  TransferNotifier transfers, {
  required bool isQueued,
}) {
  final saved = transfers.savedJob(operation.id);
  final live = transfers.isJobLive(operation.id);
  if (operation.isCancelled) {
    return live ? _JobState.cancelling : _JobState.cancelled;
  }
  if (!live && saved?.status == TransferJobStatus.cancelled) {
    return _JobState.cancelled;
  }
  if (operation.isWaitingForDecision) return _JobState.waiting;
  // A cleanup/checkpoint warning must not turn an installed, verified archive
  // into a retryable failed operation.
  if (operation.status == OperationStatus.completed &&
      operation.type == OperationType.archive) {
    return _JobState.completed;
  }
  if (operation.error != null || operation.status == OperationStatus.failed) {
    return _JobState.needsReview;
  }
  if (operation.isComplete) return _JobState.completed;
  if (operation.isPaused) return _JobState.paused;
  if (isQueued) {
    final start = saved?.scheduledAt;
    return start != null && start.isAfter(DateTime.now())
        ? _JobState.scheduled
        : _JobState.queued;
  }
  return transfers.isRunning(operation.id)
      ? _JobState.running
      : _JobState.queued;
}

bool _canPause(_JobState state) => const {
  _JobState.running,
  _JobState.queued,
  _JobState.scheduled,
}.contains(state);

bool _canCancel(_JobState state) =>
    _canPause(state) || state == _JobState.paused || state == _JobState.waiting;

String _stateLabel(_JobState state) => switch (state) {
  _JobState.running => 'Running',
  _JobState.queued => 'Queued',
  _JobState.scheduled => 'Scheduled',
  _JobState.paused => 'Paused',
  _JobState.cancelling => 'Cancelling',
  _JobState.waiting => 'Waiting for a conflict decision',
  _JobState.needsReview => 'Needs review',
  _JobState.completed => 'Completed',
  _JobState.cancelled => 'Cancelled',
};

String _phaseText(BuildContext context, String phase) {
  final recovery = switch (phase) {
    'zipRecovery:scanning' => 'Scanning ZIP records…',
    'zipRecovery:recovering' => 'Recovering files…',
    'zipRecovery:verifying' => 'Verifying recovered ZIP…',
    'zipRecovery:publishing' => 'Saving new ZIP…',
    _ => null,
  };
  if (recovery != null) return archiveZipRecoveryText(context, recovery);
  final creation = switch (phase) {
    'archive:scanning' => 'Scanning selection…',
    'archive:packing' => 'Packing…',
    'archive:verifying' => 'Verifying archive…',
    'archive:saving' => 'Saving verified archive…',
    'archivePublication:prepared' ||
    'archivePublication:candidateWritten' ||
    'archivePublication:installing' ||
    'archivePublication:published' => 'Saving verified archive…',
    _ => null,
  };
  if (creation != null) return archiveCreationText(context, creation);
  return context.commanderTr(switch (phase) {
    'archivePublication:backingUp' ||
    'archivePublication:backedUp' => 'Preserving original archive…',
    'archivePublication:cleaningBackup' ||
    'archivePublication:cleaningCandidate' => 'Cleaning up…',
    'archivePublication:restoring' ||
    'archivePublication:restored' => 'Restoring original archive…',
    'archivePublication:complete' => 'Completed',
    'archivePublication:discarded' => 'Cancelled',
    'archivePublication:needsReview' => 'Needs review',
    _ => phase,
  });
}

class OperationsPanel extends ConsumerStatefulWidget {
  const OperationsPanel({super.key});

  @override
  ConsumerState<OperationsPanel> createState() => _OperationsPanelState();
}

class _OperationsPanelState extends ConsumerState<OperationsPanel> {
  final _searchController = TextEditingController();
  final _selectedIds = <String>{};
  String? _expandedOperationId;
  bool _isPanelExpanded = true;
  _QueueFilter _filter = _QueueFilter.all;
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _action(FutureOr<void> Function() run) async {
    try {
      await run();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  bool _matchesFilter(_JobState state, bool isQueued, _QueueFilter filter) {
    return switch (filter) {
      _QueueFilter.active =>
        _canPause(state) ||
            state == _JobState.paused ||
            state == _JobState.cancelling,
      _QueueFilter.queued => isQueued,
      _QueueFilter.attention =>
        state == _JobState.waiting || state == _JobState.needsReview,
      _QueueFilter.finished =>
        state == _JobState.completed || state == _JobState.cancelled,
      _QueueFilter.all => true,
    };
  }

  bool _matchesSearch(OperationProgress operation, TransferNotifier transfers) {
    if (_search.isEmpty) return true;
    final saved = transfers.savedJob(operation.id);
    if ([
      operation.fileName,
      operation.sourcePath,
      operation.targetPath,
      saved?.sourceLabel ?? '',
      saved?.destinationLabel ?? '',
    ].any((value) => value.toLowerCase().contains(_search))) {
      return true;
    }
    // Copy/move headers use a count and backend label, so the real member
    // names and paths must participate when searching a batch.
    if (operation.files?.any(
          (file) =>
              file.name.toLowerCase().contains(_search) ||
              file.path.toLowerCase().contains(_search),
        ) ==
        true) {
      return true;
    }
    return saved?.entries.any(
          (entry) => entry.destination.toLowerCase().contains(_search),
        ) ??
        false;
  }

  Future<void> _jobAction(
    TransferNotifier transfers,
    OperationProgress operation,
    String choice,
  ) => _action(() async {
    switch (choice) {
      case 'pause':
        transfers.pauseOperations([operation.id]);
      case 'resume':
        transfers.resumeOperations([operation.id]);
      case 'cancel':
        transfers.cancelOperations([operation.id]);
      case 'first':
        await transfers.moveQueuedFirst(operation.id);
      case 'last':
        await transfers.moveQueuedLast(operation.id);
      case 'high':
        await transfers.setPriority(operation.id, 10);
      case 'normal':
        await transfers.setPriority(operation.id, 0);
      case 'low':
        await transfers.setPriority(operation.id, -10);
      case 'schedule':
        final start = await showTransferStartPicker(
          context,
          initialValue: transfers.savedJob(operation.id)?.scheduledAt,
        );
        if (start != null && mounted) {
          await transfers.setScheduledStart(operation.id, start);
        }
      case 'now':
        await transfers.setScheduledStart(operation.id, null);
      case 'files':
        setState(() {
          _expandedOperationId = _expandedOperationId == operation.id
              ? null
              : operation.id;
        });
      case 'hide':
        transfers.removeOperation(operation.id);
        setState(() => _selectedIds.remove(operation.id));
    }
  });

  @override
  Widget build(BuildContext context) {
    final transfers = ref.watch(transferProvider);
    if (transfers.operations.isEmpty &&
        transfers.savedJobs.isEmpty &&
        transfers.recoveryError == null) {
      return const SizedBox.shrink();
    }

    final order = {
      for (final (index, id) in transfers.queuedIds.indexed) id: index,
    };
    final originalOrder = {
      for (final (index, operation) in transfers.operations.indexed)
        operation.id: index,
    };
    final operations = transfers.operations.toList()
      ..sort((a, b) {
        final ai = order[a.id];
        final bi = order[b.id];
        if (ai != null && bi != null) return ai.compareTo(bi);
        if (ai != null) return -1;
        if (bi != null) return 1;
        return originalOrder[a.id]!.compareTo(originalOrder[b.id]!);
      });
    // Build admission/status lookups once per update, rather than rescanning
    // the scheduler for each filter and selected row in a long queue.
    final states = {
      for (final operation in operations)
        operation.id: _stateOf(
          operation,
          transfers,
          isQueued: order.containsKey(operation.id),
        ),
    };
    final visible = operations
        .where(
          (operation) =>
              _matchesFilter(
                states[operation.id]!,
                order.containsKey(operation.id),
                _filter,
              ) &&
              _matchesSearch(operation, transfers),
        )
        .toList();
    final selected = operations
        .where((operation) => _selectedIds.contains(operation.id))
        .toList();
    final finished = operations.where((operation) {
      final state = states[operation.id]!;
      return state == _JobState.completed || state == _JobState.cancelled;
    }).toList();

    // Keep the browser usable when controls wrap on a narrow phone. The queue
    // and its file details remain lazy, within a bounded scrolling surface.
    final contentHeight = (MediaQuery.sizeOf(context).height * .48).clamp(
      180.0,
      420.0,
    );
    // Large text can make the complete status header taller than a phone's
    // remaining viewport. Keep its information in the same bounded scroll
    // area while the expansion control stays reachable.
    final scrollHeader =
        MediaQuery.sizeOf(context).width < 480 &&
        MediaQuery.textScalerOf(context).scale(16) > 24;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      child: ExpansionTile(
        key: const ValueKey('operations-panel'),
        title: scrollHeader
            ? Text(context.commanderTr('Operations'))
            : _buildPanelHeader(context, transfers),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        initiallyExpanded: true,
        onExpansionChanged: (expanded) =>
            setState(() => _isPanelExpanded = expanded),
        trailing: Icon(
          _isPanelExpanded ? Icons.expand_less : Icons.expand_more,
        ),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: contentHeight),
            child: CustomScrollView(
              key: const ValueKey('queue-scroll'),
              shrinkWrap: true,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (scrollHeader) _buildPanelHeader(context, transfers),
                        _buildQueueControls(context, transfers, finished, [
                          for (final operation in operations)
                            if (_canCancel(states[operation.id]!)) operation.id,
                        ]),
                        const TransferBandwidthTrafficSummary(),
                        const SizedBox(height: 4),
                        _buildFilters(context, operations, states, order),
                        const SizedBox(height: 6),
                        _buildSearch(context, visible),
                        if (selected.isNotEmpty)
                          _buildSelectionControls(
                            context,
                            transfers,
                            selected,
                            states,
                          ),
                        if (transfers.recoveryError != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              transfers.recoveryError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        operations.isEmpty
                            ? context.commanderTr(
                                'Open history to review saved transfers',
                              )
                            : context.commanderTr('No jobs match this view'),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final operation = visible[index];
                      final saved = transfers.savedJob(operation.id);
                      final isQueued = order.containsKey(operation.id);
                      return _OperationTile(
                        key: ValueKey('queue-job-${operation.id}'),
                        operation: operation,
                        savedEntries: saved?.entries ?? const [],
                        fileQuery: _search,
                        state: states[operation.id]!,
                        selected: _selectedIds.contains(operation.id),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _selectedIds.add(operation.id);
                          } else {
                            _selectedIds.remove(operation.id);
                          }
                        }),
                        isExpanded: _expandedOperationId == operation.id,
                        isQueued: isQueued,
                        priority: transfers.priorityOf(operation.id),
                        scheduledAt: saved?.scheduledAt,
                        canSchedule: isQueued && saved != null,
                        blockedReason: transfers.queueBlockedReason(
                          operation.id,
                        ),
                        onReview:
                            saved != null && !transfers.isJobLive(operation.id)
                            ? () => _action(
                                () => isArchiveTransferJob(saved)
                                    ? showArchiveJobRecoveryDialog(
                                        context,
                                        ref,
                                        jobId: operation.id,
                                      )
                                    : showTransferHistoryDialog(
                                        context,
                                        ref,
                                        jobId: operation.id,
                                        reviewOnOpen:
                                            operation.isWaitingForDecision,
                                      ),
                              )
                            : null,
                        onAction: (choice) =>
                            _jobAction(transfers, operation, choice),
                      );
                    }, childCount: visible.length),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader(BuildContext context, TransferNotifier transfers) {
    final summary = transfers.queueSummary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.commanderTr('Transfer queue · {0} jobs', [
              summary.totalJobs,
            ]),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 3,
            children: [
              if (summary.running > 0)
                Text(context.commanderTr('{0} running', [summary.running])),
              if (summary.queued > 0)
                Text(context.commanderTr('{0} queued', [summary.queued])),
              if (summary.scheduled > 0)
                Text(context.commanderTr('{0} scheduled', [summary.scheduled])),
              if (summary.paused > 0)
                Text(context.commanderTr('{0} paused', [summary.paused])),
              if (summary.cancelling > 0)
                Text(
                  context.commanderTr('{0} cancelling', [summary.cancelling]),
                ),
              if (summary.waiting > 0)
                Text(
                  context.commanderTr('{0} waiting for a decision', [
                    summary.waiting,
                  ]),
                ),
              if (summary.needsReview > 0)
                Text(
                  context.commanderTr('{0} need review', [summary.needsReview]),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (summary.completed > 0)
                Text(context.commanderTr('{0} completed', [summary.completed])),
              if (summary.cancelled > 0)
                Text(context.commanderTr('{0} cancelled', [summary.cancelled])),
              if (transfers.operations.isEmpty)
                Text(
                  context.commanderTr('Saved transfers: {0}', [
                    transfers.savedJobs.length,
                  ]),
                ),
            ],
          ),
          if (summary.liveJobs > summary.cancelling) ...[
            if (summary.totalBytes > 0 || summary.bytesPerSecond > 0) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 3,
                children: [
                  if (summary.totalBytes > 0)
                    Text(
                      '${formatBytes(summary.transferredBytes)} / '
                      '${formatBytes(summary.totalBytes)}',
                      key: const ValueKey('queue-byte-summary'),
                    ),
                  if (summary.bytesPerSecond > 0)
                    Text(
                      formatSpeed(summary.bytesPerSecond),
                      key: const ValueKey('queue-speed-summary'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            LinearProgressIndicator(
              key: const ValueKey('queue-overall-progress'),
              value: summary.progress ?? (summary.running > 0 ? null : 0.0),
            ),
          ],
          if (transfers.queuePaused) ...[
            const SizedBox(height: 4),
            Text(
              context.commanderTr('Queue paused. Running jobs may finish.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQueueControls(
    BuildContext context,
    TransferNotifier transfers,
    List<OperationProgress> finished,
    List<String> stoppableIds,
  ) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FilledButton.tonalIcon(
        key: const ValueKey('queue-pause'),
        onPressed: () =>
            _action(() => transfers.setQueuePaused(!transfers.queuePaused)),
        icon: Icon(transfers.queuePaused ? Icons.play_arrow : Icons.pause),
        label: Text(
          transfers.queuePaused
              ? context.commanderTr('Resume queue')
              : context.commanderTr('Pause queue'),
        ),
      ),
      TextButton.icon(
        key: const ValueKey('queue-stop-all'),
        onPressed: stoppableIds.isEmpty
            ? null
            : () => _action(() => transfers.cancelOperations(stoppableIds)),
        icon: const Icon(Icons.stop_circle_outlined),
        label: Text(context.commanderTr('Stop all')),
      ),
      TextButton.icon(
        onPressed: () => _action(() => showTransferHistoryDialog(context, ref)),
        icon: const Icon(Icons.history),
        label: Text(context.commanderTr('History and recovery')),
      ),
      const TransferBandwidthActionButton(),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(context.commanderTr('Parallel transfers')),
          DropdownButton<int>(
            key: const ValueKey('queue-concurrency'),
            value: transfers.maxConcurrent,
            items: [
              for (final limit in {
                if (transfers.maxConcurrent == 0) 0,
                1,
                2,
                3,
                4,
                6,
                8,
                12,
                16,
                transfers.maxConcurrent,
              }.toList()..sort())
                DropdownMenuItem(value: limit, child: Text('$limit')),
            ],
            onChanged: (limit) {
              if (limit != null) _action(() => transfers.setConcurrency(limit));
            },
          ),
        ],
      ),
      if (finished.isNotEmpty)
        TextButton.icon(
          onPressed: () => _action(() {
            transfers.clearFinishedOperations();
            for (final operation in finished) {
              _selectedIds.remove(operation.id);
            }
          }),
          icon: const Icon(Icons.clear_all),
          label: Text(context.commanderTr('Hide finished')),
        ),
    ],
  );

  Widget _buildFilters(
    BuildContext context,
    List<OperationProgress> operations,
    Map<String, _JobState> states,
    Map<String, int> queueOrder,
  ) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final filter in _QueueFilter.values)
        ChoiceChip(
          key: ValueKey('queue-filter-${filter.name}'),
          selected: _filter == filter,
          label: Text(
            '${context.commanderTr(switch (filter) {
              _QueueFilter.active => 'Active',
              _QueueFilter.queued => 'Queued',
              _QueueFilter.attention => 'Attention',
              _QueueFilter.finished => 'Finished',
              _QueueFilter.all => 'All',
            })} '
            '(${operations.where((op) => _matchesFilter(states[op.id]!, queueOrder.containsKey(op.id), filter)).length})',
          ),
          onSelected: (_) => setState(() => _filter = filter),
        ),
    ],
  );

  Widget _buildSearch(BuildContext context, List<OperationProgress> visible) {
    final selectedVisible = visible
        .where((operation) => _selectedIds.contains(operation.id))
        .length;
    return Row(
      children: [
        Tooltip(
          message: context.commanderTr('Select visible jobs'),
          child: Checkbox(
            key: const ValueKey('queue-select-visible'),
            tristate: true,
            value: selectedVisible == 0
                ? false
                : selectedVisible == visible.length
                ? true
                : null,
            onChanged: visible.isEmpty
                ? null
                : (_) => setState(() {
                    final ids = visible.map((operation) => operation.id);
                    if (selectedVisible == visible.length) {
                      _selectedIds.removeAll(ids);
                    } else {
                      _selectedIds.addAll(ids);
                    }
                  }),
          ),
        ),
        Expanded(
          child: TextField(
            key: const ValueKey('queue-search'),
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: context.commanderTr('Search jobs or paths'),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.commanderTr('Clear search'),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                    ),
            ),
            onChanged: (value) =>
                setState(() => _search = value.trim().toLowerCase()),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionControls(
    BuildContext context,
    TransferNotifier transfers,
    List<OperationProgress> selected,
    Map<String, _JobState> states,
  ) {
    final pausable = selected
        .where((op) => _canPause(states[op.id]!))
        .map((op) => op.id)
        .toList();
    final resumable = selected
        .where((op) => states[op.id] == _JobState.paused)
        .map((op) => op.id)
        .toList();
    final cancellable = selected
        .where((op) => _canCancel(states[op.id]!))
        .map((op) => op.id)
        .toList();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(context.commanderTr('{0} selected', [selected.length])),
          TextButton(
            onPressed: () => setState(_selectedIds.clear),
            child: Text(context.commanderTr('Clear selection')),
          ),
          TextButton.icon(
            key: const ValueKey('queue-pause-selected'),
            onPressed: pausable.isEmpty
                ? null
                : () => _action(() => transfers.pauseOperations(pausable)),
            icon: const Icon(Icons.pause),
            label: Text(context.commanderTr('Pause selected')),
          ),
          TextButton.icon(
            key: const ValueKey('queue-resume-selected'),
            onPressed: resumable.isEmpty
                ? null
                : () => _action(() => transfers.resumeOperations(resumable)),
            icon: const Icon(Icons.play_arrow),
            label: Text(context.commanderTr('Resume selected')),
          ),
          TextButton.icon(
            key: const ValueKey('queue-cancel-selected'),
            onPressed: cancellable.isEmpty
                ? null
                : () => _action(() {
                    transfers.cancelOperations(cancellable);
                    setState(() => _selectedIds.removeAll(cancellable));
                  }),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(context.commanderTr('Cancel selected')),
          ),
        ],
      ),
    );
  }
}

class _OperationTile extends StatelessWidget {
  const _OperationTile({
    super.key,
    required this.operation,
    required this.savedEntries,
    required this.fileQuery,
    required this.state,
    required this.selected,
    required this.onSelected,
    required this.isExpanded,
    required this.isQueued,
    required this.priority,
    required this.scheduledAt,
    required this.canSchedule,
    required this.blockedReason,
    required this.onReview,
    required this.onAction,
  });

  final OperationProgress operation;
  final List<TransferEntryRecord> savedEntries;
  final String fileQuery;
  final _JobState state;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final bool isExpanded;
  final bool isQueued;
  final int priority;
  final DateTime? scheduledAt;
  final bool canSchedule;
  final String? blockedReason;
  final VoidCallback? onReview;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = TransferErrorStrings(context);
    final error = strings.error(operation);
    final title =
        operation.isBatch &&
            operation.fileName == '${operation.totalFiles} files'
        ? strings.text('batchFiles', {'count': operation.totalFiles})
        : operation.fileName;
    final color = switch (state) {
      _JobState.needsReview => theme.colorScheme.error,
      _JobState.cancelled => theme.colorScheme.onSurfaceVariant,
      _JobState.cancelling => theme.colorScheme.onSurfaceVariant,
      _ => theme.colorScheme.primary,
    };
    final icon = switch (state) {
      _JobState.waiting => Icons.help_outline,
      _JobState.needsReview => Icons.error_outline,
      _JobState.cancelled => Icons.cancel_outlined,
      _JobState.cancelling => Icons.hourglass_top,
      _JobState.completed => Icons.check_circle_outline,
      _JobState.paused => Icons.pause_circle_outline,
      _JobState.scheduled => Icons.schedule,
      _JobState.queued => Icons.pending_outlined,
      _JobState.running => switch (operation.type) {
        OperationType.upload => Icons.upload,
        OperationType.download => Icons.download,
        OperationType.move => Icons.drive_file_move_outline,
        OperationType.copy => Icons.file_copy_outlined,
        OperationType.delete => Icons.delete_outline,
        OperationType.archive => Icons.archive_outlined,
      },
    };
    final live = _canPause(state) || state == _JobState.paused;
    final route = '${operation.sourcePath} → ${operation.targetPath}';
    final currentWork = [
      if (operation.phaseLabel != null)
        _phaseText(context, operation.phaseLabel!),
      if (operation.currentFilePath != null) operation.currentFilePath!,
    ].join(' · ');
    final localStart = scheduledAt?.toLocal();
    final startLabel = localStart == null
        ? null
        : '${MaterialLocalizations.of(context).formatCompactDate(localStart)} '
              '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(localStart), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? theme.colorScheme.secondaryContainer : null,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: .3)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Semantics(
                  label: context.commanderTr('Select {0}', [title]),
                  child: Checkbox(
                    key: ValueKey('queue-select-${operation.id}'),
                    value: selected,
                    onChanged: (value) => onSelected(value ?? false),
                  ),
                ),
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onReview != null)
                  IconButton(
                    icon: Icon(
                      state == _JobState.waiting ? Icons.rule : Icons.history,
                    ),
                    tooltip: state == _JobState.waiting
                        ? context.commanderTr('Resolve conflict')
                        : context.commanderTr('Review saved transfer'),
                    onPressed: onReview,
                  ),
                PopupMenuButton<String>(
                  key: ValueKey('queue-menu-${operation.id}'),
                  tooltip: context.commanderTr('Job actions'),
                  enabled: state != _JobState.cancelling || operation.isBatch,
                  onSelected: onAction,
                  itemBuilder: (context) => [
                    if (_canPause(state))
                      PopupMenuItem(
                        value: 'pause',
                        child: Text(context.commanderTr('Pause')),
                      ),
                    if (state == _JobState.paused)
                      PopupMenuItem(
                        value: 'resume',
                        child: Text(context.commanderTr('Resume')),
                      ),
                    if (isQueued && state != _JobState.cancelling) ...[
                      PopupMenuItem(
                        value: 'first',
                        child: Text(context.commanderTr('Run next')),
                      ),
                      PopupMenuItem(
                        value: 'last',
                        child: Text(context.commanderTr('Move to end')),
                      ),
                      if (canSchedule) ...[
                        PopupMenuItem(
                          value: 'schedule',
                          child: Text(context.commanderTr('Start later')),
                        ),
                        if (scheduledAt != null)
                          PopupMenuItem(
                            value: 'now',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.commanderTr('Run now')),
                                Text(
                                  context.commanderTr(
                                    'Removes the start time; queue controls still apply.',
                                  ),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                      ],
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'high',
                        child: Text(context.commanderTr('High priority')),
                      ),
                      PopupMenuItem(
                        value: 'normal',
                        child: Text(context.commanderTr('Normal priority')),
                      ),
                      PopupMenuItem(
                        value: 'low',
                        child: Text(context.commanderTr('Low priority')),
                      ),
                    ],
                    if (operation.isBatch)
                      PopupMenuItem(
                        value: 'files',
                        child: Text(
                          isExpanded
                              ? context.commanderTr('Hide files')
                              : context.commanderTr('Show files'),
                        ),
                      ),
                    if (_canCancel(state))
                      PopupMenuItem(
                        value: 'cancel',
                        child: Text(context.commanderTr('Cancel')),
                      )
                    else if (state != _JobState.cancelling)
                      PopupMenuItem(
                        value: 'hide',
                        child: Text(context.commanderTr('Hide from queue')),
                      ),
                  ],
                ),
              ],
            ),
            if (_canCancel(state))
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (_canPause(state))
                    TextButton.icon(
                      key: ValueKey('queue-pause-${operation.id}'),
                      onPressed: () => onAction('pause'),
                      icon: const Icon(Icons.pause),
                      label: Text(context.commanderTr('Pause')),
                    ),
                  if (state == _JobState.paused)
                    TextButton.icon(
                      key: ValueKey('queue-resume-${operation.id}'),
                      onPressed: () => onAction('resume'),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(context.commanderTr('Resume')),
                    ),
                  TextButton.icon(
                    key: ValueKey('queue-stop-${operation.id}'),
                    onPressed: () => onAction('cancel'),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(context.commanderTr('Stop')),
                  ),
                ],
              ),
            Tooltip(
              message: route,
              child: Text(
                route,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              runSpacing: 3,
              children: [
                Text(
                  context.commanderTr(_stateLabel(state)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isQueued)
                  Text(
                    context.commanderTr('Priority {0}', [priority]),
                    style: theme.textTheme.bodySmall,
                  ),
                if (operation.isBatch)
                  Text(
                    context.commanderTr('{0}/{1} items processed', [
                      operation.processedFiles,
                      operation.totalFiles,
                    ]),
                    style: theme.textTheme.bodySmall,
                  ),
                if (operation.skippedFiles > 0)
                  Text(
                    context.commanderTr('{0} skipped', [
                      operation.skippedFiles,
                    ]),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            if (live) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: operation.totalBytes > 0
                    ? operation.progress.clamp(0, 1)
                    : state == _JobState.running
                    ? null
                    : 0.0,
              ),
              if (operation.totalBytes > 0 ||
                  state == _JobState.running && operation.currentSpeed > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 3,
                    children: [
                      if (operation.totalBytes > 0)
                        Text(
                          '${formatBytes(operation.transferredBytes)} / '
                          '${formatBytes(operation.totalBytes)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      if (state == _JobState.running &&
                          operation.currentSpeed > 0)
                        Text(
                          formatSpeed(operation.currentSpeed),
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
            ],
            if ((state == _JobState.running || state == _JobState.paused) &&
                currentWork.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Tooltip(
                  message: currentWork,
                  child: Text(
                    currentWork,
                    key: ValueKey('queue-current-${operation.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            if (blockedReason != null && state != _JobState.cancelled)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.commanderTr(blockedReason!),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (startLabel != null && isQueued) ...[
              const SizedBox(height: 4),
              Text(
                context.commanderTr('Scheduled: {0}', [startLabel]),
                style: theme.textTheme.bodySmall,
              ),
              Text(
                context.commanderTr(
                  'Starts while CrispCloud is open. Restored jobs require review.',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (error != null && state == _JobState.needsReview)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Tooltip(
                  message: error,
                  child: Text(
                    error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (state == _JobState.completed &&
                operation.type == OperationType.archive &&
                operation.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  archiveCreationText(
                    context,
                    'The archive was created. Recovery information: {0}',
                    [operation.errorMessage],
                  ),
                  key: ValueKey('queue-publication-warning-${operation.id}'),
                ),
              ),
            if (isExpanded && operation.isBatch)
              TransferFileDetails(
                key: ValueKey('queue-file-details-${operation.id}'),
                operation: operation,
                savedEntries: savedEntries,
                initialQuery: fileQuery,
              ),
          ],
        ),
      ),
    );
  }
}
