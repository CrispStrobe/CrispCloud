import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/archive_creation_strings.dart';
import '../l10n/archive_job_strings.dart';
import '../models/archive_job.dart';
import '../providers/archive_jobs_provider.dart';
import '../services/archive_creation_service.dart';
import '../services/archive_job_controller.dart';

Future<void> showArchiveJobsDialog(BuildContext context, WidgetRef ref) =>
    showDialog<void>(
      context: context,
      builder: (_) => const ArchiveJobsDialog(),
    );

class ArchiveJobsDialog extends ConsumerStatefulWidget {
  const ArchiveJobsDialog({super.key});
  @override
  ConsumerState<ArchiveJobsDialog> createState() => _ArchiveJobsDialogState();
}

class _ArchiveJobsDialogState extends ConsumerState<ArchiveJobsDialog> {
  String? _busy;
  Object? _error;

  Future<void> _action(String id, Future<void> Function() action) async {
    setState(() {
      _busy = id;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restart(
    ArchiveJobController controller,
    ArchiveJobRecord record,
  ) async {
    final password = TextEditingController();
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(archiveJobText(context, 'Restart archive job')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(archiveJobText(context, 'Source selection')),
                  for (final file in record.request.files)
                    SelectableText(
                      file.path!,
                      textDirection: TextDirection.ltr,
                    ),
                  const SizedBox(height: 12),
                  Text(archiveJobText(context, 'Destination')),
                  SelectableText(
                    record.request.outputPath,
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    archiveJobText(
                      context,
                      'Sources are checked when a job starts. Restarting rebuilds from the saved paths. Existing files are never replaced.',
                    ),
                  ),
                  if (record.request.passwordRequired) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: archiveCreationText(context, 'Password'),
                      ),
                    ),
                    Text(
                      archiveJobText(
                        context,
                        'Passwords are not saved. Enter the password again after restarting the app.',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(archiveCreationText(context, 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(archiveJobText(context, 'Restart from source')),
            ),
          ],
        ),
      );
      if (approved == true && mounted) {
        await _action(
          record.id,
          () => controller.restart(
            record.id,
            password: record.request.passwordRequired ? password.text : null,
          ),
        );
      }
    } finally {
      password.clear();
      password.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(archiveJobsProvider);
    String tr(String key) => archiveJobText(context, key);
    final available = controller.isReady && _busy == null;
    return AlertDialog(
      title: Text(tr('Archive jobs')),
      content: SizedBox(
        width: 760,
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                'Sources are checked when a job starts. Restarting rebuilds from the saved paths. Existing files are never replaced.',
              ),
            ),
            if (!controller.initialized) const LinearProgressIndicator(),
            if (controller.ownedElsewhere)
              Text(tr('Another window owns this queue.')),
            if (_error ?? controller.error case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SelectableText(
                  '$error',
                  key: const ValueKey('archive-jobs-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: controller.jobs.isEmpty
                  ? Center(child: Text(tr('No archive jobs.')))
                  : ListView(
                      children: [
                        for (final record in controller.jobs)
                          _card(controller, record, available),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy == null
              ? () => _action('reload', () async {
                  await controller.close();
                  ref.invalidate(archiveJobsProvider);
                })
              : null,
          child: Text(tr('Reload')),
        ),
        TextButton(
          onPressed: available
              ? () => _action(
                  'queue',
                  () => controller.setQueuePaused(!controller.queuePaused),
                )
              : null,
          child: Text(
            tr(controller.queuePaused ? 'Resume queue' : 'Pause queue'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(archiveCreationText(context, 'Close')),
        ),
      ],
    );
  }

  Widget _card(
    ArchiveJobController controller,
    ArchiveJobRecord record,
    bool available,
  ) {
    String tr(String key) => archiveJobText(context, key);
    final progress = controller.progress(record.id);
    final status = switch (record.status) {
      ArchiveJobStatus.queued => 'Queued',
      ArchiveJobStatus.running => 'Running',
      ArchiveJobStatus.paused => 'Paused',
      ArchiveJobStatus.stopping => 'Stopping',
      ArchiveJobStatus.interrupted => 'Interrupted',
      ArchiveJobStatus.completed => 'Completed',
      ArchiveJobStatus.failed => 'Failed',
      ArchiveJobStatus.cancelled => 'Cancelled',
    };
    Widget action(String label, Future<void> Function() callback) => TextButton(
      onPressed: available ? () => _action(record.id, callback) : null,
      child: Text(tr(label)),
    );
    return Card(
      key: ValueKey('archive-job-${record.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              record.request.name,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              '${tr(status)} · ${archiveCreationText(context, record.request.format.label)}',
            ),
            SelectableText(
              record.request.outputPath,
              textDirection: TextDirection.ltr,
            ),
            if (progress != null && controller.activeId == record.id) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress.total > 0
                    ? (progress.completed / progress.total).clamp(0.0, 1.0)
                    : null,
              ),
              Text(
                archiveCreationText(context, switch (progress.phase) {
                  ArchiveCreationPhase.scanning => 'Scanning',
                  ArchiveCreationPhase.packing => 'Packing',
                  ArchiveCreationPhase.verifying => 'Verifying',
                  ArchiveCreationPhase.saving => 'Saving',
                }),
              ),
              Text(progress.path, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (record.error != null) SelectableText(record.error!),
            if (_busy == record.id) const LinearProgressIndicator(),
            Wrap(
              spacing: 4,
              children: [
                if (const {
                  ArchiveJobStatus.queued,
                  ArchiveJobStatus.running,
                }.contains(record.status))
                  action('Pause', () => controller.pause(record.id)),
                if (record.status == ArchiveJobStatus.paused)
                  action('Resume', () => controller.resume(record.id)),
                if (!record.terminal &&
                    record.status != ArchiveJobStatus.stopping)
                  action('Stop', () => controller.cancel(record.id)),
                if (record.status == ArchiveJobStatus.queued)
                  action('Run next', () => controller.moveToTop(record.id)),
                if (const {
                  ArchiveJobStatus.interrupted,
                  ArchiveJobStatus.failed,
                  ArchiveJobStatus.cancelled,
                }.contains(record.status))
                  TextButton(
                    onPressed: available
                        ? () => _restart(controller, record)
                        : null,
                    child: Text(tr('Restart from source')),
                  ),
                if (record.prepared != null &&
                    controller.activeId != record.id &&
                    record.status != ArchiveJobStatus.completed)
                  action(
                    'Verify saved output',
                    () => controller.verifyPublishedOutput(record.id),
                  ),
                if (record.terminal && controller.activeId != record.id)
                  action(
                    'Remove from history',
                    () => controller.remove(record.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
