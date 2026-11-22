import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _boundaryKey = ValueKey('zotero-context-raster');
const _canvasKey = ValueKey('zotero-context-canvas');
const _config = OfficeSurfaceConfig(
  mode: OfficeInteractionMode.selecting,
  showRulers: false,
);

typedef _Raster = ({Uint8List bytes, int width, int height});

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlDocument _document(List<WmlBlock> blocks) => WmlDocument(
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 320, height: 260),
      margins: const WmlPageMargins(top: 20, bottom: 20, left: 24, right: 24),
      blocks: blocks,
    ),
  ],
);

WmlTable _table(WmlParagraph left, WmlParagraph right) => WmlTable(
  grid: [120, 120],
  rows: [
    WmlTableRow(
      cells: [
        WmlTableCell(blocks: [left]),
        WmlTableCell(blocks: [right]),
      ],
    ),
  ],
);

Future<RenderWordCanvas> _mount(
  WidgetTester tester,
  WmlDocument document,
  LaidOutDocument layout,
  CaretEngine caret, {
  List<WordZoteroFieldSelectionRange> ranges = const [],
  List<OfficeFindHit> findHits = const [],
  bool compact = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(560, 460);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: WordCanvas(
          key: _canvasKey,
          document: document,
          laidOut: layout,
          caret: caret,
          config: _config,
          zoteroFieldRanges: ranges,
          findHits: findHits,
          activeFindIndex: findHits.isEmpty ? -1 : 0,
          compact: compact,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return tester.renderObject<RenderWordCanvas>(find.byKey(_canvasKey));
}

Future<_Raster> _raster(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return (
        bytes: Uint8List.fromList(data.buffer.asUint8List()),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }))!;
}

List<Rect> _screenRects(
  RenderWordCanvas canvas,
  LaidOutLine line,
  int from,
  int to, {
  Rect? clip,
  bool compact = false,
}) => [
  for (final rect in CaretEngine.rangeRectsOnLine(
    line,
    line.y,
    line.height,
    from,
    to,
  ))
    if (clip == null || rect.overlaps(clip))
      if (compact)
        clip == null ? rect : rect.intersect(clip)
      else
        Rect.fromPoints(
          canvas.windowForPagePoint(
            line.pageIndex,
            (clip == null ? rect : rect.intersect(clip)).topLeft,
          ),
          canvas.windowForPagePoint(
            line.pageIndex,
            (clip == null ? rect : rect.intersect(clip)).bottomRight,
          ),
        ),
];

void _expectOnlyRanges(_Raster before, _Raster after, List<Rect> ranges) {
  expect(after.width, before.width);
  expect(after.height, before.height);
  var changed = 0;
  var outside = 0;
  for (var offset = 0; offset < before.bytes.length; offset += 4) {
    if (before.bytes[offset] == after.bytes[offset] &&
        before.bytes[offset + 1] == after.bytes[offset + 1] &&
        before.bytes[offset + 2] == after.bytes[offset + 2] &&
        before.bytes[offset + 3] == after.bytes[offset + 3]) {
      continue;
    }
    changed++;
    final pixel = offset ~/ 4;
    final point = Offset(
      (pixel % after.width) + .5,
      (pixel ~/ after.width) + .5,
    );
    if (!ranges.any((range) => range.inflate(1.1).contains(point))) outside++;
  }
  expect(changed, greaterThan(10), reason: 'the field context must be visible');
  expect(
    outside,
    0,
    reason: 'context must stay inside its original text range',
  );
}

