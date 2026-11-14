import 'dart:async';

import 'package:crisp_cloud/models/archive_job.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/services/archive_viewer_service.dart';
import 'package:crisp_cloud/services/archive_zip_recovery_workflow.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/zip_recovery_workflow_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransferJournal journal;
  late ProviderContainer container;
  late TransferNotifier transfers;
  late RecoveryWorkflowBackend source, destination;
  late CapturedArchiveZipRecovery captured;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    journal = TransferJournal(MemoryTransferJournalStorage());
    container = ProviderContainer(
      overrides: [transferJournalProvider.overrideWithValue(journal)],
    );
    transfers = container.read(transferProvider);
    await transfers.ready;
    source = RecoveryWorkflowBackend('source')
      ..put('/input/broken.zip', recoveryWorkflowZip());
    destination = RecoveryWorkflowBackend('destination');
    captured = await captureArchiveZipRecovery(
      source: source,
      file: (await source.stat('/input/broken.zip'))!,
    );
  });
  tearDown(() => container.dispose());

  test(
    'paused admission is durable and Stop never writes a pending candidate',
    () async {
      await transfers.setQueuePaused(true);
      final handle = await transfers.enqueueArchiveZipRecovery(
        captured: captured,
        destination: destination,
        destinationDirectory: '/output',
        outputName: 'recovered.zip',
        selectedOffsets: captured.report.recoverableEntries
            .map((e) => e.offset)
            .toSet(),
      );
      final job = journal.job(handle.id)!;
      expect(job.ready, isTrue);
      expect(isArchiveTransferJob(job), isTrue);
      expect(job.entries.single.recovery['archiveKind'], 'zipRecovery');
      expect(
        job.entries.single.recovery['sourceSha256'],
        captured.report.sourceSha256,
      );
      expect(job.entries.single.recovery.containsKey('password'), isFalse);
      expect(destination.writes, isEmpty);
      transfers.cancelOperation(handle.id);
      await handle.completion;
      expect(handle.error, isA<FileOperationCancelled>());
      expect(journal.job(handle.id)!.status, TransferJobStatus.cancelled);
      expect(destination.writes, isEmpty);
    },
  );

  test(
    'detached observers do not cancel selected recovery or lose its receipts',
    () async {
      await transfers.setQueuePaused(true);
      final offsets = {captured.report.recoverableEntries.first.offset};
      final admission = transfers.enqueueArchiveZipRecovery(
        captured: captured,
        destination: destination,
        destinationDirectory: '/output',
        outputName: 'recovered.zip',
        selectedOffsets: offsets,
      );
      offsets
        ..clear()
        ..add(captured.report.recoverableEntries.last.offset);
      final handle = await admission;
      void listener() {}
      handle.addListener(listener);
      handle.removeListener(listener);
      await transfers.setQueuePaused(false);
      await handle.completion;
      expect(handle.error, isNull);
      expect(handle.operation.type, OperationType.archive);
      expect(handle.operation.status, OperationStatus.completed);
      final archive = await openViewerArchive(
        destination.contents['/output/recovered.zip']!,
        name: 'recovered.zip',
      );
      expect(archive.members.map((m) => m.name), ['one.txt']);
      await archive.close();
      final job = journal.job(handle.id)!;
      expect(job.status, TransferJobStatus.completed);
      final receipt = job.entries.single.recovery['archivePublication'] as Map;
      expect(receipt['phase'], 'committed');
      expect(receipt['sourceSha256'], captured.report.sourceSha256);
      expect(receipt['packedSha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
    },
  );

  test(
    'content changed while queued causes review without publication',
    () async {
      await transfers.setQueuePaused(true);
      final handle = await transfers.enqueueArchiveZipRecovery(
        captured: captured,
        destination: destination,
        destinationDirectory: '/output',
        outputName: 'recovered.zip',
        selectedOffsets: captured.report.recoverableEntries
            .map((e) => e.offset)
            .toSet(),
      );
      source.contents['/input/broken.zip']!.last ^= 1;
      await transfers.setQueuePaused(false);
      await handle.completion;
      expect(handle.error, isA<StateError>());
      expect(journal.job(handle.id)!.status, TransferJobStatus.failed);
      expect(destination.writes, isEmpty);
    },
  );

  test('Stop after install retains success in the shared queue', () async {
    await transfers.setQueuePaused(true);
    final handle = await transfers.enqueueArchiveZipRecovery(
      captured: captured,
      destination: destination,
      destinationDirectory: '/output',
      outputName: 'recovered.zip',
      selectedOffsets: captured.report.recoverableEntries
          .map((e) => e.offset)
          .toSet(),
    );
    destination.afterInstall = () => transfers.cancelOperation(handle.id);
    await transfers.setQueuePaused(false);
    await handle.completion;
    expect(handle.error, isNull);
    expect(handle.result!.path, '/output/recovered.zip');
    expect(handle.operation.status, OperationStatus.completed);
    expect(journal.job(handle.id)!.status, TransferJobStatus.completed);
  });

  test('pausing a live recovery holds publication and Stop wakes it', () async {
    final atCommit = Completer<void>();
    final release = Completer<void>();
    destination.beforeCommit = () async {
      atCommit.complete();
      await release.future;
    };
    final handle = await transfers.enqueueArchiveZipRecovery(
      captured: captured,
      destination: destination,
      destinationDirectory: '/output',
      outputName: 'recovered.zip',
      selectedOffsets: captured.report.recoverableEntries
          .map((e) => e.offset)
          .toSet(),
    );
    await atCommit.future;
    transfers.pauseOperation(handle.id);
    release.complete();
    await Future<void>.delayed(Duration.zero);
    expect(handle.isSettled, isFalse);
    expect(destination.writes, isEmpty);
    transfers.cancelOperation(handle.id);
    await handle.completion;
    expect(handle.error, isA<FileOperationCancelled>());
    expect(destination.writes, isEmpty);
  });
}
