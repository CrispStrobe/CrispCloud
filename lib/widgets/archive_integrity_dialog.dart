import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/archive_integrity_strings.dart';
import '../services/archive_integrity_service.dart';
import '../services/archive_types.dart';
import '../utils/formatters.dart';

Future<void> showArchiveIntegrityDialog(
  BuildContext context, {
  required ViewerArchive archive,
  required String displayName,
  bool Function()? isCurrent,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ArchiveIntegrityDialog(
    archive: archive,
    displayName: displayName,
    isCurrent: isCurrent,
  ),
);

class ArchiveIntegrityDialog extends StatefulWidget {
  const ArchiveIntegrityDialog({
    super.key,
    required this.archive,
    required this.displayName,
    this.isCurrent,
  });

  final ViewerArchive archive;
  final String displayName;
  final bool Function()? isCurrent;

  @override
  State<ArchiveIntegrityDialog> createState() => _ArchiveIntegrityDialogState();
}

class _ArchiveIntegrityDialogState extends State<ArchiveIntegrityDialog> {
  ArchiveIntegrityReport? _report;
  ArchiveIntegrityProgress? _progress;
  Object? _error;
  bool _cancelled = false, _running = true;
  var _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  String text(String key, [List<Object> values = const []]) =>
      archiveIntegrityText(context, key, values);

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.delayed(Duration.zero, _run));
  }

  Future<void> _run() async {
    if (!mounted) return;
    try {
      final report = await checkArchiveIntegrity(
        widget.archive,
        isCancelled: () => _cancelled || !mounted,
        isCurrent: widget.isCurrent,
        onProgress: (progress) {
          if (!mounted) return;
          final now = DateTime.now();
          if (progress.completedEntries == progress.totalEntries ||
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

  String _status(ArchiveIntegrityEntry entry) => text(switch (entry.status) {
    ArchiveIntegrityStatus.checked => 'Checked',
    ArchiveIntegrityStatus.failed => 'Failed',
    ArchiveIntegrityStatus.skipped => 'Skipped',
    ArchiveIntegrityStatus.directory => 'Directory',
  });

  String? _reason(ArchiveIntegrityEntry entry) => entry.skipReason == null
      ? null
      : text(switch (entry.skipReason!) {
          ArchiveIntegritySkipReason.unsafePath => 'Unsafe path',
          ArchiveIntegritySkipReason.specialEntry => 'Unsupported entry',
          ArchiveIntegritySkipReason.memberLimit => 'Member size limit',
          ArchiveIntegritySkipReason.totalLimit => 'Total read limit',
          ArchiveIntegritySkipReason.passwordRequired => 'Password required',
        });

  String _summary(ArchiveIntegrityReport report) =>
      text('Checked {0} · Failed {1} · Skipped {2} · Unchecked {3}', [
        report.checkedCount,
        report.failedCount,
        report.skippedCount,
        report.unprocessedCount,
      ]);

  String _heading(ArchiveIntegrityReport report) {
    if (report.stopReason == ArchiveIntegrityStopReason.cancelled) {
      return text('Cancelled');
    }
    if (report.stopReason == ArchiveIntegrityStopReason.unavailable) {
      return text('Archive no longer available');
    }
    if (!report.allRegularMembersChecked) {
      return text('Check incomplete or issues found');
    }
    return text(
      report.checkedCount == 0
          ? 'No regular files to check'
          : 'All regular files checked',
    );
  }

  static const _explanation =
      'Reads regular files and checks available checksums. Calculated SHA-256 values describe this snapshot; they do not authenticate its publisher.';

  String _reportText(ArchiveIntegrityReport report) => [
    '${text('Archive integrity')}: ${widget.displayName}',
    '${report.formatName} — ${_heading(report)}',
    _summary(report),
    text(_explanation),
    text('Limits: {0} per file, {1} total.', [
      formatBytes(report.maxMemberBytes),
      formatBytes(report.maxTotalBytes),
    ]),
    text('Bytes read: {0}', [formatBytes(report.bytesRead)]),
    if (report.namespaceIssue != null)
      '${text('Namespace issue')}: ${report.namespaceIssue}',
    ...report.notices,
    '',
    for (final entry in report.entries)
      '${_status(entry)}\t${entry.member.name.replaceAll(RegExp(r'[\r\n\t]'), ' ')}\t${entry.member.size}\t${entry.sha256 ?? _reason(entry) ?? entry.detail ?? ''}',
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final progress = _progress;
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _running) _cancel();
      },
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: Text(text('Archive integrity')),
        content: SizedBox(
          width: 720,
          height: 480,
          // A single scrolling body keeps long translations, reader notices
          // and large accessibility text usable on narrow/short windows.
          child: ListView.builder(
            itemCount: (report?.entries.length ?? 0) + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (report != null) ...[
                      Text(
                        _heading(report),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(_summary(report)),
                      Text(
                        text('Bytes read: {0}', [
                          formatBytes(report.bytesRead),
                        ]),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_running) ...[
                      LinearProgressIndicator(
                        value: progress == null || progress.totalEntries == 0
                            ? null
                            : progress.completedEntries / progress.totalEntries,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        text('Checking {0} of {1}', [
                          progress?.completedEntries ?? 0,
                          widget.archive.members.length,
                        ]),
                      ),
                      if (progress?.memberName != null)
                        Text(
                          progress!.memberName!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        text('Bytes read: {0}', [
                          formatBytes(progress?.bytesRead ?? 0),
                        ]),
                      ),
                      if (_cancelled)
                        Text(
                          text(
                            'Stops between reads. A bounded decode may finish first.',
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      text(_explanation),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      text('Limits: {0} per file, {1} total.', [
                        formatBytes(kArchiveReadLimit),
                        formatBytes(256 * 1024 * 1024),
                      ]),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    if (_error != null)
                      SelectableText(
                        '$_error',
                        style: TextStyle(color: scheme.error),
                      ),
                    if (report?.namespaceIssue != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${text('Namespace issue')}: ${report!.namespaceIssue}',
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    for (final notice in report?.notices ?? <String>[])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          notice,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                );
              }
              final entry = report!.entries[index - 1];
              return ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: Icon(
                  switch (entry.status) {
                    ArchiveIntegrityStatus.checked =>
                      Icons.check_circle_outline,
                    ArchiveIntegrityStatus.failed => Icons.error_outline,
                    ArchiveIntegrityStatus.skipped => Icons.skip_next_outlined,
                    ArchiveIntegrityStatus.directory => Icons.folder_outlined,
                  },
                  color: entry.status == ArchiveIntegrityStatus.failed
                      ? scheme.error
                      : null,
                ),
                title: Text(
                  entry.member.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    _status(entry),
                    if (_reason(entry) != null) _reason(entry)!,
                    formatBytes(entry.member.size),
                  ].join(' · '),
                ),
                children: [
                  if (entry.sha256 != null)
                    SelectableText('SHA-256: ${entry.sha256}'),
                  if (entry.detail != null) SelectableText(entry.detail!),
                ],
              );
            },
          ),
        ),
        actions: [
          if (report != null)
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _reportText(report))),
              icon: const Icon(Icons.copy_outlined),
              label: Text(text('Copy report')),
            ),
          if (_running)
            TextButton(
              onPressed: _cancelled ? null : _cancel,
              child: Text(text('Cancel')),
            )
          else
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(text('Close')),
            ),
        ],
      ),
    );
  }
}
