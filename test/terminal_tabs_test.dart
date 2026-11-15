import 'dart:async';

import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_provider.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/terminal_connection.dart';
import 'package:crisp_cloud/services/terminal_menu.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/terminal_tabs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  late ProviderContainer container;
  late List<_Fixture> fixtures;

  setUp(() {
    fixtures = [];
    container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
      ],
    );
    container.read(showTerminalProvider.notifier).state = true;
    container.read(terminalHeightProvider.notifier).state = 480;
  });

  tearDown(() async {
    for (final fixture in fixtures) {
      if (fixture.session.disposals == 0) fixture.session.dispose();
    }
    container.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  _Fixture makeFixture() {
    final fixture = _Fixture('session-${fixtures.length + 1}@example');
    fixtures.add(fixture);
    return fixture;
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final first = makeFixture();
    await first.connect();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final visible = ref.watch(showTerminalProvider);
                return Visibility(
                  visible: visible,
                  maintainState: true,
                  child: TerminalTabs(
                    session: first.session,
                    visible: visible,
                    sessionFactory: () {
                      final fixture = makeFixture();
                      unawaited(fixture.connect());
                      return fixture.session;
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  TerminalView view(WidgetTester tester, int index) => tester
      .widgetList<TerminalView>(find.byType(TerminalView, skipOffstage: false))
      .singleWhere(
        (widget) =>
            identical(widget.terminal, fixtures[index].session.terminal),
      );

  Finder viewFinder(int index) => find.byWidgetPredicate(
    (widget) =>
        widget is TerminalView &&
        identical(widget.terminal, fixtures[index].session.terminal),
  );

  Future<void> newTab(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('terminal-new-tab')));
    await tester.pump();
    await tester.pump();
  }

  Future<void> activate(WidgetTester tester, int id) async {
    final tab = find.byKey(ValueKey('terminal-tab-$id'));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    // The tab distinguishes a single click from double-click rename.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  Future<void> layout(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('terminal-layout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> closeTab(WidgetTester tester, int id) async {
    final close = find.byKey(ValueKey('terminal-close-tab-$id'));
    await tester.ensureVisible(close);
    await tester.tap(close);
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('tabs retain independent buffers, views and input ownership', (
    tester,
  ) async {
    await mount(tester);
    final original = tester.state<TerminalViewState>(viewFinder(0));
    fixtures[0].connection.outputController.add('first output\r\n');
    await tester.pump();
    await newTab(tester);
    expect(fixtures, hasLength(2));
    expect(fixtures.every((fixture) => fixture.session.isConnected), isTrue);
    fixtures[1].connection.outputController.add('second output\r\n');
    fixtures[0].connection.outputController.add('first while hidden\r\n');
    await tester.pump();
    expect(view(tester, 1).focusNode!.hasFocus, isTrue);
    expect(view(tester, 0).focusNode!.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
    await tester.pump();
    expect(fixtures[0].connection.input, isEmpty);
    expect(fixtures[1].connection.input.join(), 'b');
    await activate(tester, 1);
    expect(tester.state<TerminalViewState>(viewFinder(0)), same(original));
    expect(view(tester, 0).focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.pump();
    expect(fixtures[0].connection.input.join(), 'a');
    expect(fixtures[1].connection.input.join(), 'b');
    expect(
      fixtures[0].session.terminal.buffer.getText(),
      contains('first while hidden'),
    );
    expect(
      fixtures[0].session.terminal.buffer.getText(),
      isNot(contains('second output')),
    );
    expect(
      fixtures[1].session.terminal.buffer.getText(),
      contains('second output'),
    );
    expect(fixtures.every((fixture) => fixture.connection.closes == 0), isTrue);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('split panes are visible and only the clicked pane owns focus', (
    tester,
  ) async {
    await mount(tester);
    await layout(tester, 'Split side by side');
    expect(find.byType(TerminalView), findsNWidgets(2));
    expect(fixtures, hasLength(2));
    expect(
      tester.getRect(viewFinder(0)).right,
      lessThan(tester.getRect(viewFinder(1)).left),
    );
    expect(view(tester, 1).focusNode!.hasFocus, isTrue);
    await tester.tap(viewFinder(0));
    await tester.pump();
    await tester.pump();
    expect(view(tester, 0).focusNode!.hasFocus, isTrue);
    expect(view(tester, 1).focusNode!.hasFocus, isFalse);
    expect(container.read(terminalInputFocusedProvider), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.pump();
    fixtures[1].connection.outputController.add('background\r\n');
    await tester.pump();
    expect(view(tester, 0).focusNode!.hasFocus, isTrue);
    expect(container.read(terminalInputFocusedProvider), isTrue);
    expect(fixtures[0].connection.input.join(), 'a');
    expect(fixtures[1].connection.input, isEmpty);
    await layout(tester, 'Split top and bottom');
    expect(
      fixtures,
      hasLength(2),
      reason: 'Changing split direction reuses both sessions',
    );
    expect(find.byType(TerminalView), findsNWidgets(2));
    expect(
      tester.getRect(viewFinder(0)).bottom,
      lessThan(tester.getRect(viewFinder(1)).top),
    );
    expect(view(tester, 0).focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
    'clicking current or another tab reclaims typing from a file pane',
    (tester) async {
      await mount(tester);
      container.read(focusAreaProvider.notifier).state = FocusArea.local;
      await tester.pump();
      expect(view(tester, 0).focusNode!.hasFocus, isFalse);
      await activate(tester, 1);
      expect(container.read(focusAreaProvider), FocusArea.terminal);
      expect(view(tester, 0).focusNode!.hasFocus, isTrue);
      await newTab(tester);
      container.read(focusAreaProvider.notifier).state = FocusArea.remote;
      await tester.pump();
      await activate(tester, 1);
      expect(container.read(focusAreaProvider), FocusArea.terminal);
      expect(view(tester, 0).focusNode!.hasFocus, isTrue);
      expect(view(tester, 1).focusNode!.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.pump();
      expect(fixtures[0].connection.input.join(), 'a');
      expect(fixtures[1].connection.input, isEmpty);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'mobile control keys activate their pane before subsequent typing',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await mount(tester);
      await layout(tester, 'Split side by side');
      expect(view(tester, 1).focusNode!.hasFocus, isTrue);
      final control = find.descendant(
        of: find.byKey(const ValueKey('terminal-pane-1')),
        matching: find.text('Ctrl+A'),
      );
      await tester.tap(control);
      await tester.pump();
      await tester.pump();
      expect(view(tester, 0).focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
      await tester.pump();
      expect(fixtures[0].connection.input.join(), '\x01b');
      expect(fixtures[1].connection.input, isEmpty);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
    skip: kIsWeb,
  );

  testWidgets(
    'narrow and short layouts collapse and restore splits without losing sessions',
    (tester) async {
      await mount(tester);
      await layout(tester, 'Split side by side');
      tester.view.physicalSize = const Size(400, 900);
      await tester.pump();
      await tester.pump();
      expect(find.byType(TerminalView), findsOneWidget);
      expect(view(tester, 1).focusNode!.hasFocus, isTrue);
      fixtures[0].connection.outputController.add('narrow background\r\n');
      await tester.pump();
      tester.view.physicalSize = const Size(1000, 900);
      await tester.pump();
      expect(find.byType(TerminalView), findsNWidgets(2));
      await layout(tester, 'Split top and bottom');
      tester.view.physicalSize = const Size(1000, 420);
      await tester.pump();
      await tester.pump();
      expect(find.byType(TerminalView), findsOneWidget);
      tester.view.physicalSize = const Size(1000, 900);
      await tester.pump();
      expect(find.byType(TerminalView), findsNWidgets(2));
      expect(
        fixtures[0].session.terminal.buffer.getText(),
        contains('narrow background'),
      );
      expect(
        fixtures.every(
          (fixture) =>
              fixture.session.isConnected && fixture.connection.closes == 0,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'a delayed clipboard read cannot paste into a pane that lost focus',
    (tester) async {
      final clipboard = Completer<Map<String, String>>();
      var reads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            reads++;
            return clipboard.future;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await mount(tester);
      await layout(tester, 'Split side by side');
      await _chord(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyV);
      expect(reads, 1);
      await tester.tap(viewFinder(0));
      await tester.pump();
      await tester.pump();
      expect(view(tester, 0).focusNode!.hasFocus, isTrue);
      clipboard.complete({'text': 'late secret clipboard content'});
      await tester.pump();
      await tester.pump();
      expect(fixtures[0].connection.input, isEmpty);
      expect(fixtures[1].connection.input, isEmpty);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'hide and reopen preserve all sessions and release keyboard and menu ownership',
    (tester) async {
      await mount(tester);
      await newTab(tester);
      container.read(showTerminalProvider.notifier).state = false;
      await tester.pump();
      await tester.pump();
      expect(find.byType(TerminalView), findsNothing);
      expect(view(tester, 0).focusNode!.hasFocus, isFalse);
      expect(view(tester, 1).focusNode!.hasFocus, isFalse);
      expect(container.read(terminalInputFocusedProvider), isFalse);
      expect(container.read(terminalMenuProvider), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
      fixtures[0].connection.outputController.add('hidden first\r\n');
      fixtures[1].connection.outputController.add('hidden second\r\n');
      await tester.pump();
      expect(
        fixtures.every((fixture) => fixture.connection.input.isEmpty),
        isTrue,
      );
      container.read(showTerminalProvider.notifier).state = true;
      container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
      await tester.pump();
      await tester.pump();
      expect(view(tester, 1).focusNode!.hasFocus, isTrue);
      expect(view(tester, 0).focusNode!.hasFocus, isFalse);
      expect(
        fixtures[0].session.terminal.buffer.getText(),
        contains('hidden first'),
      );
      expect(
        fixtures[1].session.terminal.buffer.getText(),
        contains('hidden second'),
      );
      expect(
        fixtures.every((fixture) => fixture.connection.closes == 0),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'cancel keeps a live tab, confirm closes only that owned session',
    (tester) async {
      await mount(tester);
      await newTab(tester);
      await closeTab(tester, 2);
      expect(find.text('Close terminal?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixtures[1].connection.closes, 0);
      expect(find.byKey(const ValueKey('terminal-tab-2')), findsOneWidget);
      await closeTab(tester, 2);
      await tester.tap(find.widgetWithText(FilledButton, 'Close terminal'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('terminal-tab-2')), findsNothing);
      expect(fixtures[1].connection.closes, 1);
      expect(fixtures[1].session.disposals, 1);
      expect(fixtures[0].connection.closes, 0);
      expect(fixtures[0].session.disposals, 0);
      expect(fixtures[0].session.isConnected, isTrue);
      expect(view(tester, 0).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('failed close keeps the tab available for a cleanup retry', (
    tester,
  ) async {
    await mount(tester);
    await newTab(tester);
    fixtures[1].connection.failures = 1;
    await closeTab(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, 'Close terminal'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('terminal-tab-2')), findsOneWidget);
    expect(fixtures[1].session.canDisconnect, isTrue);
    expect(fixtures[1].session.disposals, 0);
    expect(fixtures[0].connection.closes, 0);
    await closeTab(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, 'Close terminal'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('terminal-tab-2')), findsNothing);
    expect(fixtures[1].connection.closes, 2);
    expect(fixtures[1].session.disposals, 1);
    expect(fixtures[0].session.isConnected, isTrue);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
    'the final tab stays available and the tab limit blocks additional sessions',
    (tester) async {
      await mount(tester);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('terminal-close-tab-1')),
            )
            .onPressed,
        isNull,
      );
      for (var i = 1; i < TerminalTabs.maxTabs; i++) {
        await newTab(tester);
      }
      expect(fixtures, hasLength(TerminalTabs.maxTabs));
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('terminal-new-tab')))
            .onPressed,
        isNull,
      );
      await _chord(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyT);
      expect(fixtures, hasLength(TerminalTabs.maxTabs));
      await tester.tap(find.byKey(const ValueKey('terminal-layout')));
      await tester.pumpAndSettle();
      for (final label in ['Split side by side', 'Split top and bottom']) {
        expect(
          tester
              .widget<PopupMenuItem<String>>(
                find.widgetWithText(PopupMenuItem<String>, label),
              )
              .enabled,
          isFalse,
        );
      }
      expect(
        fixtures.every((fixture) => fixture.connection.input.isEmpty),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'workspace shortcuts add, cycle and close without sending control input',
    (tester) async {
      await mount(tester);
      await _chord(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyT);
      expect(fixtures, hasLength(2));
      expect(view(tester, 1).focusNode!.hasFocus, isTrue);
      await _chord(tester, [
        LogicalKeyboardKey.controlLeft,
      ], LogicalKeyboardKey.tab);
      expect(view(tester, 0).focusNode!.hasFocus, isTrue);
      await _chord(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.tab);
      expect(view(tester, 1).focusNode!.hasFocus, isTrue);
      await _chord(tester, [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftLeft,
      ], LogicalKeyboardKey.keyW);
      await tester.pumpAndSettle();
      expect(find.text('Close terminal?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fixtures, hasLength(2));
      expect(
        fixtures.every(
          (fixture) =>
              fixture.connection.input.isEmpty &&
              fixture.connection.closes == 0,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('macOS command shortcuts also stay inside the workspace', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await mount(tester);
    await _chord(tester, [
      LogicalKeyboardKey.metaLeft,
    ], LogicalKeyboardKey.keyT);
    expect(fixtures, hasLength(2));
    await _chord(tester, [
      LogicalKeyboardKey.metaLeft,
    ], LogicalKeyboardKey.keyW);
    await tester.pumpAndSettle();
    expect(find.text('Close terminal?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      fixtures.every((fixture) => fixture.connection.input.isEmpty),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('renaming a tab preserves its connection and other tab labels', (
    tester,
  ) async {
    await mount(tester);
    await newTab(tester);
    await layout(tester, 'Rename terminal');
    await tester.enterText(
      find.byKey(const ValueKey('terminal-tab-name')),
      'Build machine',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('terminal-tab-2')),
        matching: find.text('Build machine'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('terminal-tab-1')),
        matching: find.text('session-1@example'),
      ),
      findsOneWidget,
    );
    expect(fixtures[1].session.label, 'session-2@example');
    expect(
      fixtures.every(
        (fixture) =>
            fixture.connection.closes == 0 && fixture.connection.input.isEmpty,
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
    'unmount disposes owned sessions but leaves the injected session caller-owned',
    (tester) async {
      await mount(tester);
      await newTab(tester);
      await newTab(tester);
      await unmount(tester);
      expect(fixtures[0].session.disposals, 0);
      expect(fixtures[0].connection.closes, 0);
      expect(fixtures[0].session.isConnected, isTrue);
      for (final fixture in fixtures.skip(1)) {
        expect(fixture.session.disposals, 1);
        expect(fixture.connection.closes, 1);
      }
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _chord(
  WidgetTester tester,
  List<LogicalKeyboardKey> modifiers,
  LogicalKeyboardKey key,
) async {
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
  await tester.pump();
}

class _Fixture {
  _Fixture(this.label);
  final String label;
  final session = _TrackedSession();
  final connection = _Connection();

  Future<void> connect() => session.connect(
    (_, __) async => connection,
    kind: TerminalSessionKind.ssh,
    label: label,
  );
}

class _TrackedSession extends TerminalSession {
  int disposals = 0;
  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _Connection implements TerminalConnection {
  final outputController = StreamController<String>();
  final finished = Completer<int?>();
  final input = <String>[];
  int closes = 0;
  int failures = 0;

  @override
  bool get isSandbox => false;
  @override
  Stream<String> get output => outputController.stream;
  @override
  Future<int?> get exitCode => finished.future;
  @override
  Future<void> write(String data) async => input.add(data);
  @override
  Future<void> resize(int columns, int rows) async {}
  @override
  Future<void> close() async {
    closes++;
    if (failures > 0) {
      failures--;
      throw StateError('Fixture cleanup failed');
    }
    if (!finished.isCompleted) finished.complete(0);
    if (!outputController.isClosed) unawaited(outputController.close());
  }
}
