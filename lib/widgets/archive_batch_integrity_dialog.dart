import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/archive_batch_integrity_strings.dart';
import '../models/file_item.dart';
import '../services/archive_batch_integrity_service.dart';
import '../services/archive_integrity_service.dart';
import '../services/file_operation_service.dart';
import '../utils/formatters.dart';

Future<void> showArchiveBatchIntegrityDialog(
  BuildContext context, {
  required FileOperationBackend source,
  required List<FileItem> files,
}) {
  final run = ArchiveBatchIntegrityRun(source: source, files: files);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ArchiveBatchIntegrityDialog(run: run),
  );
}

class ArchiveBatchIntegrityDialog extends StatefulWidget {
  const ArchiveBatchIntegrityDialog({super.key, required this.run});
  final ArchiveBatchIntegrityRun run;
  @override
  State<ArchiveBatchIntegrityDialog> createState() =>
      _ArchiveBatchIntegrityDialogState();
}

class _ArchiveBatchIntegrityDialogState
    extends State<ArchiveBatchIntegrityDialog> {
  ArchiveBatchIntegrityReport? _report;
  ArchiveBatchIntegrityProgress? _progress;
  Object? _error;
  bool _running = true, _cancelled = false;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  String tr(String key, [List<Object> values = const []]) =>
      archiveBatchIntegrityText(context, key, values);

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.delayed(Duration.zero, _run));
  }

  Future<void> _run() async {
    if (!mounted) return;
    try {
      final report = await widget.run.check(
        isCancelled: () => _cancelled || !mounted,
        requestPassword: (file, {required wrongPassword}) async {
          if (!mounted || _cancelled) return null;
          return showDialog<String>(
            context: context,
            builder: (_) => _BatchPasswordDialog(
              name: file.name,
              wrongPassword: wrongPassword,
            ),
          );
        },
        onProgress: (progress) {
          if (!mounted) return;
          final now = DateTime.now();
          if (progress.currentFile != _progress?.currentFile ||
              progress.completedArchives != _progress?.completedArchives ||
              now.difference(_lastUpdate).inMilliseconds >= 80) {
            _lastUpdate = now;
            setState(() => _progress = progress);
          }
        },
      );
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  void _cancel() => setState(() => _cancelled = true);

  String _summary(ArchiveBatchIntegrityReport report) => tr(
    'Archives: {0} checked · {1} with issues · {2} skipped · {3} unchecked',
    [
      report.checkedCount,
      report.issueCount,
      report.skippedCount,
      report.unprocessedCount,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final progress = _progress;
    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _running) _cancel();
      },
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: Text(
          tr('Batch archive integrity'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: SizedBox(
          width: 740,
          height: 480,
          child: ListView.builder(
            itemCount: (report?.items.length ?? 0) + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(_explanation),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    if (_running) ...[
                      LinearProgressIndicator(
                        value: progress == null || progress.totalArchives == 0
                            ? null
                            : progress.completedArchives /
                                  progress.totalArchives,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('Checking archive {0} of {1}', [
                          ((progress?.completedArchives ?? 0) + 1).clamp(
                            0,
                            widget.run.files.length,
                          ),
                          widget.run.files.length,
                        ]),
                      ),
                      if (progress?.currentFile != null)
                        Text(
                          progress!.currentFile!.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (progress?.memberProgress case final member?) ...[
                        Text(
                          tr('Checking {0} of {1}', [
                            member.completedEntries,
                            member.totalEntries,
                          ]),
                        ),
                        if (member.memberName != null)
                          Text(
                            member.memberName!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text(
                          tr('Bytes read: {0}', [
                            formatBytes(member.bytesRead),
                          ]),
                        ),
                      ],
                      if (_cancelled)
                        Text(
                          tr(
                            'Stops between reads. A bounded decode may finish first.',
                          ),
                        ),
                    ],
                    if (_error != null)
                      SelectableText(
                        '$_error',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (report != null) ...[
                      if (report.totalArchives == 0)
                        Text(tr('No archives selected.')),
                      if (report.stopReason != null)
                        Text(
                          tr(switch (report.stopReason!) {
                            ArchiveBatchIntegrityStopReason.cancelled =>
                              'Cancelled',
                            ArchiveBatchIntegrityStopReason.unavailable =>
                              'Archive no longer available',
                            ArchiveBatchIntegrityStopReason.reportLimit =>
                              'Batch report limit reached',
                          }),
                        ),
                      Text(
                        _summary(report),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                );
              }
              final item = report!.items[index - 1];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            item.fullyChecked
                                ? Icons.check_circle_outline
                                : item.hasIssues
                                ? Icons.error_outline
                                : Icons.skip_next_outlined,
                            color: item.hasIssues
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.file.name,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(_itemHeading(context, item)),
                      if (item.report case final members?)
                        Text(_memberSummary(context, members)),
                      if (item.error != null) SelectableText(item.error!),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (item.report != null)
                            TextButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => _BatchItemDialog(item: item),
                              ),
                              child: Text(tr('View results')),
                            ),
                          TextButton.icon(
                            key: ValueKey('copy-archive-report-${index - 1}'),
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: _itemText(context, item)),
                            ),
                            icon: const Icon(Icons.copy_outlined),
                            label: Text(tr('Copy report')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          if (report != null)
            TextButton.icon(
              key: const ValueKey('copy-batch-report'),
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text: [
                    tr('Batch archive integrity'),
                    _summary(report),
                    if (report.stopReason != null) report.stopReason!.name,
                    '',
                    ...report.items.map((item) => _itemText(context, item)),
                  ].join('\n'),
                ),
              ),
              icon: const Icon(Icons.copy_outlined),
              label: Text(tr('Copy report')),
            ),
          if (_running)
            TextButton(
              onPressed: _cancelled ? null : _cancel,
              child: Text(tr('Cancel')),
            )
          else
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('Close')),
            ),
        ],
      ),
    );
  }
}

