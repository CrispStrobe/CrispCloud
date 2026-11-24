import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

class _CountedLines extends ListBase<LaidOutLine> {
  _CountedLines(this._lines);

  final List<LaidOutLine> _lines;
  var reads = 0;

  @override
  int get length => _lines.length;

  @override
  set length(int value) => throw UnsupportedError('Read-only lines');

  @override
  LaidOutLine operator [](int index) {
    reads++;
    return _lines[index];
  }

  @override
  void operator []=(int index, LaidOutLine value) =>
      throw UnsupportedError('Read-only lines');
}

void main() {
  testWidgets('table-band repaint matches a fresh selection canvas', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 300);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final table = WmlTable(
      grid: [120, 120],
      rows: [
        WmlTableRow(
          cells: [
            for (final text in ['First cell', 'Second cell'])
              WmlTableCell(
                width: 120,
                blocks: [
                  WmlParagraph(inlines: [WmlRun(text: text)]),
                ],
              ),
          ],
        ),
      ],
    );
    final document = WmlDocument(
      sections: [
        WmlSection(
          pageSize: const WmlPageSize(width: 300, height: 220),
          margins: const WmlPageMargins(
            top: 20,
            bottom: 20,
            left: 20,
            right: 20,
          ),
          blocks: [table],
        ),
      ],
    );
    final measured = WordLayoutEngine(font: null).layout(document);
    final page = measured.pages.single;
    final lines = _CountedLines(page.lines);
    final layout = LaidOutDocument(
      pageSize: measured.pageSize,
      pages: [
        LaidOutPage(
          index: page.index,
          width: page.width,
          height: page.height,
          lines: lines,
          frames: page.frames,
          header: page.header,
          footer: page.footer,
          notes: page.notes,
          headerBand: page.headerBand,
          footerBand: page.footerBand,
        ),
      ],
    );
    final caret = CaretEngine()
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = 1
      ..paragraphIndex = 0
      ..logicalIndex = 5;
    const boundaryKey = ValueKey('selection-cache-image');
    const retainedKey = ValueKey('retained-selection-canvas');
    final band = (table: table, column: false, from: 0, to: 0);

    Future<void> mount(Key key, {bool tableBand = false}) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: boundaryKey,
            child: WordCanvas(
              key: key,
              document: document,
              laidOut: layout,
              caret: caret,
              selectedTableBand: tableBand ? band : null,
              config: const OfficeSurfaceConfig(
                mode: OfficeInteractionMode.selecting,
                showRulers: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    Future<Uint8List> pixels() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      ))!;
      final data = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      final result = Uint8List.fromList(data.buffer.asUint8List());
      image.dispose();
      return result;
    }

    await mount(retainedKey);
    final retained = tester.renderObject<RenderWordCanvas>(
      find.byType(WordCanvas),
    );
    await mount(retainedKey, tableBand: true);
    expect(
      tester.renderObject<RenderWordCanvas>(find.byType(WordCanvas)),
      same(retained),
    );
    final cachedPixels = await pixels();
    await mount(UniqueKey(), tableBand: true);
    final freshPixels = await pixels();
    expect(
      cachedPixels,
      orderedEquals(freshPixels),
      reason: 'Switching to a table band must not reuse the old text fill.',
    );

    final fresh = tester.renderObject<RenderWordCanvas>(
      find.byType(WordCanvas),
    );
    Future<int> repaintAndCountLines() async {
      lines.reads = 0;
      fresh.markNeedsPaint();
      await tester.pump();
      return lines.reads;
    }

    final heldSelectionReads = await repaintAndCountLines();
    caret.logicalIndex = caret.selectionAnchor;
    final collapsedReads = await repaintAndCountLines();
    expect(
      heldSelectionReads,
      collapsedReads,
      reason: 'A cached empty text band should cause no extra line reads.',
    );
  });

  testWidgets('search overlays skip pages outside the selection', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 230);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final document = WmlDocument(
      sections: [
        WmlSection(
          pageSize: const WmlPageSize(width: 300, height: 220),
          margins: const WmlPageMargins(
            top: 20,
            bottom: 20,
            left: 20,
            right: 20,
          ),
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'First result')]),
            WmlParagraph(
              properties: WmlParagraphProps(pageBreakBefore: true),
              inlines: [WmlRun(text: 'Second result')],
            ),
          ],
        ),
      ],
    );
    final original = WordLayoutEngine(font: null).layout(document);
    expect(original.pages, hasLength(2));
    final first = original.pages.first;
    final lines = _CountedLines(first.lines);
    final layout = LaidOutDocument(
      pageSize: original.pageSize,
      pages: [
        LaidOutPage(
          index: first.index,
          width: first.width,
          height: first.height,
          lines: lines,
          frames: first.frames,
        ),
        original.pages.last,
      ],
    );
    final caret = CaretEngine()
      ..selectionAnchorParagraph = 1
      ..paragraphIndex = 1
      ..logicalIndex = 5;
    final hits = OfficeFind.inWord(
      document,
      const OfficeFindOptions(query: 'result'),
    );
    expect(hits, hasLength(2));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WordCanvas(
          document: document,
          laidOut: layout,
          caret: caret,
          findHits: hits,
          config: const OfficeSurfaceConfig(
            mode: OfficeInteractionMode.selecting,
            showRulers: false,
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderWordCanvas>(
      find.byType(WordCanvas),
    );
    Future<int> repaintWith(List<OfficeFindHit> results) async {
      lines.reads = 0;
      render.findHits = results;
      render.markNeedsPaint();
      await tester.pump();
      return lines.reads;
    }

    expect(await repaintWith(hits), await repaintWith(const []));
    caret
      ..selectionAnchorParagraph = 0
      ..paragraphIndex = 0;
    await repaintWith(hits);
    expect(await repaintWith(hits), greaterThan(await repaintWith(const [])));
    expect(tester.takeException(), isNull);
  });
}
