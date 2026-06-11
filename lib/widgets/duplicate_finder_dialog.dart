// lib/widgets/duplicate_finder_dialog.dart
//
// Scans files in the current panel for duplicates by size + name pattern.
// For local files, computes MD5 hashes to confirm true duplicates.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';
import '../l10n/app_localizations.dart';

void showDuplicateFinderDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (_) => const _DuplicateFinderDialog(),
  );
}

class _DuplicateFinderDialog extends ConsumerStatefulWidget {
  const _DuplicateFinderDialog();

  @override
  ConsumerState<_DuplicateFinderDialog> createState() => _DuplicateFinderDialogState();
}

class _DuplicateFinderDialogState extends ConsumerState<_DuplicateFinderDialog> {
  List<List<FileItem>> _duplicateGroups = [];
  bool _scanning = false;
  bool _done = false;
  int _scannedCount = 0;
  int _totalCount = 0;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _done = false;
      _duplicateGroups = [];
      _scannedCount = 0;
    });

    final activePanel = ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(activePanel));
    final files = panel.files?.where((f) => !f.isFolder).toList() ?? [];
    _totalCount = files.length;

    // Group by size first (fast pre-filter)
    final sizeGroups = <int, List<FileItem>>{};
    for (final file in files) {
      final size = file.size ?? -1;
      if (size <= 0) continue;
      sizeGroups.putIfAbsent(size, () => []).add(file);
    }

    // Only keep groups with 2+ files of same size
    final candidates = sizeGroups.values.where((g) => g.length > 1).toList();

    if (activePanel == PanelSide.local && !kIsWeb) {
      // Local: verify with MD5 hash
      for (final group in candidates) {
        final hashGroups = <String, List<FileItem>>{};
        for (final file in group) {
          if (file.path == null) continue;
          try {
            final bytes = await File(file.path!).readAsBytes();
            final hash = md5.convert(bytes).toString();
            hashGroups.putIfAbsent(hash, () => []).add(file);
          } catch (_) {}
          _scannedCount++;
          if (mounted) setState(() {});
        }
        for (final hg in hashGroups.values) {
          if (hg.length > 1) _duplicateGroups.add(hg);
        }
      }
    } else {
      // Remote: use size + name similarity (can't hash without downloading)
      for (final group in candidates) {
        _duplicateGroups.add(group);
        _scannedCount += group.length;
        if (mounted) setState(() {});
      }
    }

    if (mounted) {
      setState(() {
        _scanning = false;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePanel = ref.watch(activePanelProvider);
    final totalDuplicates = _duplicateGroups.fold<int>(0, (s, g) => s + g.length - 1);
    final wastedBytes = _duplicateGroups.fold<int>(0, (s, g) {
      final size = g.first.size ?? 0;
      return s + size * (g.length - 1);
    });

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.find_replace, size: 20),
          SizedBox(width: 8),
          Text('Duplicate Finder'),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            // Status bar
            if (_scanning) ...[
              LinearProgressIndicator(value: _totalCount > 0 ? _scannedCount / _totalCount : null),
              const SizedBox(height: 8),
              Text('Scanning... $_scannedCount / $_totalCount files', style: const TextStyle(fontSize: 12)),
            ] else if (_done) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _duplicateGroups.isEmpty ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _duplicateGroups.isEmpty ? Icons.check_circle : Icons.warning,
                      size: 16,
                      color: _duplicateGroups.isEmpty ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _duplicateGroups.isEmpty
                            ? 'No duplicates found!'
                            : '$totalDuplicates duplicate files in ${_duplicateGroups.length} groups (${formatBytes(wastedBytes)} wasted)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                'Scan ${activePanel == PanelSide.local ? "local" : "remote"} files for duplicates.\n'
                '${activePanel == PanelSide.local ? "Uses MD5 hash for accurate matching." : "Uses file size matching (no download)."}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            // Results
            Expanded(
              child: _duplicateGroups.isEmpty
                  ? Center(
                      child: _done
                          ? const Icon(Icons.check_circle_outline, size: 48, color: Colors.green)
                          : const Icon(Icons.search, size: 48, color: Colors.grey),
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
                              child: Text('${group.length}', style: const TextStyle(fontSize: 12)),
                            ),
                            title: Text(group.first.name, style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                              '${group.length} copies • ${formatBytes(group.first.size ?? 0)} each',
                              style: const TextStyle(fontSize: 11),
                            ),
                            children: group.map((f) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.insert_drive_file, size: 16),
                              title: Text(f.path ?? f.name, style: const TextStyle(fontSize: 11)),
                              subtitle: f.updatedAt != null
                                  ? Text(formatDate(f.updatedAt!), style: const TextStyle(fontSize: 10))
                                  : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                tooltip: 'Delete this copy',
                                onPressed: () async {
                                  final panel = ref.read(panelProvider(activePanel));
                                  await panel.deleteFiles([f]);
                                  setState(() => group.remove(f));
                                  if (group.length <= 1) {
                                    setState(() => _duplicateGroups.remove(group));
                                  }
                                },
                              ),
                            )).toList(),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.close)),
        if (!_scanning)
          ElevatedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: Text(_done ? 'Scan Again' : 'Scan'),
            onPressed: _scan,
          ),
      ],
    );
  }
}
