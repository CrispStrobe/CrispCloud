import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart' as codecs;
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/archive_operation.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_zip_recovery_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/widgets/archive_zip_recovery_dialog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/zip_recovery_workflow_fixture.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var count = 0; count < 100 && !ready(); count++) {
    // Stream.timeout's SDK completion path can finish outside FakeAsync even
    // for an in-memory async generator. Let that real asynchronous callback
    // run, then advance the widget's controlled timers and frames.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready(),
    isTrue,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
        .join('\n'),
  );
  await tester.pump();
}

Future<void> _open(
  WidgetTester tester,
  RecoveryWorkflowBackend source,
  RecoveryWorkflowBackend destination, {
  String locale = 'en',
  double width = 800,
  double height = 750,
  double textScale = 1,
  bool waitForReview = true,
  EnqueueArchiveZipRecovery? enqueue,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final file = (await source.stat('/input/broken.zip'))!;
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<ArchiveCreationResult>(
              context: context,
              builder: (_) => ArchiveZipRecoveryDialog(
                source: source,
                file: file,
                destination: destination,
                destinationDirectory: '/output',
                enqueue: enqueue,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump(const Duration(milliseconds: 20));
  if (waitForReview) {
    await _until(
      tester,
      () =>
          find.byKey(const ValueKey('zip-recovery-save')).evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byType(ArchiveZipRecoveryDialog),
        matching: find.byType(Scrollable),
      )
      // The first scrollable is the outer lazy report. The filename field
      // contributes another, internal horizontal editor scrollable.
      .first;
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 160, scrollable: scrollable);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  late RecoveryWorkflowBackend source, destination;
  late Uint8List original;
  setUp(() {
    original = recoveryWorkflowZip();
    source = RecoveryWorkflowBackend('source')
      ..put('/input/broken.zip', original);
    destination = RecoveryWorkflowBackend('destination');
  });

  testWidgets('review and report copy preserve input and do not publish', (
    tester,
  ) async {
    String? clipboard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _open(tester, source, destination);
    expect(find.text('2 ready · 0 excluded · 2 selected'), findsOneWidget);
    await _reveal(tester, find.text('Copy report'));
    await tester.tap(find.text('Copy report'));
    await tester.pump();
    expect(clipboard, contains(sha256.convert(original).toString()));
    expect(clipboard, contains('one.txt'));
    expect(clipboard, contains('two.txt'));
    expect(source.writes, isEmpty);
    expect(destination.writes, isEmpty);
    expect(source.contents['/input/broken.zip'], original);
    await tester.tap(find.byKey(const ValueKey('zip-recovery-close')));
    await tester.pumpAndSettle();
    expect(find.byType(ArchiveZipRecoveryDialog), findsNothing);
  });

  testWidgets('unchecked entries are omitted from a separate verified output', (
    tester,
  ) async {
    await _open(tester, source, destination);
    await _reveal(tester, find.text('Clear selection'));
    await tester.tap(find.text('Clear selection'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('zip-recovery-save')))
          .onPressed,
      isNull,
    );
    await _reveal(tester, find.widgetWithText(CheckboxListTile, 'two.txt'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'two.txt'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('zip-recovery-save')));
    await _until(tester, () => destination.writes.isNotEmpty);
    await tester.pumpAndSettle();
    expect(destination.writes, ['/output/broken.recovered.zip']);
    final recovered = codecs.ZipDecoder().decodeBytes(
      destination.contents[destination.writes.single]!,
      verify: true,
    );
    expect(recovered.map((e) => e.name), ['two.txt']);
    expect(utf8.decode(recovered.single.readBytes()!), 'second payload');
    expect(source.contents['/input/broken.zip'], original);
    expect(source.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('excluded unsafe records cannot be selected', (tester) async {
    original = recoveryWorkflowZip({
      '../escape.txt': [1],
      'safe.txt': [2],
    });
    source.put('/input/broken.zip', original);
    await _open(tester, source, destination);
    expect(find.text('1 ready · 1 excluded · 1 selected'), findsOneWidget);
    final excluded = find.widgetWithText(CheckboxListTile, '../escape.txt');
    await _reveal(tester, excluded);
    final row = tester.widget<CheckboxListTile>(excluded);
    expect(row.value, isFalse);
    expect(row.onChanged, isNull);
    expect(
      find.textContaining('Unsafe or unsupported member name'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('zip-recovery-save')));
    await _until(tester, () => destination.writes.isNotEmpty);
    await tester.pumpAndSettle();
    final recovered = codecs.ZipDecoder().decodeBytes(
      destination.contents[destination.writes.single]!,
      verify: true,
    );
    expect(recovered.map((e) => e.name), ['safe.txt']);
    expect(source.contents['/input/broken.zip'], original);
  });

  testWidgets('an existing output is retained and a collision is reported', (
    tester,
  ) async {
    destination.put('/output/broken.recovered.zip', [9, 8, 7]);
    await _open(tester, source, destination);
    await tester.tap(find.byKey(const ValueKey('zip-recovery-save')));
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('zip-recovery-error'))
          .evaluate()
          .isNotEmpty,
    );
    expect(destination.writes, isEmpty);
    expect(destination.contents['/output/broken.recovered.zip'], [9, 8, 7]);
    expect(source.contents['/input/broken.zip'], original);
    expect(find.byKey(const ValueKey('zip-recovery-result')), findsNothing);
  });

  testWidgets('narrow large-text dialog keeps recovery and close reachable', (
    tester,
  ) async {
    await _open(
      tester,
      source,
      destination,
      width: 320,
      height: 720,
      textScale: 2.5,
    );
    final save = find.byKey(const ValueKey('zip-recovery-save'));
    final close = find.byKey(const ValueKey('zip-recovery-close'));
    expect(save.hitTestable(), findsOneWidget);
    expect(close.hitTestable(), findsOneWidget);
    await _reveal(tester, find.widgetWithText(CheckboxListTile, 'two.txt'));
    expect(tester.takeException(), isNull);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(ArchiveZipRecoveryDialog), findsNothing);
    expect(destination.writes, isEmpty);
  });

  testWidgets('German review exposes translated controls and summary', (
    tester,
  ) async {
    await _open(tester, source, destination, locale: 'de');
    expect(find.text('ZIP-Wiederherstellung'), findsOneWidget);
    expect(
      find.text('2 bereit · 0 ausgeschlossen · 2 ausgewählt'),
      findsOneWidget,
    );
    expect(find.text('Auswahl retten'), findsOneWidget);
    await _reveal(tester, find.text('Auswahl aufheben'));
    await tester.tap(find.text('Auswahl aufheben'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('zip-recovery-save')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel interrupts a pending capture and enables Close', (
    tester,
  ) async {
    final blocked = _BlockedBackend()..put('/input/broken.zip', original);
    addTearDown(() => unawaited(blocked.stream.close()));
    await _open(tester, blocked, destination, waitForReview: false);
    await _until(tester, () => blocked.reading);
    await tester.tap(find.byKey(const ValueKey('zip-recovery-cancel')));
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('zip-recovery-error'))
          .evaluate()
          .isNotEmpty,
    );
    final close = find.byKey(const ValueKey('zip-recovery-close'));
    expect(tester.widget<TextButton>(close).onPressed, isNotNull);
    expect(blocked.stream.hasListener, isFalse);
    expect(destination.writes, isEmpty);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing a pending scan prevents late callbacks and writes', (
    tester,
  ) async {
    final blocked = _BlockedBackend()..put('/input/broken.zip', original);
    addTearDown(() => unawaited(blocked.stream.close()));
    await _open(tester, blocked, destination, waitForReview: false);
    await _until(tester, () => blocked.reading);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(blocked.stream.hasListener, isFalse);
    expect(destination.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing an admitted job detaches without cancelling queue control',
    (tester) async {
      final control = FileOperationControl();
      final handle = ArchiveOperationHandle<ArchiveCreationResult>(
        id: 'recovery-test',
        operation: OperationProgress(
          id: 'recovery-test',
          type: OperationType.archive,
          sourcePath: '/input/broken.zip',
          targetPath: '/output/recovered.zip',
          fileName: 'recovered.zip',
        ),
        control: control,
      );
      addTearDown(handle.dispose);
      Set<int>? selected;
      await _open(
        tester,
        source,
        destination,
        enqueue: (captured, name, offsets) async {
          selected = offsets;
          handle.zipRecoveryProgress = const ArchiveZipRecoveryProgress(
            ArchiveZipRecoveryPhase.recovering,
            0,
            2,
          );
          return handle;
        },
      );
      await tester.tap(find.byKey(const ValueKey('zip-recovery-save')));
      await _until(tester, () => find.text('Pause').evaluate().isNotEmpty);
      expect(selected, hasLength(2));
      await tester.tap(find.byKey(const ValueKey('zip-recovery-close')));
      await tester.pumpAndSettle();
      expect(find.byType(ArchiveZipRecoveryDialog), findsNothing);
      expect(control.isCancelled, isFalse);
      handle.settle(
        result: const ArchiveCreationResult('/output/recovered.zip', 2, 100),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposal during queue admission leaves the admitted job owned by its queue',
    (tester) async {
      final admission =
          Completer<ArchiveOperationHandle<ArchiveCreationResult>>();
      final control = FileOperationControl();
      final handle = ArchiveOperationHandle<ArchiveCreationResult>(
        id: 'late-admission',
        operation: OperationProgress(
          id: 'late-admission',
          type: OperationType.archive,
          sourcePath: '/input/broken.zip',
          targetPath: '/output/recovered.zip',
          fileName: 'recovered.zip',
        ),
        control: control,
      );
      addTearDown(handle.dispose);
      var admitting = false;
      await _open(
        tester,
        source,
        destination,
        enqueue: (_, _, _) {
          admitting = true;
          return admission.future;
        },
      );
      await tester.tap(find.byKey(const ValueKey('zip-recovery-save')));
      await _until(tester, () => admitting);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('zip-recovery-close')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      admission.complete(handle);
      await tester.pumpAndSettle();
      expect(control.isCancelled, isFalse);
      handle.settle(
        result: const ArchiveCreationResult('/output/recovered.zip', 2, 100),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

class _BlockedBackend extends RecoveryWorkflowBackend {
  _BlockedBackend() : super('blocked');
  final stream = StreamController<List<int>>();
  bool reading = false;
  @override
  Stream<List<int>> readFile(FileItem file) {
    reading = true;
    return stream.stream;
  }
}
