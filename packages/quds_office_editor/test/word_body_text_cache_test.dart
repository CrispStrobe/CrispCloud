import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundaryKey = ValueKey<String>('body-text-cache-image');
const _retainedKey = ValueKey<String>('retained-body-text-canvas');
const _config = OfficeSurfaceConfig(
  mode: OfficeInteractionMode.selecting,
  theme: OfficeTheme.dark,
  showRulers: false,
);

WmlParagraph _paragraph(String text) => WmlParagraph(
  inlines: [
    WmlRun(
      text: text,
      properties: WmlRunProps(
        asciiFont: 'Liberation Serif',
        fontSizeHalfPoints: 24,
        color: '999999',
      ),
    ),
  ],
);

WmlDocument _document(List<WmlBlock> blocks) => WmlDocument(
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 300, height: 270),
      margins: const WmlPageMargins(
        top: 50,
        bottom: 50,
        left: 20,
        right: 20,
        header: 15,
        footer: 15,
      ),
      header: [_paragraph('Header story')],
      footer: [_paragraph('Footer story')],
      blocks: blocks,
    ),
  ],
);

WmlTable _table() => WmlTable(
  grid: [120, 120],
  rows: [
    WmlTableRow(
      cells: [
        for (final text in ['First cell', 'Second cell'])
          WmlTableCell(width: 120, blocks: [_paragraph(text)]),
      ],
    ),
  ],
);

LaidOutDocument _layout(WmlDocument document) => WordLayoutEngine(
  font: null,
  measure: (cp, size, props) => PaintRunText.advanceOf(cp, size, props),
).layout(document, updateFields: false);

class _CanvasFixture {
  _CanvasFixture(this.tester, this.document) : laidOut = _layout(document) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 350);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  final WidgetTester tester;
  final WmlDocument document;
  LaidOutDocument laidOut;
  final CaretEngine caret = CaretEngine();
  ({WmlTable table, bool column, int from, int to})? selectedTableBand;
  bool editingHeader = false;
  bool editingFooter = false;
  List<WmlParagraph>? storyParagraphs;
  Map<WmlParagraph, List<OfficeProofingFinding>> findings = const {};

  Future<RenderWordCanvas> mount({Key key = _retainedKey}) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _boundaryKey,
          child: WordCanvas(
            key: key,
            document: document,
            laidOut: laidOut,
            caret: caret,
            config: _config,
            selectedTableBand: selectedTableBand,
            editingHeader: editingHeader,
            editingFooter: editingFooter,
            storyParagraphs: storyParagraphs,
            proofingFindings: findings,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    return tester.renderObject<RenderWordCanvas>(find.byType(WordCanvas));
  }

  Future<Uint8List> pixels() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_boundaryKey),
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

  Future<void> expectFreshPixels(
    RenderWordCanvas retained, {
    required String reason,
    Uint8List? changedFrom,
  }) async {
    expect(await mount(), same(retained));
    final retainedPixels = await pixels();
    await mount(key: UniqueKey());
    final freshPixels = await pixels();
    if (changedFrom != null) {
      expect(
        _differentPixels(changedFrom, freshPixels),
        greaterThan(0),
        reason: 'The fixture must visibly exercise the changed state.',
      );
    }
    expect(_differentPixels(retainedPixels, freshPixels), 0, reason: reason);
  }
}

int _differentPixels(Uint8List first, Uint8List second) {
  expect(first.length, second.length);
  var count = 0;
  for (var index = 0; index < first.length; index += 4) {
    if (first[index] != second[index] ||
        first[index + 1] != second[index + 1] ||
        first[index + 2] != second[index + 2] ||
        first[index + 3] != second[index + 3]) {
      count++;
    }
  }
  return count;
}

