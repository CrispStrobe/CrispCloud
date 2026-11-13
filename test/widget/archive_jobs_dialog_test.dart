import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/archive_operation.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:crisp_cloud/widgets/archive_jobs_dialog.dart';
import 'package:crisp_cloud/widgets/operations_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/archive_queue_fixture.dart';

void main() {
  testWidgets('closing Archive jobs preserves the shared queued operation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final journal = TransferJournal(MemoryTransferJournalStorage());
    late ProviderContainer container;
    late TransferNotifier transfers;
    addTearDown(() => container.dispose());
    final source = QueueArchiveBackend('source')
      ..put('/input/notes.txt', [1, 2, 3]);
    final destination = QueueArchiveBackend('destination');
    late ArchiveOperationHandle<ArchiveCreationResult> handle;
    await tester.runAsync(() async {
      container = ProviderContainer(
        overrides: [transferJournalProvider.overrideWithValue(journal)],
      );
      transfers = container.read(transferProvider);
      await transfers.ready;
      await transfers.setQueuePaused(true);
      handle = await transfers.enqueueArchiveCreation(
        source: source,
        destination: destination,
        files: [(await source.stat('/input/notes.txt'))!],
        destinationDirectory: '/output',
        options: const ArchiveCreationOptions(name: 'notes.zip'),
      );
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showArchiveJobsDialog(context, ref),
                child: const Text('Open archive jobs'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open archive jobs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(OperationsPanel), findsOneWidget);
    expect(find.text('Transfer history'), findsOneWidget);
    expect(transfers.isQueued(handle.id), isTrue);
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ArchiveJobsDialog), findsNothing);
    expect(transfers.isQueued(handle.id), isTrue);
    expect(handle.control.isCancelled, isFalse);
    expect(journal.job(handle.id), isNotNull);
    expect(destination.writes, isEmpty);
    await tester.runAsync(() async {
      transfers.cancelOperation(handle.id);
      await handle.completion;
    });
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
