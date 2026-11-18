import 'dart:convert';

import 'package:crisp_cloud/models/terminal_pane_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

TerminalPaneLayout _layout() => TerminalPaneSplit(
  axis: TerminalSplitAxis.horizontal,
  fraction: 0.6,
  first: TerminalPaneSplit(
    axis: TerminalSplitAxis.vertical,
    fraction: 0.3,
    first: TerminalPaneLeaf(10),
    second: TerminalPaneLeaf(20),
  ),
  second: TerminalPaneSplit(
    axis: TerminalSplitAxis.vertical,
    fraction: 0.7,
    first: TerminalPaneLeaf(30),
    second: TerminalPaneLeaf(40),
  ),
);

void main() {
  test('nested layout round-trips order, axes and independent dividers', () {
    final layout = _layout();
    final decoded = TerminalPaneLayout.fromJson(
      jsonDecode(jsonEncode(layout.toJson())),
    );
    expect(decoded, layout);
    expect(decoded.hashCode, layout.hashCode);
    expect(decoded.leafIds, [10, 20, 30, 40]);
    expect(decoded.splitAt('')!.fraction, 0.6);
    expect(decoded.splitAt('0')!.fraction, 0.3);
    expect(decoded.splitAt('1')!.fraction, 0.7);
    expect(decoded.splitAt('1')!.axis, TerminalSplitAxis.vertical);
    expect(decoded.splitAt('10'), isNull);
    expect(() => decoded.leafIds.add(50), throwsUnsupportedError);
  });

  test('repeated splits retain prior sessions and stop at eight panes', () {
    TerminalPaneLayout layout = TerminalPaneLeaf(1);
    for (var id = 2; id <= TerminalPaneLayout.maximumLeaves; id++) {
      layout = layout.splitLeaf(
        id - 1,
        id,
        id.isEven ? TerminalSplitAxis.horizontal : TerminalSplitAxis.vertical,
      );
    }
    expect(layout.leafIds, [1, 2, 3, 4, 5, 6, 7, 8]);
    final before = layout.toJson();
    expect(
      () => layout.splitLeaf(8, 9, TerminalSplitAxis.vertical),
      throwsFormatException,
    );
    expect(layout.toJson(), before);
    expect(
      () => layout.splitLeaf(4, 2, TerminalSplitAxis.horizontal),
      throwsFormatException,
    );
    expect(layout.splitLeaf(99, 100, TerminalSplitAxis.vertical), same(layout));
  });

  test('switching a hidden terminal replaces only the selected leaf', () {
    final layout = _layout();
    final changed = layout.replaceLeaf(20, 50);
    expect(changed.leafIds, [10, 50, 30, 40]);
    expect(changed.splitAt('')!.fraction, 0.6);
    expect(changed.splitAt('0')!.fraction, 0.3);
    expect(changed.splitAt('1'), layout.splitAt('1'));
    expect(layout.leafIds, [10, 20, 30, 40]);
    expect(layout.replaceLeaf(20, 20), same(layout));
    expect(layout.replaceLeaf(99, 100), same(layout));
    expect(() => layout.replaceLeaf(20, 10), throwsFormatException);
    expect(() => layout.replaceLeaf(20, -1), throwsFormatException);
  });

  test('closing a pane collapses parents without losing sibling topology', () {
    final layout = _layout();
    final firstRemoved = layout.removeLeaf(10)!;
    expect(firstRemoved.leafIds, [20, 30, 40]);
    expect(firstRemoved.splitAt('')!.fraction, 0.6);
    expect(firstRemoved.splitAt('0'), isNull);
    expect(firstRemoved.splitAt('1')!.fraction, 0.7);
    final leftRemoved = firstRemoved.removeLeaf(20)!;
    expect(leftRemoved.leafIds, [30, 40]);
    expect(leftRemoved.splitAt('')!.axis, TerminalSplitAxis.vertical);
    expect(leftRemoved.splitAt('')!.fraction, 0.7);
    final single = leftRemoved.removeLeaf(30)!;
    expect(single, TerminalPaneLeaf(40));
    expect(single.removeLeaf(40), isNull);
    expect(layout.removeLeaf(99), same(layout));
  });

  test(
    'divider movement targets its branch and balance preserves topology',
    () {
      final layout = _layout();
      final resized = layout.withSplitFraction('1', 0.4);
      expect(resized.splitAt('1')!.fraction, 0.4);
      expect(resized.splitAt('0'), same(layout.splitAt('0')));
      expect(resized.splitAt('')!.fraction, 0.6);
      expect(resized.leafIds, layout.leafIds);
      final balanced = resized.balance();
      for (final path in ['', '0', '1']) {
        expect(balanced.splitAt(path)!.fraction, 0.5);
        expect(balanced.splitAt(path)!.axis, layout.splitAt(path)!.axis);
      }
      expect(balanced.leafIds, layout.leafIds);
      expect(layout.withSplitFraction('10', 0.6), same(layout));
      for (final path in ['x', '02', '1/0', '0' * 8]) {
        expect(() => layout.splitAt(path), throwsFormatException);
        expect(
          () => layout.withSplitFraction(path, 0.6),
          throwsFormatException,
        );
      }
      for (final fraction in [double.nan, double.infinity, 0.19, 0.81]) {
        expect(
          () => layout.withSplitFraction('', fraction),
          throwsFormatException,
        );
      }
    },
  );

  test('runtime IDs map to saved indexes and back without changing layout', () {
    final layout = _layout();
    final tabs = [40, 10, 30, 20, 50];
    final saved = layout.mapIds(tabs.indexOf);
    expect(saved.leafIds, [1, 3, 2, 0]);
    expect(saved.mapIds((index) => tabs[index]), layout);
    expect(() => layout.mapIds((_) => 0), throwsFormatException);
    expect(() => layout.mapIds((_) => -1), throwsFormatException);
  });

  test(
    'constructors reject duplicate IDs, negative IDs and bad proportions',
    () {
      expect(() => TerminalPaneLeaf(-1), throwsFormatException);
      expect(
        () => TerminalPaneSplit(
          axis: TerminalSplitAxis.horizontal,
          first: TerminalPaneLeaf(1),
          second: TerminalPaneLeaf(1),
        ),
        throwsFormatException,
      );
      for (final fraction in [double.nan, double.negativeInfinity, 0.1, 0.9]) {
        expect(
          () => TerminalPaneSplit(
            axis: TerminalSplitAxis.horizontal,
            fraction: fraction,
            first: TerminalPaneLeaf(1),
            second: TerminalPaneLeaf(2),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'decoder rejects malformed and over-deep trees before traversing them',
    () {
      final split = {
        'kind': 'split',
        'axis': 'horizontal',
        'fraction': 0.5,
        'first': {'kind': 'leaf', 'id': 0},
        'second': {'kind': 'leaf', 'id': 1},
      };
      for (final value in <Map<String, dynamic>>[
        {},
        {'kind': 'new-layout'},
        {'kind': 'leaf', 'id': -1},
        // Reject fractional IDs on every backend; integral doubles
        // retain a distinct type only on the VM.
        if (!kIsWeb) {'kind': 'leaf', 'id': 0.0},
        {'kind': 'leaf', 'id': 0.5},
        {'kind': 'leaf', 'id': '0'},
        {...split, 'axis': 'diagonal'},
        {...split, 'fraction': '0.5'},
        {...split, 'fraction': double.nan},
        {...split, 'fraction': 1.0},
        {...split, 'first': null},
        {...split, 'second': split['first']},
      ]) {
        expect(
          () => TerminalPaneLayout.fromJson(value),
          throwsFormatException,
          reason: '$value',
        );
      }
      Map<String, dynamic> deep = {'kind': 'leaf', 'id': 0};
      for (var index = 1; index < 10000; index++) {
        deep = {
          ...split,
          'first': deep,
          'second': {'kind': 'leaf', 'id': index},
        };
      }
      expect(() => TerminalPaneLayout.fromJson(deep), throwsFormatException);
    },
  );
}
