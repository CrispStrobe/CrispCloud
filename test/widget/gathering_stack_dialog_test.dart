import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/gathering_stack_strings.dart';
import 'package:crisp_cloud/models/gathering_stack.dart';
import 'package:crisp_cloud/services/file_collection_storage.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/services/gathering_stack_service.dart';
import 'package:crisp_cloud/services/gathering_stack_store.dart';
import 'package:crisp_cloud/widgets/gathering_stack_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/gathering_stack_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GatheringStackStore store;
  late GatheringStackService service;
  late GatheringMemoryBackend a, b, target;
  late int transfers;
  GatheringTransferReview? transfer;

  setUp(() async {
    store = GatheringStackStore(storage: MemoryFileCollectionStorage());
    await store.ready;
    service = GatheringStackService(store);
    a = GatheringMemoryBackend(gatheringAccountA)
      ..file('/first/same.txt', 'A', objectId: 'same');
    b = GatheringMemoryBackend(gatheringAccountB)
      ..file('/second/same.txt', 'B', objectId: 'same');
    target = GatheringMemoryBackend(gatheringTarget)
      ..directory('/exact destination ');
    await service.add([
      GatheringAddition(file: a.items['/first/same.txt']!, source: a.binding()),
      GatheringAddition(
        file: b.items['/second/same.txt']!,
        source: b.binding(),
      ),
    ]);
    transfers = 0;
    transfer = null;
  });
  tearDown(() => store.dispose());

  Future<void> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size size = const Size(1000, 1100),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: GatheringStackDialog(
            service: service,
            resolve: (storage, path) => storage == a.reference
                ? a.binding()
                : storage == b.reference
                ? b.binding()
                : null,
            destination: target.destination('/exact destination '),
            sourceLabel: (storage) => 'Same label · ${storage.accountKey}',
            onTransfer: (context, review, kind) async {
              transfers++;
              await transfer?.call(context, review, kind);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'distinct originals stay visible and reordering or removing references does not touch files',
    (tester) async {
      await open(tester);
      expect(find.text('same.txt'), findsNWidgets(2));
      expect(find.text('Same label · account-a'), findsOneWidget);
      expect(find.text('Same label · account-b'), findsOneWidget);
      final secondId = store.entries.last.id;
      final up = find.byKey(ValueKey('gathering-up-$secondId'));
      await tester.ensureVisible(up);
      await tester.tap(up);
      await tester.pumpAndSettle();
      expect(store.entries.first.reference.storage, b.reference);
      final remove = find.byKey(ValueKey('gathering-remove-$secondId'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(store.entries.single.reference.storage, a.reference);
      expect(b.items.containsKey('/second/same.txt'), isTrue);
      expect(target.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'complete overview pins the exact destination and cancel keeps every reference',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('gathering-copy')));
      await tester.pumpAndSettle();
      final overview = find.byType(GatheringTransferOverview);
      expect(overview, findsOneWidget);
      expect(
        find.descendant(
          of: overview,
          matching: find.text('Same label · account-a'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: overview,
          matching: find.text('Same label · account-b'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: overview,
          matching: find.text(
            'Destination: Same label · target-account · /exact destination ',
          ),
        ),
        findsOneWidget,
      );
      expect(target.writes, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(transfers, 0);
      expect(store.entries, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'accepted transfer reports partial successes while preserving later untouched sources',
    (tester) async {
      transfer = (context, review, kind) async {
        final first = review.capture.entries.first;
        final plan = await const FileOperationService().prepare(
          files: [review.verified[first.id]!.file],
          source: a,
          destination: target,
          targetDirectory: '/exact destination ',
          options: FileOperationOptions(kind: kind),
        );
        review.validatePlan(plan);
        await const FileOperationService().execute(
          plan,
          control: FileOperationControl(),
        );
        await service.reconcile(review, plan);
        // The next source's review is canceled before it executes.
      };
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('gathering-copy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gathering-continue')));
      await tester.pumpAndSettle();
      expect(transfers, 1);
      expect(store.entries.single.reference.storage, b.reference);
      expect(target.writes, ['/exact destination /same.txt']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing originals are visible and cannot reach the execution callback',
    (tester) async {
      b.items.remove('/second/same.txt');
      await open(tester);
      expect(find.text('Original path missing'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('gathering-move')));
      await tester.pumpAndSettle();
      expect(find.byType(GatheringTransferOverview), findsNothing);
      expect(
        find.text(
          'Unavailable references must be removed or gathered again before this transfer.',
        ),
        findsOneWidget,
      );
      expect(transfers, 0);
      expect(store.entries, hasLength(2));
      expect(target.writes, isEmpty);
    },
  );

  testWidgets(
    'canceling verification does not wait for a provider and preserves references',
    (tester) async {
      await open(tester);
      final gate = Completer<void>();
      a.beforeList = (_) => gate.future;
      await tester.tap(find.byKey(const ValueKey('gathering-refresh')));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.text('Review cancelled. References remain in the stack.'),
        findsOneWidget,
      );
      expect(store.entries, hasLength(2));
      gate.complete();
      await tester.pumpAndSettle();
      expect(target.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['de', 'ar']) {
    testWidgets('narrow enlarged $language stack and overview remain usable', (
      tester,
    ) async {
      await open(
        tester,
        locale: Locale(language),
        size: const Size(360, 760),
        textScale: 1.7,
      );
      expect(tester.takeException(), isNull);
      final copy = find.byKey(const ValueKey('gathering-copy'));
      await tester.ensureVisible(copy);
      await tester.pumpAndSettle();
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(find.byType(GatheringTransferOverview), findsOneWidget);
      expect(tester.takeException(), isNull);
      final continueButton = find.byKey(const ValueKey('gathering-continue'));
      expect(
        Directionality.of(tester.element(continueButton)),
        language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
      expect(transfers, 1);
      expect(store.entries, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }

  test('every gathering string has all nine complete translations', () {
    for (final entry in GatheringStackStrings.messages.entries) {
      expect(
        entry.value,
        hasLength(GatheringStackStrings.languages.length),
        reason: entry.key,
      );
      final placeholders = RegExp(r'\{\d+\}')
          .allMatches(entry.value.first)
          .map((match) => match.group(0))
          .toSet();
      for (final translated in entry.value) {
        expect(translated.trim(), isNotEmpty, reason: entry.key);
        expect(
          RegExp(r'\{\d+\}')
              .allMatches(translated)
              .map((match) => match.group(0))
              .toSet(),
          placeholders,
          reason: entry.key,
        );
      }
    }
    expect(
      GatheringReferenceState.values.map(
        (state) => state == GatheringReferenceState.changed
            ? 'changedStatus'
            : state.name,
      ),
      everyElement(isIn(GatheringStackStrings.messages.keys)),
    );
  });
}