List<int> _caretState(CaretEngine caret) => [
  caret.paragraphIndex,
  caret.logicalIndex,
  caret.selectionAnchorParagraph,
  caret.selectionAnchor,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'body prompt context paints without moving or focusing the caret',
    (tester) async {
      final first = _paragraph('Continue writing here.');
      final source = _paragraph('Before (Source, 2024) after.');
      final document = _document([first, source]);
      final layout = WordLayoutEngine(font: null).layout(document);
      final caret = CaretEngine()..logicalIndex = 3;
      caret.selectionAnchor = caret.logicalIndex;
      final originalCaret = _caretState(caret);
      final originalTexts = document.paragraphs.map((p) => p.text).toList();
      final render = await _mount(tester, document, layout, caret);
      final before = await _raster(tester);
      final highlighted = await _mount(
        tester,
        document,
        layout,
        caret,
        ranges: [(paragraph: source, start: 7, end: 20)],
      );
      expect(highlighted, same(render));
      expect(highlighted.hasFocus, isFalse);
      final line = layout.pages.single.lines.singleWhere(
        (line) => identical(line.sourceParagraph, source),
      );
      _expectOnlyRanges(
        before,
        await _raster(tester),
        _screenRects(render, line, 7, 20),
      );
      expect(_caretState(caret), originalCaret);
      expect(document.paragraphs.map((p) => p.text).toList(), originalTexts);
      await _mount(tester, document, layout, caret);
      expect((await _raster(tester)).bytes, orderedEquals(before.bytes));
      expect(_caretState(caret), originalCaret);
    },
  );

  testWidgets('context coexists with the writing selection and Find', (
    tester,
  ) async {
    final first = _paragraph('Selected writing and Find result.');
    final source = _paragraph('Second citation.');
    final document = _document([first, source]);
    final layout = WordLayoutEngine(font: null).layout(document);
    final caret = CaretEngine()
      ..logicalIndex = 8
      ..selectionAnchor = 0;
    final originalCaret = _caretState(caret);
    final findHits = [
      const OfficeFindHit(
        kind: OpcPackageKindHint.word,
        preview: 'Find',
        paragraphIndex: 0,
        start: 21,
        end: 25,
      ),
    ];
    final render = await _mount(
      tester,
      document,
      layout,
      caret,
      findHits: findHits,
    );
    final before = await _raster(tester);
    await _mount(
      tester,
      document,
      layout,
      caret,
      ranges: [(paragraph: source, start: 0, end: source.text.length)],
      findHits: findHits,
    );
    final line = layout.pages.single.lines.singleWhere(
      (line) => identical(line.sourceParagraph, source),
    );
    _expectOnlyRanges(
      before,
      await _raster(tester),
      _screenRects(render, line, 0, source.text.length),
    );
    expect(_caretState(caret), originalCaret);
    expect(render.findHits, same(findHits));
    expect(render.activeFindIndex, 0);
  });

  testWidgets('stale paragraph identity and invalid offsets paint nothing', (
    tester,
  ) async {
    final source = _paragraph('Citation with the same text.');
    final oldSource = _paragraph(source.text);
    final document = _document([source]);
    final layout = WordLayoutEngine(font: null).layout(document);
    final caret = CaretEngine();
    await _mount(tester, document, layout, caret);
    final before = await _raster(tester);
    await _mount(
      tester,
      document,
      layout,
      caret,
      ranges: [
        (paragraph: oldSource, start: 0, end: oldSource.text.length),
        (paragraph: source, start: -1, end: 4),
        (paragraph: source, start: 0, end: source.text.length + 1),
        (paragraph: source, start: 4, end: 4),
        (paragraph: source, start: 4, end: 2),
      ],
    );
    expect((await _raster(tester)).bytes, orderedEquals(before.bytes));
  });

  testWidgets('multipart field highlights every owned paragraph only', (
    tester,
  ) async {
    final first = _paragraph('First bibliography entry.');
    final second = _paragraph('Second bibliography entry.');
    final following = _paragraph('Unrelated prose.');
    final document = _document([first, second, following]);
    final layout = WordLayoutEngine(font: null).layout(document);
    final caret = CaretEngine()..paragraphIndex = 2;
    final render = await _mount(tester, document, layout, caret);
    final before = await _raster(tester);
    await _mount(
      tester,
      document,
      layout,
      caret,
      ranges: [
        (paragraph: first, start: 0, end: first.text.length),
        (paragraph: second, start: 0, end: second.text.length),
      ],
    );
    final expected = [
      for (final line in layout.pages.single.lines)
        if (identical(line.sourceParagraph, first) ||
            identical(line.sourceParagraph, second))
          ..._screenRects(render, line, 0, line.sourceParagraph!.text.length),
    ];
    final after = await _raster(tester);
    _expectOnlyRanges(before, after, expected);
    for (final rectangle in expected) {
      var changed = false;
      for (var y = rectangle.top.ceil(); y < rectangle.bottom.floor(); y++) {
        for (var x = rectangle.left.ceil(); x < rectangle.right.floor(); x++) {
          final offset = (y * after.width + x) * 4;
          if (before.bytes[offset] != after.bytes[offset]) changed = true;
        }
      }
      expect(changed, isTrue, reason: 'each bibliography entry must be marked');
    }
  });

  for (final endnote in [false, true]) {
    testWidgets(
      'context excludes the automatic ${endnote ? 'endnote' : 'footnote'} label',
      (tester) async {
        final body = _paragraph('Body.');
        final document = _document([body]);
        final note = WordNotes.insert(
          document,
          body,
          endnote: endnote,
          text: 'Source citation followed by prose.',
        );
        final paragraph = note.paragraphs.single;
        final layout = WordLayoutEngine(font: null).layout(document);
        final caret = CaretEngine();
        final render = await _mount(tester, document, layout, caret);
        final before = await _raster(tester);
        await _mount(
          tester,
          document,
          layout,
          caret,
          ranges: [(paragraph: paragraph, start: 0, end: 15)],
        );
        final lines = [
          for (final page in layout.pages)
            ...page.notes.where(
              (line) => identical(line.sourceParagraph, paragraph),
            ),
        ];
        expect(lines, isNotEmpty);
        expect(lines.first.proofingOffsets!.first, isNull);
        final displayStart = lines.first.proofingOffsets!.indexOf(0);
        final displayEnd = lines.first.proofingOffsets!.indexOf(15);
        expect(displayStart, greaterThan(0));
        _expectOnlyRanges(before, await _raster(tester), [
          for (final line in lines)
            ..._screenRects(render, line, displayStart, displayEnd),
        ]);
        expect(caret.isCollapsed, isTrue);
        expect(render.hasFocus, isFalse);
        expect(paragraph.text, 'Source citation followed by prose.');
      },
    );
  }

  testWidgets('mixed-direction RTL citation uses logical source bounds', (
    tester,
  ) async {
    final paragraph = _paragraph('تمهيد (دراسة، 2024) خاتمة')
      ..properties.rightToLeft = true;
    final document = _document([paragraph]);
    final layout = WordLayoutEngine(font: null).layout(document);
    final caret = CaretEngine();
    final start = paragraph.text.indexOf('(');
    final end = paragraph.text.indexOf(')') + 1;
    final render = await _mount(tester, document, layout, caret);
    final before = await _raster(tester);
    await _mount(
      tester,
      document,
      layout,
      caret,
      ranges: [(paragraph: paragraph, start: start, end: end)],
    );
    _expectOnlyRanges(before, await _raster(tester), [
      for (final line in layout.pages.single.lines)
        ..._screenRects(render, line, start, end),
    ]);
  });

  testWidgets('compact table context respects the native cell clip', (
    tester,
  ) async {
    final source = _paragraph('Citation spans a cell.');
    final adjacent = _paragraph('Adjacent cell.');
    final table = _table(source, adjacent);
    final document = _document([table]);
    final layout = WordLayoutEngine(font: null).layout(document);
    final page = layout.pages.single;
    final cell = page.frames.firstWhere(
      (box) => box.kind == LaidOutBoxKind.tableCell && box.tableCol == 0,
    );
    // A clipped physical fragment retains its already shaped line.
    cell.width = 42;
    final caret = CaretEngine();
    final render = await _mount(tester, document, layout, caret, compact: true);
    final before = await _raster(tester);
    await _mount(
      tester,
      document,
      layout,
      caret,
      ranges: [(paragraph: source, start: 0, end: source.text.length)],
      compact: true,
    );
    _expectOnlyRanges(before, await _raster(tester), [
      for (final line in page.lines)
        if (identical(line.sourceParagraph, source))
          ..._screenRects(
            render,
            line,
            0,
            source.text.length,
            clip: Rect.fromLTWH(cell.x, cell.y, cell.width, cell.height),
            compact: true,
          ),
    ]);
  });

  testWidgets('note table fields retain exact original paragraph ownership', (
    tester,
  ) async {
    final body = _paragraph('Body.');
    final document = _document([body]);
    final note = WordNotes.insert(document, body, endnote: false);
    final source = _paragraph('Note cell citation.');
    final adjacent = _paragraph('Other note cell.');
    note.blocks.add(_table(source, adjacent));
    final layout = WordLayoutEngine(font: null).layout(document);
    final caret = CaretEngine();
    final render = await _mount(tester, document, layout, caret);
    final before = await _raster(tester);
    await _mount(
      tester,
      document,
      layout,
      caret,
      ranges: [(paragraph: source, start: 0, end: source.text.length)],
    );
    final lines = [
      for (final page in layout.pages)
        ...page.notes.where((line) => identical(line.sourceParagraph, source)),
    ];
    expect(lines, isNotEmpty);
    expect(lines.every((line) => line.paragraphIndex < 0), isTrue);
    _expectOnlyRanges(before, await _raster(tester), [
      for (final line in lines)
        ..._screenRects(
          render,
          line,
          0,
          source.text.length,
          clip: Rect.fromLTWH(line.boxX, line.y, line.boxWidth, line.height),
        ),
    ]);
    expect(source.text, 'Note cell citation.');
    expect(adjacent.text, 'Other note cell.');
  });
}
