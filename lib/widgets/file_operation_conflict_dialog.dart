import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_operation_service.dart';
import 'diff_viewer_dialog.dart';

Future<FileConflictResolution> showFileOperationConflict(
  BuildContext context, {
  required FileOperationEntry entry,
  required FileItem existing,
  required FileOperationBackend source,
  required FileOperationBackend destination,
}) async =>
    await showDialog<FileConflictResolution>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConflictDialog(
        entry: entry,
        existing: existing,
        source: source,
        destination: destination,
      ),
    ) ??
    const FileConflictResolution(FileConflictDecision.cancel);

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({
    required this.entry,
    required this.existing,
    required this.source,
    required this.destination,
  });
  final FileOperationEntry entry;
  final FileItem existing;
  final FileOperationBackend source;
  final FileOperationBackend destination;
  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  final _name = TextEditingController();
  bool _all = false;
  bool _comparing = false;
  String? _comparison;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _choose(FileConflictDecision decision, {bool renamed = false}) {
    if (renamed && _name.text.trim().isEmpty) {
      setState(() => _comparison = 'Enter a new filename first.');
      return;
    }
    Navigator.pop(
      context,
      FileConflictResolution(
        decision,
        name: renamed ? _name.text.trim() : null,
        applyToAll: !renamed && _all,
      ),
    );
  }

  Future<void> _compare({required bool text}) async {
    setState(() {
      _comparing = true;
      _comparison = null;
    });
    try {
      if (!widget.source.isCurrent || !widget.destination.isCurrent) {
        throw StateError('The original storage account is unavailable.');
      }
      if (text) {
        Future<String> read(FileOperationBackend backend, FileItem file) async {
          final bytes = <int>[];
          await for (final chunk in backend.readFile(file)) {
            if (!backend.isCurrent) {
              throw StateError('Storage account changed.');
            }
            if (bytes.length + chunk.length > 1024 * 1024) {
              throw StateError(
                'Text comparison is limited to 1 MiB per file. Use Compare SHA-256 for larger files.',
              );
            }
            bytes.addAll(chunk);
          }
          if (bytes.contains(0)) {
            throw StateError('Binary file. Use Compare SHA-256.');
          }
          return utf8.decode(bytes);
        }

        final left = await read(widget.source, widget.entry.source);
        final right = await read(widget.destination, widget.existing);
        if (!mounted) return;
        showDiffViewerFromContent(
          context,
          leftContent: left,
          rightContent: right,
          leftLabel: widget.entry.source.path!,
          rightLabel: widget.entry.destination,
        );
      } else {
        Future<Digest> hash(FileOperationBackend backend, FileItem file) =>
            sha256
                .bind(
                  backend.readFile(file).map((chunk) {
                    if (!backend.isCurrent) {
                      throw StateError('Storage account changed.');
                    }
                    return chunk;
                  }),
                )
                .first;
        final left = await hash(widget.source, widget.entry.source);
        final right = await hash(widget.destination, widget.existing);
        if (mounted) {
          setState(
            () => _comparison = left == right
                ? 'Contents are identical (SHA-256).'
                : 'Contents differ (SHA-256).',
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _comparison = error.toString());
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final folder = entry.source.isFolder;
    return AlertDialog(
      title: Text(folder ? 'Folder already exists' : 'File already exists'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                'Source: ${entry.source.path}\nDestination: ${entry.destination}\n\n'
                'Source: ${entry.source.size ?? 'unknown'} bytes · ${entry.source.updatedAt ?? 'time unknown'}\n'
                'Destination: ${widget.existing.size ?? 'unknown'} bytes · ${widget.existing.updatedAt ?? 'time unknown'}',
              ),
              if (!folder) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _comparing ? null : () => _compare(text: true),
                      child: const Text('Compare text'),
                    ),
                    TextButton(
                      onPressed: _comparing
                          ? null
                          : () => _compare(text: false),
                      child: const Text('Compare SHA-256'),
                    ),
                  ],
                ),
                if (_comparing) const LinearProgressIndicator(),
                if (_comparison != null) SelectableText(_comparison!),
                const SizedBox(height: 8),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'New filename for this conflict',
                    border: OutlineInputBorder(),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => _choose(
                        FileConflictDecision.renameSource,
                        renamed: true,
                      ),
                      child: const Text('Rename incoming file'),
                    ),
                    if (widget.destination.capabilities.noReplaceMove)
                      TextButton(
                        onPressed: () => _choose(
                          FileConflictDecision.renameDestination,
                          renamed: true,
                        ),
                        child: const Text('Rename existing file'),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () =>
                          _choose(FileConflictDecision.resumeVerified),
                      child: const Text('Resume after prefix check'),
                    ),
                    TextButton(
                      onPressed: () => _choose(FileConflictDecision.append),
                      child: const Text('Append to existing file'),
                    ),
                  ],
                ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _all,
                title: Text(
                  'Apply this decision to remaining ${folder ? 'folders' : 'files'}',
                ),
                onChanged: (value) => setState(() => _all = value!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _choose(FileConflictDecision.cancel),
          child: const Text('Cancel operation'),
        ),
        TextButton(
          onPressed: () => _choose(FileConflictDecision.skip),
          child: const Text('Skip'),
        ),
        if (!folder)
          TextButton(
            onPressed: () => _choose(FileConflictDecision.keepBoth),
            child: const Text('Keep both'),
          ),
        FilledButton(
          onPressed: () => _choose(
            folder ? FileConflictDecision.merge : FileConflictDecision.replace,
          ),
          child: Text(folder ? 'Merge folder' : 'Replace file'),
        ),
      ],
    );
  }
}