const _explanation =
    'Reads regular files and checks available checksums. Calculated SHA-256 values describe this snapshot; they do not authenticate its publisher.';
String _line(String value) => value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ');
String _itemHeading(BuildContext context, ArchiveBatchIntegrityItem item) =>
    archiveBatchIntegrityText(
      context,
      item.skipReason != null
          ? switch (item.skipReason!) {
              ArchiveBatchIntegritySkipReason.directory => 'Folder selected',
              ArchiveBatchIntegritySkipReason.symbolicLink =>
                'Symbolic link selected',
              ArchiveBatchIntegritySkipReason.duplicate => 'Already selected',
              ArchiveBatchIntegritySkipReason.passwordRequired =>
                'Password required',
            }
          : item.fullyChecked
          ? item.report!.checkedCount == 0
                ? 'No regular files to check'
                : 'All regular files checked'
          : 'Check incomplete or issues found',
    );
String _memberSummary(BuildContext context, ArchiveIntegrityReport report) =>
    archiveBatchIntegrityText(
      context,
      'Checked {0} · Failed {1} · Skipped {2} · Unchecked {3}',
      [
        report.checkedCount,
        report.failedCount,
        report.skippedCount,
        report.unprocessedCount,
      ],
    );
String _entryStatus(BuildContext context, ArchiveIntegrityEntry entry) =>
    archiveBatchIntegrityText(context, switch (entry.status) {
      ArchiveIntegrityStatus.checked => 'Checked',
      ArchiveIntegrityStatus.failed => 'Failed',
      ArchiveIntegrityStatus.skipped => 'Skipped',
      ArchiveIntegrityStatus.directory => 'Directory',
    });
String? _entryReason(BuildContext context, ArchiveIntegrityEntry entry) =>
    entry.skipReason == null
    ? entry.detail
    : archiveBatchIntegrityText(context, switch (entry.skipReason!) {
        ArchiveIntegritySkipReason.unsafePath => 'Unsafe path',
        ArchiveIntegritySkipReason.specialEntry => 'Unsupported entry',
        ArchiveIntegritySkipReason.memberLimit => 'Member size limit',
        ArchiveIntegritySkipReason.totalLimit => 'Total read limit',
        ArchiveIntegritySkipReason.passwordRequired => 'Password required',
      });
