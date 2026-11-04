// lib/widgets/cache_settings_dialog.dart
//
// Dialog to view cache usage and configure the maximum cache size.
// Options: 100 MB, 250 MB, 500 MB, 1 GB, 2 GB, Unlimited.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../utils/formatters.dart' as fmt;
import '../l10n/app_localizations.dart';
import '../l10n/cache_settings_strings.dart';

void showCacheSettingsDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (_) => const _CacheSettingsDialog(),
  );
}

/// Predefined cache size options in bytes. 0 = unlimited.
const _cacheSizeOptions = <({String label, int bytes})>[
  (label: '100 MB', bytes: 100 * 1024 * 1024),
  (label: '250 MB', bytes: 250 * 1024 * 1024),
  (label: '500 MB', bytes: 500 * 1024 * 1024),
  (label: '1 GB', bytes: 1024 * 1024 * 1024),
  (label: '2 GB', bytes: 2 * 1024 * 1024 * 1024),
  (label: 'Unlimited', bytes: 0),
];

class _CacheSettingsDialog extends ConsumerStatefulWidget {
  const _CacheSettingsDialog();

  @override
  ConsumerState<_CacheSettingsDialog> createState() => _CacheSettingsDialogState();
}

class _CacheSettingsDialogState extends ConsumerState<_CacheSettingsDialog> {
  bool _clearing = false;

  Future<void> _setMaxSize(int bytes) async {
    final cache = ref.read(fileCacheProvider);
    await cache.setMaxSize(bytes);
    if (mounted) setState(() {});
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(CacheSettingsStrings(context).text('clearTitle')),
        content: Text(CacheSettingsStrings(context).text('clearConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(AppLocalizations.of(context)!.clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    await ref.read(fileCacheProvider).clear();
    if (mounted) setState(() => _clearing = false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = CacheSettingsStrings(context);
    final cache = ref.read(fileCacheProvider);
    final totalSize = cache.totalSize;
    final maxSize = cache.maxSize;
    final entryCount = cache.entryCount;
    final usagePercent = maxSize > 0 ? (totalSize / maxSize).clamp(0.0, 1.0) : 0.0;

    final usageText = maxSize == 0
        ? strings.text('usedUnlimited', {'used': fmt.formatBytes(totalSize)})
        : strings.text('usedLimit', {'used': fmt.formatBytes(totalSize), 'max': fmt.formatBytes(maxSize)});

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.storage),
          const SizedBox(width: 8),
          Text(strings.text('settings')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Usage section
            Text(strings.text('usage'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (maxSize > 0)
              LinearProgressIndicator(
                value: usagePercent,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(usageText, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  strings.files(entryCount),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const Divider(height: 24),

            // Max size selector
            Text(strings.text('max'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _cacheSizeOptions.map((opt) {
                final isSelected = opt.bytes == maxSize ||
                    (opt.bytes == 0 && maxSize == 0) ||
                    (opt.bytes == 0 && maxSize > 2 * 1024 * 1024 * 1024);
                return ChoiceChip(
                  label: Text(opt.bytes == 0 ? strings.text('unlimited') : opt.label),
                  selected: isSelected,
                  onSelected: (_) => _setMaxSize(opt.bytes),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Text(
              strings.text('eviction'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: _clearing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.delete_sweep, size: 18, color: Theme.of(context).colorScheme.error),
          label: Text(
            strings.text('clearTitle'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          onPressed: _clearing ? null : _clearCache,
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
      ],
    );
  }
}
