// lib/widgets/status_bar.dart
//
// Bottom status bar showing connection info, item counts,
// transfer speed, active operations, sync status, quota.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';

class StatusBar extends ConsumerStatefulWidget {
  const StatusBar({super.key});

  @override
  ConsumerState<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends ConsumerState<StatusBar> {
  Map<String, int>? _quota;
  bool _quotaLoading = false;
  String? _lastProvider;

  void _fetchQuota() {
    final auth = ref.read(authProvider);
    if (!auth.isConnected) {
      if (_quota != null) setState(() => _quota = null);
      return;
    }
    final providerName = auth.providerName;
    if (providerName == _lastProvider && _quota != null) return;
    if (_quotaLoading) return;

    _lastProvider = providerName;
    _quotaLoading = true;

    auth.client.getQuota().then((q) {
      if (mounted) setState(() { _quota = q; _quotaLoading = false; });
    }).catchError((_) {
      if (mounted) setState(() { _quota = null; _quotaLoading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final activePanel = ref.watch(activePanelProvider);
    final transfers = ref.watch(transferProvider);
    final sync = ref.watch(syncProvider);

    final isLocal = activePanel == PanelSide.local;
    final panel = ref.watch(panelProvider(activePanel));

    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = TextStyle(fontSize: 12, color: color);

    final itemCount = panel.filteredFiles?.length ?? 0;
    final totalCount = panel.files?.length ?? 0;
    final selectedCount = panel.selection.length;
    final selectedSize = panel.selection.fold<int>(0, (s, f) => s + (f.size ?? 0));

    final activeOps = transfers.operations.where((op) => !op.isComplete).length;
    final totalTransferred = transfers.operations
        .where((op) => !op.isComplete)
        .fold<int>(0, (s, op) => s + op.transferredBytes);
    final totalSize = transfers.operations
        .where((op) => !op.isComplete)
        .fold<int>(0, (s, op) => s + op.totalBytes);

    // Lazy-fetch quota when connected
    _fetchQuota();

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

          // Encryption status indicator
          if (auth.isConnected && auth.providerName.contains('Encrypted')) ...[
            const SizedBox(width: 4),
            Icon(Icons.lock, size: 12, color: Colors.green),
          ],

          // Privacy score
          if (auth.isConnected) ...[
            const SizedBox(width: 6),
            Builder(builder: (_) {
              final score = privacyScore(auth.providerName);
              final scoreColor = score >= 70 ? Colors.green : score >= 50 ? Colors.orange : Colors.red;
              return Tooltip(
                message: 'Privacy: ${privacyLabel(score)} ($score/100)',
                child: Icon(Icons.shield, size: 12, color: scoreColor),
              );
            }),
          ],

          // Quota display
          if (_quota != null) ...[
            const SizedBox(width: 8),
            Text(
              '(${formatBytes(_quota!['used'] ?? 0)} / ${formatBytes(_quota!['total'] ?? 0)})',
              style: style.copyWith(fontSize: 11),
            ),
          ],

          const SizedBox(width: 16),
          Container(width: 1, height: 14, color: theme.dividerColor),
          const SizedBox(width: 16),

          // Item count (show filtered count if filter active)
          Text(
            panel.filterQuery.isNotEmpty
                ? '$itemCount / $totalCount items'
                : '$itemCount items',
            style: style,
          ),

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
          ] else if (sync.lastResult != null && sync.lastResult!.hasChanges) ...[
            Icon(Icons.sync_alt, size: 14, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              'Last sync: ${sync.lastResult!.uploaded + sync.lastResult!.downloaded} changes',
              style: style,
            ),
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

          // Filter indicator
          if (panel.filterQuery.isNotEmpty) ...[
            Icon(Icons.filter_list, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              'Filter: "${panel.filterQuery}"',
              style: style.copyWith(color: theme.colorScheme.primary),
            ),
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
