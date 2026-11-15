// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/archive_creation_strings.dart';
import '../l10n/archive_job_strings.dart';
import '../l10n/archive_png_carving_strings.dart';
import '../models/archive_operation.dart';
import '../models/file_item.dart';
import '../services/archive_creation_service.dart';
import '../services/archive_png_carving_service.dart';
import '../services/archive_png_carving_workflow.dart';
import '../services/file_operation_service.dart';
import '../utils/formatters.dart';

typedef EnqueueArchivePngCarving =
    Future<ArchiveOperationHandle<ArchiveCreationResult>> Function(
      CapturedArchivePngCarving captured,
      String outputName,
      Set<int> selectedOffsets,
    );

class ArchivePngCarvingDialog extends StatefulWidget {
  const ArchivePngCarvingDialog({
    super.key,
    required this.source,
    required this.file,
    required this.destination,
    required this.destinationDirectory,
    this.enqueue,
    this.onViewJobs,
  });
  final FileOperationBackend source;
  final FileItem file;
  final FileOperationBackend destination;
  final String destinationDirectory;
  final EnqueueArchivePngCarving? enqueue;
  final Future<void> Function()? onViewJobs;

  @override
  State<ArchivePngCarvingDialog> createState() =>
      _ArchivePngCarvingDialogState();
}

class _ArchivePngCarvingDialogState extends State<ArchivePngCarvingDialog> {
  late final TextEditingController _name;
  final _control = FileOperationControl();
  final _selection = <int>{};
  CapturedArchivePngCarving? _captured;
  ArchivePngCarvingProgress? _progress;
  ArchiveOperationHandle<ArchiveCreationResult>? _job;
  ArchiveCreationResult? _result;
  Object? _error;
  bool _busy = true, _admitting = false;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  String tr(String key, [List<Object> values = const []]) =>
      archivePngCarvingText(context, key, values);
  String common(String key) => archiveCreationText(context, key);
  FileOperationControl get control => _job?.control ?? _control;

  @override
  void initState() {
    super.initState();
    final file = widget.file.name;
    final dot = file.lastIndexOf('.');
    _name = TextEditingController(
      text: '${dot > 0 ? file.substring(0, dot) : file}.carved-png.zip',
    );
    unawaited(Future<void>.delayed(Duration.zero, _scan));
  }

  void _progressChanged(ArchivePngCarvingProgress progress) {
    if (!mounted) return;
    final now = DateTime.now();
    if (progress.phase != _progress?.phase ||
        progress.completed == progress.total ||
        now.difference(_lastUpdate).inMilliseconds >= 80) {
      _lastUpdate = now;
      setState(() => _progress = progress);
    }
  }

