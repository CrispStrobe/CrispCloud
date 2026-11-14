import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/operation_progress.dart';
import 'package:crisp_cloud/models/transfer_job.dart';
import 'package:crisp_cloud/models/transfer_queue_summary.dart';
import 'package:crisp_cloud/providers/transfer_provider.dart';
import 'package:crisp_cloud/providers/transfer_bandwidth_provider.dart';
import 'package:crisp_storage/crisp_storage.dart'
    show TransferBandwidthAllocator, TransferBandwidthDirection;
import 'package:crisp_cloud/services/file_operation_options.dart';
import 'package:crisp_cloud/utils/formatters.dart' show formatBytes;
import 'package:crisp_cloud/widgets/operations_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OperationProgress _operation(
  String id, {
  OperationStatus status = OperationStatus.inProgress,
  int bytes = 100,
  List<FileProgress>? files,
}) => OperationProgress(
  id: id,
  type: OperationType.copy,
  sourcePath: '/source/$id',
  targetPath: '/cloud/$id',
  fileName: '$id.txt',
  totalBytes: bytes,
  currentBytes: 25,
  status: status,
  files: files,
);

TransferJobRecord _savedJob(
  String id, {
  TransferJobStatus status = TransferJobStatus.queued,
  DateTime? scheduledAt,
}) => TransferJobRecord(
  id: id,
  created: DateTime.utc(2026),
  source: null,
  destination: null,
  targetDirectory: '/cloud/$id',
  options: const FileOperationOptions(),
  sourceLabel: 'Local files',
  destinationLabel: 'Cloud storage',
  expectedEntries: 1,
  canRecover: true,
  status: status,
  scheduledAt: scheduledAt,
);

/// The view receives a deliberate summary so tests catch accidentally summing
/// retained history or trusting a queued row's transfer counters.
class _Transfers extends ChangeNotifier implements TransferNotifier {
  _Transfers({
    required this.rows,
    this.summary = const TransferQueueSummary(queued: 1, totalBytes: 100),
    Set<String>? pending,
    Set<String>? running,
    Map<String, TransferJobRecord>? saved,
  }) : pending = pending ?? {},
       running = running ?? {},
       saved = saved ?? {};

  final List<OperationProgress> rows;
  final Set<String> pending;
  final Set<String> running;
  final Map<String, TransferJobRecord> saved;
  TransferQueueSummary summary;
  final pausedRequests = <List<String>>[];
  final resumedRequests = <List<String>>[];
  final cancelledRequests = <List<String>>[];
  final scheduledRequests = <(String, DateTime?)>[];
  Object? queueFailure;
  bool pausedQueue = false;
  int concurrency = 3;

  @override
  List<OperationProgress> get operations => List.unmodifiable(rows);
  @override
  List<TransferJobRecord> get savedJobs => saved.values.toList();
  @override
  TransferJobRecord? savedJob(String id) => saved[id];
  @override
  String? recoveryError;
  @override
  TransferQueueSummary get queueSummary => summary;
  @override
  bool get queuePaused => pausedQueue;
  @override
  int get maxConcurrent => concurrency;
  @override
  List<String> get queuedIds => pending.toList();
  @override
  bool isQueued(String id) => pending.contains(id);
  @override
  bool isRunning(String id) => running.contains(id);
  @override
  bool isJobLive(String id) => isQueued(id) || isRunning(id);
  @override
  int priorityOf(String id) => saved[id]?.priority ?? 0;
  @override
  String? queueBlockedReason(String id) =>
      isQueued(id) ? 'Waiting for transfer slot' : null;

  @override
  Future<void> setQueuePaused(bool value) async {
    if (queueFailure != null) throw queueFailure!;
    pausedQueue = value;
    notifyListeners();
  }

  @override
  Future<void> setConcurrency(int value) async {
    concurrency = value;
    notifyListeners();
  }

  @override
  void pauseOperations(Iterable<String> ids) =>
      pausedRequests.add(ids.toList());
  @override
  void resumeOperations(Iterable<String> ids) =>
      resumedRequests.add(ids.toList());
  @override
  void cancelOperations(Iterable<String> ids) =>
      cancelledRequests.add(ids.toList());
  @override
  Future<void> setScheduledStart(String id, DateTime? value) async {
    scheduledRequests.add((id, value));
    saved[id]?.scheduledAt = value;
    notifyListeners();
  }

