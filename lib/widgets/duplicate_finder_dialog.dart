// lib/widgets/duplicate_finder_dialog.dart
//
// Scans files in the current panel for duplicates by size + name pattern.
// For local files, computes MD5 hashes to confirm true duplicates.

import 'package:flutter/material.dart';

import 'file_delete_dialog.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/file_operation_backend.dart';
import '../services/duplicate_finder_service.dart';
import '../utils/formatters.dart';
import '../l10n/app_localizations.dart';
import '../l10n/duplicate_finder_strings.dart';

void showDuplicateFinderDialog(BuildContext context, WidgetRef ref) {
  showDialog(context: context, builder: (_) => const _DuplicateFinderDialog());
}

class _DuplicateFinderDialog extends ConsumerStatefulWidget {
  const _DuplicateFinderDialog();

  @override
  ConsumerState<_DuplicateFinderDialog> createState() =>
      _DuplicateFinderDialogState();
}

class _DuplicateFinderDialogState
    extends ConsumerState<_DuplicateFinderDialog> {
  List<List<FileItem>> _duplicateGroups = [];
  bool _scanning = false;
  bool _done = false;
  int _scannedCount = 0;
  int _totalCount = 0;
  bool _cancelled = false;
  List<String> _errors = [];
  PanelSide? _sourceSide;
  PanelFileOrigin? _origin;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _done = false;
      _duplicateGroups = [];
      _scannedCount = 0;
    });

    _cancelled = false;
    _errors = [];
    final side = ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(side));
    final files = panel.files?.where((file) => !file.isFolder).toList() ?? [];
    _sourceSide = side;
    try {
      _origin = panel.captureOperationOrigin(files);
      final origin = _origin!;
      final backend = fileOperationBackend(
        source: origin.source,
        local: ref.read(localFileServiceProvider),
        isCurrent: () => origin.isCurrent,
      );
      final result = await DuplicateFinderService().scan(
        backend,
        files,
        isCancelled: () => _cancelled,
        onProgress: (checked, total) {
          if (mounted)
            setState(() {
              _scannedCount = checked;
              _totalCount = total;
            });
        },
      );
      if (mounted)
        setState(() {
          _duplicateGroups = result.groups;
          _errors = result.errors;
          _cancelled = result.cancelled;
        });
    } catch (error) {
      if (mounted) setState(() => _errors = [error.toString()]);
    } finally {
      if (mounted)
        setState(() {
          _scanning = false;
          _done = true;
        });
    }
  }

  Future<void> _deleteCopy(FileItem file, List<FileItem> group) async {
    final origin = _origin;
    if (origin == null || !origin.isCurrent || group.length < 2) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete verified duplicate?'),
        content: Text(
          'Delete ${file.path ?? file.name}? Another verified copy will be retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !origin.isCurrent) return;
    final backend = fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => origin.isCurrent,
    );
    final verification = await DuplicateFinderService().scan(backend, group);
    if (!mounted || !origin.isCurrent) return;
    if (!verification.groups.any(
      (copies) => copies.contains(file) && copies.length > 1,
    )) {
      setState(
        () => _errors = ['The files changed. Scan again before deleting.'],
      );
      return;
    }
    if (!mounted) return;
    await showFileDeleteDialog(context, ref, _sourceSide!, [file]);
    if (mounted) await _scan();
  }

  @override
  Widget build(BuildContext context) {
    final strings = DuplicateFinderStrings(context);
    final totalDuplicates = _duplicateGroups.fold<int>(
      0,
      (s, g) => s + g.length - 1,
    );
    final wastedBytes = _duplicateGroups.fold<int>(0, (s, g) {
      final size = g.first.size ?? 0;
      return s + size * (g.length - 1);
    });

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.find_replace, size: 20),
          const SizedBox(width: 8),
          Text(strings.text('finder')),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            // Status bar
            if (_scanning) ...[
              LinearProgressIndicator(
                value: _totalCount > 0 ? _scannedCount / _totalCount : null,
              ),
              const SizedBox(height: 8),
              Text(
                'Scanning... $_scannedCount / $_totalCount files',
                style: const TextStyle(fontSize: 12),
              ),
            ] else if (_done) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _duplicateGroups.isEmpty
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _duplicateGroups.isEmpty
                          ? Icons.check_circle
                          : Icons.warning,
                      size: 16,
                      color: _duplicateGroups.isEmpty
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _duplicateGroups.isEmpty
                            ? (_cancelled
                                  ? 'Scan cancelled.'
                                  : 'No verified duplicates found.')
                            : '$totalDuplicates duplicate files in ${_duplicateGroups.length} groups (${formatBytes(wastedBytes)} duplicate content)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                'Compare file contents using SHA-256. Cloud candidates are downloaded '
                'for verification. Only verified matches are listed.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (_errors.isNotEmpty)
              Text(
                '${_errors.length} items could not be verified. ${_errors.first}',
                maxLines: 3,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            // Results
            Expanded(
              child: _duplicateGroups.isEmpty
                  ? Center(
                      child: _done
                          ? const Icon(
                              Icons.check_circle_outline,
                              size: 48,
                              color: Colors.green,
                            )
                          : const Icon(
                              Icons.search,
                              size: 48,
                              color: Colors.grey,
                            ),
                    )
                  : ListView.builder(
                      itemCount: _duplicateGroups.length,
                      itemBuilder: (context, groupIdx) {
                        final group = _duplicateGroups[groupIdx];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.orange.shade100,
                              child: Text(
                                '${group.length}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            title: Text(
                              group.first.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              strings.text('copies', {
                                'count': group.length,
                                'size': formatBytes(group.first.size ?? 0),
                              }),
                              style: const TextStyle(fontSize: 11),
                            ),
                            children: group
                                .map(
                                  (f) => ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.insert_drive_file,
                                      size: 16,
                                    ),
                                    title: Text(
                                      f.path ?? f.name,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    subtitle: f.updatedAt != null
                                        ? Text(
                                            formatDate(f.updatedAt!),
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          )
                                        : null,
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        size: 16,
                                        color: Colors.red,
                                      ),
                                      tooltip: 'Delete this copy',
                                      onPressed:
                                          group.length < 2 ||
                                              _origin?.isCurrent != true
                                          ? null
                                          : () => _deleteCopy(f, group),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
        if (_scanning)
          TextButton(
            onPressed: () => setState(() => _cancelled = true),
            child: const Text('Cancel scan'),
          ),
        if (!_scanning)
          ElevatedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: Text(strings.text(_done ? 'scanAgain' : 'scan')),
            onPressed: _scan,
          ),
      ],
    );
  }
}
