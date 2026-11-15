// Word-like text selection: geometry of the selection band and one golden.
//
// The original goldens were generated on macOS. Linux references preserve
// its rasterization of the same document; see goldens/linux/provenance.json.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _pageKey = ValueKey('word-selection-page');

String _selectionGolden(String targetPlatform) {
  // TargetPlatformVariant changes selection colours, not the host rasterizer.
  final hostDirectory = Platform.isLinux ? 'linux/' : '';
  return 'goldens/${hostDirectory}word_selection_$targetPlatform.png';
}

String _run(String text, {int halfPoints = 22}) =>
    '<w:r><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial"/>'
    '<w:sz w:val="$halfPoints"/></w:rPr>'
    '<w:t xml:space="preserve">$text</w:t></w:r>';

String _para(List<String> runs, {int before = 0, int after = 0}) =>
    '<w:p><w:pPr><w:spacing w:before="$before" w:after="$after" '
    'w:line="240" w:lineRule="auto"/></w:pPr>${runs.join()}</w:p>';

String _cell(String text) =>
    '<w:tc><w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>'
    '${_para([_run(text)])}</w:tc>';

/// The same synthetic document that was opened in Word for the comparison.
WmlDocument _sample() {
  const borders = ['top', 'left', 'bottom', 'right', 'insideH', 'insideV'];
  final body = [
    _para(
      [
        _run('Selection sample. The quick brown fox '),
        _run('JUMPS', halfPoints: 40),
        _run(
          ' over the lazy dog and keeps running across the meadow until '
          'the line wraps onto a second and a third line of ordinary text.',
        ),
      ],
      before: 240,
      after: 240,
    ),
    _para([_run('Second paragraph, short.')], before: 240, after: 240),
    _para([_run('Third paragraph with a few more words in it.')]),
    '<w:tbl><w:tblPr><w:tblW w:w="6000" w:type="dxa"/><w:tblBorders>'
        '${borders.map((s) => '<w:$s w:val="single" w:sz="4" w:space="0" w:color="000000"/>').join()}'
        '</w:tblBorders></w:tblPr><w:tblGrid><w:gridCol w:w="3000"/>'
        '<w:gridCol w:w="3000"/></w:tblGrid>'
        '<w:tr>${_cell('Cell A1')}${_cell('Cell B1')}</w:tr>'
        '<w:tr>${_cell('Cell A2')}${_cell('Cell B2')}</w:tr></w:tbl>',
    _para([_run('After the table.')]),
  ].join();
  final xml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
      'w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body>'
      '</w:document>';
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText(xml);
  return WordDeserializer().read(package);
}

CaretEngine _select(int fromPara, int from, int toPara, int to) => CaretEngine()
  ..selectionAnchorParagraph = fromPara
  ..selectionAnchor = from
  ..paragraphIndex = toPara
  ..logicalIndex = to;

