import 'dart:async';

import 'package:crisp_cloud/models/terminal_key_binding.dart';
import 'package:crisp_cloud/models/terminal_trigger.dart';
import 'package:crisp_cloud/providers/focus_area_provider.dart';
import 'package:crisp_cloud/providers/terminal_key_bindings_provider.dart';
import 'package:crisp_cloud/providers/terminal_provider.dart';
import 'package:crisp_cloud/providers/terminal_triggers_provider.dart';
import 'package:crisp_cloud/services/terminal_session.dart';
import 'package:crisp_cloud/widgets/tmux_control_workspace.dart';
import 'package:crisp_cloud/services/tmux_control_client.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm2/xterm.dart';

import 'support/tmux_control_workspace_fixture.dart';

void main() {
  late TmuxWorkspaceFixture client;
  late ProviderContainer container;
  late List<TerminalKeyBinding> bindings;
  late List<TerminalTrigger> triggers;
  late List<bool> focusChanges;
  late List<LogicalKeyboardKey> escapedKeys;
  late bool visible;
  late bool active;
  late void Function(VoidCallback) rebuild;
  late int detached;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    bindings = [];
    triggers = [];
    focusChanges = [];
    escapedKeys = [];
    visible = true;
    active = true;
    detached = 0;
    client = TmuxWorkspaceFixture();
    container = ProviderContainer(
      overrides: [
        terminalKeyBindingListProvider.overrideWith((ref) async => bindings),
        terminalTriggerListProvider.overrideWith((ref) async => triggers),
      ],
    );
    container.read(focusAreaProvider.notifier).state = FocusArea.terminal;
    container.read(showTerminalProvider.notifier).state = true;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    client.dispose();
    container.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1000, 600),
    VoidCallback? onDetach,
  }) async {
    await client.initialize();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await container.read(terminalKeyBindingListProvider.future);
    await container.read(terminalTriggerListProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Focus(
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent) {
                      escapedKeys.add(event.logicalKey);
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TmuxControlWorkspace(
                    client: client,
                    visible: visible,
                    active: active,
                    onActivate: () => setState(() => active = true),
                    onDetach: onDetach,
                    onPaneFocusChanged: focusChanges.add,
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

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets(
    'native windows keep independent pane grids and route keyboard to selected pane',
    (tester) async {
      await mount(tester);
      expect(find.byKey(const ValueKey('tmux-pane-%1')), findsOneWidget);
      expect(find.byKey(const ValueKey('tmux-pane-%2')), findsOneWidget);
      expect(find.byKey(const ValueKey('tmux-pane-%3')), findsNothing);
      expect(
        tester
            .widgetList<TerminalView>(find.byType(TerminalView))
            .every((view) => !view.autoResize),
        isTrue,
      );
      expect(client.panes['%1']!.session.terminal.viewWidth, 40);
      expect(client.panes['%2']!.session.terminal.viewWidth, 39);
      final first = tester.getRect(find.byKey(const ValueKey('tmux-pane-%1')));
      final second = tester.getRect(find.byKey(const ValueKey('tmux-pane-%2')));
      expect(second.left, greaterThan(first.right));
      await tester.tap(find.byKey(const ValueKey('tmux-activate-%2')));
      await tester.pump();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(client.commands, ['pane %2']);
      expect(client.connections['%1']!.input, isEmpty);
      expect(client.connections['%2']!.input, ['\r']);
      expect(escapedKeys, isEmpty);

      await tester.tap(find.byKey(const ValueKey('tmux-window-@2')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('tmux-pane-%3')), findsOneWidget);
      expect(find.byKey(const ValueKey('tmux-pane-%1')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(client.connections['%3']!.input, ['\r']);
      expect(client.connections['%1']!.closed, isFalse);
      expect(client.connections['%2']!.closed, isFalse);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'remote creation and split controls use active target; local zoom preserves remote layout',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('tmux-action-newWindow')));
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('tmux-action-splitHorizontal')),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tmux-action-splitVertical')));
      await tester.pump();
      await tester.pump();
      expect(client.commands, [
        'new window',
        'split %1 true',
        'split %1 false',
      ]);
      await tester.tap(find.byKey(const ValueKey('tmux-action-zoom')));
      await tester.pump();
      expect(find.byType(TerminalView), findsOneWidget);
      expect(client.windows.first.paneIds, ['%1', '%2']);
      await tester.tap(find.byKey(const ValueKey('tmux-action-zoom')));
      await tester.pump();
      expect(find.byType(TerminalView), findsNWidgets(2));
      expect(client.commands, [
        'new window',
        'split %1 true',
        'split %1 false',
      ]);
      await finish(tester);
    },
  );

  testWidgets(
    '320 by 320 shows active pane and native pane selector without overflow',
    (tester) async {
      await mount(tester, size: const Size(320, 320));
      expect(tester.takeException(), isNull);
      expect(find.byType(TerminalView), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tmux-pane-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<String> && widget.value == '%2',
        ),
      );
      await tester.pumpAndSettle();
      expect(client.activePaneId, '%2');
      expect(find.byKey(const ValueKey('tmux-pane-%2')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('tmux-action-find')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('terminal-search-query')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('terminal-search-query')),
        'ready',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('1/1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'hidden workspace revokes keyboard and does not reclaim focus after server events',
    (tester) async {
      await mount(tester);
      expect(focusChanges, contains(true));
      rebuild(() => visible = false);
      await tester.pump();
      client.selectFromRemote('%2');
      await tester.pump();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        client.connections.values.every(
          (connection) => connection.input.isEmpty,
        ),
        isTrue,
      );
      expect(focusChanges.last, false);
      expect(
        tester
            .widgetList<TerminalView>(find.byType(TerminalView))
            .every((view) => !view.focusNode!.hasFocus),
        isTrue,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'narrow outer split keeps pane selection and overflow actions available',
    (tester) async {
      await mount(tester, size: const Size(160, 240));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('tmux-pane-selector')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tmux-action-splitHorizontal')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('tmux-actions')));
      await tester.pumpAndSettle();
      expect(find.text('Split side by side'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('remote zoom retains hidden panes in the native selector', (
    tester,
  ) async {
    await mount(tester);
    client.windows[0] = const TmuxControlWindow(
      id: '@1',
      index: 0,
      name: 'shell',
      width: 80,
      height: 24,
      paneIds: ['%1'],
      activePaneId: '%1',
      zoomed: true,
    );
    client.notifyListeners();
    await tester.pump();
    expect(find.byType(TerminalView), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tmux-pane-selector')));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == '%2',
      ),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets(
    'clipboard read is revoked on pane switch, while explicit current paste keeps bracketed mode',
    (tester) async {
      final clipboard = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return clipboard.future;
            return null;
          });
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('tmux-action-paste')));
      await tester.pump();
      client.selectFromRemote('%2');
      await tester.pump();
      clipboard.complete({'text': 'should not reach either shell\n'});
      await tester.pump();
      await tester.pump();
      expect(
        client.connections.values.every(
          (connection) => connection.input.isEmpty,
        ),
        isTrue,
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': 'echo café🙂\n'};
            }
            return null;
          });
      client.panes['%2']!.session.terminal.write('\x1b[?2004h');
      await tester.tap(find.byKey(const ValueKey('tmux-action-paste')));
      await tester.pump();
      await tester.pump();
      expect(client.connections['%2']!.input, [
        '\x1b[200~echo café🙂\n\x1b[201~',
      ]);
      expect(client.connections['%1']!.input, isEmpty);
      await finish(tester);
    },
  );

  testWidgets(
    'server pane selection does not take focus from the file browser',
    (tester) async {
      await mount(tester);
      container.read(focusAreaProvider.notifier).state = FocusArea.local;
      await tester.pump();
      client.selectFromRemote('%2');
      await tester.pump();
      await tester.pump();
      expect(
        tester
            .widgetList<TerminalView>(find.byType(TerminalView))
            .every((view) => !view.focusNode!.hasFocus),
        isTrue,
      );
      expect(focusChanges.last, false);
      await finish(tester);
    },
  );

  testWidgets(
    'mapped press executes once and repeat or release cannot leak after remote pane selection',
    (tester) async {
      bindings.add(
        TerminalKeyBinding(
          chord: TerminalKeyChord(
            keyId: LogicalKeyboardKey.keyK.keyId,
            ctrl: true,
            alt: true,
          ),
          action: TerminalKeyBindingAction.text,
          text: 'echo café🙂',
        ),
      );
      await mount(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      client.selectFromRemote('%2');
      await tester.pump();
      await tester.pump();
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(client.connections['%1']!.input, ['echo café🙂']);
      expect(client.connections['%2']!.input, isEmpty);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(client.connections['%2']!.input, ['\x03']);
      expect(escapedKeys, isEmpty);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'saved output triggers run for hidden remote windows and identify their pane',
    (tester) async {
      triggers.add(
        TerminalTrigger(
          id: 'ready',
          name: 'Build ready',
          pattern: 'compiled',
          cooldownSeconds: 0,
        ),
      );
      await mount(tester);
      client.connections['%3']!.controller.add('compiled successfully\r\n');
      await tester.pump();
      await tester.pump();
      expect(client.panes['%3']!.session.triggerNotificationSerial, 1);
      expect(
        client.panes['%3']!.session.triggerNotification?.line,
        'compiled successfully',
      );
      await tester.pump();
      expect(
        find.text('%3 · Build ready · compiled successfully'),
        findsOneWidget,
      );
      expect(
        client.connections.values.every(
          (connection) => connection.input.isEmpty,
        ),
        isTrue,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'oversized paste exposes active pane failure and keeps its buffer readable',
    (tester) async {
      client.dispose();
      client = TmuxWorkspaceFixture(maximumPendingInputCodeUnits: 16384);
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': 'x' * 16385};
            }
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      await mount(tester, size: const Size(320, 320));
      await tester.tap(find.byKey(const ValueKey('tmux-action-paste')));
      await tester.pump();
      await tester.pump();
      final session = client.panes['%1']!.session;
      expect(session.status, TerminalSessionStatus.failed);
      expect(session.error, isNotNull);
      expect(client.connections['%1']!.input, isEmpty);
      expect(find.text('Pane failed. Reconnect to continue.'), findsOneWidget);
      expect(find.byKey(const ValueKey('tmux-error')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('tmux-action-paste')))
            .onPressed,
        isNull,
      );
      final terminalFinder = find.byType(TerminalView);
      final view = tester.widget<TerminalView>(terminalFinder);
      expect(view.readOnly, isTrue);
      expect(view.focusNode!.hasFocus, isFalse);
      final render = tester
          .state<TerminalViewState>(terminalFinder)
          .renderTerminal;
      final start =
          tester.getTopLeft(terminalFinder) +
          Offset(render.cellSize.width / 2, render.lineHeight / 2);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(Offset(render.cellSize.width * 12, 0));
      await gesture.up();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tmux-action-copy')));
      await tester.pump();
      expect(copied, contains('%1 ready'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(client.connections['%1']!.input, isEmpty);

      client.selectFromRemote('%2');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('tmux-error')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(client.connections['%2']!.input, ['\r']);
      client.selectFromRemote('%1');
      await tester.pump();
      expect(find.text('Pane failed. Reconnect to continue.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'closed buffers allow local scrolling selection copying and window navigation without input',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      await mount(tester);
      final terminal = client.panes['%1']!.session.terminal;
      terminal.write(
        [for (var line = 0; line < 160; line++) 'retained line $line\r\n']
            .join(),
      );
      // Leave the remote mouse mode set at disconnect. The read-only view must
      // route wheel gestures to local history, not emit mouse reports.
      terminal.write('\x1b[?1000h\x1b[?1006h');
      await tester.pump();
      // Keep the fixture pane connections alive to prove that UI input is
      // revoked immediately, before asynchronous pane teardown completes.
      client.isClosed = true;
      client.ready = false;
      client.notifyListeners();
      await tester.pump();
      await tester.pump();
      final paneFinder = find.byKey(const ValueKey('tmux-pane-%1'));
      final terminalFinder = find.descendant(
        of: paneFinder,
        matching: find.byType(TerminalView),
      );
      final view = tester.widget<TerminalView>(terminalFinder);
      expect(view.readOnly, isTrue);
      expect(view.focusNode!.hasFocus, isFalse);
      final scroll = view.scrollController!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      scroll.jumpTo(scroll.position.maxScrollExtent);
      final previousOffset = scroll.offset;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(terminalFinder),
          scrollDelta: const Offset(0, -120),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      expect(scroll.offset, lessThan(previousOffset));

      scroll.jumpTo(0);
      await tester.pump();
      final render = tester
          .state<TerminalViewState>(terminalFinder)
          .renderTerminal;
      final start =
          tester.getTopLeft(terminalFinder) +
          Offset(render.cellSize.width / 2, render.lineHeight * 1.5);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(Offset(render.cellSize.width * 16, 0));
      await gesture.up();
      await tester.pump();
      final selection = view.controller!.selectionFor(terminal.buffer);
      expect(selection, isNotNull);
      final selectedText = terminal.buffer.getText(selection!, true);
      expect(selectedText, contains('retained line'));
      await tester.tap(find.byKey(const ValueKey('tmux-action-copy')));
      await tester.pump();
      expect(copied, selectedText);

      await tester.tap(find.byKey(const ValueKey('tmux-activate-%2')));
      await tester.pump();
      expect(find.text('Pane %2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tmux-window-@2')));
      await tester.pump();
      expect(find.byKey(const ValueKey('tmux-pane-%3')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tmux-window-@1')));
      await tester.pump();
      expect(find.text('Pane %2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tmux-pane-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<String> && widget.value == '%1',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pane %1'), findsOneWidget);
      expect(client.activePaneId, '%1');
      expect(client.activeWindowId, '@1');
      expect(client.commands, isEmpty);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('tmux-action-paste')))
            .onPressed,
        isNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        client.connections.values.every(
          (connection) => connection.input.isEmpty,
        ),
        isTrue,
      );
      expect(focusChanges.last, false);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'detach delegates to owner without closing or killing individual panes',
    (tester) async {
      await mount(tester, onDetach: () => detached++);
      await tester.tap(find.byKey(const ValueKey('tmux-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detach from tmux'));
      await tester.pumpAndSettle();
      expect(detached, 1);
      expect(client.commands, isEmpty);
      expect(
        client.connections.values.every((connection) => !connection.closed),
        isTrue,
      );
      await finish(tester);
    },
  );
}
