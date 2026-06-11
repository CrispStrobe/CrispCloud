// lib/widgets/batch_rename_dialog.dart
//
// Batch rename dialog supporting pattern-based renaming:
// - Find & replace (text or regex)
// - Sequential numbering
// - Add prefix/suffix
// - Change extension

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../l10n/app_localizations.dart';
import '../services/log_service.dart';

enum RenameMode { findReplace, numbering, prefixSuffix, extension }

class BatchRenameDialog extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  final PanelSide side;
  final List<FileItem> files;

  const BatchRenameDialog({
    super.key,
    required this.parentRef,
    required this.side,
    required this.files,
  });

  @override
  ConsumerState<BatchRenameDialog> createState() => _BatchRenameDialogState();
}

class _BatchRenameDialogState extends ConsumerState<BatchRenameDialog> {
  RenameMode _mode = RenameMode.findReplace;
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  final _prefixController = TextEditingController();
  final _suffixController = TextEditingController();
  final _extensionController = TextEditingController();
  final _startNumController = TextEditingController(text: '1');
  bool _useRegex = false;
  bool _isProcessing = false;

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    _prefixController.dispose();
    _suffixController.dispose();
    _extensionController.dispose();
    _startNumController.dispose();
    super.dispose();
  }

  List<String> get _preview {
    return widget.files.map((f) => _applyRename(f.name, widget.files.indexOf(f))).toList();
  }

  String _applyRename(String name, int index) {
    switch (_mode) {
      case RenameMode.findReplace:
        final find = _findController.text;
        if (find.isEmpty) return name;
        if (_useRegex) {
          try {
            return name.replaceAll(RegExp(find), _replaceController.text);
          } catch (e) {
            // TODO: add logging
            return name;
          }
        }
        return name.replaceAll(find, _replaceController.text);

      case RenameMode.numbering:
        final start = int.tryParse(_startNumController.text) ?? 1;
        final num = (start + index).toString().padLeft(3, '0');
        final dot = name.lastIndexOf('.');
        if (dot > 0) {
          final ext = name.substring(dot);
          final base = name.substring(0, dot);
          return '${base}_$num$ext';
        }
        return '${name}_$num';

      case RenameMode.prefixSuffix:
        final prefix = _prefixController.text;
        final suffix = _suffixController.text;
        final dot = name.lastIndexOf('.');
        if (dot > 0 && suffix.isNotEmpty) {
          final ext = name.substring(dot);
          final base = name.substring(0, dot);
          return '$prefix$base$suffix$ext';
        }
        return '$prefix$name$suffix';

      case RenameMode.extension:
        final newExt = _extensionController.text;
        if (newExt.isEmpty) return name;
        final dot = name.lastIndexOf('.');
        if (dot > 0) {
          return '${name.substring(0, dot)}.$newExt';
        }
        return '$name.$newExt';
    }
  }

  @override
  Widget build(BuildContext context) {
    final previews = _preview;

    return AlertDialog(
      title: Text('Batch Rename (${widget.files.length} files)'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mode selector
            SegmentedButton<RenameMode>(
              segments: const [
                ButtonSegment(value: RenameMode.findReplace, label: Text('Find/Replace')),
                ButtonSegment(value: RenameMode.numbering, label: Text('Number')),
                ButtonSegment(value: RenameMode.prefixSuffix, label: Text('Prefix/Suffix')),
                ButtonSegment(value: RenameMode.extension, label: Text('Extension')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 16),

            // Mode-specific fields
            ..._buildFields(),

            const SizedBox(height: 16),

            // Preview
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.files.length.clamp(0, 10),
                itemBuilder: (context, i) {
                  final original = widget.files[i].name;
                  final renamed = previews[i];
                  final changed = original != renamed;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(original,
                              style: TextStyle(
                                fontSize: 12,
                                color: changed ? Theme.of(context).colorScheme.onSurfaceVariant : null,
                                decoration: changed ? TextDecoration.lineThrough : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (changed) ...[
                          const Icon(Icons.arrow_forward, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(renamed,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            if (widget.files.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('... and ${widget.files.length - 10} more',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _executeRename,
          child: _isProcessing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Rename All'),
        ),
      ],
    );
  }

  List<Widget> _buildFields() {
    switch (_mode) {
      case RenameMode.findReplace:
        return [
          TextField(
            controller: _findController,
            decoration: const InputDecoration(labelText: 'Find', border: OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _replaceController,
            decoration: const InputDecoration(labelText: 'Replace with', border: OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Checkbox(value: _useRegex, onChanged: (v) => setState(() => _useRegex = v ?? false)),
              const Text('Use regex', style: TextStyle(fontSize: 13)),
            ],
          ),
        ];
      case RenameMode.numbering:
        return [
          TextField(
            controller: _startNumController,
            decoration: const InputDecoration(labelText: 'Start number', border: OutlineInputBorder(), isDense: true),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
        ];
      case RenameMode.prefixSuffix:
        return [
          TextField(
            controller: _prefixController,
            decoration: const InputDecoration(labelText: 'Prefix', border: OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _suffixController,
            decoration: const InputDecoration(labelText: 'Suffix (before extension)', border: OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
        ];
      case RenameMode.extension:
        return [
          TextField(
            controller: _extensionController,
            decoration: const InputDecoration(labelText: 'New extension (without dot)', border: OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
        ];
    }
  }

  Future<void> _executeRename() async {
    setState(() => _isProcessing = true);

    try {
      final panel = ref.read(panelProvider(widget.side));
      for (int i = 0; i < widget.files.length; i++) {
        final file = widget.files[i];
        final newName = _applyRename(file.name, i);
        if (newName != file.name && newName.isNotEmpty) {
          await panel.renameFile(file, newName);
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rename failed: $e')),
        );
      }
    }

    if (mounted) setState(() => _isProcessing = false);
  }
}

/// Show the batch rename dialog.
void showBatchRenameDialog(BuildContext context, WidgetRef ref, PanelSide side, List<FileItem> files) {
  if (files.length < 2) return;
  showDialog(
    context: context,
    builder: (_) => BatchRenameDialog(
      parentRef: ref,
      side: side,
      files: files,
    ),
  );
}
