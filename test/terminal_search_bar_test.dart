import 'package:crisp_cloud/widgets/terminal_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  late Terminal terminal;
  late TerminalController controller;
  late ScrollController scroll;
  late GlobalKey<TerminalViewState> view;
  late int closed;
  late List<LogicalKeyboardKey> bubbled;

  setUp(() {
    terminal = Terminal(maxLines: 3000)..resize(80, 8);
    controller = TerminalController();
    scroll = ScrollController();
    view = GlobalKey<TerminalViewState>();
    closed = 0;
    bubbled = [];
  });

  tearDown(() {
    controller.dispose();
    terminal.dispose();
    scroll.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    double width = 640,
    bool active = true,
    int focusRequest = 0,
    KeyEventResult Function(KeyEvent)? onWorkspaceKey,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent) bubbled.add(event.logicalKey);
              return KeyEventResult.ignored;
            },
            child: SizedBox(
              width: width,
              height: 300,
              child: Column(
                children: [
                  TerminalSearchBar(
                    terminal: terminal,
                    controller: controller,
                    scrollController: scroll,
                    lineHeight: () =>
                        view.currentState!.renderTerminal.lineHeight,
                    onClose: () => closed++,
                    active: active,
                    focusRequest: focusRequest,
                    onWorkspaceKey: onWorkspaceKey,
                  ),
                  Expanded(
                    child: TerminalView(
                      terminal,
                      key: view,
                      controller: controller,
                      scrollController: scroll,
                      readOnly: true,
                      autofocus: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> findText(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey('terminal-search-query')),
      text,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  testWidgets('find navigates scrollback and keyboard stays inside search', (
    tester,
  ) async {
    terminal.write('needle first\r\n');
    terminal.write(List.generate(60, (i) => 'line $i\r\n').join());
    terminal.write('needle last');
    await mount(tester);
    await findText(tester, 'needle');
    expect(find.text('1/2'), findsOneWidget);
    expect(controller.searchHighlights, hasLength(2));
    expect(scroll.offset, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('2/2'), findsOneWidget);
    expect(scroll.offset, greaterThan(0));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('1/2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, 1);
    expect(bubbled, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('small pane exposes options without overflowing', (tester) async {
    terminal.write('Hit hit hits');
    await mount(tester, width: 240);
    await findText(tester, 'hit');
    expect(find.text('1/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('terminal-search-options')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Match case'),
        matching: find.byWidgetPredicate((widget) => widget is PopupMenuEntry),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('terminal-search-options')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Whole words'),
        matching: find.byWidgetPredicate((widget) => widget is PopupMenuEntry),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('replacement terminal cancels stale search and reuses query', (
    tester,
  ) async {
    terminal.write('hit old');
    await mount(tester);
    await findText(tester, 'hit');
    final old = terminal;
    terminal = Terminal()..write('new hit hit');
    await mount(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('1/2'), findsOneWidget);
    for (final highlight in controller.searchHighlights) {
      expect(highlight.rangeFor(old.buffer), isNull);
    }
    old.write('hit stale');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('1/2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    old.dispose();
  });

  testWidgets('reactivating a retained search restores its input focus', (
    tester,
  ) async {
    terminal.write('hit');
    await mount(tester);
    await findText(tester, 'hit');
    await mount(tester, active: false);
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('terminal-search-query')),
    );
    expect(field.focusNode!.hasFocus, isFalse);
    terminal.write(' hit');
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.searchHighlights, isEmpty);
    await mount(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.text('1/2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('explicit focus request reclaims an already-active search', (
    tester,
  ) async {
    terminal.write('hit');
    await mount(tester);
    await findText(tester, 'hit');
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('terminal-search-query')),
    );
    field.focusNode!.unfocus();
    await tester.pump();
    expect(field.focusNode!.hasFocus, isFalse);
    await mount(tester, focusRequest: 1);
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, 'hit');
    expect(find.text('1/1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('workspace shortcut is forwarded without leaking other keys', (
    tester,
  ) async {
    var cycles = 0;
    await mount(
      tester,
      onWorkspaceKey: (event) {
        if (event.logicalKey == LogicalKeyboardKey.tab &&
            HardwareKeyboard.instance.isControlPressed) {
          if (event is KeyDownEvent) cycles++;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    await findText(tester, 'retained query');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump();
    expect(cycles, 1);
    expect(bubbled, isEmpty);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('terminal-search-query')),
    );
    expect(field.controller!.text, 'retained query');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
