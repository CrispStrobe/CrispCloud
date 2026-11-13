import 'dart:async';

import 'package:crisp_cloud/models/archive_operation.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/widgets/archive_creation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/archive_creation_backend.dart';

class _ForegroundService extends ArchiveCreationService {
  FileOperationControl? receivedControl;
  final completed = Completer<ArchiveCreationResult>();

  @override
  Future<ArchiveCreationResult> create({
    required FileOperationBackend source,
    required FileOperationBackend destination,
    required List<FileItem> files,
    required String destinationDirectory,
    required ArchiveCreationOptions options,
    FileOperationControl? control,
    bool background = false,
    String? expectedSourceManifestSha256,
    Future<void> Function(Map<String, dynamic>)? onPublicationCheckpoint,
    bool Function()? isCancelled,
    void Function(ArchiveCreationProgress)? onProgress,
  }) {
    receivedControl = control;
    return completed.future;
  }
}

ArchiveOperationHandle<ArchiveCreationResult> _job() => ArchiveOperationHandle(
  id: 'archive_create_widget',
  operation: OperationProgress(
    id: 'archive_create_widget',
    type: OperationType.archive,
    sourcePath: '/input/notes.txt',
    targetPath: '/output/notes.zip',
    fileName: 'notes.zip',
    totalBytes: 0,
  ),
  control: FileOperationControl(),
);

void main() {
  Future<GlobalKey<NavigatorState>> show(
    WidgetTester tester, {
    Future<ArchiveOperationHandle<ArchiveCreationResult>> Function(
      ArchiveCreationOptions,
    )? enqueue,
    ArchiveCreationService service = const ArchiveCreationService(),
  }) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = ArchiveCreationBackend()..put('/input/notes.txt', [1, 2, 3]);
    final file = (await backend.stat('/input/notes.txt'))!;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => ArchiveCreationDialog(
              source: backend,
              destination: backend,
              files: [file],
              destinationDirectory: '/output',
              service: service,
              enqueue: enqueue,
            ),
          ),
          child: const Text('Open'),
        ),
      )),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return navigator;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    // An active operation deliberately keeps an indeterminate indicator alive.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('background closes only after durable admission and detaches', (
    tester,
  ) async {
    final accepted = Completer<ArchiveOperationHandle<ArchiveCreationResult>>();
    final requests = <ArchiveCreationOptions>[];
    final job = _job();
    await show(tester, enqueue: (options) {
      requests.add(options);
      return accepted.future;
    });
    await tap(tester, 'archive-create-background');
    expect(requests, hasLength(1));
    expect(requests.single.name, 'notes.zip');
    expect(find.byType(ArchiveCreationDialog), findsOneWidget);
    expect(find.text('Queueing archive…'), findsOneWidget);
    expect(find.byKey(const ValueKey('archive-create-background')), findsNothing);

    accepted.complete(job);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ArchiveCreationDialog), findsNothing);
    expect(job.control.isCancelled, isFalse);
    job.creationProgress = const ArchiveCreationProgress(
      ArchiveCreationPhase.verifying, 3, 3, '/input/notes.txt',
    );
    job.update();
    job.settle(result: const ArchiveCreationResult('/output/notes.zip', 1, 120));
    await job.completion;
    await tester.pump();
    expect(job.result!.path, '/output/notes.zip');
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed admission leaves the reviewed dialog open', (tester) async {
    await show(tester, enqueue: (_) async => throw StateError('Journal unavailable'));
    await tap(tester, 'archive-create-background');
    expect(find.byType(ArchiveCreationDialog), findsOneWidget);
    expect(find.textContaining('Journal unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('archive-create-background')), findsOneWidget);
    expect(find.byKey(const ValueKey('archive-create-stop')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('foreground queue observer pauses resumes and stops the same job', (
    tester,
  ) async {
    final job = _job();
    var admissions = 0;
    await show(tester, enqueue: (_) async {
      admissions++;
      return job;
    });
    await tap(tester, 'archive-create-submit');
    expect(admissions, 1);
    job.creationProgress = const ArchiveCreationProgress(
      ArchiveCreationPhase.packing, 1, 4, '/input/notes.txt',
    );
    job.update();
    await tester.pump();
    expect(find.text('Packing…'), findsOneWidget);
    await tap(tester, 'archive-create-pause');
    expect(job.control.isPaused, isTrue);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await tap(tester, 'archive-create-pause');
    expect(job.control.isPaused, isFalse);
    await tap(tester, 'archive-create-pause');
    await tap(tester, 'archive-create-stop');
    expect(job.control.isCancelled, isTrue);
    expect(job.control.isPaused, isFalse);
    expect(find.text('Cancelling…'), findsOneWidget);
    job.settle(error: const ArchiveCreationException(ArchiveCreationError.cancelled));
    await tester.pump();
    expect(find.text('Archive creation cancelled. No archive was published.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending a paused job to background does not resume or stop it', (
    tester,
  ) async {
    final job = _job();
    await show(tester, enqueue: (_) async => job);
    await tap(tester, 'archive-create-submit');
    await tap(tester, 'archive-create-pause');
    await tap(tester, 'archive-create-background-running');
    expect(find.byType(ArchiveCreationDialog), findsNothing);
    expect(job.control.isPaused, isTrue);
    expect(job.control.isCancelled, isFalse);
    job.control.cancel();
    job.settle(error: const FileOperationCancelled());
    await job.completion;
    expect(tester.takeException(), isNull);
  });

  testWidgets('external route removal during admission preserves accepted work', (
    tester,
  ) async {
    final accepted = Completer<ArchiveOperationHandle<ArchiveCreationResult>>();
    final job = _job();
    final navigator = await show(tester, enqueue: (_) => accepted.future);
    await tap(tester, 'archive-create-background');
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    accepted.complete(job);
    await tester.pump();
    expect(find.byType(ArchiveCreationDialog), findsNothing);
    expect(job.control.isCancelled, isFalse);
    job.settle(result: const ArchiveCreationResult('/output/notes.zip', 1, 120));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful publication keeps success when cleanup warns', (tester) async {
    final job = _job();
    await show(tester, enqueue: (_) async => job);
    await tap(tester, 'archive-create-submit');
    job.settle(result: const ArchiveCreationResult(
      '/output/notes.zip', 1, 120,
      publicationWarning: 'Review saved publication details',
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('archive-create-success')), findsOneWidget);
    expect(find.byKey(const ValueKey('archive-create-warning')), findsOneWidget);
    expect(find.byKey(const ValueKey('archive-create-error')), findsNothing);
    expect(find.byKey(const ValueKey('archive-create-submit')), findsNothing);
  });

  testWidgets('standalone foreground owner cancels on disposal', (tester) async {
    final service = _ForegroundService();
    final navigator = await show(tester, service: service);
    expect(find.byKey(const ValueKey('archive-create-background')), findsNothing);
    await tap(tester, 'archive-create-submit');
    expect(service.receivedControl, isNotNull);
    await tap(tester, 'archive-create-pause');
    expect(service.receivedControl!.isPaused, isTrue);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(service.receivedControl!.isCancelled, isTrue);
    service.completed.completeError(const FileOperationCancelled());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
