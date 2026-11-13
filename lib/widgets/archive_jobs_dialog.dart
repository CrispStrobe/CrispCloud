import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/archive_creation_strings.dart';
import '../l10n/archive_job_strings.dart';
import '../l10n/commander_strings.dart';
import '../providers/providers.dart';
import 'operations_panel.dart';
import 'transfer_history_dialog.dart';

/// Archive creation and workspace saves use the same durable scheduler and
/// recovery history as other operations. This route never owns or stops jobs.
Future<void> showArchiveJobsDialog(BuildContext context, WidgetRef ref) =>
    showDialog<void>(
      context: context,
      builder: (_) => const ArchiveJobsDialog(),
    );

class ArchiveJobsDialog extends ConsumerWidget {
  const ArchiveJobsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transferProvider);
    return AlertDialog(
      title: Text(archiveJobText(context, 'Archive jobs')),
      content: SizedBox(
        width: 900,
        height: math.min(620, MediaQuery.sizeOf(context).height * .68),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                archiveJobText(
                  context,
                  'Archive jobs share the operation queue and recovery history.',
                ),
              ),
              const SizedBox(height: 12),
              if (transfers.operations.isEmpty && transfers.savedJobs.isEmpty)
                Text(archiveJobText(context, 'No archive jobs.')),
              const OperationsPanel(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showTransferHistoryDialog(context, ref),
          child: Text(context.commanderTr('Transfer history')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(archiveCreationText(context, 'Close')),
        ),
      ],
    );
  }
}