String _itemText(BuildContext context, ArchiveBatchIntegrityItem item) {
  String tr(String key, [List<Object> values = const []]) =>
      archiveBatchIntegrityText(context, key, values);
  final report = item.report;
  return [
    '${tr('Archive integrity')}: ${_line(item.file.name)}',
    if (item.file.path != null) _line(item.file.path!),
    _itemHeading(context, item),
    tr(_explanation),
    if (item.snapshotSha256 != null)
      'SHA-256 (archive): ${item.snapshotSha256}',
    if (item.error != null) _line(item.error!),
    if (report != null) ...[
      '${report.formatName} — ${_memberSummary(context, report)}',
      tr('Limits: {0} per file, {1} total.', [
        formatBytes(report.maxMemberBytes),
        formatBytes(report.maxTotalBytes),
      ]),
      tr('Bytes read: {0}', [formatBytes(report.bytesRead)]),
      if (report.namespaceIssue != null)
        '${tr('Namespace issue')}: ${_line(report.namespaceIssue!)}',
      ...report.notices.map(_line),
      '',
      for (final entry in report.entries)
        '${_entryStatus(context, entry)}\t${_line(entry.member.name)}\t${entry.member.size}\t${entry.sha256 ?? _line(_entryReason(context, entry) ?? '')}',
    ],
    '',
  ].join('\n');
}

class _BatchItemDialog extends StatelessWidget {
  const _BatchItemDialog({required this.item});
  final ArchiveBatchIntegrityItem item;
  @override
  Widget build(BuildContext context) {
    final report = item.report!;
    String tr(String key) => archiveBatchIntegrityText(context, key);
    return AlertDialog(
      title: Text(item.file.name, maxLines: 3, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 700,
        height: 480,
        child: ListView.builder(
          itemCount: report.entries.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_itemHeading(context, item)),
                  Text(_memberSummary(context, report)),
                  Text(
                    tr(_explanation),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (report.namespaceIssue != null)
                    SelectableText(
                      '${tr('Namespace issue')}: ${report.namespaceIssue}',
                    ),
                  ...report.notices.map((notice) => Text(notice)),
                  const SizedBox(height: 12),
                ],
              );
            }
            final entry = report.entries[index - 1];
            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                entry.member.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${_entryStatus(context, entry)} · ${formatBytes(entry.member.size)}',
              ),
              children: [
                if (entry.sha256 != null)
                  SelectableText('SHA-256: ${entry.sha256}'),
                if (_entryReason(context, entry) case final reason?)
                  SelectableText(reason),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: _itemText(context, item))),
          icon: const Icon(Icons.copy_outlined),
          label: Text(tr('Copy report')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Close')),
        ),
      ],
    );
  }
}

// The controller belongs to the route widget, including its dismissal animation.
class _BatchPasswordDialog extends StatefulWidget {
  const _BatchPasswordDialog({required this.name, required this.wrongPassword});
  final String name;
  final bool wrongPassword;
  @override
  State<_BatchPasswordDialog> createState() => _BatchPasswordDialogState();
}

class _BatchPasswordDialogState extends State<_BatchPasswordDialog> {
  final _password = TextEditingController();
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String tr(String key, [List<Object> values = const []]) =>
        archiveBatchIntegrityText(context, key, values);
    void submit() => Navigator.of(context).pop(_password.text);
    return AlertDialog(
      title: Text(
        tr('Password for {0}', [widget.name]),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.wrongPassword)
                Text(tr('The password was rejected. Try again or skip.')),
              Text(tr('Passwords are used for this check only.')),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                autofocus: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(labelText: tr('Password')),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Skip')),
        ),
        FilledButton(onPressed: submit, child: Text(tr('Check'))),
      ],
    );
  }
}
