// widgets/operations_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/operation_progress.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart' show formatBytes, formatSpeed;
import '../l10n/app_localizations.dart';

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

    if (transfers.operations.isEmpty) {
      return const SizedBox.shrink();
    }

    int totalBytes = 0;
    int transferredBytes = 0;
    int activeCount = 0;
    int completeCount = 0;
    int errorCount = 0;

    for (final op in transfers.operations) {
      totalBytes += op.totalBytes;
      transferredBytes += op.transferredBytes;
      if (op.isCancelled) {
        errorCount++;
      } else if (op.error != null) {
        errorCount++;
      } else if (op.isComplete) {
        completeCount++;
      } else {
        activeCount++;
      }
    }

    final overallProgress = totalBytes > 0 ? transferredBytes / totalBytes : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ExpansionTile(
        title: _buildPanelHeader(context, transfers, activeCount, completeCount, errorCount, overallProgress, transferredBytes, totalBytes),
        initiallyExpanded: true,
        onExpansionChanged: (isExpanded) => setState(() => _isPanelExpanded = isExpanded),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (completeCount > 0 || errorCount > 0)
              IconButton(
                icon: const Icon(Icons.clear_all, size: 20),
                tooltip: 'Clear completed',
                onPressed: () => transfers.clearCompletedOperations(),
              ),
            Icon(_isPanelExpanded ? Icons.expand_less : Icons.expand_more),
          ],
        ),
        children: [
          Container(
            constraints: const BoxConstraints(maxHeight: 250),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: transfers.operations.length,
              itemBuilder: (context, index) {
                final op = transfers.operations[index];
                final isExpanded = _expandedOperationId == op.id;
                return _OperationTile(
                  operation: op,
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
    int activeCount, int completeCount, int errorCount,
    double overallProgress, int transferredBytes, int totalBytes,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            activeCount > 0 ? Icons.sync : Icons.check_circle,
            size: 20,
            color: errorCount > 0
                ? Theme.of(context).colorScheme.error
                : activeCount > 0
                    ? Theme.of(context).colorScheme.primary
                    : Colors.green,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${transfers.operations.length} operation(s)',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (activeCount > 0) ...[
                      const SizedBox(width: 8),
                      Text('• ${(overallProgress * 100).toStringAsFixed(0)}%', style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(width: 8),
                      Text('${formatBytes(transferredBytes)} / ${formatBytes(totalBytes)}', style: Theme.of(context).textTheme.bodySmall),
                      // Aggregate speed
                      Builder(builder: (_) {
                        final totalSpeed = transfers.operations
                            .where((op) => !op.isComplete && !op.isCancelled)
                            .fold<double>(0, (s, op) => s + op.currentSpeed);
                        if (totalSpeed > 0) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(formatSpeed(totalSpeed),
                                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
                          );
                        }
                        return const SizedBox.shrink();
                      }),
                    ],
                    if (completeCount > 0) ...[
                      const SizedBox(width: 8),
                      Text('✓ $completeCount', style: TextStyle(color: Colors.green[700])),
                    ],
                    if (errorCount > 0) ...[
                      const SizedBox(width: 8),
                      Text('✗ $errorCount', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(color: Colors.grey[300]),
                        Row(
                          children: transfers.operations.map((op) {
                            final segmentWidth = totalBytes > 0
                                ? op.totalBytes / totalBytes
                                : 1.0 / transfers.operations.length;
                            Color segmentColor;
                            if (op.isCancelled) {
                              segmentColor = Colors.orange;
                            } else if (op.error != null) {
                              segmentColor = Theme.of(context).colorScheme.error;
                            } else if (op.isComplete) {
                              segmentColor = Colors.green;
                            } else {
                              segmentColor = Theme.of(context).colorScheme.primary;
                            }
                            return Expanded(
                              flex: (segmentWidth * 1000).toInt(),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 0.5),
                                child: LinearProgressIndicator(
                                  value: op.progress,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: AlwaysStoppedAnimation<Color>(segmentColor),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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

  const _OperationTile({
    required this.operation,
    required this.isExpanded,
    required this.onToggleExpanded,
    required this.onRemove,
    this.onCancel,
    required this.onPause,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color? color;

    if (operation.isCancelled) {
      icon = Icons.cancel; color = Colors.orange;
    } else if (operation.isPaused) {
      icon = Icons.pause_circle; color = Colors.blue;
    } else if (operation.isComplete) {
      icon = Icons.check_circle; color = Colors.green;
    } else if (operation.error != null) {
      icon = Icons.error; color = Colors.red;
    } else {
      icon = operation.type == OperationType.upload ? Icons.upload : Icons.download;
      color = Theme.of(context).colorScheme.primary;
    }

    return Column(
      children: [
        ListTile(
          dense: true,
          leading: Icon(icon, size: 20, color: color),
          title: Row(
            children: [
              Expanded(child: Text(operation.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
              if (operation.isBatch) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${operation.completedFiles}/${operation.totalFiles} files',
                    style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!operation.isComplete && operation.error == null && !operation.isCancelled)
                LinearProgressIndicator(value: operation.progress, backgroundColor: Colors.grey[300]),
              const SizedBox(height: 2),
              Text(
                operation.isCancelled ? 'Cancelled'
                    : operation.isPaused ? 'Paused'
                    : operation.error ?? _getStatusText(operation),
                style: TextStyle(
                  fontSize: 11,
                  color: operation.error != null ? Colors.red
                      : operation.isCancelled ? Colors.orange
                      : operation.isPaused ? Colors.blue : null,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!operation.isComplete && !operation.isCancelled)
                IconButton(
                  icon: Icon(operation.isPaused ? Icons.play_arrow : Icons.pause, size: 20),
                  tooltip: operation.isPaused ? 'Resume' : 'Pause',
                  color: Colors.blue,
                  onPressed: operation.isPaused ? onResume : onPause,
                ),
              if (!operation.isComplete && !operation.isCancelled && onCancel != null)
                IconButton(icon: const Icon(Icons.cancel, size: 20), tooltip: 'Cancel', color: Colors.red, onPressed: onCancel),
              if (operation.isBatch)
                IconButton(icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 20), onPressed: onToggleExpanded),
              if (operation.isComplete || operation.error != null || operation.isCancelled)
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: onRemove),
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
                        file.error != null ? Icons.error : file.isComplete ? Icons.check_circle : Icons.pending,
                        size: 12,
                        color: file.error != null ? Colors.red : file.isComplete ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(file.name, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(formatBytes(file.size), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
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
    if (op.isComplete) return 'Complete';
    if (op.error != null) return 'Error: ${op.error}';
    final percent = (op.progress * 100).toStringAsFixed(0);
    final speedStr = op.currentSpeed > 0 ? ' • ${formatSpeed(op.currentSpeed)}' : '';
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
