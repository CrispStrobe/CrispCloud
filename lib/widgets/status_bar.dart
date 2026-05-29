// lib/widgets/status_bar.dart
//
// Bottom status bar showing connection info, item counts,
// transfer speed, and active operations.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final activePanel = ref.watch(activePanelProvider);
    final transfers = ref.watch(transferProvider);
    final sync = ref.watch(syncProvider);

    final isLocal = activePanel == PanelSide.local;
    final panel = ref.watch(panelProvider(activePanel));

    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = TextStyle(fontSize: 12, color: color);

    final itemCount = panel.files?.length ?? 0;
    final selectedCount = panel.selection.length;
    final selectedSize = panel.selection.fold<int>(0, (s, f) => s + (f.size ?? 0));

    final activeOps = transfers.operations.where((op) => !op.isComplete).length;
    final totalTransferred = transfers.operations
        .where((op) => !op.isComplete)
        .fold<int>(0, (s, op) => s + op.transferredBytes);
    final totalSize = transfers.operations
        .where((op) => !op.isComplete)
        .fold<int>(0, (s, op) => s + op.totalBytes);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            auth.isConnected ? Icons.cloud_done : Icons.cloud_off,
            size: 14,
            color: auth.isConnected ? Colors.green : color,
          ),
          const SizedBox(width: 6),
          Text(
            auth.isConnected ? auth.providerName : 'Disconnected',
            style: style.copyWith(fontWeight: FontWeight.w500),
          ),

          const SizedBox(width: 16),
          Container(width: 1, height: 14, color: theme.dividerColor),
          const SizedBox(width: 16),

          Text('$itemCount items', style: style),

          if (selectedCount > 0) ...[
            const SizedBox(width: 8),
            Text('•', style: style),
            const SizedBox(width: 8),
            Text(
              '$selectedCount selected${selectedSize > 0 ? ' (${formatBytes(selectedSize)})' : ''}',
              style: style.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
            ),
          ],

          const Spacer(),

          if (activeOps > 0) ...[
            SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                value: totalSize > 0 ? totalTransferred / totalSize : null,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text('$activeOps transfer${activeOps > 1 ? 's' : ''}', style: style),
            if (totalSize > 0) ...[
              const SizedBox(width: 4),
              Text('${formatBytes(totalTransferred)} / ${formatBytes(totalSize)}', style: style),
            ],
            const SizedBox(width: 16),
            Container(width: 1, height: 14, color: theme.dividerColor),
            const SizedBox(width: 16),
          ],

          // Sync status
          if (sync.isSyncing) ...[
            SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: theme.colorScheme.tertiary),
            ),
            const SizedBox(width: 6),
            Text('Syncing${sync.currentPairName != null ? ' ${sync.currentPairName}' : ''}...', style: style),
            const SizedBox(width: 16),
            Container(width: 1, height: 14, color: theme.dividerColor),
            const SizedBox(width: 16),
          ] else if (sync.pairs.isNotEmpty) ...[
            Icon(Icons.sync, size: 14, color: color),
            const SizedBox(width: 4),
            Text('${sync.pairs.length} pair${sync.pairs.length > 1 ? 's' : ''}', style: style),
            const SizedBox(width: 16),
            Container(width: 1, height: 14, color: theme.dividerColor),
            const SizedBox(width: 16),
          ],

          Icon(isLocal ? Icons.folder : Icons.cloud, size: 14, color: color),
          const SizedBox(width: 4),
          Text(isLocal ? 'Local' : 'Remote', style: style),
        ],
      ),
    );
  }
}
