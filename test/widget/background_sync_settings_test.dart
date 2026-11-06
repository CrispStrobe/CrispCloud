import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/providers/sync_provider.dart';
import 'package:crisp_cloud/widgets/sync_dialog.dart';

class _Sync extends ChangeNotifier implements SyncNotifier {
  bool enabled = false;
  int interval = 15;
  final requests = <int>[];
  int cancellations = 0;
  Completer<void>? pending;
  Object? failure;

  @override
  bool get isBackgroundSyncEnabled => enabled;
  @override
  int get backgroundSyncIntervalMinutes => interval;

  Future<void> _acknowledge() async {
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> enableBackgroundSync({int intervalMinutes = 15}) async {
    requests.add(intervalMinutes);
    await _acknowledge();
    enabled = true;
    interval = intervalMinutes;
    notifyListeners();
  }

  @override
  Future<void> disableBackgroundSync() async {
    cancellations++;
    await _acknowledge();
    enabled = false;
    notifyListeners();
  }

  void restore({required bool enabled, required int interval}) {
    this.enabled = enabled;
    this.interval = interval;
    notifyListeners();
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

  Future<void> open(
    WidgetTester tester, {
    String language = 'en',
    bool narrow = false,
  }) async {
    if (narrow) {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: BackgroundSyncSettings(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SwitchListTile toggle(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byType(SwitchListTile));
  DropdownButton<int> interval(WidgetTester tester) =>
      tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>));

  testWidgets(
    'a failed enable preserves the disabled state and reports failure',
    (tester) async {
      sync.failure = StateError('Scheduler unavailable');
      await open(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(sync.requests, [15]);
      expect(toggle(tester).value, isFalse);
      expect(toggle(tester).onChanged, isNotNull);
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(find.textContaining('Scheduler unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a rejected interval retains the active schedule and blocks duplicate requests',
    (tester) async {
      sync.enabled = true;
      sync.pending = Completer<void>();
      sync.failure = StateError('Request rejected');
      await open(tester);
      final changeInterval = interval(tester).onChanged!;
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min').last);
      await tester.pumpAndSettle();

      changeInterval(60);
      await tester.pump();
      expect(sync.requests, [30]);
      expect(toggle(tester).onChanged, isNull);
      expect(interval(tester).onChanged, isNull);
      expect(interval(tester).value, 15);
      expect(
        find.text('Background sync requested every 15 min'),
        findsOneWidget,
      );

      sync.pending!.complete();
      await tester.pumpAndSettle();
      expect(toggle(tester).value, isTrue);
      expect(interval(tester).value, 15);
      expect(interval(tester).onChanged, isNotNull);
      expect(find.textContaining('Request rejected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a failed cancellation retains the enabled schedule', (
    tester,
  ) async {
    sync.enabled = true;
    sync.interval = 60;
    sync.failure = StateError('Cancellation rejected');
    await open(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(sync.cancellations, 1);
    expect(toggle(tester).value, isTrue);
    expect(interval(tester).value, 60);
    expect(find.textContaining('Cancellation rejected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the schedule changes only after acknowledgement', (
    tester,
  ) async {
    sync.pending = Completer<void>();
    await open(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(toggle(tester).value, isFalse);
    expect(toggle(tester).onChanged, isNull);

    sync.pending!.complete();
    await tester.pumpAndSettle();
    expect(toggle(tester).value, isTrue);
    expect(interval(tester).value, 15);
    expect(toggle(tester).onChanged, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoring persisted state updates the visible interval', (
    tester,
  ) async {
    await open(tester);
    sync.restore(enabled: true, interval: 120);
    await tester.pumpAndSettle();

    expect(toggle(tester).value, isTrue);
    expect(interval(tester).value, 120);
    expect(
      find.text('Background sync requested every 120 min'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in ['de', 'ar']) {
    testWidgets('background settings fit narrow $language with large text', (
      tester,
    ) async {
      sync.enabled = true;
      sync.interval = 120;
      await open(tester, language: language, narrow: true);
      expect(toggle(tester).value, isTrue);
      expect(interval(tester).value, 120);
      expect(tester.takeException(), isNull);
    });
  }
}
