import 'dart:math';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/editor_word/page_cell_index.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

LaidOutBox _box(
  int? start,
  int? end,
  double width, {
  double height = 30,
  double x = 0,
  double y = 0,
  WmlTable? table,
  LaidOutBoxKind kind = LaidOutBoxKind.tableCell,
}) => LaidOutBox(
  x: x,
  y: y,
  width: width,
  height: height,
  kind: kind,
  paragraphIndex: start,
  paragraphEnd: end,
  table: table,
);

LaidOutBox? _scan(List<LaidOutBox> boxes, int paragraph, WmlFrame? frame) {
  LaidOutBox? best;
  var bestArea = double.infinity;
  for (final box in boxes) {
    final start = box.paragraphIndex;
    if (box.kind != LaidOutBoxKind.tableCell ||
        box.height <= 0 ||
        start == null ||
        paragraph < start ||
        paragraph > (box.paragraphEnd ?? start)) {
      continue;
    }
    if (frame != null &&
        !WordTree.descendants(frame.blocks).contains(box.table)) {
      continue;
    }
    final area = box.width * box.height;
    if (area < bestArea) {
      best = box;
      bestArea = area;
    }
  }
  return best;
}

LaidOutBox? _scanPoint(List<LaidOutBox> boxes, double x, double y) {
  LaidOutBox? best;
  var bestArea = double.infinity;
  for (final box in boxes) {
    if (box.kind != LaidOutBoxKind.tableCell || box.height <= 0) continue;
    if (x >= box.x &&
        x <= box.x + box.width &&
        y >= box.y &&
        y <= box.y + box.height) {
      final area = box.width * box.height;
      if (area < bestArea) {
        best = box;
        bestArea = area;
      }
    }
  }
  return best;
}

