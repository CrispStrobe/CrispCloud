// widgets/operations_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/commander_strings.dart';
import '../models/operation_progress.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart' show formatBytes, formatSpeed;
import 'transfer_history_dialog.dart';

class OperationsPanel extends ConsumerStatefulWidget {
  const OperationsPanel({super.key});

  @override
  ConsumerState<OperationsPanel> createState() => _OperationsPanelState();
}

class _OperationsPanelState extends ConsumerState<OperationsPanel> {
  String? _expandedOperationId;
  bool _isPanelExpanded = true;

  @override
  Widget build(BuildContext context) {
    final transfers = ref.watch(transferProvider);

    if (transfers.operations.isEmpty &&
        transfers.savedJobs.isEmpty &&
        transfers.recoveryError == null) {
      return const SizedBox.shrink();
    }

    final order = transfers.queuedIds;
    final operations = transfers.operations.toList()
      ..sort((a, b) {
        final ai = order.indexOf(a.id);
        final bi = order.indexOf(b.id);
        if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
        if (ai >= 0) return -1;
        if (bi >= 0) return 1;
        return 0;
      });
    Future<void> action(Future<void> Function() run) async {
      try {
        await run();
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }

    int totalBytes = 0;
    int transferredBytes = 0;
    int activeCount = 0;
    int completeCount = 0;
    int errorCount = 0;
    int waitingCount = 0;

    for (final op in transfers.operations) {
      totalBytes += op.totalBytes;
      transferredBytes += op.transferredBytes;
      if (op.isWaitingForDecision) {
        waitingCount++;
      } else if (op.isCancelled) {
        errorCount++;
      } else if (op.error != null) {
        errorCount++;
      } else if (op.isComplete) {
        completeCount++;
      } else {
        activeCount++;
      }
    }

    final overallProgress = totalBytes > 0
        ? transferredBytes / totalBytes
        : 0.0;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      child: ExpansionTile(
        title: _buildPanelHeader(
          context,
          transfers,
          activeCount,
          completeCount,
          errorCount,
          waitingCount,
          overallProgress,
          transferredBytes,
          totalBytes,
        ),
        initiallyExpanded: true,
        onExpansionChanged: (isExpanded) =>
            setState(() => _isPanelExpanded = isExpanded),
        trailing: Icon(
          _isPanelExpanded ? Icons.expand_less : Icons.expand_more,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => showTransferHistoryDialog(context, ref),
                  icon: const Icon(Icons.history),
                  label: const Text('History and recovery'),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Parallel transfers: '),
                    DropdownButton<int>(
                      value: transfers.maxConcurrent,
                      items: [
                        for (final limit in {
                          0,
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
                          DropdownMenuItem(
                            value: limit,
                            child: Text(limit == 0 ? 'Queue only' : '$limit'),
                          ),
                      ],
                      onChanged: (limit) {
                        if (limit != null) {
                          action(() => transfers.setConcurrency(limit));
                        }
                      },
                    ),
                  ],
                ),
                if (activeCount > 0)
                  TextButton.icon(
                    onPressed: transfers.cancelAllOperations,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Cancel active'),
                  ),
                if (completeCount > 0 || errorCount > 0)
                  TextButton.icon(
                    onPressed: transfers.clearCompletedOperations,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Hide finished'),
                  ),
              ],
            ),
          ),
          if (transfers.recoveryError != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                transfers.recoveryError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxHeight: 250),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: operations.length,
              itemBuilder: (context, index) {
                final op = operations[index];
                final isExpanded = _expandedOperationId == op.id;
                return _OperationTile(
                  operation: op,
                  statusLabel:
                      transfers.isQueued(op.id) ||
                          op.isComplete ||
                          op.isWaitingForDecision
                      ? transfers.statusLabel(op.id)
                      : null,
                  onReview:
                      transfers.savedJob(op.id) != null &&
                          !transfers.isJobLive(op.id)
                      ? () => showTransferHistoryDialog(
                          context,
                          ref,
                          jobId: op.id,
                          reviewOnOpen: op.isWaitingForDecision,
                        )
                      : null,
                  onQueueAction: transfers.isQueued(op.id)
                      ? (choice) => action(() async {
                          switch (choice) {
                            case 'first':
                              await transfers.moveQueuedFirst(op.id);
                            case 'last':
                              await transfers.moveQueuedLast(op.id);
                            case 'high':
                              await transfers.setPriority(op.id, 10);
                            case 'normal':
                              await transfers.setPriority(op.id, 0);
                            case 'low':
                              await transfers.setPriority(op.id, -10);
                          }
                        })
                      : null,
                  isExpanded: isExpanded,
                  onToggleExpanded: () => setState(() {
                    _expandedOperationId = isExpanded ? null : op.id;
                  }),
                  onRemove: () => transfers.removeOperation(op.id),
                  onCancel: !op.isComplete && !op.isCancelled
                      ? () => transfers.cancelOperation(op.id)
                      : null,
                  onPause: () => transfers.pauseOperation(op.id),
                  onResume: () => transfers.resumeOperation(op.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeader(
    BuildContext context,
    TransferNotifier transfers,
    int activeCount,
    int completeCount,
    int errorCount,
    int waitingCount,
    double overallProgress,
    int transferredBytes,
    int totalBytes,
  ) {
    final speed = transfers.operations
        .where((op) => op.isActive)
        .fold<double>(0, (sum, op) => sum + op.currentSpeed);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${transfers.operations.length} operation(s) · ${transfers.queuedCount} queued',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (activeCount > 0)
                Text(
                  '${formatBytes(transferredBytes)} / ${formatBytes(totalBytes)}',
                ),
              if (speed > 0) Text(formatSpeed(speed)),
              if (completeCount > 0)
                Text(
                  '$completeCount complete',
                  style: TextStyle(color: Colors.green[700]),
                ),
              if (errorCount > 0)
                Text(
                  '$errorCount need review',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (waitingCount > 0)
                Text(
                  context.commanderTr("{0} waiting for a decision", [
                    waitingCount,
                  ]),
                ),
              if (transfers.operations.isEmpty)
                Text('${transfers.savedJobs.length} saved transfer(s)'),
            ],
          ),
          if (activeCount > 0) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: overallProgress.clamp(0, 1)),
          ],
        ],
      ),
    );
  }
}

