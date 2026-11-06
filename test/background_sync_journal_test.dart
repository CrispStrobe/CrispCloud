import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/services/background_sync_service.dart';
import 'package:crisp_cloud/services/background_transfer_journal.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/transfer_journal.dart';
import 'package:crisp_cloud/services/transfer_journal_storage.dart';

import 'support/sync_test_binding.dart';
import 'support/workflow_fake_client.dart';

class _PausedUploadClient extends WorkflowFakeClient {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> uploadStream(
    Stream<List<int>> input,
    int length,
    String fileName,
    String targetPath, {
    Function(int, int)? onProgress,
  }) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await super.uploadStream(
      input,
      length,
      fileName,
      targetPath,
      onProgress: onProgress,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fail in [false, true]) {
    test(
      'background ${fail ? "failed" : "completed"} sync retains a leased, importable transfer journal',
      () async {
        final root = await Directory.systemTemp.createTemp('background-sync-');
        addTearDown(() => root.delete(recursive: true));
        final local = await Directory(p.join(root.path, 'local')).create();
        final journalRoot = p.join(root.path, 'runs');
        final db = SyncDatabase.forTesting(NativeDatabase.memory());
        final cloud = _PausedUploadClient()
          ..directories.add('/docs')
          ..failUploads = fail;
        final pair = await db.getPair(
          await db.insertPair(
            SyncPairsCompanion.insert(
              name: 'Background upload',
              localPath: local.path,
              remotePath: '/docs',
              provider: 'fixture',
            ),
          ),
        );
        await bindTestPair(db, pair, cloud);
        const payload = 'background sync retains recoverable evidence';
        await File(p.join(local.path, 'file.txt')).writeAsString(payload);
        final foreground = TransferJournal(MemoryTransferJournalStorage());
        final requestedProviders = <String>[];
        final pending = BackgroundSyncService.executeBackgroundTask(
          databaseFactory: () => db,
          clientFactory: (provider) async {
            requestedProviders.add(provider);
            return cloud;
          },
          journalFactory: () =>
              createBackgroundTransferJournalRun(rootPath: journalRoot),
        );
        addTearDown(() async {
          if (!cloud.release.isCompleted) cloud.release.complete();
          await pending;
        });
        try {
          await cloud.entered.future.timeout(const Duration(seconds: 10));
          final whileActive = await importBackgroundTransferJournals(
            foreground,
            rootPath: journalRoot,
          );
          expect(whileActive.activeRuns, 1);
          expect(whileActive.importedJobs, 0);
          expect(foreground.jobs, isEmpty);
        } finally {
          cloud.release.complete();
        }
        final succeeded = await pending;
        expect(succeeded, !fail);
        expect(requestedProviders, ['fixture']);
        final afterTask = await importBackgroundTransferJournals(
          foreground,
          rootPath: journalRoot,
        );
        expect(afterTask.activeRuns, 0);
        expect(afterTask.importedJobs, 1);
        expect(afterTask.warnings, isEmpty);
        final job = foreground.jobs.single;
        expect(job.source!.isLocal, isTrue);
        expect(job.source!.persistent, isTrue);
        expect(job.source!.accountKey, isNotEmpty);
        expect(job.destination!.accountKey, isNotEmpty);
        expect(
          job.status,
          fail ? TransferJobStatus.failed : TransferJobStatus.completed,
        );
        expect(job.entries.single.source.path, p.join(local.path, 'file.txt'));
        if (fail) {
          expect(cloud.files['/docs/file.txt'], isNull);
          expect(
            await File(p.join(local.path, 'file.txt')).readAsString(),
            payload,
          );
        } else {
          expect(cloud.files['/docs/file.txt'], payload.codeUnits);
          expect(job.entries.single.recovery['dataVerified'], isTrue);
        }
      },
    );
  }
}
