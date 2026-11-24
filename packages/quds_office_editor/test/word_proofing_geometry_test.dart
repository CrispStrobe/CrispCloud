import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/editor_word/proofing_geometry.dart';
import 'package:quds_office_editor/src/proofing/word_proofing_findings.dart';

const _boundaryKey = ValueKey<String>('proofing-geometry-image');

WmlDocument _document(List<WmlBlock> blocks, {double width = 300}) =>
    WmlDocument(
      proofingLanguage: 'de-DE',
      sections: [
        WmlSection(
          pageSize: WmlPageSize(width: width, height: 320),
          margins: const WmlPageMargins(
            top: 60,
            bottom: 70,
            left: 30,
            right: 30,
            header: 15,
            footer: 15,
          ),
          blocks: blocks,
        ),
      ],
    );

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

LaidOutDocument _layout(WmlDocument document) => WordLayoutEngine(
  font: null,
  measure: (cp, size, props) => PaintRunText.advanceOf(cp, size, props),
).layout(document, updateFields: false);

OfficeProofingFinding _finding(WmlParagraph paragraph, int start, int end) =>
    OfficeProofingFinding.forRequest(
      OfficeProofingRequest(
        documentId: 'geometry',
        blockId: 'paragraph',
        revision: 0,
        text: paragraph.text,
      ),
      providerId: 'geometry-provider',
      start: start,
      end: end,
      ruleId: 'geometry.spelling',
      message: 'Check this source range.',
      category: OfficeProofingCategory.spelling,
    );