class _OperationTile extends StatelessWidget {
  final OperationProgress operation;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onRemove;
  final VoidCallback? onCancel;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final String? statusLabel;
  final VoidCallback? onReview;
  final void Function(String)? onQueueAction;

  const _OperationTile({
    required this.operation,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onRemove,
    this.onCancel,
    required this.onPause,
    required this.onResume,
    this.statusLabel,
    this.onReview,
    this.onQueueAction,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color? color;

    if (operation.isWaitingForDecision) {
      icon = Icons.help_outline;
      color = Theme.of(context).colorScheme.primary;
    } else if (operation.isCancelled) {
      icon = Icons.cancel;
      color = Colors.orange;
    } else if (operation.isPaused) {
      icon = Icons.pause_circle;
      color = Colors.blue;
    } else if (operation.error != null) {
      icon = Icons.error;
      color = Theme.of(context).colorScheme.error;
    } else if (operation.isComplete) {
      icon = Icons.check_circle;
      color = Colors.green;
    } else {
      icon = operation.type == OperationType.upload
          ? Icons.upload
          : Icons.download;
      color = Theme.of(context).colorScheme.primary;
    }

    return Column(
      children: [
        ListTile(
          dense: true,
          leading: Icon(icon, size: 20, color: color),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  operation.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (operation.isBatch) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${operation.completedFiles}/${operation.totalFiles} files',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (operation.isActive &&
                  operation.error == null &&
                  !operation.isCancelled)
                LinearProgressIndicator(
                  value: operation.progress.clamp(0, 1),
                  backgroundColor: Colors.grey[300],
                ),
              const SizedBox(height: 2),
              Text(
                operation.isCancelled
                    ? 'Cancelled'
                    : operation.isPaused
                    ? 'Paused'
                    : statusLabel ??
                          operation.error ??
                          _getStatusText(operation),
                style: TextStyle(
                  fontSize: 11,
                  color: operation.error != null
                      ? Colors.red
                      : operation.isCancelled
                      ? Colors.orange
                      : operation.isPaused
                      ? Colors.blue
                      : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onReview != null)
                IconButton(
                  icon: Icon(
                    operation.isWaitingForDecision ? Icons.rule : Icons.history,
                    size: 20,
                  ),
                  tooltip: operation.isWaitingForDecision
                      ? context.commanderTr("Resolve conflict")
                      : 'Review saved transfer',
                  onPressed: onReview,
                ),
              if (onQueueAction != null)
                PopupMenuButton<String>(
                  tooltip: 'Queue order and priority',
                  onSelected: onQueueAction,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'first', child: Text('Run next')),
                    PopupMenuItem(value: 'last', child: Text('Move to end')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'high', child: Text('High priority')),
                    PopupMenuItem(
                      value: 'normal',
                      child: Text('Normal priority'),
                    ),
                    PopupMenuItem(value: 'low', child: Text('Low priority')),
                  ],
                ),
              if (operation.isActive)
                IconButton(
                  icon: Icon(
                    operation.isPaused ? Icons.play_arrow : Icons.pause,
                    size: 20,
                  ),
                  tooltip: operation.isPaused ? 'Resume' : 'Pause',
                  color: Colors.blue,
                  onPressed: operation.isPaused ? onResume : onPause,
                ),
              if (!operation.isComplete &&
                  !operation.isCancelled &&
                  onCancel != null)
                IconButton(
                  icon: const Icon(Icons.cancel, size: 20),
                  tooltip: 'Cancel',
                  color: Colors.red,
                  onPressed: onCancel,
                ),
              if (operation.isBatch)
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  onPressed: onToggleExpanded,
                ),
              if (operation.isComplete ||
                  operation.error != null ||
                  operation.isCancelled)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
        if (isExpanded && operation.isBatch && operation.files != null)
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            constraints: const BoxConstraints(maxHeight: 150),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: operation.files!.length,
              itemBuilder: (context, index) {
                final file = operation.files![index];
                return Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2),
                  child: Row(
                    children: [
                      Icon(
                        file.error != null
                            ? Icons.error
                            : file.isComplete
                            ? Icons.check_circle
                            : Icons.pending,
                        size: 12,
                        color: file.error != null
                            ? Colors.red
                            : file.isComplete
                            ? Colors.green
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.name,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Tooltip(
                        message: file.error ?? file.path,
                        child: Text(
                          file.statusLabel ?? formatBytes(file.size),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _getStatusText(OperationProgress op) {
    if (op.isWaitingForDecision) return 'Waiting for a conflict decision';
    if (op.error != null) return 'Error: ${op.error}';
    if (op.isComplete) return 'Complete';
    final percent = (op.progress * 100).toStringAsFixed(0);
    final speedStr = op.currentSpeed > 0
        ? ' • ${formatSpeed(op.currentSpeed)}'
        : '';
    final etaStr = op.estimatedSecondsRemaining > 0
        ? ' • ${_formatEta(op.estimatedSecondsRemaining)}'
        : '';
    return '$percent% • ${formatBytes(op.transferredBytes)} / ${formatBytes(op.totalBytes)}$speedStr$etaStr';
  }

  String _formatEta(double seconds) {
    final s = seconds.round();
    if (s < 60) return '${s}s left';
    if (s < 3600) return '${s ~/ 60}m ${s % 60}s left';
    return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m left';
  }
}
