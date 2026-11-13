import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/archive_batch_extraction_strings.dart';
import '../models/file_item.dart';
import '../services/archive_batch_extraction_service.dart';
import '../services/file_operation_service.dart';
import '../services/local_file_service.dart';
import '../utils/formatters.dart';

Future<void> showArchiveBatchExtractionDialog(
  BuildContext context, {
  required FileOperationBackend source,
  required List<FileItem> files,
  required String targetDirectory,
  LocalFileService? local,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ArchiveBatchExtractionDialog(
    source: source,
    files: files,
    targetDirectory: targetDirectory,
    local: local,
  ),
);

class ArchiveBatchExtractionDialog extends StatefulWidget {
  const ArchiveBatchExtractionDialog({
    super.key,
    required this.source,
    required this.files,
    required this.targetDirectory,
    this.local,
  });
  final FileOperationBackend source;
  final List<FileItem> files;
  final String targetDirectory;
  final LocalFileService? local;
  @override
  State<ArchiveBatchExtractionDialog> createState() =>
      _ArchiveBatchExtractionDialogState();
}

class _ArchiveBatchExtractionDialogState
    extends State<ArchiveBatchExtractionDialog> {
  late final TextEditingController _destination;
  final _mask = TextEditingController(text: '*');
  ArchiveExtractionFolderMode _mode = ArchiveExtractionFolderMode.perArchive;
  bool _flatten = false, _fullPath = false, _caseSensitive = false;
  bool _busy = false, _cancelled = false;
  ArchiveBatchExtractionPlan? _plan;
  ArchiveBatchExtractionReport? _report;
  ArchiveBatchExtractionProgress? _progress;
  Object? _error;
  int _generation = 0;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  String tr(String key, [List<Object> values = const []]) =>
      archiveBatchExtractionText(context, key, values);

  @override
  void initState() {
    super.initState();
    _destination = TextEditingController(text: widget.targetDirectory);
  }

  @override
  void dispose() {
    _cancelled = true;
    _generation++;
    final plan = _plan;
    if (plan != null) unawaited(plan.close());
    _destination.dispose();
    _mask.dispose();
    super.dispose();
  }

  void _changed([String? _]) {
    if (_busy || _report != null) return;
    final previous = _plan;
    setState(() {
      _plan = null;
      _error = null;
    });
    if (previous != null) unawaited(previous.close());
  }

  void _update(ArchiveBatchExtractionProgress progress) {
    if (!mounted) return;
    final now = DateTime.now();
    if (_progress?.currentFile != progress.currentFile ||
        _progress?.completedArchives != progress.completedArchives ||
        now.difference(_lastUpdate).inMilliseconds >= 80) {
      _lastUpdate = now;
      setState(() => _progress = progress);
    }
  }

  Future<String?> _password(
    FileItem file, {
    required bool wrongPassword,
  }) async {
    if (!mounted || _cancelled) return null;
    return showDialog<String>(
      context: context,
      builder: (_) => _PasswordDialog(file.name, wrongPassword),
    );
  }

  Future<void> _preview() async {
    final token = ++_generation;
    final old = _plan;
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _plan = null;
      _progress = null;
    });
    await old?.close();
    try {
      final plan = await ArchiveBatchExtractionPlan.prepare(
        source: widget.source,
        files: widget.files,
        targetDirectory: _destination.text,
        local: widget.local,
        options: ArchiveBatchExtractionOptions(
          folderMode: _mode,
          mask: _mask.text,
          flatten: _flatten,
          matchFullPath: _fullPath,
          caseSensitive: _caseSensitive,
        ),
        isCancelled: () => _cancelled || !mounted || token != _generation,
        onProgress: _update,
        requestPassword: _password,
      );
      if (!mounted || token != _generation || _cancelled) {
        await plan.close();
        return;
      }
      setState(() => _plan = plan);
    } catch (error) {
      if (mounted && token == _generation) {
        setState(() => _error = _cancelled ? tr('Cancelled') : error);
      }
    } finally {
      if (mounted && token == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _extract() async {
    final plan = _plan;
    if (plan == null || _busy || plan.isClosed) return;
    setState(() {
      _busy = true;
      _cancelled = false;
      _progress = null;
      _error = null;
    });
    try {
      final report = await plan.extract(
        isCancelled: () => _cancelled || !mounted,
        onProgress: _update,
      );
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _status(ArchiveBatchExtractionItem item) => tr(switch (item.status) {
    ArchiveBatchExtractionStatus.completed => 'Completed',
    ArchiveBatchExtractionStatus.failed => 'Failed',
    ArchiveBatchExtractionStatus.cancelled => 'Cancelled',
    ArchiveBatchExtractionStatus.skipped => 'Skipped',
  });
  String _skip(ArchiveBatchExtractionSkipReason reason) => tr(switch (reason) {
    ArchiveBatchExtractionSkipReason.directory => 'Folder selected',
    ArchiveBatchExtractionSkipReason.symbolicLink => 'Symbolic link selected',
    ArchiveBatchExtractionSkipReason.duplicate => 'Already selected',
    ArchiveBatchExtractionSkipReason.passwordDeclined => 'Password skipped',
    ArchiveBatchExtractionSkipReason.noMatches => 'No matching members',
  });
  String _summary(ArchiveBatchExtractionReport report) => tr(
    'Result: {0} completed · {1} files written · {2} skipped · {3} unprocessed',
    [
      report.completedCount,
      report.publishedFileCount,
      report.skippedCount,
      report.unprocessedCount,
    ],
  );
  String _reportText(ArchiveBatchExtractionReport report) => [
    tr('Batch archive extraction'),
    _line(_destination.text),
    _summary(report),
    tr('Completed files stay in place if the batch stops.'),
    if (report.detail != null) _line(report.detail!),
    for (final item in report.items) ...[
      '${_status(item)}\t${_line(item.file.name)}\t${item.skipReason == null ? '' : _skip(item.skipReason!)}',
      if (item.snapshotSha256 != null) 'SHA-256: ${item.snapshotSha256}',
      if (item.detail != null) _line(item.detail!),
      ...item.publishedFiles.map(_line),
      '',
    ],
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final report = _report;
    final editable = !_busy && report == null;
    final count =
        report?.items.length ??
        ((plan?.entries.length ?? 0) + (plan?.skipped.length ?? 0));
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _busy) setState(() => _cancelled = true);
      },
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: Text(tr('Batch archive extraction')),
        content: SizedBox(
          width: 760,
          height: math.min(560, MediaQuery.sizeOf(context).height * .60),
          child: ListView.builder(
            key: const ValueKey('batch-extraction-content'),
            itemCount: count + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        'Existing files and colliding names are refused. Source archives stay unchanged.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('batch-extraction-destination'),
                      controller: _destination,
                      enabled: editable,
                      onChanged: _changed,
                      decoration: InputDecoration(
                        labelText: tr('Destination folder'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('batch-extraction-mask'),
                      controller: _mask,
                      enabled: editable,
                      onChanged: _changed,
                      decoration: InputDecoration(
                        labelText: tr('Mask'),
                        helperText: tr('Example: *.jpg;*.png|thumb*'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<ArchiveExtractionFolderMode>(
                      key: const ValueKey('batch-extraction-folder-mode'),
                      initialValue: _mode,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: tr('Folder layout'),
                      ),
                      items: [
                        for (final mode in ArchiveExtractionFolderMode.values)
                          DropdownMenuItem(
                            value: mode,
                            child: Text(
                              tr(switch (mode) {
                                ArchiveExtractionFolderMode.perArchive =>
                                  'One folder per archive',
                                ArchiveExtractionFolderMode.shared =>
                                  'Shared destination',
                                ArchiveExtractionFolderMode.smart =>
                                  'Smart folders',
                              }),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: editable
                          ? (value) {
                              if (value != null) {
                                _changed();
                                setState(() => _mode = value);
                              }
                            }
                          : null,
                    ),
                    if (_mode == ArchiveExtractionFolderMode.smart)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          tr(
                            'Smart keeps one top-level item; otherwise it creates an archive folder.',
                          ),
                        ),
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(tr('Match full member paths')),
                      value: _fullPath,
                      onChanged: editable
                          ? (value) {
                              _changed();
                              setState(() => _fullPath = value!);
                            }
                          : null,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(tr('Case sensitive')),
                      value: _caseSensitive,
                      onChanged: editable
                          ? (value) {
                              _changed();
                              setState(() => _caseSensitive = value!);
                            }
                          : null,
                    ),
                    CheckboxListTile(
                      key: const ValueKey('batch-extraction-flatten'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(tr('Flatten files')),
                      value: _flatten,
                      onChanged: editable
                          ? (value) {
                              _changed();
                              setState(() => _flatten = value!);
                            }
                          : null,
                    ),
                    if (_flatten)
                      Text(
                        tr(
                          'Flattening omits empty folders and requires unique destination filenames.',
                        ),
                      ),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      Text(
                        tr(
                          _progress?.preparing ?? true
                              ? 'Preparing {0} of {1}'
                              : 'Extracting {0} of {1}',
                          [
                            ((_progress?.completedArchives ?? 0) + 1).clamp(
                              0,
                              widget.files.length,
                            ),
                            widget.files.length,
                          ],
                        ),
                      ),
                      if (_progress?.currentFile != null)
                        Text(
                          _progress!.currentFile!.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SelectableText(
                          '$_error',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (plan != null && report == null) ...[
                      const SizedBox(height: 12),
                      Text(
                        tr(
                          'Preview: {0} destinations · {1} · {2} skipped archives',
                          [
                            plan.entries.length,
                            formatBytes(plan.outputBytes),
                            plan.skipped.length,
                          ],
                        ),
                        key: const ValueKey('batch-extraction-preview-summary'),
                      ),
                      Text(tr('No destination files have been written.')),
                    ],
                    if (report != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _summary(report),
                        key: const ValueKey('batch-extraction-report-summary'),
                      ),
                      Text(
                        tr('Completed files stay in place if the batch stops.'),
                      ),
                      if (report.stopReason != null)
                        Text(
                          tr(switch (report.stopReason!) {
                            ArchiveBatchExtractionStopReason.cancelled =>
                              'Cancelled',
                            ArchiveBatchExtractionStopReason.unavailable =>
                              'Archive no longer available',
                            ArchiveBatchExtractionStopReason.failed => 'Failed',
                          }),
                        ),
                      if (report.detail != null) SelectableText(report.detail!),
                    ],
                    const SizedBox(height: 8),
                  ],
                );
              }
              if (report != null) {
                final item = report.items[index - 1];
                return ListTile(
                  title: Text(item.file.name),
                  subtitle: Text(
                    [
                      _status(item),
                      if (item.skipReason != null) _skip(item.skipReason!),
                      if (item.detail != null) item.detail!,
                      ...item.publishedFiles,
                    ].join('\n'),
                  ),
                  isThreeLine: false,
                );
              }
              final entryIndex = index - 1;
              if (entryIndex >= plan!.entries.length) {
                final skip = plan.skipped[entryIndex - plan.entries.length];
                return ListTile(
                  title: Text(skip.file.name),
                  subtitle: Text(_skip(skip.reason)),
                );
              }
              final entry = plan.entries[entryIndex];
              return ListTile(
                leading: Icon(
                  entry.isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                ),
                title: Text(entry.destination),
                subtitle: Text(
                  '${entry.archiveFile.name} · ${entry.memberPath}',
                ),
                trailing: entry.isDirectory
                    ? null
                    : Text(formatBytes(entry.size)),
              );
            },
          ),
        ),
        actions: [
          if (report != null)
            TextButton.icon(
              key: const ValueKey('copy-batch-extraction-report'),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _reportText(report))),
              icon: const Icon(Icons.copy_outlined),
              label: Text(tr('Copy report')),
            ),
          if (_busy)
            TextButton(
              onPressed: _cancelled
                  ? null
                  : () => setState(() => _cancelled = true),
              child: Text(tr('Cancel')),
            )
          else ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('Close')),
            ),
            if (report == null)
              TextButton(
                key: const ValueKey('batch-extraction-preview'),
                onPressed: _preview,
                child: Text(tr('Preview')),
              ),
            if (report == null && plan != null && plan.entries.isNotEmpty)
              FilledButton(
                key: const ValueKey('batch-extraction-extract'),
                onPressed: _extract,
                child: Text(tr('Extract')),
              ),
          ],
        ],
      ),
    );
  }
}

String _line(String value) => value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog(this.name, this.wrong);
  final String name;
  final bool wrong;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.clear();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String tr(String key, [List<Object> values = const []]) =>
        archiveBatchExtractionText(context, key, values);
    return AlertDialog(
      title: Text(tr('Password for {0}', [widget.name])),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.wrong)
              Text(
                tr(
                  'The password was rejected or the protected data is damaged.',
                ),
              ),
            TextField(
              key: const ValueKey('batch-extraction-password'),
              controller: controller,
              autofocus: true,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(labelText: tr('Password')),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Skip')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(tr('Unlock')),
        ),
      ],
    );
  }
}
