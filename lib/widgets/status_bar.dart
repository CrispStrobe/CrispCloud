// lib/widgets/status_bar.dart
//
// Bottom status bar showing connection info, item counts,
// transfer speed, active operations, sync status, quota.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../providers/providers.dart';
import '../l10n/app_localizations.dart';
import '../l10n/misc_ui_strings.dart';
import '../l10n/quick_search_status_strings.dart';
import '../l10n/status_bar_strings.dart';
import '../services/panel_source_service.dart';
import '../utils/formatters.dart';

class StatusBar extends ConsumerStatefulWidget {
  const StatusBar({super.key});

  @override
  ConsumerState<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends ConsumerState<StatusBar> {
  _QuotaRequest? _quotaRequest;

  /// Quota belongs to the displayed storage session, not to a provider label
  /// or the physical left/right position of its pane.
  void _synchronizeQuota(PanelNotifier panel) {
    final storage = panel.directoryStorage;
    final source = panel.directorySource;
    final origin =
        storage != null &&
            source is RemotePanelSource &&
            panel.directorySourceAvailable
        ? panel.directoryPresentationOrigin
        : null;
    final resolved = origin?.source;
    if (origin == null ||
        !origin.isCurrent ||
        source is! RemotePanelSource ||
        resolved is! RemotePanelSource ||
        !identical(source.client, resolved.client)) {
      _quotaRequest = null;
      return;
    }
    final previous = _quotaRequest;
    if (previous != null &&
        previous.origin.isCurrent &&
        previous.origin.storageReference == origin.storageReference &&
        identical(previous.source.client, resolved.client)) {
      return;
    }
    final request = _QuotaRequest(origin, resolved);
    _quotaRequest = request;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isQuotaCurrent(request)) unawaited(_fetchQuota(request));
    });
  }

  bool _isQuotaCurrent(_QuotaRequest request) {
    if (!mounted ||
        !identical(_quotaRequest, request) ||
        !request.origin.isCurrent) {
      return false;
    }
    final panel = ref.read(panelProvider(ref.read(activePanelProvider)));
    final source = panel.directorySource;
    return panel.directorySourceAvailable &&
        panel.directoryStorage == request.origin.storageReference &&
        source is RemotePanelSource &&
        identical(source.client, request.source.client);
  }

  Future<void> _fetchQuota(_QuotaRequest request) async {
    if (!_isQuotaCurrent(request)) return;
    try {
      final quota = await request.source.client.getQuota();
      if (!_isQuotaCurrent(request)) return;
      setState(() {
        request.quota = quota == null ? null : Map.unmodifiable(quota);
        request.loading = false;
        request.failed = false;
      });
    } catch (_) {
      if (!_isQuotaCurrent(request)) return;
      setState(() {
        request.quota = null;
        request.loading = false;
        request.failed = true;
      });
    }
  }

  void _refreshQuota(_QuotaRequest request) {
    if (!_isQuotaCurrent(request) || request.loading) return;
    setState(() {
      request.loading = true;
      request.failed = false;
      request.quota = null;
    });
    unawaited(_fetchQuota(request));
  }

  Widget _quotaStatus(BuildContext context, TextStyle style) {
    final request = _quotaRequest!;
    final strings = StatusBarStrings(context);
    if (request.loading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 6),
          Text(strings.text('quotaLoading'), style: style),
        ],
      );
    }
    final used = request.quota?['used'];
    final total = request.quota?['total'];
    final hasUsed = used != null && used >= 0;
    final hasTotal = total != null && total > 0;
    final label = hasUsed && hasTotal
        ? '${formatBytes(used)} / ${formatBytes(total)}'
        : hasUsed
        ? strings.value('quotaUsed', formatBytes(used))
        : hasTotal
        ? strings.value('quotaTotal', formatBytes(total))
        : strings.text('quotaUnavailable');
    return Tooltip(
      message: strings.text(request.failed ? 'quotaFailed' : 'quotaRefresh'),
      child: TextButton(
        key: const ValueKey('status-quota-refresh'),
        onPressed: () => _refreshQuota(request),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 20),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: style),
            const SizedBox(width: 4),
            Icon(
              request.failed ? Icons.refresh : Icons.refresh_outlined,
              size: 12,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Labels and origin guards may change without a different pane location.
    ref.watch(authProvider);
    final connections = ref.watch(multiCloudProvider).connections;
    final activePanel = ref.watch(activePanelProvider);
    final transfers = ref.watch(transferProvider);
    final sync = ref.watch(syncProvider);

    final panel = ref.watch(panelProvider(activePanel));
    final storage = panel.directoryStorage;
    final source = panel.directorySource;
    final isLocal = storage?.isLocal == true;
    final available = storage != null && panel.directorySourceAvailable;
    final remote = source is RemotePanelSource ? source : null;
    final strings = StatusBarStrings(context);
    String? sessionLabel;
    if (storage != null && remote != null) {
      for (final connection in connections) {
        if (identical(connection.client, remote.client)) {
          sessionLabel = '${connection.label} (${storage.provider})';
          break;
        }
      }
    }
    final sourceLabel = storage != null
        ? isLocal
              ? l.local
              : sessionLabel ?? panel.storageDisplayName(storage)
        : panel.isInArchive
        ? panel.archiveSource!.archiveName
        : panel.isFlatView
        ? strings.text('flatView')
        : panel.showingSearchResults
        ? panel.activeCollectionId != null
              ? panel.fileListTitle
              : l.searchResults
        : strings.text('unavailable');
    final sourceTooltip = storage == null
        ? sourceLabel
        : '$sourceLabel\n${storage.root}\n${source?.currentPath ?? panel.currentPath}';
    _synchronizeQuota(panel);

    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = TextStyle(fontSize: 12, color: color);

    final displayed =
        panel.filteredFiles?.where((file) => file.name != '..').toList() ??
        const [];
    final itemCount = panel.isPagedCollection
        ? panel.collectionMatchingCount
        : displayed.length;
    final totalCount = panel.isPagedCollection
        ? panel.collectionTotalCount
        : panel.files?.where((file) => file.name != '..').length ?? 0;
    final cursor = panel.cursorItem;
    final cursorIndex = cursor == null
        ? -1
        : displayed.indexWhere((file) => identical(file, cursor));
    final cursorPosition = cursorIndex < 0
        ? null
        : (panel.isPagedCollection ? panel.collectionPageStart : 0) +
              cursorIndex +
              1;
    final selectedCount = panel.selection.length;
    int? knownSize(FileItem file) {
      final size = file.isFolder ? file.calculatedSize : file.size;
      return size != null && size >= 0 ? size : null;
    }

    final selectedSize = panel.selection.fold<int>(
      0,
      (size, file) => size + (knownSize(file) ?? 0),
    );
    final selectionHasUnknownSize = panel.selection.any(
      (file) => knownSize(file) == null,
    );

    final activeOps = transfers.operations.where((op) => op.isActive).length;
    final totalTransferred = transfers.operations
        .where((op) => op.isActive)
        .fold<int>(0, (s, op) => s + op.transferredBytes);
    final totalSize = transfers.operations
        .where((op) => op.isActive)
        .fold<int>(0, (s, op) => s + op.totalBytes);

    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: IntrinsicWidth(
              child: Row(
                children: [
                  Icon(
                    storage == null
                        ? panel.isInArchive
                              ? Icons.archive_outlined
                              : Icons.list_alt
                        : isLocal
                        ? available
                              ? Icons.folder
                              : Icons.folder_off_outlined
                        : available
                        ? Icons.cloud_done
                        : Icons.cloud_off,
                    size: 14,
                    color: available ? theme.colorScheme.primary : color,
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: sourceTooltip,
                    child: Text(
                      sourceLabel,
                      key: const ValueKey('status-source-label'),
                      style: style.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (storage != null && !available) ...[
                    const SizedBox(width: 6),
                    Text(strings.text('unavailable'), style: style),
                  ],

                  // Encryption status indicator
                  if (available &&
                      remote?.providerName.contains('Encrypted') == true) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.lock, size: 12, color: Colors.green),
                  ],

                  // Privacy score
                  if (available && remote != null) ...[
                    const SizedBox(width: 6),
                    Builder(
                      builder: (_) {
                        final score = privacyScore(remote.providerName);
                        final scoreColor = score >= 70
                            ? Colors.green
                            : score >= 50
                            ? Colors.orange
                            : Colors.red;
                        return Tooltip(
                          message:
                              '${MiscUiStrings(context).text('privacy')}: ${MiscUiStrings(context).privacyLevel(score)} ($score/100)',
                          child: Icon(
                            Icons.shield,
                            size: 12,
                            color: scoreColor,
                          ),
                        );
                      },
                    ),
                  ],

                  // Quota display
                  if (_quotaRequest != null) ...[
                    const SizedBox(width: 8),
                    _quotaStatus(context, style.copyWith(fontSize: 11)),
                  ],

                  const SizedBox(width: 16),
                  Container(width: 1, height: 14, color: theme.dividerColor),
                  const SizedBox(width: 16),

                  // Item count + cursor position (DC-style "15 / 169")
                  Text(
                    panel.filterQuery.isNotEmpty
                        ? '$itemCount / ${l.nItems(totalCount)}'
                        : l.nItems(itemCount),
                    style: style,
                  ),
                  if (cursorPosition != null && itemCount > 0) ...[
                    const SizedBox(width: 8),
                    Text('•', style: style),
                    const SizedBox(width: 8),
                    Text(
                      '$cursorPosition / $itemCount',
                      style: style.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],

                  if (selectedCount > 0) ...[
                    const SizedBox(width: 8),
                    Text('•', style: style),
                    const SizedBox(width: 8),
                    Text(
                      '${l.nSelected(selectedCount)}${selectedSize > 0 || !selectionHasUnknownSize ? ' (${selectionHasUnknownSize ? '≥ ' : ''}${formatBytes(selectedSize)})' : ''}',
                      style: style.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],

                  const Spacer(),

                  if (activeOps > 0) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        value: totalSize > 0
                            ? (totalTransferred / totalSize).clamp(0.0, 1.0)
                            : null,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(l.nTransfers(activeOps), style: style),
                    if (totalSize > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${formatBytes(totalTransferred)} / ${formatBytes(totalSize)}',
                        style: style,
                      ),
                    ],
                    const SizedBox(width: 16),
                    Container(width: 1, height: 14, color: theme.dividerColor),
                    const SizedBox(width: 16),
                  ],

                  // Sync status
                  if (sync.isSyncing) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${l.syncing}${sync.currentPairName != null ? ' ${sync.currentPairName}' : ''}...',
                      style: style,
                    ),
                    const SizedBox(width: 16),
                    Container(width: 1, height: 14, color: theme.dividerColor),
                    const SizedBox(width: 16),
                  ] else if (sync.lastResult != null &&
                      sync.lastResult!.hasChanges) ...[
                    const Icon(Icons.sync_alt, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      l.lastSyncChanges(
                        sync.lastResult!.uploaded + sync.lastResult!.downloaded,
                      ),
                      style: style,
                    ),
                    const SizedBox(width: 16),
                    Container(width: 1, height: 14, color: theme.dividerColor),
                    const SizedBox(width: 16),
                  ] else if (sync.pairs.isNotEmpty) ...[
                    Icon(Icons.sync, size: 14, color: color),
                    const SizedBox(width: 4),
                    Text(l.nPairs(sync.pairs.length), style: style),
                    const SizedBox(width: 16),
                    Container(width: 1, height: 14, color: theme.dividerColor),
                    const SizedBox(width: 16),
                  ],

                  // Filter / type-ahead indicator
                  if (panel.filterQuery.isNotEmpty) ...[
                    Icon(
                      (!panel.isTypeahead || panel.isQuickFilterActive)
                          ? Icons.filter_list
                          : Icons.search,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      QuickSearchStatusStrings(context).status(
                        query: panel.filterQuery,
                        isTypeahead: panel.isTypeahead,
                        isQuickFilterActive: panel.isQuickFilterActive,
                        matchPosition: panel.typeaheadMatchPosition,
                        matchCount: panel.typeaheadMatchCount,
                      ),
                      style: style.copyWith(color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 16),
                    Container(width: 1, height: 14, color: theme.dividerColor),
                    const SizedBox(width: 16),
                  ],

                  // Hidden files indicator
                  if (isLocal && panel.showHiddenFiles) ...[
                    Icon(
                      Icons.visibility,
                      size: 14,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l.hidden,
                      style: style.copyWith(
                        color: theme.colorScheme.secondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Loading indicator
                  if (panel.isLoading) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],

                  if (isLocal && available && panel.freeBytes != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      l.free(formatBytes(panel.freeBytes!)),
                      style: style.copyWith(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuotaRequest {
  _QuotaRequest(this.origin, this.source);
  final PanelFileOrigin origin;
  final RemotePanelSource source;
  Map<String, int>? quota;
  bool loading = true;
  bool failed = false;
}