  @override
  void clearFinishedOperations() {
    rows.removeWhere(
      (operation) =>
          operation.status == OperationStatus.completed ||
          operation.isCancelled ||
          saved[operation.id]?.status == TransferJobStatus.cancelled,
    );
    notifyListeners();
  }

  @override
  void removeOperation(String id) {
    rows.removeWhere((operation) => operation.id == id);
    pending.remove(id);
    running.remove(id);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

_Transfers _mixedTransfers() {
  final later = DateTime.now().add(const Duration(days: 1));
  return _Transfers(
    rows: [
      _operation('running'),
      _operation('queued'),
      _operation('scheduled'),
      _operation('paused')..pause(),
      _operation('waiting', status: OperationStatus.waitingForDecision),
      _operation('review', status: OperationStatus.failed),
      _operation('completed', status: OperationStatus.completed, bytes: 100000),
      // Restored cancellation is represented by its journal status.
      _operation('cancelled', status: OperationStatus.failed),
    ],
    pending: {'queued', 'scheduled', 'paused'},
    running: {'running'},
    saved: {
      'scheduled': _savedJob('scheduled', scheduledAt: later),
      'cancelled': _savedJob('cancelled', status: TransferJobStatus.cancelled),
    },
    summary: const TransferQueueSummary(
      running: 1,
      queued: 1,
      scheduled: 1,
      paused: 1,
      waiting: 1,
      needsReview: 1,
      completed: 1,
      cancelled: 1,
      totalBytes: 400,
      transferredBytes: 100,
    ),
  );
}

void main() {
  Future<void> show(
    WidgetTester tester,
    _Transfers transfers, {
    Size size = const Size(1100, 1000),
    TransferBandwidthController? bandwidth,
    String language = 'en',
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final policy =
        bandwidth ??
        TransferBandwidthController(readSettings: () async => null);
    addTearDown(policy.dispose);
    await policy.ready;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transferProvider.overrideWith((ref) => transfers),
          transferBandwidthProvider.overrideWith((ref) => policy),
        ],
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    if (finder.evaluate().isEmpty) {
      // A narrow toolbar can fill the viewport. Exercise the lazy queue by
      // scrolling until the target row is built before ensuring its position.
      await tester.scrollUntilVisible(
        finder,
        120,
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
    'filters count distinct states and search source or target paths',
    (tester) async {
      final transfers = _mixedTransfers();
      await show(tester, transfers);
      for (final label in [
        'Active (4)',
        'Queued (3)',
        'Attention (2)',
        'Finished (2)',
        'All (8)',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('1 waiting for a decision'), findsOneWidget);

      await tapKey(tester, 'queue-filter-attention');
      expect(find.byKey(const ValueKey('queue-job-waiting')), findsOneWidget);
      expect(find.byKey(const ValueKey('queue-job-review')), findsOneWidget);
      expect(find.byKey(const ValueKey('queue-job-queued')), findsNothing);
      expect(find.byKey(const ValueKey('queue-job-cancelled')), findsNothing);

      await tapKey(tester, 'queue-filter-finished');
      await tester.enterText(
        find.byKey(const ValueKey('queue-search')),
        '/CLOUD/cancelled',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('queue-job-cancelled')), findsOneWidget);
      expect(find.byKey(const ValueKey('queue-job-completed')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('queue-search')),
        'does-not-exist',
      );
      await tester.pumpAndSettle();
      expect(find.text('No jobs match this view'), findsOneWidget);
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('queue-select-visible')),
            )
            .onChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('batch search includes member paths and renamed destinations', (
    tester,
  ) async {
    final saved = _savedJob('batch');
    saved.entries.add(
      TransferEntryRecord(
        index: 0,
        source: FileItem(
          name: 'statement.csv',
          path: '/original/accounts/statement.csv',
          isFolder: false,
        ),
        destination: '/destination/renamed.csv',
      ),
    );
    final transfers = _Transfers(
      rows: [
        OperationProgress(
          id: 'batch',
          type: OperationType.copy,
          sourcePath: 'Local',
          targetPath: '/destination',
          fileName: '1 files',
          totalBytes: 100,
          files: [
            FileProgress(
              name: 'statement.csv',
              path: '/original/accounts/statement.csv',
              size: 100,
            ),
          ],
        ),
      ],
      pending: {'batch'},
      saved: {'batch': saved},
    );
    await show(tester, transfers);
    for (final query in [
      'STATEMENT.csv',
      '/original/accounts',
      '/destination/renamed.csv',
    ]) {
      await tester.enterText(find.byKey(const ValueKey('queue-search')), query);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('queue-job-batch')), findsOneWidget);
      expect(find.text('No jobs match this view'), findsNothing);
    }
  });

  testWidgets('bulk controls pass only eligible selected jobs', (tester) async {
    final transfers = _mixedTransfers();
    await show(tester, transfers);
    await tapKey(tester, 'queue-select-visible');
    expect(find.text('8 selected'), findsOneWidget);

    await tapKey(tester, 'queue-pause-selected');
    expect(
      transfers.pausedRequests.single,
      unorderedEquals(['running', 'queued', 'scheduled']),
    );
    await tapKey(tester, 'queue-resume-selected');
    expect(transfers.resumedRequests.single, ['paused']);
    await tapKey(tester, 'queue-cancel-selected');
    expect(
      transfers.cancelledRequests.single,
      unorderedEquals(['running', 'queued', 'scheduled', 'paused', 'waiting']),
    );
    expect(find.text('3 selected'), findsOneWidget);
    for (final key in [
      'queue-pause-selected',
      'queue-resume-selected',
      'queue-cancel-selected',
    ]) {
      expect(
        tester.widget<TextButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expanded members follow queue path search including renamed destinations',
    (tester) async {
      final saved = _savedJob('batch');
      saved.entries.add(
        TransferEntryRecord(
          index: 0,
          source: FileItem(
            name: 'statement.csv',
            path: '/source/statement.csv',
            isFolder: false,
          ),
          destination: '/archive/renamed.csv',
        ),
      );
      final transfers = _Transfers(
        rows: [
          _operation(
            'batch',
            files: [
              FileProgress(
                name: 'statement.csv',
                path: '/source/statement.csv',
                size: 100,
              ),
              FileProgress(
                name: 'other.txt',
                path: '/source/other.txt',
                size: 100,
              ),
            ],
          ),
        ],
        pending: {'batch'},
        saved: {'batch': saved},
      );
      await show(tester, transfers);
      final search = find.byKey(const ValueKey('queue-search'));
      await tester.enterText(search, 'RENAMED.csv');
      await tester.pumpAndSettle();
      await tapKey(tester, 'queue-menu-batch');
      await tester.tap(find.text('Show files'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('queue-file-batch-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('queue-file-batch-1')), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('queue-file-search-batch')),
            )
            .controller!
            .text,
        'renamed.csv',
      );
      await tester.ensureVisible(search);
      await tester.enterText(search, 'other.txt');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('queue-file-batch-0')), findsNothing);
      expect(find.byKey(const ValueKey('queue-file-batch-1')), findsOneWidget);
      expect(transfers.rows.single.files, hasLength(2));
      expect(transfers.pausedRequests, isEmpty);
      expect(transfers.cancelledRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('queue pause is independent from the concurrency setting', (
    tester,
  ) async {
    final transfers = _Transfers(
      rows: [_operation('queued')],
      pending: {'queued'},
    );
    await show(tester, transfers);
    await tapKey(tester, 'queue-pause');
    expect(transfers.queuePaused, isTrue);
    expect(transfers.maxConcurrent, 3);
    expect(find.text('Resume queue'), findsOneWidget);
    expect(find.text('Queue paused. Running jobs may finish.'), findsOneWidget);

    await tapKey(tester, 'queue-concurrency');
    await tester.tap(find.text('4').last);
    await tester.pumpAndSettle();
    expect(transfers.maxConcurrent, 4);
    expect(transfers.queuePaused, isTrue);

    await tapKey(tester, 'queue-pause');
    expect(transfers.queuePaused, isFalse);
    expect(transfers.maxConcurrent, 4);
  });

  testWidgets(
    'cancelling jobs stay active with destructive controls disabled',
    (tester) async {
      final operation = _operation('stopping')..cancel();
      final transfers = _Transfers(
        rows: [operation],
        running: {'stopping'},
        summary: const TransferQueueSummary(cancelling: 1),
      );
      await show(tester, transfers);
      expect(find.text('1 cancelling'), findsOneWidget);
      expect(find.text('Cancelling'), findsOneWidget);
      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('Finished (0)'), findsOneWidget);
      expect(find.text('Hide finished'), findsNothing);
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('queue-menu-stopping')),
            )
            .enabled,
        isFalse,
      );
      await tapKey(tester, 'queue-select-visible');
      for (final key in [
        'queue-pause-selected',
        'queue-resume-selected',
        'queue-cancel-selected',
      ]) {
        expect(
          tester.widget<TextButton>(find.byKey(ValueKey(key))).onPressed,
          isNull,
        );
      }
      expect(
        find.byKey(const ValueKey('queue-overall-progress')),
        findsNothing,
      );
    },
  );

  testWidgets('paused work keeps its phase and literal current member path', (
    tester,
  ) async {
    final operation = _operation('paused')
      ..currentFilePath = '/accounts/{0}/current.csv'
      ..phaseLabel = 'Preserving metadata'
      ..pause();
    final transfers = _Transfers(
      rows: [operation],
      running: {'paused'},
      summary: const TransferQueueSummary(paused: 1, totalBytes: 100),
    );
    await show(tester, transfers);
    expect(
      find.text('Preserving metadata · /accounts/{0}/current.csv'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('queue-speed-summary')), findsNothing);
  });

  testWidgets('header uses live summary rather than finished transfer bytes', (
    tester,
  ) async {
    final transfers = _mixedTransfers();
    await show(tester, transfers);
    final bytes = tester.widget<Text>(
      find.byKey(const ValueKey('queue-byte-summary')),
    );
    expect(bytes.data, '${formatBytes(100)} / ${formatBytes(400)}');
    expect(find.byKey(const ValueKey('queue-speed-summary')), findsNothing);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('queue-overall-progress')),
    );
    expect(progress.value, .25);
  });

  testWidgets('hide finished keeps attention rows and all recovery records', (
    tester,
  ) async {
    final transfers = _mixedTransfers();
    await show(tester, transfers);
    await tester.tap(find.text('Hide finished'));
    await tester.pumpAndSettle();
    expect(
      transfers.rows.map((row) => row.id),
      unorderedEquals([
        'running',
        'queued',
        'scheduled',
        'paused',
        'waiting',
        'review',
      ]),
    );
    expect(transfers.savedJob('cancelled'), isNotNull);
  });

  testWidgets('run now removes schedule without bypassing queue pause', (
    tester,
  ) async {
    final transfers = _Transfers(
      rows: [_operation('scheduled')],
      pending: {'scheduled'},
      saved: {
        'scheduled': _savedJob(
          'scheduled',
          scheduledAt: DateTime.now().add(const Duration(days: 1)),
        ),
      },
      summary: const TransferQueueSummary(scheduled: 1, totalBytes: 100),
    )..pausedQueue = true;
    await show(tester, transfers);
    await tapKey(tester, 'queue-menu-scheduled');
    expect(
      find.text('Removes the start time; queue controls still apply.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Run now'));
    await tester.pumpAndSettle();
    expect(transfers.scheduledRequests, [('scheduled', null)]);
    expect(transfers.queuePaused, isTrue);
    expect(transfers.isQueued('scheduled'), isTrue);
  });

  testWidgets('narrow rows and expanded batch details do not overflow', (
    tester,
  ) async {
    final files = [
      FileProgress(
        name: 'copied file with a very long name.txt',
        path: '/source/deep/path/file.txt',
        size: 50,
        isComplete: true,
        statusLabel: 'copied',
      ),
      FileProgress(
        name: 'excluded.tmp',
        path: '/source/excluded.tmp',
        size: 50,
        statusLabel: 'filtered',
      ),
    ];
    final transfers = _Transfers(
      rows: [
        _operation(
          'completed',
          status: OperationStatus.completed,
          files: files,
        ),
      ],
      saved: {
        'completed': _savedJob(
          'completed',
          status: TransferJobStatus.completed,
        ),
      },
      summary: const TransferQueueSummary(completed: 1),
    );
    await show(tester, transfers, size: const Size(320, 720));
    await tapKey(tester, 'queue-menu-completed');
    await tester.tap(find.text('Show files'));
    await tester.pumpAndSettle();
    expect(find.text('2/2 items processed'), findsOneWidget);
    expect(find.text('1 skipped'), findsOneWidget);
    expect(find.text('/source/completed → /cloud/completed'), findsOneWidget);
    expect(find.byKey(const ValueKey('queue-files-completed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue persistence failures are reported in a snackbar', (
    tester,
  ) async {
    final transfers = _Transfers(
      rows: [_operation('queued')],
      pending: {'queued'},
    )..queueFailure = StateError('Could not save queue settings');
    await show(tester, transfers);
    await tapKey(tester, 'queue-pause');
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining('Could not save queue settings'),
      findsOneWidget,
    );
    expect(transfers.queuePaused, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'covered HTTP counters stay separate from logical queue progress',
    (tester) async {
      var now = Duration.zero;
      final allocator = TransferBandwidthAllocator(clock: () => now);
      final policy = TransferBandwidthController(
        allocator: allocator,
        readSettings: () async => null,
      );
      await policy.ready;
      final job = allocator.openContext('payload');
      addTearDown(job.close);
      await job
          .bind(
            Stream.value(List<int>.filled(1024, 1)),
            direction: TransferBandwidthDirection.upload,
          )
          .drain<void>();
      await job
          .bind(
            Stream.value(List<int>.filled(2048, 2)),
            direction: TransferBandwidthDirection.download,
          )
          .drain<void>();
      job.markUnsupported(TransferBandwidthDirection.upload);
      final transfers = _Transfers(
        rows: [_operation('running')],
        running: {'running'},
        summary: const TransferQueueSummary(
          running: 1,
          totalBytes: 100,
          transferredBytes: 25,
          bytesPerSecond: 999,
        ),
      );
      await show(tester, transfers, bandwidth: policy);
      now = const Duration(milliseconds: 250);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('queue-bandwidth')), findsOneWidget);
      expect(find.byKey(const ValueKey('queue-byte-summary')), findsOneWidget);
      expect(find.text('25 B / 100 B'), findsOneWidget);
      expect(find.byKey(const ValueKey('queue-speed-summary')), findsOneWidget);
      final up = tester
          .widget<Text>(find.byKey(const ValueKey('queue-http-upload')))
          .data!;
      final down = tester
          .widget<Text>(find.byKey(const ValueKey('queue-http-download')))
          .data!;
      expect(up, contains(formatBytes(1024)));
      expect(down, contains(formatBytes(2048)));
      expect(up, contains('this session'));
      expect(
        find.byKey(const ValueKey('queue-http-unsupported')),
        findsOneWidget,
      );
      now = const Duration(seconds: 3);
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('queue-http-upload')))
            .data,
        startsWith('Upload: 0 B/s'),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('queue-http-download')))
            .data,
        startsWith('Download: 0 B/s'),
      );
      expect(policy.snapshot.uploadBytes, 1024);
      expect(policy.snapshot.downloadBytes, 2048);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['de', 'ar']) {
    testWidgets(
      'covered HTTP summary stays scrollable in narrow enlarged $language Activity',
      (tester) async {
        final policy = TransferBandwidthController(
          readSettings: () async => null,
          writeSettings: (_) async => true,
        );
        await policy.ready;
        await policy.updateLimits(
          const TransferBandwidthLimits(
            uploadBytesPerSecond: 1024,
            downloadBytesPerSecond: 2048,
          ),
        );
        await show(
          tester,
          _Transfers(rows: [_operation('running')], running: {'running'}),
          bandwidth: policy,
          language: language,
          textScale: 2,
          size: const Size(320, 800),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('queue-http-traffic')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('queue-http-upload')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('queue-http-download')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
