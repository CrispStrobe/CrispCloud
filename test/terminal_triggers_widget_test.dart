import 'package:crisp_cloud/l10n/terminal_trigger_strings.dart';
import 'package:crisp_cloud/models/terminal_trigger.dart';
import 'package:crisp_cloud/providers/terminal_triggers_provider.dart';
import 'package:crisp_cloud/services/terminal_triggers.dart';
import 'package:crisp_cloud/widgets/terminal_triggers_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String? raw;
  late TerminalTriggers store;
  late ProviderContainer container;

  setUp(() {
    raw = null;
    store = TerminalTriggers(
      read: () async => raw,
      write: (value) async => raw = value,
    );
    container = ProviderContainer(
      overrides: [terminalTriggersProvider.overrideWithValue(store)],
    );
  });
  tearDown(() => container.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(900, 850),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await container.read(terminalTriggerListProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const TerminalTriggersDialog(),
                ),
                child: const Text('Open triggers'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open triggers'));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'add, preview, disable, edit and delete a trigger from the dialog',
    (tester) async {
      await mount(tester);
      expect(find.text('No output triggers'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('terminal-add-trigger')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('terminal-trigger-name')),
        'Build failed',
      );
      await tester.enterText(
        find.byKey(const ValueKey('terminal-trigger-pattern')),
        'ERROR',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('terminal-trigger-sample')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('terminal-trigger-sample')),
        'ERROR: build failed',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('terminal-test-trigger')),
      );
      expect(find.text('Pattern matches sample.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('terminal-trigger-sample')),
        'done',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('terminal-trigger-preview')),
        findsNothing,
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('terminal-test-trigger')),
      );
      expect(find.text('No match in sample.'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('terminal-save-trigger')),
      );
      final first = (await store.load()).single;
      expect(first.name, 'Build failed');
      expect(first.pattern, 'ERROR');
      expect(first.enabled, isTrue);
      expect(raw, isNot(contains('ERROR: build failed')));
      await tapVisible(
        tester,
        find.byKey(ValueKey('terminal-trigger-enabled-${first.id}')),
      );
      expect((await store.load()).single.enabled, isFalse);
      await tapVisible(tester, find.text('Build failed'));
      await tester.enterText(
        find.byKey(const ValueKey('terminal-trigger-name')),
        'Build status',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('terminal-save-trigger')),
      );
      expect((await store.load()).single.id, first.id);
      expect((await store.load()).single.name, 'Build status');
      await tapVisible(
        tester,
        find.byKey(ValueKey('terminal-trigger-delete-${first.id}')),
      );
      expect(await store.load(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unsupported regular expression cannot be saved or previewed', (
    tester,
  ) async {
    await mount(tester);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('terminal-add-trigger')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('terminal-trigger-name')),
      'Unsafe expression',
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('terminal-trigger-kind')),
    );
    await tester.tap(find.text('Limited pattern').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('terminal-trigger-pattern')),
      '(a+)+',
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('terminal-save-trigger')),
    );
    expect(
      find.text('Unsupported pattern. Use the syntax shown below.'),
      findsOneWidget,
    );
    expect(await store.load(), isEmpty);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('terminal-test-trigger')),
    );
    expect(find.text('Check the matching pattern.'), findsOneWidget);
    expect(find.text('Pattern matches sample.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'management and editor remain scrollable in a 320 by 320 window',
    (tester) async {
      await store.save(
        TerminalTrigger(
          id: 'long',
          name: 'A long but valid trigger name for a narrow terminal',
          pattern:
              'Error: the long output pattern remains readable by scrolling',
        ),
      );
      await mount(tester, size: const Size(320, 320));
      expect(tester.takeException(), isNull);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('terminal-add-trigger')),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('terminal-trigger-name')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('terminal-trigger-name')),
        'Small window',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('terminal-trigger-pattern')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('terminal-trigger-pattern')),
        'READY',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('terminal-save-trigger')),
      );
      expect((await store.load()).length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'corrupt stores show a load error and cannot be overwritten by Add',
    (tester) async {
      raw = '{"version":2,"triggers":[]}';
      await expectLater(
        container.read(terminalTriggerListProvider.future),
        throwsFormatException,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: TerminalTriggersDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load triggers.'), findsOneWidget);
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('terminal-add-trigger')),
      );
      expect(button.onPressed, isNull);
      expect(raw, '{"version":2,"triggers":[]}');
    },
  );

  testWidgets(
    'new controls translate in all eight existing non-English languages',
    (tester) async {
      for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
        final translated = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: [Locale(language)],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (context) {
                for (final label in [
                  'Output triggers',
                  'Add trigger',
                  'Once per connection',
                  'Test pattern',
                  'Rules are stored locally as plain text.',
                ]) {
                  translated.add(context.terminalTriggerTr(label));
                }
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(translated, isNotEmpty);
        expect(
          translated,
          isNot(contains('Output triggers')),
          reason: language,
        );
        expect(translated, isNot(contains('Add trigger')), reason: language);
        expect(
          translated,
          isNot(contains('Once per connection')),
          reason: language,
        );
        expect(translated, isNot(contains('Test pattern')), reason: language);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
