// lib/widgets/audit_log_dialog.dart
//
// Dialog showing recent audit log entries with export and clear actions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/audit_service.dart';
import '../utils/formatters.dart' as fmt;
import '../l10n/app_localizations.dart';

void showAuditLogDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _AuditLogDialog(),
  );
}

class _AuditLogDialog extends ConsumerStatefulWidget {
  const _AuditLogDialog();

  @override
  ConsumerState<_AuditLogDialog> createState() => _AuditLogDialogState();
}

class _AuditLogDialogState extends ConsumerState<_AuditLogDialog> {
  List<AuditEntry> _entries = [];
  bool _loading = true;
  static const _pageSize = 100;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final audit = ref.read(auditServiceProvider);
    final entries = await audit.getRecent(_pageSize);
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  Future<void> _export() async {
    final audit = ref.read(auditServiceProvider);
    final json = await audit.exportAsJson();
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Audit log copied to clipboard as JSON')),
    );
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Audit Log'),
        content: const Text('This will permanently delete all audit log entries. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(AppLocalizations.of(context)!.clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final audit = ref.read(auditServiceProvider);
    await audit.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.history),
          const SizedBox(width: 8),
          const Text('Audit Log'),
          const Spacer(),
          if (_loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: 440,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No audit entries yet', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final entry = _entries[i];
                      return _AuditEntryTile(entry: entry);
                    },
                  ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Export JSON'),
          onPressed: _entries.isEmpty ? null : _export,
        ),
        TextButton.icon(
          icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
          label: Text('Clear', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onPressed: _entries.isEmpty ? null : _clear,
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
      ],
    );
  }
}

class _AuditEntryTile extends StatelessWidget {
  final AuditEntry entry;

  const _AuditEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final icon = _operationIcon(entry.operation);
    final color = entry.success ? colorScheme.primary : colorScheme.error;
    final opLabel = entry.operation.name.toUpperCase();

    final ts = entry.timestamp;
    final timeStr = '${ts.year}-${_pad(ts.month)}-${_pad(ts.day)} '
        '${_pad(ts.hour)}:${_pad(ts.minute)}:${_pad(ts.second)}';

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, size: 16, color: color),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              opLabel,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.sourcePath,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (entry.sizeBytes != null) ...[
            const SizedBox(width: 8),
            Text(
              fmt.formatBytes(entry.sizeBytes!),
              style: TextStyle(fontSize: 11, color: colorScheme.outline),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.targetPath != null)
            Text(
              '-> ${entry.targetPath}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          Row(
            children: [
              Text(timeStr, style: TextStyle(fontSize: 11, color: colorScheme.outline)),
              if (entry.provider != null) ...[
                const SizedBox(width: 8),
                Text(
                  entry.provider!,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (entry.error != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.error!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colorScheme.error),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  IconData _operationIcon(AuditOperation op) {
    switch (op) {
      case AuditOperation.upload:
        return Icons.upload;
      case AuditOperation.download:
        return Icons.download;
      case AuditOperation.delete:
        return Icons.delete;
      case AuditOperation.rename:
        return Icons.drive_file_rename_outline;
      case AuditOperation.move:
        return Icons.drive_file_move;
      case AuditOperation.copy:
        return Icons.copy;
      case AuditOperation.createFolder:
        return Icons.create_new_folder;
      case AuditOperation.sync:
        return Icons.sync;
    }
  }
}
