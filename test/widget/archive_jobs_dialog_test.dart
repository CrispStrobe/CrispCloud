import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/archive_job_strings.dart';
import 'package:crisp_cloud/models/archive_job.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/providers/archive_jobs_provider.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_creation_worker.dart';
import 'package:crisp_cloud/services/archive_job_controller.dart';
import 'package:crisp_cloud/services/archive_job_journal.dart';
import 'package:crisp_cloud/services/archive_publication_lease.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/local_file_service.dart';
import 'package:crisp_cloud/widgets/archive_jobs_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/archive_creation_backend.dart';

class _Local extends Fake implements LocalFileService {}

class _Backend extends ArchiveCreationBackend {
  @override
  StorageReference get storageReference => const StorageReference(
    kind: 'local',
    provider: 'test',
    accountKey: 'widget-jobs',
  );
  @override
  bool get canRecover => true;
}

class _Worker implements ArchiveCreationWorker {
  _Worker(this.options, this.prepared);
  final ArchiveCreationOptions options;
  final Future<void> Function(ArchiveCreationPrepared) prepared;
  final done = Completer<ArchiveCreationResult>();
  bool cancelled = false, paused = false;
  Future<void> finish() async {
    final receipt = ArchiveCreationPrepared(
      '/output/${options.name}',
      1,
      3,
      sha256.convert([1, 2, 3]).toString(),
    );
    try {
      await prepared(receipt);
      if (!done.isCompleted) done.complete(receipt);
    } catch (error, stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    }
  }

  @override
  Future<ArchiveCreationResult> get result => done.future;
  @override
  void cancel() {
    cancelled = true;
    paused = false;
  }

  @override
  void pause() => paused = true;
  @override
  void resume() => paused = false;
  @override
  Future<void> close() async {}
}

void main() {
  late ArchiveJobController controller;
  late MemoryFileCollectionStorage storage;
  late _Backend backend;
  final workers = <_Worker>[];
  Future<ArchiveCreationWorker> factory({
    required LocalFileService local,
    required List<FileItem> files,
    required String destinationDirectory,
    required ArchiveCreationOptions options,
    required void Function(ArchiveCreationProgress) onProgress,
    required Future<void> Function(ArchiveCreationPrepared) onPrepared,
  }) async {
    final worker = _Worker(options, onPrepared);
    workers.add(worker);
    return worker;
  }

  ArchiveJobController makeController() => ArchiveJobController(
    local: _Local(),
    backend: backend,
    journal: ArchiveJobJournal(storage: storage),
    acquireLease: MemoryArchivePublicationLease.acquire,
    workerFactory: factory,
  );

  setUp(() {
    workers.clear();
    storage = MemoryFileCollectionStorage();
    backend = _Backend()..put('/input/source.txt', [1, 2, 3]);
    controller = makeController();
  });
  tearDown(() {
    for (final worker in workers) {
      if (!worker.done.isCompleted) {
        worker.done.completeError(StateError('Test shutdown'));
      }
    }
  });
  Future<ArchiveJobRecord> enqueue({
    String name = 'queued.zip',
    String? password,
  }) async {
    if (!controller.initialized) {
      await controller.initialize();
      await controller.setQueuePaused(true);
    }
    return controller.enqueue(
      files: [(await backend.stat('/input/source.txt'))!],
      destinationDirectory: '/output',
      options: ArchiveCreationOptions(name: name, password: password),
    );
  }

  Future<void> show(
    WidgetTester tester, {
    String locale = 'en',
    double width = 800,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [archiveJobsProvider.overrideWith((ref) => controller)],
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const ArchiveJobsDialog(),
                ),
                child: const Text('Open jobs'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open jobs'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'closing the jobs dialog leaves its application-owned worker running',
    (tester) async {
      final record = await enqueue();
      await show(tester);
      await tester.tap(find.text('Resume queue'));
      await tester.pumpAndSettle();
      expect(workers.length, 1);
      expect(controller.job(record.id)!.status, ArchiveJobStatus.running);
      expect(find.text('Reload'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ArchiveJobsDialog), findsNothing);
      expect(workers.single.cancelled, isFalse);
      await workers.single.finish();
      await tester.pumpAndSettle();
      await controller.idle;
      expect(controller.job(record.id)!.status, ArchiveJobStatus.completed);
      await tester.tap(find.text('Open jobs'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Completed'), findsOneWidget);
      await controller.close();
    },
  );

  testWidgets(
    'queued pause, resume, reorder and stop operate on the saved jobs',
    (tester) async {
      final first = await enqueue();
      final second = await enqueue(name: 'second.zip');
      await show(tester);
      Finder card(String id) => find.byKey(ValueKey('archive-job-$id'));
      Future<void> action(String id, String label) async {
        final button = find.descendant(
          of: card(id),
          matching: find.text(label),
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await action(second.id, 'Run next');
      expect(controller.jobs.first.id, second.id);
      await action(first.id, 'Pause');
      expect(controller.job(first.id)!.status, ArchiveJobStatus.paused);
      await action(first.id, 'Resume');
      expect(controller.job(first.id)!.status, ArchiveJobStatus.queued);
      await action(first.id, 'Stop');
      expect(controller.job(first.id)!.status, ArchiveJobStatus.cancelled);
      expect(workers, isEmpty);
      await controller.close();
    },
  );

  testWidgets(
    'interrupted protected jobs require explicit source review and a fresh password',
    (tester) async {
      final record = await enqueue(password: 'old-session-password');
      await controller.close();
      controller = makeController();
      await controller.initialize();
      await show(tester);
      await tester.tap(find.text('Restart from source'));
      await tester.pumpAndSettle();
      expect(find.text('/input/source.txt'), findsOneWidget);
      expect(find.text('Restart archive job'), findsOneWidget);
      final password = find.byType(TextField);
      expect(tester.widget<TextField>(password).obscureText, isTrue);
      expect(tester.widget<TextField>(password).controller!.text, isEmpty);
      await tester.enterText(password, 'new-session-password');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Restart from source'),
      );
      await tester.pumpAndSettle();
      expect(controller.job(record.id)!.status, ArchiveJobStatus.queued);
      expect(
        storage.values.values.single,
        isNot(contains('new-session-password')),
      );
      await tester.tap(find.text('Resume queue'));
      await tester.pumpAndSettle();
      expect(workers.single.options.password, 'new-session-password');
      await workers.single.finish();
      await tester.pumpAndSettle();
      await controller.idle;
      await controller.close();
    },
  );

  for (final locale in ['en', 'de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
    testWidgets('$locale queue controls and long names fit a narrow dialog', (
      tester,
    ) async {
      await enqueue(name: 'A long Unicode archive 日本語 with spaces.zip');
      await show(tester, locale: locale, width: 390, scale: 1.15);
      final context = tester.element(find.byType(ArchiveJobsDialog));
      expect(
        find.text(archiveJobText(context, 'Archive jobs')),
        findsOneWidget,
      );
      expect(
        find.text(archiveJobText(context, 'Resume queue')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await controller.close();
    });
  }
}