  Future<void> _scan() async {
    if (!mounted) return;
    try {
      final captured = await captureArchivePngCarving(
        source: widget.source,
        file: widget.file,
        control: _control,
        onProgress: _progressChanged,
      );
      if (!mounted) return;
      setState(() {
        _captured = captured;
        _selection.addAll(
          captured.report.recoverableCandidates.map((e) => e.offset),
        );
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _jobChanged() {
    final job = _job;
    if (!mounted || job == null) return;
    setState(() {
      _progress = job.pngCarvingProgress;
      _result = job.result;
      _error = job.error;
      _busy = !job.isSettled;
    });
  }

  Future<void> _recover() async {
    final captured = _captured;
    if (_busy ||
        _job != null ||
        _result != null ||
        captured == null ||
        _selection.isEmpty) {
      return;
    }
    try {
      ArchiveCreationOptions(name: _name.text).validate();
    } catch (error) {
      setState(() => _error = error);
      return;
    }
    final selected = Set<int>.unmodifiable(_selection);
    setState(() {
      _busy = true;
      _admitting = widget.enqueue != null;
      _error = null;
    });
    try {
      if (widget.enqueue case final enqueue?) {
        final job = await enqueue(captured, _name.text, selected);
        // Queue admission transfers lifetime ownership even if this route was
        // disposed while its journal acknowledgement was pending.
        if (!mounted) return;
        _job = job;
        job.addListener(_jobChanged);
        _jobChanged();
      } else {
        final result = await publishArchivePngCarving(
          captured: captured,
          destination: widget.destination,
          destinationDirectory: widget.destinationDirectory,
          outputName: _name.text,
          selectedOffsets: selected,
          control: _control,
          onProgress: _progressChanged,
        );
        if (mounted) setState(() => _result = result);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _admitting = false;
          _busy = _job != null && !_job!.isSettled;
        });
      }
    }
  }

  @override
  void dispose() {
    _job?.removeListener(_jobChanged);
    _control.cancel();
    _name.dispose();
    super.dispose();
  }

  String _phase() => tr(switch (_progress?.phase) {
    ArchivePngCarvingPhase.recovering => 'Recovering files…',
    ArchivePngCarvingPhase.verifying => 'Verifying recovered ZIP…',
    ArchivePngCarvingPhase.publishing => 'Saving new ZIP…',
    _ => 'Scanning for PNG images…',
  });

  String _reportText() {
    final report = _captured!.report;
    String clean(String value) =>
        value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');
    return [
      '${tr('PNG carving')}: ${clean(widget.file.name)}',
      '${tr('Source SHA-256')}: ${report.sourceSha256}',
      'Source bytes: ${report.sourceBytes}; scanned bytes: ${report.scannedBytes}',
      pngCarvingStopDescription(report.stopReason),
      'Offset\tName\tSize\tStatus\tReason',
      for (final entry in report.candidates)
        '${entry.offset}\t${clean(entry.name)}\t${entry.size}\t${entry.status.name}\t${pngCarvingReasonDescription(entry.reason)}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final report = _captured?.report;
    final enabled = !_busy && _job == null && _result == null;
    final progress = _progress;
    final result = _result;
    final publicationWarning =
        _job?.publicationWarning ?? result?.publicationWarning;
    return PopScope(
      canPop: !_admitting && (!_busy || _job != null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_admitting && _job == null) {
          setState(control.cancel);
        }
      },
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Text(
          tr('PNG carving'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: SizedBox(
          width: 760,
          height: 500,
          child: ListView.builder(
            itemCount: (report?.candidates.length ?? 0) + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.file.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        'Review validated PNG images, then save them with an offset and hash report in a new ZIP. The original file is retained.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        'Limits: 64 MiB input and output. Only supported complete PNG images are offered; names, directories and fragmented files are not reconstructed.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        'Profile: non-interlaced 8-bit PNG. Indexed color and animation are unsupported.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    if (_busy) ...[
                      LinearProgressIndicator(
                        value: progress == null || progress.total <= 0
                            ? null
                            : (progress.completed / progress.total).clamp(0, 1),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _admitting
                            ? archiveJobText(context, 'Queue in background')
                            : _phase(),
                      ),
                      if (progress?.path.isNotEmpty == true)
                        Text(
                          progress!.path,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                    if (_job != null && _busy)
                      Text(
                        tr(
                          'The recovery job continues in the Operations queue.',
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        archiveCreationError(context, _error!),
                        key: const ValueKey('png-carving-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (result != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        tr('Saved {0}', [result.path]),
                        key: const ValueKey('png-carving-result'),
                      ),
                      if (publicationWarning != null)
                        Text('$publicationWarning'),
                    ],
                    if (report != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        tr('{0} ready · {1} excluded · {2} selected', [
                          report.recoverableCandidates.length,
                          report.candidates.length -
                              report.recoverableCandidates.length,
                          _selection.length,
                        ]),
                      ),
                      Text(pngCarvingStopDescription(report.stopReason)),
                      Text(
                        '${formatBytes(report.scannedBytes)} / ${formatBytes(report.sourceBytes)}',
                      ),
                      ExpansionTile(
                        title: Text(tr('Source SHA-256')),
                        children: [SelectableText(report.sourceSha256)],
                      ),
                      TextField(
                        key: const ValueKey('png-carving-name'),
                        controller: _name,
                        enabled: enabled,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: tr('New ZIP filename'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.destination.paths.join(
                          widget.destinationDirectory,
                          _name.text,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: enabled
                                ? () => setState(
                                    () => _selection
                                      ..clear()
                                      ..addAll(
                                        report.recoverableCandidates.map(
                                          (e) => e.offset,
                                        ),
                                      ),
                                  )
                                : null,
                            child: Text(tr('Select all')),
                          ),
                          TextButton(
                            onPressed: enabled
                                ? () => setState(_selection.clear)
                                : null,
                            child: Text(tr('Clear selection')),
                          ),
                          TextButton(
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: _reportText()),
                            ),
                            child: Text(tr('Copy report')),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              }
              final entry = report!.candidates[index - 1];
              return CheckboxListTile(
                key: ValueKey('png-carving-entry-${entry.offset}'),
                value: _selection.contains(entry.offset),
                onChanged: enabled && entry.isRecoverable
                    ? (value) => setState(() {
                        if (value == true) {
                          _selection.add(entry.offset);
                        } else {
                          _selection.remove(entry.offset);
                        }
                      })
                    : null,
                title: Text(
                  entry.name.isEmpty ? 'Offset ${entry.offset}' : entry.name,
                ),
                subtitle: Text(
                  '${tr(entry.isRecoverable ? 'Ready for recovery' : 'Excluded')} · ${formatBytes(entry.size)}\n'
                  '${entry.offset}–${entry.endOffset} · ${entry.width ?? '?'} × ${entry.height ?? '?'}\n'
                  '${pngCarvingReasonDescription(entry.reason)}',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              );
            },
          ),
        ),
        actions: [
          if (_busy && !_admitting) ...[
            if (_job != null)
              TextButton(
                onPressed: () => setState(() {
                  if (control.isPaused) {
                    control.resume();
                  } else {
                    control.pause();
                  }
                }),
                child: Text(
                  archiveJobText(
                    context,
                    control.isPaused ? 'Resume' : 'Pause',
                  ),
                ),
              ),
            TextButton(
              key: const ValueKey('png-carving-cancel'),
              onPressed: () => setState(control.cancel),
              child: Text(common('Cancel')),
            ),
          ],
          if (_job != null && widget.onViewJobs != null)
            TextButton(
              onPressed: widget.onViewJobs,
              child: Text(archiveJobText(context, 'View jobs')),
            ),
          TextButton(
            key: const ValueKey('png-carving-close'),
            onPressed: !_admitting && (!_busy || _job != null)
                ? () => Navigator.of(context).pop(result)
                : null,
            child: Text(common('Close')),
          ),
          if (enabled && report != null)
            FilledButton(
              key: const ValueKey('png-carving-save'),
              onPressed: _selection.isEmpty ? null : _recover,
              child: Text(tr('Recover selected')),
            ),
        ],
      ),
    );
  }
}