Future<ui.Image> _paintImage(
  WidgetTester tester,
  WmlDocument document,
  CaretEngine caret, {
  OfficeTheme? theme,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(820, 560);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final layout = WordLayoutEngine(font: null).layout(document);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _pageKey,
        child: WordCanvas(
          key: UniqueKey(),
          document: document,
          laidOut: layout,
          caret: caret,
          config: OfficeSurfaceConfig(
            mode: OfficeInteractionMode.selecting,
            theme: theme ?? OfficeTheme.light.copyWith(fontFamily: 'Arial'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_pageKey),
  );
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
}

Future<Uint8List> _bytes(
  WidgetTester tester,
  ui.Image image,
  ui.ImageByteFormat format,
) async {
  final data = await tester.runAsync(() => image.toByteData(format: format));
  return data!.buffer.asUint8List();
}

/// Bounding box of the pixels that differ between two same-size images.
Future<({int count, Rect bounds})> _diff(
  WidgetTester tester,
  ui.Image a,
  ui.Image b,
) async {
  final pa = await _bytes(tester, a, ui.ImageByteFormat.rawRgba);
  final pb = await _bytes(tester, b, ui.ImageByteFormat.rawRgba);
  var count = 0;
  var left = a.width, top = a.height, right = -1, bottom = -1;
  // Skip the rulers along the top and left edge: they follow the caret.
  for (var y = 60; y < a.height; y++) {
    for (var x = 60; x < a.width; x++) {
      final i = (y * a.width + x) * 4;
      if (pa[i] != pb[i] || pa[i + 1] != pb[i + 1] || pa[i + 2] != pb[i + 2]) {
        count++;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  return (
    count: count,
    bounds: count == 0
        ? Rect.zero
        : Rect.fromLTRB(
            left.toDouble(),
            top.toDouble(),
            right + 1.0,
            bottom + 1.0,
          ),
  );
}

void _dump(String name, Uint8List png) {
  final dir = Platform.environment['QUDS_SELECTION_DUMP'];
  if (dir == null || dir.isEmpty) return;
  File('$dir/$name.png').writeAsBytesSync(png);
}

List<LaidOutLine> _linesOf(LaidOutDocument layout, int paragraph) => [
  for (final page in layout.pages)
    for (final line in page.lines)
      if (line.paragraphIndex == paragraph) line,
];

double _penLeft(LaidOutLine line) =>
    line.glyphs.map((g) => g.x - g.paintDx).reduce((a, b) => a < b ? a : b);

double _penRight(LaidOutLine line) => line.glyphs
    .map((g) => g.x - g.paintDx + g.advance)
    .reduce((a, b) => a > b ? a : b);

List<Rect> _band(CaretEngine caret, LaidOutDocument layout, LaidOutLine line) {
  final lines = _linesOf(layout, line.paragraphIndex);
  return caret.selectionRectsOnLine(
    line,
    line.y,
    line.height,
    paragraph: line.paragraphIndex,
    lastOfParagraph: identical(lines.last, line),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  group('selection band geometry', () {
    final doc = _sample();
    final layout = WordLayoutEngine(font: null).layout(doc);
    final first = _linesOf(layout, 0);

    test('a line with mixed font sizes gets one even band', () {
      expect(first.length, greaterThanOrEqualTo(2));
      final line = first.first;
      // The 20 pt run grows its line and every run shares its baseline.
      expect(line.height, greaterThan(first[1].height + 1));
      final baselines = line.glyphs.map((g) => g.y.toStringAsFixed(3)).toSet();
      expect(baselines, hasLength(1));
      final caret = _select(0, 0, 0, 1 << 20);
      final rects = _band(caret, layout, line);
      expect(rects, hasLength(1));
      expect(rects.single.top, line.y);
      expect(rects.single.height, closeTo(line.height, 1e-9));
      expect(rects.single.left, closeTo(_penLeft(line), 0.001));
    });

    test('multi-line selection is seamless, stops at the text and adds a '
        'paragraph-mark block', () {
      final caret = _select(0, 10, 2, 15);
      final bands = [for (final line in first) _band(caret, layout, line)];
      for (final rects in bands) {
        expect(rects, hasLength(1));
      }
      for (var i = 1; i < first.length; i++) {
        // Consecutive lines touch exactly: no gap, no overlap.
        expect(bands[i].single.top, closeTo(bands[i - 1].single.bottom, 1e-9));
      }
      // Full middle line: from the text's left edge to its last glyph,
      // never out to the right margin.
      final middle = first[first.length - 2];
      expect(
        bands[first.length - 2].single.left,
        closeTo(_penLeft(middle), .001),
      );
      expect(
        bands[first.length - 2].single.right,
        closeTo(_penRight(middle), .001),
      );
      // Last line of a paragraph the selection runs past: mark block.
      final last = first.last;
      final mark = CaretEngine.paragraphMarkWidth(last.glyphs.last.fontSize);
      expect(mark, inInclusiveRange(2.5, 4.0));
      expect(bands.last.single.right, closeTo(_penRight(last) + mark, .001));
      expect(
        bands.last.single.right,
        lessThan(layout.pageSize.width - 72 - 20),
        reason: 'the band must not fill to the right margin',
      );
      // Third paragraph: partial, no mark.
      final third = _linesOf(layout, 2).single;
      final partial = _band(caret, layout, third).single;
      expect(partial.left, closeTo(_penLeft(third), .001));
      expect(partial.right, lessThan(_penRight(third) - 50));
    });

    test('a selection ending at the paragraph end leaves the mark out', () {
      final second = _linesOf(layout, 1).single;
      final length = doc.paragraphs.elementAt(1).text.length;
      final rects = _band(_select(1, 0, 1, length), layout, second);
      expect(rects.single.right, closeTo(_penRight(second), .001));
    });

    test('paragraph spacing before and after is not highlighted', () {
      final caret = _select(0, 0, 2, 5);
      final endOfFirst = _band(caret, layout, first.last).single;
      final second = _band(caret, layout, _linesOf(layout, 1).single).single;
      final props = doc.paragraphs.first.properties;
      final gap =
          props.spacingAfter +
          doc.paragraphs.elementAt(1).properties.spacingBefore;
      expect(gap, greaterThan(0));
      expect(second.top - endOfFirst.bottom, closeTo(gap, .001));
    });

    test('right-to-left paragraphs show the mark on the left', () {
      final line = _linesOf(layout, 1).single;
      final rects = CaretEngine.selectionBandOnLine(
        line,
        line.y,
        line.height,
        0,
        1 << 20,
        paragraphMark: true,
        rtl: true,
      );
      expect(rects.single.left, lessThan(_penLeft(line) - 2));
      expect(rects.single.right, closeTo(_penRight(line), .001));
    });

    test('an empty paragraph shows only its mark block', () {
      final line = LaidOutLine(
        glyphs: const [],
        x: 72,
        y: 100,
        width: 0,
        height: 23,
        pageIndex: 0,
        justification: WmlJustification.left,
      );
      final rects = CaretEngine.selectionBandOnLine(
        line,
        line.y,
        line.height,
        0,
        1 << 20,
        paragraphMark: true,
      );
      expect(rects, [Rect.fromLTWH(72, 100, rects.single.width, 23)]);
      expect(rects.single.width, inInclusiveRange(2.5, 8.0));
      expect(
        CaretEngine.selectionBandOnLine(line, line.y, line.height, 0, 1 << 20),
        isEmpty,
      );
    });
  });

  group('selection colour', () {
    test('defaults to Word\'s colour per platform and stays configurable', () {
      const light = OfficeTheme.light;
      final mac = light.textSelectionFillFor(TargetPlatform.macOS);
      final windows = light.textSelectionFillFor(TargetPlatform.windows);
      // Translucent, so text keeps its own colour underneath.
      expect(mac.a, inExclusiveRange(0.1, 0.6));
      expect(windows.a, inExclusiveRange(0.1, 0.6));
      Color over(Color c, Color page) => Color.alphaBlend(c, page);
      final macOnWhite = over(mac, const Color(0xFFFFFFFF));
      final winOnWhite = over(windows, const Color(0xFFFFFFFF));
      // macOS: light blue (#B3D7FF); Windows: neutral grey (#C8C8C8).
      expect((macOnWhite.r * 255).round(), closeTo(0xB3, 3));
      expect((macOnWhite.g * 255).round(), closeTo(0xD7, 3));
      expect((macOnWhite.b * 255).round(), 0xFF);
      for (final channel in [winOnWhite.r, winOnWhite.g, winOnWhite.b]) {
        expect((channel * 255).round(), closeTo(0xC8, 2));
      }
      const custom = Color(0x5500FF00);
      expect(
        light
            .copyWith(textSelectionFill: custom)
            .textSelectionFillFor(TargetPlatform.macOS),
        custom,
      );
      expect(
        OfficeTheme.dark.textSelectionFillFor(TargetPlatform.windows),
        isNot(windows),
      );
    });
  });

  testWidgets('whole cells are filled; a selection inside one cell is not', (
    tester,
  ) async {
    final doc = _sample();
    final none = await _paintImage(tester, doc, CaretEngine());
    final cells = await _paintImage(tester, doc, _select(3, 0, 4, 7));
    final inCell = await _paintImage(tester, doc, _select(3, 1, 3, 5));
    final layout = WordLayoutEngine(font: null).layout(doc);
    final cellBoxes = layout.pages.first.frames
        .where((b) => b.kind == LaidOutBoxKind.tableCell)
        .toList();
    expect(cellBoxes, hasLength(4));
    final cellsDiff = await _diff(tester, none, cells);
    final inCellDiff = await _diff(tester, none, inCell);
    // Row 1 is filled edge to edge: far wider than its text.
    expect(cellsDiff.bounds.width, greaterThan(300));
    expect(cellsDiff.count, greaterThan(300 * 20));
    // "ell " only: a small band, no cell fill.
    expect(inCellDiff.bounds.width, lessThan(40));
    expect(inCellDiff.bounds.height, lessThan(30));
    expect(inCellDiff.count, greaterThan(50));
  });

  testWidgets('Word-like selection golden', (tester) async {
    final image = await _paintImage(tester, _sample(), _select(0, 10, 2, 15));
    final png = await _bytes(tester, image, ui.ImageByteFormat.png);
    _dump('golden_${defaultTargetPlatform.name}', png);
    await expectLater(
      find.byKey(_pageKey),
      matchesGoldenFile(_selectionGolden(defaultTargetPlatform.name)),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Word-like selection golden (Windows grey)', (tester) async {
    await _paintImage(tester, _sample(), _select(0, 10, 2, 15));
    await expectLater(
      find.byKey(_pageKey),
      matchesGoldenFile(_selectionGolden('windows')),
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
