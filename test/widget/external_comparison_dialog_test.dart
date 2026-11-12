import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/external_comparison_strings.dart';
import 'package:crisp_cloud/services/command_entry_service.dart';
import 'package:crisp_cloud/services/external_comparison_service.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/widgets/external_comparison_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_comparison_fixture.dart';
import '../support/gathering_stack_fixture.dart';

void main() {
  late ComparisonHost host;
  late ComparisonMemoryStages stages;
  late ComparisonBackend left, right;
  late ExternalComparisonPair pair;
  late ExternalComparisonService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    host = ComparisonHost();
    stages = ComparisonMemoryStages();
    left = ComparisonBackend(gatheringAccountA)
      ..file('/same/name.txt', 'first');
    right = ComparisonBackend(gatheringAccountB)
      ..file('/same/name.txt', 'second');
    pair = comparisonPair(left, right);
    service = ExternalComparisonService(host: host, staging: stages);
    await service.ready;
    await service.saveConfiguration(comparisonConfiguration());
  });
  tearDown(() {
    pair.dispose();
    service.dispose();
  });

  Finder field(String name) =>
      find.byKey(ValueKey('external-comparison-$name'));
  String text(String key, String language) =>
      ExternalComparisonStrings.messages[key]![ExternalComparisonStrings
          .languages
          .indexOf(language)];

  Future<void> mount(
    WidgetTester tester, {
    String language = 'en',
    double scale = 1,
    bool withPair = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
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
                builder: (_) => ExternalComparisonDialog(
                  service: service,
                  pair: withPair ? pair : null,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester, {int ticks = 8}) async {
    for (var tick = 0; tick < ticks; tick++) {
      // Preferences can complete in the setup zone. Flush that continuation
      // before advancing the widget-zone frames.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> prepare(WidgetTester tester) async {
    await tester.ensureVisible(field('prepare'));
    await tester.pump();
    await tester.tap(field('prepare'));
    await drain(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ExternalComparisonReview), findsOneWidget);
    expect(host.launches, isEmpty);
  }

  Future<void> closeReview(
    WidgetTester tester, {
    String language = 'en',
  }) async {
    final close = find.descendant(
      of: find.byType(ExternalComparisonReview),
      matching: find.widgetWithText(TextButton, text('close', language)),
    );
    await tester.ensureVisible(close);
    await tester.pump();
    await tester.tap(close);
    await drain(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('preferences can be saved without a pair or any tool launch', (
    tester,
  ) async {
    await mount(tester, withPair: false);
    expect(tester.widget<FilledButton>(field('prepare')).onPressed, isNull);
    await tester.enterText(
      field('arguments'),
      '--mode "literal with spaces" {left} {right}',
    );
    await tester.ensureVisible(field('save'));
    await tester.tap(field('save'));
    await drain(tester);
    await tester.pumpAndSettle();
    expect(service.configuration(ExternalComparisonKind.text)!.arguments, [
      '--mode',
      'literal with spaces',
      '{left}',
      '{right}',
    ]);
    expect(find.text(text('saved', 'en')), findsOneWidget);
    expect(host.launches, isEmpty);
    expect(stages.entries, isEmpty);
  });

  testWidgets(
    'review shows both account identities and actual private argv before launching',
    (tester) async {
      await mount(tester);
      await prepare(tester);
      final review = tester.widget<ExternalComparisonReview>(
        find.byType(ExternalComparisonReview),
      );
      expect(
        find.descendant(
          of: find.byType(ExternalComparisonReview),
          matching: find.textContaining('account-a'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ExternalComparisonReview),
          matching: find.textContaining('account-b'),
        ),
        findsOneWidget,
      );
      expect(find.text(review.prepared.left.path), findsOneWidget);
      expect(find.text(review.prepared.right.path), findsOneWidget);
      await tester.ensureVisible(field('launch'));
      await tester.pump();
      await tester.tap(field('launch'));
      await drain(tester);
      await tester.pumpAndSettle();
      expect(host.launches, hasLength(1));
      expect(host.launches.single.arguments, [
        '--',
        review.prepared.left.path,
        review.prepared.right.path,
      ]);
      expect(find.text(text('launched', 'en')), findsOneWidget);
      expect(field('launch'), findsNothing);
      await closeReview(tester);
      expect(stages.entries, hasLength(1));
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(stages.entries, hasLength(1));
      expect(pair.isCurrent, isFalse);
    },
  );

  testWidgets('closing the review removes only the unlaunched copies', (
    tester,
  ) async {
    await mount(tester);
    await prepare(tester);
    expect(stages.entries, hasLength(1));
    await closeReview(tester);
    expect(find.byType(ExternalComparisonReview), findsNothing);
    expect(stages.entries, isEmpty);
    expect(pair.isCurrent, isTrue);
    expect(host.launches, isEmpty);
    expect(
      parseCommandEntryArguments(
        tester.widget<TextField>(field('arguments')).controller!.text,
      ),
      ['--', '{left}', '{right}'],
    );
  });

  testWidgets(
    'closing while a read is pending cancels it and never opens a late review',
    (tester) async {
      final listened = Completer<void>(), cancelled = Completer<void>();
      final stream = StreamController<List<int>>(
        onListen: listened.complete,
        onCancel: cancelled.complete,
      );
      left.read = (_) => stream.stream;
      await mount(tester);
      await tester.tap(field('prepare'));
      await drain(tester);
      expect(listened.isCompleted, isTrue);
      expect(find.byType(ExternalComparisonReview), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await drain(tester);
      await tester.pumpAndSettle();
      expect(cancelled.isCompleted, isTrue);
      expect(stages.entries, isEmpty);
      expect(find.byType(ExternalComparisonDialog), findsNothing);
      expect(find.byType(ExternalComparisonReview), findsNothing);
      expect(host.launches, isEmpty);
      // The cancelled controller may return Dart's root-zone completed future.
      await tester.runAsync(() => stream.close());
    },
  );

  testWidgets('captured source loss while review is open prevents launching', (
    tester,
  ) async {
    await mount(tester);
    await prepare(tester);
    right.current = false;
    await tester.tap(field('launch'));
    await drain(tester);
    await tester.pumpAndSettle();
    expect(host.launches, isEmpty);
    expect(find.text(text('changed', 'en')), findsOneWidget);
    await closeReview(tester);
    expect(stages.entries, isEmpty);
  });

  testWidgets(
    'failed launch stays retained and requires the tool-closed checkbox to remove',
    (tester) async {
      host.launchError = StateError('Launch unavailable');
      await mount(tester);
      await prepare(tester);
      await tester.tap(field('launch'));
      await drain(tester);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ExternalComparisonReview),
          matching: find.text(text('launchFailed', 'en')),
        ),
        findsOneWidget,
      );
      await closeReview(tester);
      expect(stages.entries, hasLength(1));
      final remove = find.widgetWithText(TextButton, text('release', 'en'));
      await tester.ensureVisible(remove);
      await tester.pump();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, text('release', 'en'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await drain(tester);
      await tester.pumpAndSettle();
      expect(stages.entries, isEmpty);
      expect(left.writes, isEmpty);
      expect(right.writes, isEmpty);
    },
  );

  testWidgets(
    'retained comparisons show on reopening without replaying a launch',
    (tester) async {
      final prepared = await tester.runAsync(
        () => service.prepare(
          comparisonConfiguration(),
          pair,
          control: FileOperationControl(),
          isCurrent: () => true,
        ),
      );
      await tester.runAsync(
        () => service.launch(
          prepared!,
          control: FileOperationControl(),
          isReviewCurrent: () => true,
        ),
      );
      await mount(tester, withPair: false);
      expect(find.text(prepared!.session.stage.directoryPath), findsOneWidget);
      expect(host.launches, hasLength(1));
      expect(tester.widget<FilledButton>(field('prepare')).onPressed, isNull);
    },
  );

  for (final language in ['de', 'ar']) {
    testWidgets(
      'narrow enlarged $language preference and review actions remain reachable',
      (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(tester, language: language, scale: 1.8);
        expect(tester.takeException(), isNull);
        await prepare(tester);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(field('launch'));
        await tester.pump();
        expect(tester.getRect(field('launch')).bottom, lessThanOrEqualTo(760));
        await closeReview(tester, language: language);
        expect(stages.entries, isEmpty);
        expect(host.launches, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