void main() {
  test('paint batches retain mixed boxes and preserve cell paint order', () {
    final frames = [
      for (var index = 0; index < 105; index++)
        _box(index, index, 35, x: index.isEven ? 0 : 50, y: index * 8.0),
    ];
    frames[40] = _box(40, 40, 80, y: 320, kind: LaidOutBoxKind.paragraphShade);
    // This cell crosses a row boundary and starts well above the viewport.
    frames[5] = _box(5, 5, 35, y: 40, height: 520);
    final index = WordPageCellIndex(frames).paintIndex!;
    for (final clip in [
      const Rect.fromLTWH(0, 200, 40, 51),
      const Rect.fromLTWH(45, 540, 50, 30),
      const Rect.fromLTWH(0, 825, 100, 60),
    ]) {
      bool wouldPaint(LaidOutBox box) =>
          box.kind != LaidOutBoxKind.tableCell ||
          clip.overlaps(Rect.fromLTWH(box.x, box.y, box.width, box.height));
      final retained = <LaidOutBox>[];
      var batch = index.nextBatch(0, clip);
      while (batch != null) {
        retained.addAll(frames.getRange(batch.start, batch.end));
        batch = index.nextBatch(batch.end, clip);
      }
      expect(retained.length, lessThan(frames.length));
      expect(
        retained.where(wouldPaint),
        orderedEquals(frames.where(wouldPaint)),
      );
    }
  });

  test('selection can inspect every covering cell, including hidden cells', () {
    final outerTable = WmlTable();
    final innerTable = WmlTable();
    final outer = _box(1, 8, 50, table: outerTable);
    final hidden = _box(2, 5, 25, height: 0, table: innerTable);
    final bandOnly = _box(null, 12, 4, table: innerTable);
    final invalid = _box(4, 3, 4, table: innerTable);
    final index = WordPageCellIndex([outer, hidden, bandOnly, invalid]);

    expect(index.anyAt(3, (box) => identical(box, hidden)), isTrue);
    expect(index.anyAt(6, (box) => identical(box, hidden)), isFalse);
    expect(index.anyAt(10, (box) => identical(box.table, innerTable)), isTrue);
    expect(index.anyAt(3, (box) => identical(box, invalid)), isFalse);
    expect(index.anyAt(13, (_) => true), isFalse);
    expect(index.smallestAt(3), same(outer));
    expect(index.smallestAt(10), isNull);
  });

  test('pointer hits include shared edges and cells without text', () {
    final lower = _box(0, 0, 40, y: 30);
    final upper = _box(1, 1, 40);
    final empty = _box(null, null, 10, x: 5, y: 10, height: 10);
    final hidden = _box(2, 2, 1, x: 10, y: 35, height: 0);
    final pointer = WordPageCellIndex([lower, upper, empty, hidden]).pointer;
    expect(pointer.cellAt(40, 30), same(lower));
    expect(pointer.cellAt(10, 20), same(empty));
    expect(pointer.cellAt(10, 35), same(lower));
    expect(pointer.cellAt(10, 61), isNull);
  });

  test('indexed pointer hits match a linear scan across overlapping boxes', () {
    final random = Random(805);
    final boxes = [
      for (var index = 0; index < 400; index++)
        _box(
          null,
          null,
          random.nextInt(20).toDouble(),
          x: random.nextInt(70).toDouble(),
          y: random.nextInt(190).toDouble(),
          height: random.nextInt(30).toDouble(),
        ),
      _box(2, 2, 5, height: double.nan),
      _box(2, 2, 5, y: double.nan),
      _box(2, 2, 5, height: double.infinity),
      _box(2, 2, 5, kind: LaidOutBoxKind.tocEntry),
    ];
    final pointer = WordPageCellIndex(boxes).pointer;
    for (var row = 0; row < 230; row++) {
      for (final x in [0.0, 5.0, 34.0, 60.0, 90.0, double.nan]) {
        final y = row.toDouble();
        expect(pointer.cellAt(x, y), same(_scanPoint(boxes, x, y)));
      }
    }
    expect(pointer.cellAt(5, double.nan), isNull);
  });

  test(
    'nested ranges preserve original tie order and absolute-frame ownership',
    () {
      final outer = WmlTable();
      final inner = WmlTable();
      final frame = WmlFrame(blocks: [inner]);
      final tiedFirst = _box(3, 7, 70, table: outer);
      final tiedSecond = _box(2, 8, 70, table: inner);
      final nested = _box(4, 5, 40, table: inner);
      final boxes = [
        tiedFirst,
        _box(null, null, 1),
        _box(4, 5, 1, height: 0),
        tiedSecond,
        nested,
      ];
      final index = WordPageCellIndex(boxes);
      expect(index.smallestAt(1), isNull);
      expect(index.smallestAt(3), same(tiedFirst));
      expect(index.smallestAt(3, containingFrame: frame), same(tiedSecond));
      expect(index.smallestAt(4), same(nested));
      expect(index.smallestAt(5), same(nested));
      expect(index.smallestAt(6), same(tiedFirst));
      expect(index.smallestAt(8), same(tiedSecond));
      expect(index.smallestAt(9), isNull);
    },
  );

  test('indexed results match a linear scan for overlapping ranges', () {
    final random = Random(804);
    final tables = [WmlTable(), WmlTable(), WmlTable()];
    final frame = WmlFrame(blocks: tables.take(2).toList());
    for (var sample = 0; sample < 30; sample++) {
      final boxes = [
        for (var index = 0; index < 160; index++)
          _box(
            random.nextInt(160) - 10,
            random.nextInt(180),
            40.0 + random.nextInt(5),
            height: random.nextBool() ? 25 : 0,
            table: tables[random.nextInt(tables.length)],
          ),
        _box(3, 7, double.infinity),
        _box(3, 7, double.nan),
        _box(3, 7, 1, kind: LaidOutBoxKind.tocEntry),
      ];
      final index = WordPageCellIndex(boxes);
      for (var paragraph = -12; paragraph < 190; paragraph++) {
        for (final owner in [null, frame]) {
          expect(
            index.smallestAt(paragraph, containingFrame: owner),
            same(_scan(boxes, paragraph, owner)),
          );
        }
      }
    }
  });
}
