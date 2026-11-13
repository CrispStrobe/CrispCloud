import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/models/transfer_queue_summary.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/widgets/operations_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OperationProgress _operation(
  String id, {
  OperationStatus status = OperationStatus.inProgress,
}) => OperationProgress(
  id: id,
  type: OperationType.archive,
  sourcePath: '/input/$id.txt',
  targetPath: '/output/$id.zip',
  fileName: '$id.zip',
  totalBytes: 100,
  currentBytes: 25,
  status: status,
);

class _Transfers extends ChangeNotifier implements TransferNotifier {
  _Transfers(this.rows, {Set<String>? pending, Set<String>? active})
    : pending = pending ?? {},
      active = active ?? {};

  final List<OperationProgress> rows;
  final Set<String> pending;
  final Set<String> active;
  final paused = <List<String>>[];
  final resumed = <List<String>>[];
  final stopped = <List<String>>[];

  @override
  List<OperationProgress> get operations => rows;
  @override
  List<TransferJobRecord> get savedJobs => const [];
  @override
  TransferJobRecord? savedJob(String id) => null;
  @override
  String? get recoveryError => null;
  @override
  bool get queuePaused => false;
  @override
  int get maxConcurrent => 3;
  @override
  List<String> get queuedIds => pending.toList();
  @override
  bool isJobLive(String id) => pending.contains(id) || active.contains(id);
  @override
  bool isQueued(String id) => pending.contains(id);
  @override
  bool isRunning(String id) => active.contains(id);
  @override
  int priorityOf(String id) => 0;
  @override
  String? queueBlockedReason(String id) => null;
  @override
  TransferQueueSummary get queueSummary =>
      TransferQueueSummary(running: active.length, queued: pending.length);
  @override
  void pauseOperations(Iterable<String> ids) {
    paused.add(ids.toList());
    for (final row in rows.where((row) => ids.contains(row.id))) {
      row.pause();
    }
    notifyListeners();
  }

  @override
  void resumeOperations(Iterable<String> ids) {
    resumed.add(ids.toList());
    for (final row in rows.where((row) => ids.contains(row.id))) {
      row.resume();
    }
    notifyListeners();
  }

  @override
  void cancelOperations(Iterable<String> ids) {
    stopped.add(ids.toList());
    for (final row in rows.where((row) => ids.contains(row.id))) {
      row.cancel();
    }
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> show(
    WidgetTester tester,
    _Transfers transfers, {
    String language = 'en',
    double width = 1100,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [transferProvider.overrideWith((ref) => transfers)],
        child: MaterialApp(
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(body: OperationsPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        100,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('queue-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'archive pause resume and stop are visible without an overflow menu',
    (tester) async {
      final operation = _operation('pack')..phaseLabel = 'archive:packing';
      final transfers = _Transfers([operation], active: {'pack'});
      await show(tester, transfers);
      expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
      expect(find.text('Packing…'), findsOneWidget);
      expect(find.textContaining('archive:'), findsNothing);
      await tap(tester, 'queue-pause-pack');
      expect(transfers.paused.single, ['pack']);
      expect(find.byKey(const ValueKey('queue-resume-pack')), findsOneWidget);
      await tap(tester, 'queue-resume-pack');
      expect(transfers.resumed.single, ['pack']);
      await tap(tester, 'queue-stop-pack');
      expect(transfers.stopped.single, ['pack']);
      expect(find.text('Cancelling'), findsOneWidget);
      expect(find.byKey(const ValueKey('queue-stop-pack')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stop all affects eligible jobs even when the view is filtered', (
    tester,
  ) async {
    final transfers = _Transfers(
      [
        _operation('active'),
        _operation('pending'),
        _operation('paused')..pause(),
        _operation('waiting', status: OperationStatus.waitingForDecision),
        _operation('review', status: OperationStatus.failed),
        _operation('finished', status: OperationStatus.completed),
        _operation('stopping')..cancel(),
      ],
      pending: {'pending', 'paused'},
      active: {'active', 'stopping'},
    );
    await show(tester, transfers);
    await tap(tester, 'queue-filter-finished');
    await tap(tester, 'queue-stop-all');
    expect(
      transfers.stopped.single,
      unorderedEquals(['active', 'pending', 'paused', 'waiting']),
    );
    expect(
      transfers.rows.singleWhere((row) => row.id == 'review').isCancelled,
      isFalse,
    );
    expect(
      transfers.rows.singleWhere((row) => row.id == 'finished').isCancelled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stop all is disabled when only completed history remains', (
    tester,
  ) async {
    await show(
      tester,
      _Transfers([
        _operation('finished', status: OperationStatus.completed),
        _operation('review', status: OperationStatus.failed),
      ]),
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('queue-stop-all')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a published archive warning stays completed and cannot restart',
    (tester) async {
      final operation = _operation(
        'published',
        status: OperationStatus.completed,
      )..errorMessage = 'The saved completion needs review';
      await show(tester, _Transfers([operation]));
      expect(find.text('Completed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('queue-publication-warning-published')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('queue-stop-published')), findsNothing);
      expect(find.byKey(const ValueKey('queue-pause-published')), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('queue-stop-all')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in [
    'en',
    'de',
    'fr',
    'es',
    'pt',
    'zh',
    'ja',
    'ko',
    'ar',
  ]) {
    testWidgets('$language archive controls fit narrow large text', (
      tester,
    ) async {
      final operation = _operation('pack')
        ..phaseLabel = 'archivePublication:backingUp';
      final transfers = _Transfers([operation], active: {'pack'});
      await show(
        tester,
        transfers,
        language: language,
        width: 320,
        textScale: 1.8,
      );
      await tap(tester, 'queue-pause-pack');
      await tap(tester, 'queue-resume-pack');
      expect(transfers.paused.single, ['pack']);
      expect(transfers.resumed.single, ['pack']);
      expect(find.textContaining('archivePublication:'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
