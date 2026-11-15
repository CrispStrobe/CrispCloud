import 'dart:async';

import 'package:crisp_cloud/models/terminal_arrangement.dart';
import 'package:crisp_cloud/providers/terminal_arrangements_provider.dart';
import 'package:crisp_cloud/services/terminal_arrangements.dart';
import 'package:crisp_cloud/widgets/terminal_arrangements_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String? raw;
  late bool failWrites;
  late TerminalArrangements store;
  TerminalArrangement? chosen;
  var tabName = 'Original';

  setUp(() {
    raw = null;
    failWrites = false;
    chosen = null;
    tabName = 'Original';
    store = TerminalArrangements(
      read: () async => raw,
      write: (value) async {
        if (failWrites) throw StateError('Unavailable storage');
        raw = value;
      },
    );
  });

  TerminalArrangement arrangement(String name) => TerminalArrangement(
    name: name,
    tabs: [TerminalArrangementTab(name: tabName)],
  );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [terminalArrangementsProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => unawaited(
                      showDialog<bool>(
                        context: context,
                        builder: (_) => SaveTerminalArrangementDialog(
                          createArrangement: arrangement,
                        ),
                      ),
                    ),
                    child: const Text('Open save'),
                  ),
                  TextButton(
                    onPressed: () async {
                      chosen = await showDialog<TerminalArrangement>(
                        context: context,
                        builder: (_) => const TerminalArrangementsDialog(),
                      );
                    },
                    child: const Text('Open list'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterName(WidgetTester tester, String name) async {
    await tester.enterText(
      find.byKey(const ValueKey('terminal-arrangement-name')),
      name,
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'save validates, names replacements and restores the selected value',
    (tester) async {
      await mount(tester);
      await open(tester, 'Open save');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a name from 1 to 80 characters.'),
        findsOneWidget,
      );
      expect(raw, isNull);
      await enterName(tester, 'Daily');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(SaveTerminalArrangementDialog), findsNothing);
      expect((await store.load()).single.tabs.single.name, 'Original');

      tabName = 'Updated';
      await open(tester, 'Open save');
      await enterName(tester, 'Daily');
      expect(
        find.text('A saved arrangement with this name will be replaced.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(await store.load(), hasLength(1));
      expect((await store.load()).single.tabs.single.name, 'Updated');
      await open(tester, 'Open list');
      await tester.tap(
        find.byKey(const ValueKey('terminal-arrangement-Daily')),
      );
      await tester.pumpAndSettle();
      expect(chosen!.name, 'Daily');
      expect(chosen!.tabs.single.name, 'Updated');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'future data disables saving and remains intact on both dialogs',
    (tester) async {
      raw = '{"version":99,"arrangements":[]}';
      await mount(tester);
      await open(tester, 'Open save');
      expect(find.text('Could not load arrangements.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await cancel(tester);
      await open(tester, 'Open list');
      expect(find.text('Could not load arrangements.'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      await cancel(tester);
      expect(raw, '{"version":99,"arrangements":[]}');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed deletion retains the saved value and retry succeeds', (
    tester,
  ) async {
    await store.save(arrangement('Keep until deleted'));
    final before = raw;
    await mount(tester);
    await open(tester, 'Open list');
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await cancel(tester);
    expect(raw, before);
    failWrites = true;
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Could not delete arrangement.'), findsOneWidget);
    expect(raw, before);
    expect(find.byType(ListTile), findsOneWidget);
    failWrites = false;
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(await store.load(), isEmpty);
    expect(find.text('No saved arrangements'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'capacity preserves existing arrangements and allows replacement',
    (tester) async {
      for (var i = 0; i < TerminalArrangements.maxArrangements; i++) {
        await store.save(arrangement('Saved $i'));
      }
      final before = raw;
      await mount(tester);
      await open(tester, 'Open save');
      await enterName(tester, 'One too many');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('At most 20 arrangements can be saved.'),
        findsOneWidget,
      );
      expect(raw, before);
      tabName = 'Replacement';
      await enterName(tester, 'Saved 0');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(await store.load(), hasLength(20));
      expect((await store.load()).first.tabs.single.name, 'Replacement');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save remains reachable with a narrow window and keyboard inset',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 600);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      await mount(tester);
      await open(tester, 'Open save');
      await enterName(tester, 'Small screen');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect((await store.load()).single.name, 'Small screen');
      expect(tester.takeException(), isNull);
    },
  );
}
