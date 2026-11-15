import 'package:crisp_cloud/services/terminal_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

void main() {
  late Terminal terminal;
  late TerminalController controller;
  late TerminalScrollbackSearch search;
  late List<String> input;
  late int reveals;

  setUp(() {
    input = [];
    reveals = 0;
    terminal = Terminal(maxLines: 3000, onOutput: input.add)..resize(80, 8);
    controller = TerminalController();
    search = TerminalScrollbackSearch(
      terminal: terminal,
      controller: controller,
      onReveal: () => reveals++,
    );
  });

  tearDown(() {
    search.dispose();
    controller.dispose();
    terminal.dispose();
  });

  testWidgets('matches wrapped text with wide and combining Unicode cells', (
    tester,
  ) async {
    terminal.resize(8, 4);
    terminal.write('xx中🙂e\u0301abcTAIL');
    search.setQuery('🙂e\u0301abcT');
    await tester.pump(const Duration(milliseconds: 160));

    expect(search.matchCount, 1);
    expect(search.currentRange!.begin, const CellOffset(4, 0));
    expect(search.currentRange!.end.y, 1);
    expect(
      terminal.buffer.getText(search.currentRange!, true),
      '🙂e\u0301abcT',
    );
    expect(input, isEmpty);
  });

  testWidgets('treats regex syntax as literal text', (tester) async {
    terminal.write('a.*b axxxb [test]');
    search.setQuery('a.*b');
    await tester.pump(const Duration(milliseconds: 160));
    expect(search.matchCount, 1);
    expect(terminal.buffer.getText(search.currentRange!, true), 'a.*b');

    search.setQuery('[');
    await tester.pump(const Duration(milliseconds: 160));
    expect(search.matchCount, 1);
    expect(terminal.buffer.getText(search.currentRange!, true), '[');
  });

  testWidgets('case and whole-word options respect Unicode word boundaries', (
    tester,
  ) async {
    terminal.write('Log logger LOG xlog Logé log');
    search.setQuery('log');
    search.refresh();
    expect(search.matchCount, 6);

    search.setWholeWord(true);
    search.refresh();
    expect(search.matchCount, 3);

    search.setCaseSensitive(true);
    search.refresh();
    expect(search.matchCount, 1);
    expect(terminal.buffer.getText(search.currentRange!, true), 'log');
  });

  testWidgets('bounds highlights and distinguishes a truncated match count', (
    tester,
  ) async {
    terminal.write(List.filled(1100, 'hit\r\n').join());
    search.setQuery('hit');
    search.refresh();
    expect(search.matchCount, TerminalScrollbackSearch.maximumMatches);
    expect(controller.searchHighlights, hasLength(1000));
    expect(search.truncated, isTrue);
    search.setQuery('no hit exists');
    search.refresh();
    expect(search.matchCount, 0);
    expect(search.truncated, isFalse);
  });

  testWidgets('navigation wraps without sending input to the shell', (
    tester,
  ) async {
    terminal.write('hit one hit two hit');
    search.setQuery('hit');
    search.refresh();
    expect(search.currentIndex, 0);
    search.previous();
    expect(search.currentIndex, 2);
    search.next();
    expect(search.currentIndex, 0);
    search.next();
    expect(search.currentIndex, 1);
    expect(controller.currentSearchHighlight, 1);
    expect(input, isEmpty);
    expect(reveals, 4);
  });

  testWidgets('navigation rescans a newly activated alternate screen', (
    tester,
  ) async {
    terminal.write('target old');
    search.setQuery('target');
    search.refresh();
    final mainBuffer = terminal.buffer;
    expect(search.matchCount, 1);

    terminal.write('\x1b[?1049h\x1b[2J\x1b[Htarget new target');
    expect(search.pending, isTrue);
    expect(search.currentRange, isNull);
    search.next();
    expect(search.pending, isFalse);
    expect(search.matchCount, 2);
    expect(search.currentIndex, 0);
    for (final highlight in controller.searchHighlights) {
      expect(highlight.rangeFor(mainBuffer), isNull);
      expect(highlight.rangeFor(terminal.buffer), isNotNull);
    }

    terminal.write('\x1b[?1049l');
    search.previous();
    expect(search.matchCount, 1);
    expect(identical(terminal.buffer, mainBuffer), isTrue);
    expect(terminal.buffer.getText(search.currentRange!, true), 'target');
  });

  testWidgets(
    'overwritten text invalidates coordinates before delayed refresh',
    (tester) async {
      terminal.write('target');
      search.setQuery('target');
      search.refresh();
      terminal.write('\r\x1b[2Knone');
      expect(search.currentRange, isNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.searchHighlights, isEmpty);
      await tester.pump(const Duration(milliseconds: 160));
      expect(search.matchCount, 0);
      expect(search.currentIndex, -1);
      expect(search.pending, isFalse);
    },
  );

  testWidgets(
    'continuous output does not starve refresh or move the viewport',
    (tester) async {
      search.setQuery('hit');
      search.refresh();
      expect(reveals, 0);
      for (var i = 0; i < 5; i++) {
        terminal.write('hit $i\r\n');
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(search.matchCount, greaterThanOrEqualTo(4));
      expect(reveals, 0);
      await tester.pump(const Duration(milliseconds: 160));
      expect(search.matchCount, 5);
      expect(search.pending, isFalse);
      expect(reveals, 0);
    },
  );

  testWidgets('resize refreshes reflowed ranges', (tester) async {
    terminal.resize(20, 4);
    terminal.write('start needle end');
    search.setQuery('needle');
    search.refresh();
    terminal.resize(6, 4);
    search.refresh();
    expect(search.matchCount, 1);
    expect(terminal.buffer.getText(search.currentRange!, true), 'needle');
  });

  testWidgets(
    'hidden search pauses output scans and refreshes when activated',
    (tester) async {
      terminal.write('hit');
      search.setQuery('hit');
      search.refresh();
      search.setActive(false);
      terminal.write(' hit');
      await tester.pump(const Duration(seconds: 1));
      expect(search.matchCount, 1);
      expect(controller.searchHighlights, isEmpty);
      expect(search.currentRange, isNull);
      search.setActive(true);
      await tester.pump(const Duration(milliseconds: 160));
      expect(search.matchCount, 2);
      expect(controller.searchHighlights, hasLength(2));
    },
  );

  testWidgets('current hit follows scrollback eviction before a rescan', (
    tester,
  ) async {
    final bounded = Terminal(maxLines: 20)..resize(12, 4);
    final boundedController = TerminalController();
    final boundedSearch = TerminalScrollbackSearch(
      terminal: bounded,
      controller: boundedController,
    );
    addTearDown(() {
      boundedSearch.dispose();
      boundedController.dispose();
      bounded.dispose();
    });
    bounded.write(List.generate(18, (i) => 'hit $i\r\n').join());
    boundedSearch.setQuery('hit');
    boundedSearch.refresh();
    for (var i = 0; i < 10; i++) {
      boundedSearch.next();
    }
    final selectedLine =
        bounded.buffer.lines[boundedSearch.currentRange!.begin.y];
    for (var i = 18; i < 24; i++) {
      bounded.write('hit $i\r\n');
    }
    boundedSearch.refresh();
    expect(
      bounded.buffer.lines[boundedSearch.currentRange!.begin.y],
      same(selectedLine),
    );
    expect(bounded.buffer.getText(boundedSearch.currentRange!, true), 'hit');
  });

  testWidgets('clearing or disposing cancels delayed searches and highlights', (
    tester,
  ) async {
    terminal.write('hit');
    search.setQuery('hit');
    search.setQuery('');
    await tester.pump(const Duration(milliseconds: 200));
    expect(search.matchCount, 0);
    expect(controller.searchHighlights, isEmpty);

    search.setQuery('hit');
    search.refresh();
    terminal.write(' hit');
    search.dispose();
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.searchHighlights, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