OfficeProofingFinding _finding(WmlParagraph paragraph) =>
    OfficeProofingFinding.forRequest(
      OfficeProofingRequest(
        documentId: 'body-text-cache',
        blockId: 'toc-entry',
        revision: 0,
        text: paragraph.text,
      ),
      providerId: 'cache-test-provider',
      start: 0,
      end: 1,
      ruleId: 'cache-test.spelling',
      message: 'Check this source range.',
      category: OfficeProofingCategory.spelling,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets('dark table-band changes match freshly painted text', (
    tester,
  ) async {
    final table = _table();
    final fixture = _CanvasFixture(tester, _document([table]));
    final retained = await fixture.mount();
    final before = await fixture.pixels();
    fixture.selectedTableBand = (table: table, column: false, from: 0, to: 0);
    await fixture.expectFreshPixels(
      retained,
      changedFrom: before,
      reason: 'Selected cells need ink adapted to their current background.',
    );
  });

  testWidgets('mutating the same caret across cells refreshes dark text', (
    tester,
  ) async {
    final fixture = _CanvasFixture(tester, _document([_table()]));
    final retained = await fixture.mount();
    final before = await fixture.pixels();
    final originalCaret = fixture.caret;
    fixture.caret
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = 1
      ..paragraphIndex = 1
      ..logicalIndex = 5;
    expect(fixture.caret, same(originalCaret));
    await fixture.expectFreshPixels(
      retained,
      changedFrom: before,
      reason: 'A spanning selection changes the background under both cells.',
    );
  });

  for (final footer in [false, true]) {
    for (final entering in [false, true]) {
      testWidgets(
        '${entering ? 'entering' : 'leaving'} ${footer ? 'footer' : 'header'} '
        'editing refreshes adaptive body ink',
        (tester) async {
          final document = _document([_table()]);
          final fixture = _CanvasFixture(tester, document);
          final story = footer
              ? document.sections.single.footer
              : document.sections.single.header;
          void editStory(bool editing) {
            fixture
              ..editingHeader = editing && !footer
              ..editingFooter = editing && footer
              ..storyParagraphs = editing ? story : null;
          }

          editStory(!entering);
          final retained = await fixture.mount();
          final before = await fixture.pixels();
          editStory(entering);
          await fixture.expectFreshPixels(
            retained,
            changedFrom: before,
            reason: 'Entering or leaving a story changes body dimming.',
          );
        },
      );
    }
  }

  testWidgets('position relayout refreshes a retained Word canvas', (
    tester,
  ) async {
    final paragraph = _paragraph('Baseline ');
    final positioned = _paragraph('Raised').inlines.single as WmlRun;
    paragraph.inlines.add(positioned);
    final document = _document([paragraph]);
    final fixture = _CanvasFixture(tester, document);
    final retained = await fixture.mount();
    final before = await fixture.pixels();
    positioned.properties.positionHalfPoints = 12;
    fixture.laidOut = _layout(document);
    await fixture.expectFreshPixels(
      retained,
      changedFrom: before,
      reason: 'A new position layout must replace the recorded text image.',
    );
    expect(paragraph.text, 'Baseline Raised');
    expect(positioned.properties.fontSizeHalfPoints, 24);
  });

  testWidgets('collapsed caret movement preserves the same body pixels', (
    tester,
  ) async {
    final fixture = _CanvasFixture(tester, _document([_table()]));
    final retained = await fixture.mount();
    final before = await fixture.pixels();
    fixture.caret
      ..paragraphIndex = 1
      ..logicalIndex = 4;
    fixture.caret.collapseSelection();
    expect(await fixture.mount(), same(retained));
    expect(_differentPixels(before, await fixture.pixels()), 0);
    await fixture.expectFreshPixels(
      retained,
      reason: 'Moving a collapsed caret must not change unfocused body ink.',
    );
  });

  testWidgets('clearing TOC findings removes recorded overlay squiggles', (
    tester,
  ) async {
    final item = _paragraph('Fehler entry');
    final toc = WmlToc(
      title: 'Contents',
      entries: [
        WmlTocEntry(
          text: item.text,
          level: 1,
          headingParagraphIndex: 2,
          pageNumber: 12,
        ),
      ],
      itemParagraphs: [item],
    );
    final fixture = _CanvasFixture(tester, _document([toc]));
    expect(
      fixture.laidOut.pages.single.lines.any(
        (line) =>
            identical(line.sourceParagraph, item) && line.overlayText == '12',
      ),
      isTrue,
    );
    fixture.findings = {
      item: [_finding(item)],
    };
    final retained = await fixture.mount();
    final before = await fixture.pixels();
    fixture.findings = const {};
    await fixture.expectFreshPixels(
      retained,
      changedFrom: before,
      reason: 'Clearing findings must remove squiggles from TOC overlays too.',
    );
  });
}