Future<RenderWordCanvas> _mount(
  WidgetTester tester,
  WmlDocument document,
  LaidOutDocument layout, {
  Map<WmlParagraph, List<OfficeProofingFinding>> findings = const {},
  List<OfficeProofingFinding>? Function(WmlParagraph)? proofingLookup,
  ValueChanged<OfficeContextHit>? onContextMenu,
  ValueChanged<OfficeContextHit>? onReviewTap,
  bool compact = false,
  bool bodyLayoutIsCurrent = false,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: WordCanvas(
          compact: compact,
          bodyLayoutIsCurrent: bodyLayoutIsCurrent,
          document: document,
          laidOut: layout,
          caret: CaretEngine(),
          config: const OfficeSurfaceConfig(showRulers: false),
          proofingFindings: findings,
          proofingLookup: proofingLookup,
          onContextMenu: onContextMenu,
          onReviewTap: onReviewTap,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return tester.renderObject<RenderWordCanvas>(find.byType(WordCanvas));
}

Future<({Uint8List bytes, int width, int height})> _pixels(
  WidgetTester tester,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final result = (
    bytes: data.buffer.asUint8List(),
    width: image.width,
    height: image.height,
  );
  image.dispose();
  return result;
}

int _redPixels(
  ({Uint8List bytes, int width, int height}) image, [
  Rect? region,
]) {
  final area =
      region ??
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  var count = 0;
  for (
    var y = area.top.floor().clamp(0, image.height);
    y < area.bottom.ceil().clamp(0, image.height);
    y++
  ) {
    for (
      var x = area.left.floor().clamp(0, image.width);
      x < area.right.ceil().clamp(0, image.width);
      x++
    ) {
      final index = (y * image.width + x) * 4;
      if (image.bytes[index] > 150 &&
          image.bytes[index + 1] < 145 &&
          image.bytes[index + 2] < 145) {
        count++;
      }
    }
  }
  return count;
}

Rect _lineRegion(RenderWordCanvas canvas, LaidOutLine line) => Rect.fromPoints(
  canvas.windowForPagePoint(line.pageIndex, Offset(line.x - 2, line.y)),
  canvas.windowForPagePoint(
    line.pageIndex,
    Offset(line.x + line.width + 6, line.y + line.height + 4),
  ),
);

Future<void> _rightClick(
  WidgetTester tester,
  RenderWordCanvas canvas,
  int page,
  Offset point,
) async {
  final position =
      tester.getTopLeft(find.byType(WordCanvas)) +
      canvas.windowForPagePoint(page, point);
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
}

class _WordProvider extends OfficeProofingProvider {
  @override
  String get id => 'test-word-provider';
  @override
  bool supportsLanguage(String language) => true;
  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: [
          for (final match in RegExp('Fehler').allMatches(request.text))
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              start: match.start,
              end: match.end,
              ruleId: 'test.word',
              message: 'Test finding.',
              category: OfficeProofingCategory.spelling,
            ),
        ],
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test(
    'published ranges preserve order, overlaps and zero-length findings',
    () {
      final paragraph = _paragraph('x' * 220);
      final marks = [
        for (var offset = 0; offset < 210; offset += 3)
          _finding(paragraph, offset, offset + 2),
        _finding(paragraph, 5, 190),
        _finding(paragraph, 6, 6),
        _finding(paragraph, 170, 170),
      ];
      final published =
          WordProofingFindings.freeze(marks) as WordProofingFindings;
      for (var min = 0; min < 220; min += 5) {
        final max = min + 2;
        expect(
          published.affecting(min, max),
          orderedEquals(
            marks.where(
              (finding) =>
                  finding.start == finding.end ||
                  (finding.start <= max && finding.end >= min),
            ),
          ),
        );
      }
      final first = marks.first;
      marks.clear();
      expect(published.first, same(first));
      expect(() => published.clear(), throwsUnsupportedError);
    },
  );

  testWidgets('proofing lookup follows visible table rows when scrolling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 350);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final paragraphs = [
      for (var row = 0; row < 80; row++) _paragraph('Fehler'),
    ];
    final table = WmlTable(
      grid: [180],
      rows: [
        for (final paragraph in paragraphs)
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [paragraph]),
            ],
          ),
      ],
    );
    final document = WmlDocument(
      sections: [
        WmlSection(
          pageSize: const WmlPageSize(width: 260, height: 2900),
          margins: const WmlPageMargins(
            top: 25,
            bottom: 25,
            left: 25,
            right: 25,
          ),
          blocks: [table],
        ),
      ],
    );
    final layout = _layout(document);
    final page = layout.pages.single;
    final seen = <WmlParagraph, int>{};
    final finding = _finding(paragraphs.first, 0, 6);
    final canvas = await _mount(
      tester,
      document,
      layout,
      proofingLookup: (paragraph) {
        seen.update(paragraph, (count) => count + 1, ifAbsent: () => 1);
        return [finding];
      },
    );
    Future<void> repaint() async {
      seen.clear();
      canvas.markNeedsPaint();
      await tester.pump();
    }

    await repaint();
    expect(seen[paragraphs.first], 1);
    expect(seen.containsKey(paragraphs.last), isFalse);

    final lastLine = page.lines.last;
    final lastY = canvas
        .windowForPagePoint(0, Offset(lastLine.x, lastLine.y))
        .dy;
    canvas.viewport.origin = Offset(0, lastY - 100);
    await repaint();
    expect(seen[paragraphs.last], 1);
    expect(seen.containsKey(paragraphs.first), isFalse);
    expect(tester.takeException(), isNull);
  });

  test(
    'mixed bidi source ranges have disjoint boxes and span wrapped lines',
    () {
      final paragraph = _paragraph('ABC אבג DEF ABC אבג DEF ABC אבג DEF');
      final lines = _layout(
        _document([paragraph], width: 160),
      ).pages.expand((page) => page.lines).toList();
      expect(lines.length, greaterThan(1));
      for (final line in lines) {
        PaintRunText.fitLine(line, paragraph.text);
      }
      final range = WordProofingGeometry.displayRanges(
        lines.first,
        2,
        5,
      ).single;
      final boxes = CaretEngine.rangeRectsOnLine(
        lines.first,
        lines.first.y,
        lines.first.height,
        range.start,
        range.end,
      );
      expect(boxes, hasLength(2));
      expect(boxes[0].right, lessThan(boxes[1].left));
      for (final line in lines) {
        final mapped = WordProofingGeometry.displayRanges(
          line,
          2,
          paragraph.text.length - 2,
        ).single;
        final lineBoxes = CaretEngine.rangeRectsOnLine(
          line,
          line.y,
          line.height,
          mapped.start,
          mapped.end,
        );
        expect(lineBoxes, isNotEmpty);
        expect(
          lineBoxes.every(
            (box) =>
                box.left >= line.x - .01 &&
                box.right <= line.x + line.width + .01,
          ),
          isTrue,
        );
      }
    },
  );

  test('repeated header text maps only to its matching source occurrence', () {
    final header = _paragraph('  Fehler\t  Fehler\t1');
    final doc = _document([_paragraph('Body')]);
    doc.sections.single.header.add(header);
    final lines = _layout(doc).pages.single.header;
    final start = header.text.lastIndexOf('Fehler');
    expect(
      WordProofingGeometry.displayRanges(lines.first, start, start + 6),
      isEmpty,
    );
    expect(WordProofingGeometry.displayRanges(lines[1], start, start + 6), [
      const TextRange(start: 0, end: 6),
    ]);
    // A literal number in the right tab remains authored text.
    expect(
      WordProofingGeometry.displayRanges(lines.last, 0, header.text.length),
      [const TextRange(start: 0, end: 1)],
    );
    expect(
      WordProofingGeometry.displayRanges(
        lines.last,
        header.text.length,
        header.text.length,
      ),
      [const TextRange(start: 1, end: 1)],
    );
  });

  test('note presentation labels cannot acquire authored source ranges', () {
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(text: 'A'),
        WmlNoteMarker(endnote: false, properties: WmlRunProps()),
        WmlRun(text: 'Fehler'),
      ],
    );
    final doc = _document([_paragraph('Body')]);
    doc.footnotes.add(WmlNote(id: 1, endnote: false, blocks: [paragraph]));
    doc.paragraphs.first.inlines.add(WmlRun(text: '1', noteRefId: 1));
    final line = _layout(doc).pages.single.notes.singleWhere(
      (line) => identical(line.sourceParagraph, paragraph),
    );
    expect(paragraph.text, 'AFehler');
    expect(line.sourceText, 'A1Fehler');
    expect(line.proofingOffsetAt(1), isNull);
    expect(WordProofingGeometry.displayRanges(line, 0, 7), [
      const TextRange(start: 0, end: 1),
      const TextRange(start: 2, end: 8),
    ]);
    expect(WordProofingGeometry.displayRanges(line, 1, 1), [
      const TextRange(start: 2, end: 2),
    ]);
  });

  testWidgets(
    'squiggles follow paragraph identity through body and table text and clear on refresh',
    (tester) async {
      final first = _paragraph('Fehler');
      final second = _paragraph('Fehler');
      final cell = _paragraph('Fehler');
      final doc = _document([
        first,
        second,
        WmlTable(
          grid: [200],
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [cell]),
              ],
            ),
          ],
        ),
      ]);
      final layout = _layout(doc);
      final canvas = await _mount(
        tester,
        doc,
        layout,
        findings: {
          first: [_finding(first, 0, 6)],
          cell: [_finding(cell, 0, 6)],
        },
      );
      final image = await _pixels(tester);
      final lines = layout.pages.single.lines;
      for (final paragraph in [first, cell]) {
        final line = lines.singleWhere(
          (line) => identical(line.sourceParagraph, paragraph),
        );
        expect(_redPixels(image, _lineRegion(canvas, line)), greaterThan(4));
      }
      final clean = lines.singleWhere(
        (line) => identical(line.sourceParagraph, second),
      );
      expect(_redPixels(image, _lineRegion(canvas, clean)), 0);
      final updated = await _mount(tester, doc, layout);
      expect(identical(updated, canvas), isTrue);
      expect(_redPixels(await _pixels(tester)), 0);
    },
  );

  for (final indexed in [false, true]) {
    testWidgets(
      '${indexed ? 'Indexed' : 'Mutable'} findings follow refreshed source ranges',
      (tester) async {
        final paragraph = _paragraph('Fehler korrekt');
        final document = _document([paragraph]);
        final layout = _layout(document);
        List<OfficeProofingFinding> publication(OfficeProofingFinding mark) =>
            indexed
            ? WordProofingFindings.freeze(List.filled(17, mark))
            : [mark];
        var findings = publication(_finding(paragraph, 0, 6));
        final canvas = await _mount(
          tester,
          document,
          layout,
          bodyLayoutIsCurrent: true,
          proofingLookup: (_) => findings,
        );
        final line = layout.pages.single.lines.single;
        Rect strip(int start, int end) {
          final rect = CaretEngine.rangeRectsOnLine(
            line,
            line.y,
            line.height,
            start,
            end,
          ).single;
          return Rect.fromPoints(
            canvas.windowForPagePoint(0, rect.topLeft),
            canvas.windowForPagePoint(0, rect.bottomRight + const Offset(0, 2)),
          );
        }

        final left = strip(0, 6);
        final right = strip(7, 14);
        final before = await _pixels(tester);
        expect(_redPixels(before, left), greaterThan(0));
        expect(_redPixels(before, right), 0);

        final moved = _finding(paragraph, 7, 14);
        if (indexed) {
          findings = publication(moved);
        } else {
          findings[0] = moved;
        }
        canvas.markNeedsPaint();
        await tester.pump();
        final after = await _pixels(tester);
        expect(_redPixels(after, left), 0);
        expect(_redPixels(after, right), greaterThan(0));
      },
    );
  }

  testWidgets('generated field text receives no findings or squiggles', (
    tester,
  ) async {
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(text: 'Fehler '),
        WmlRun(text: 'Fehler', fieldInstruction: 'REF bookmark'),
        WmlRun(text: ' Fehler'),
      ],
    );
    final doc = _document([paragraph]);
    final session = WordProofingSession(
      document: () => doc,
      revision: () => 0,
      service: OfficeProofingService(providers: [_WordProvider()]),
    );
    addTearDown(session.dispose);
    await tester.runAsync(session.checkNow);
    expect(
      session.summary.issues.map(
        (issue) => (issue.finding.start, issue.finding.end),
      ),
      [(0, 6), (14, 20)],
    );
    final layout = _layout(doc);
    final canvas = await _mount(
      tester,
      doc,
      layout,
      proofingLookup: session.paintFindingsLookup,
    );
    final line = layout.pages.single.lines.single;
    final field = CaretEngine.rangeRectsOnLine(
      line,
      line.y,
      line.height,
      7,
      13,
    ).single;
    final region = Rect.fromPoints(
      canvas.windowForPagePoint(0, Offset(field.left + 1, field.top)),
      canvas.windowForPagePoint(0, Offset(field.right - 1, field.bottom + 2)),
    );
    final image = await _pixels(tester);
    expect(_redPixels(image), greaterThan(5));
    expect(_redPixels(image, region), 0);
  });

  testWidgets('generated header labels cannot paint source squiggles', (
    tester,
  ) async {
    final header = _paragraph('1')..properties.pageNumberField = true;
    final doc = _document([_paragraph('Body')]);
    doc.sections.single.header.add(header);
    await _mount(
      tester,
      doc,
      _layout(doc),
      findings: {
        header: [_finding(header, 0, 1)],
      },
    );
    expect(_redPixels(await _pixels(tester)), 0);
  });

  testWidgets(
    'right-click source hits distinguish repeated body, table, and footnote text',
    (tester) async {
      final first = _paragraph('Fehler');
      final second = _paragraph('Fehler');
      final cell = _paragraph('Fehler');
      final note = _paragraph('Fehler');
      final doc = _document([
        first,
        second,
        WmlTable(
          grid: [200],
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [cell]),
              ],
            ),
          ],
        ),
      ]);
      doc.footnotes.add(WmlNote(id: 1, endnote: false, blocks: [note]));
      first.inlines.add(WmlRun(text: '1', noteRefId: 1));
      final layout = _layout(doc);
      final hits = <OfficeContextHit>[];
      final canvas = await _mount(tester, doc, layout, onContextMenu: hits.add);
      final page = layout.pages.single;
      for (final paragraph in [second, cell, note]) {
        final line = [
          ...page.lines,
          ...page.notes,
        ].singleWhere((line) => identical(line.sourceParagraph, paragraph));
        final glyph = line.glyphs.firstWhere(
          (g) => line.proofingOffsetAt(g.glyph.logicalIndex) == 2,
        );
        await _rightClick(
          tester,
          canvas,
          0,
          Offset(glyph.x + glyph.advance * .2, line.y + line.height / 2),
        );
        expect(hits.last.paragraph, same(paragraph));
        expect(hits.last.proofingOffset, 2);
      }
    },
  );

  testWidgets('right-click header hits use measured glyphs and alignment', (
    tester,
  ) async {
    final header = _paragraph('  WWWWiiiiiiii  ');
    header.properties.justification = WmlJustification.right;
    final doc = _document([_paragraph('Body')]);
    doc.sections.single.header.add(header);
    final layout = _layout(doc);
    final hits = <OfficeContextHit>[];
    final canvas = await _mount(tester, doc, layout, onContextMenu: hits.add);
    final line = layout.pages.single.header.single;
    final painter = PaintRunText.plain(
      text: line.overlayText!,
      fontSize: line.overlaySize,
      color: Colors.black,
      themeFamily: OfficeTheme.light.fontFamily,
    )..layout();
    addTearDown(painter.dispose);
    final origin = line.x + line.width - painter.width;
    for (final index in [2, 4, 8]) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1),
      );
      final box = boxes.single;
      await _rightClick(
        tester,
        canvas,
        0,
        Offset(
          origin + box.left + (box.right - box.left) * .2,
          line.y + line.height / 2,
        ),
      );
      expect(hits.last.paragraph, same(header));
      expect(hits.last.proofingOffset, index + 2);
    }
  });

  testWidgets(
    'compact proofing hits use story text inside default header bands',
    (tester) async {
      final paragraph = _paragraph('Fehler here.');
      final document = _document([paragraph]);
      document.sections.single.margins = const WmlPageMargins(
        top: 4,
        bottom: 4,
        left: 4,
        right: 4,
      );
      final layout = _layout(document);
      final primary = <OfficeContextHit>[];
      final secondary = <OfficeContextHit>[];
      final canvas = await _mount(
        tester,
        document,
        layout,
        compact: true,
        findings: {
          paragraph: [_finding(paragraph, 0, 6)],
        },
        onReviewTap: primary.add,
        onContextMenu: secondary.add,
      );
      final line = layout.pages.first.lines.first;
      final glyph = line.glyphs.firstWhere(
        (glyph) => glyph.glyph.logicalIndex == 1,
      );
      final local = Offset(
        glyph.x + glyph.advance * .2,
        line.y + line.height / 2,
      );
      expect(
        layout.pages.first.headerBand.contains(local.dx, local.dy),
        isTrue,
      );
      final gesture = await tester.startGesture(
        canvas.localToGlobal(local),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await gesture.up();
      await tester.pump();
      expect(primary.single.paragraph, same(paragraph));
      expect(primary.single.proofingOffset, 1);
      await _rightClick(tester, canvas, 0, local);
      expect(secondary.single.paragraph, same(paragraph));
      expect(secondary.single.proofingOffset, 1);
    },
  );

  for (final footer in [false, true]) {
    testWidgets(
      'full-page ${footer ? 'footer' : 'header'} keeps exact proofing pointer hits',
      (tester) async {
        final paragraph = _paragraph('Fehler');
        final document = _document([_paragraph('Body text.')]);
        (footer
                ? document.sections.single.footer
                : document.sections.single.header)
            .add(paragraph);
        final layout = _layout(document);
        final primary = <OfficeContextHit>[];
        final secondary = <OfficeContextHit>[];
        final canvas = await _mount(
          tester,
          document,
          layout,
          findings: {
            paragraph: [_finding(paragraph, 0, 6)],
          },
          onReviewTap: primary.add,
          onContextMenu: secondary.add,
        );
        final line =
            (footer ? layout.pages.first.footer : layout.pages.first.header)
                .single;
        final painter = PaintRunText.plain(
          text: line.overlayText!,
          fontSize: line.overlaySize,
          color: Colors.black,
          themeFamily: OfficeTheme.light.fontFamily,
        )..layout();
        addTearDown(painter.dispose);
        final box = painter
            .getBoxesForSelection(
              const TextSelection(baseOffset: 1, extentOffset: 2),
            )
            .single;
        final local = Offset(
          line.x + box.left + (box.right - box.left) * .2,
          line.y + line.height / 2,
        );
        final gesture = await tester.startGesture(
          canvas.localToGlobal(canvas.windowForPagePoint(0, local)),
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
        );
        await gesture.up();
        await tester.pump();
        expect(primary.single.paragraph, same(paragraph));
        expect(primary.single.proofingOffset, 1);
        await _rightClick(tester, canvas, 0, local);
        expect(secondary.single.paragraph, same(paragraph));
        expect(secondary.single.proofingOffset, 1);
      },
    );
  }

  testWidgets('wrapped proofing still underlines a discretionary hyphen', (
    tester,
  ) async {
    final paragraph = _paragraph(
      'Silbentrennung Silbentrennung Silbentrennung',
    );
    final document = _document([paragraph], width: 110)..autoHyphenation = true;
    final layout = _layout(document);
    final line = layout.pages.first.lines.firstWhere(
      (line) => line.glyphs.any((glyph) => glyph.glyph.isDiscretionaryHyphen),
    );
    final hyphen = line.glyphs.singleWhere(
      (glyph) => glyph.glyph.isDiscretionaryHyphen,
    );
    final boundary = hyphen.glyph.logicalIndex;
    final canvas = await _mount(
      tester,
      document,
      layout,
      findings: {
        paragraph: WordProofingFindings.freeze([
          _finding(paragraph, 0, boundary),
          for (var offset = 20; offset < 38; offset++)
            _finding(paragraph, offset, offset + 1),
        ]),
      },
    );

    final pen = hyphen.x - hyphen.paintDx;
    final region = Rect.fromPoints(
      canvas.windowForPagePoint(
        line.pageIndex,
        Offset(pen + hyphen.advance * 0.4, line.y + line.height - 4),
      ),
      canvas.windowForPagePoint(
        line.pageIndex,
        Offset(pen + hyphen.advance, line.y + line.height + 4),
      ),
    );
    expect(_redPixels(await _pixels(tester), region), greaterThan(0));
  });

  for (final inHeader in [false, true]) {
    testWidgets(
      'zero-length finding at ${inHeader ? 'header' : 'body'} end remains visible',
      (tester) async {
        final paragraph = _paragraph('Fehler');
        final doc = _document([inHeader ? _paragraph('Body') : paragraph]);
        if (inHeader) doc.sections.single.header.add(paragraph);
        await _mount(
          tester,
          doc,
          _layout(doc),
          findings: {
            paragraph: [
              _finding(paragraph, paragraph.text.length, paragraph.text.length),
            ],
          },
        );
        expect(_redPixels(await _pixels(tester)), greaterThan(1));
      },
    );
  }
}
