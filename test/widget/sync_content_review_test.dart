import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/providers/sync_provider.dart';
import 'package:crisp_cloud/services/sync_database.dart';
import 'package:crisp_cloud/services/sync_engine.dart';
import 'package:crisp_cloud/widgets/sync_plan_dialog.dart';

class _Pair extends Fake implements SyncPair {
  @override
  String get name => 'Content review';
}

class _Plan extends Fake implements SyncPlan {
  _Plan(this.compareContents);
  @override
  final bool compareContents;
  @override
  SyncPair get pair => _Pair();
  @override
  List<SyncAction> get actions => [
    if (compareContents)
      SyncAction(type: SyncActionType.upload, relativePath: 'changed.txt'),
  ];
  @override
  List<SyncActionType> choicesFor(SyncAction action) => [
    SyncActionType.skip,
    SyncActionType.upload,
  ];
}

class _Sync extends ChangeNotifier implements SyncNotifier {
  final compared = <bool>[];
  final applied = <SyncPlan>[];
  bool failContent = false;

  @override
  Future<SyncPlan> planOne(
    int pairId, {
    bool Function()? isCancelled,
    bool compareContents = false,
    void Function(int completed, int total, String path)? onCompareProgress,
  }) async {
    compared.add(compareContents);
    if (compareContents && failContent) {
      throw StateError('Content comparison interrupted.');
    }
    onCompareProgress?.call(2, 2, 'changed.txt');
    return _Plan(compareContents);
  }

  @override
  Future<SyncResult> executeReviewedPlan(
    SyncPlan plan, {
    Map<String, SyncActionType> decisions = const {},
    bool Function()? isCancelled,
    void Function(int completed, int total, String path)? onProgress,
  }) async {
    applied.add(plan);
    return const SyncResult(uploaded: 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Sync sync;
  late ProviderContainer container;
  setUp(() {
    sync = _Sync();
    container = ProviderContainer(
      overrides: [syncProvider.overrideWith((_) => sync)],
    );
  });
  tearDown(() => container.dispose());

  Future<void> open(WidgetTester tester, {bool narrow = false}) async {
    if (narrow) {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(narrow ? 1.8 : 1)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSyncPlanDialog(context, 1),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final narrow in [false, true]) {
    testWidgets(
      'full-content switch creates and applies a new reviewed plan${narrow ? " with large narrow text" : ""}',
      (tester) async {
        await open(tester, narrow: narrow);
        expect(sync.compared, [false]);
        final toggle = find.text('Compare full file contents');
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(sync.compared, [false, true]);
        await tester.scrollUntilVisible(
          find.text('changed.txt'),
          180,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('changed.txt'), findsOneWidget);
        final apply = find.text('Apply reviewed plan');
        await tester.ensureVisible(apply);
        await tester.pumpAndSettle();
        await tester.tap(apply);
        await tester.pumpAndSettle();
        expect(sync.applied.single.compareContents, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an interrupted content comparison cannot apply the previous fast plan',
    (tester) async {
      await open(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply reviewed plan'),
            )
            .onPressed,
        isNotNull,
      );
      sync.failContent = true;
      await tester.tap(find.text('Compare full file contents'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Content comparison interrupted'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply reviewed plan'),
            )
            .onPressed,
        isNull,
      );
      expect(sync.applied, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
