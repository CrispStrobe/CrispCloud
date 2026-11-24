import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlSection _section(List<WmlBlock> blocks, {List<WmlParagraph>? header}) =>
    WmlSection(
      pageSize: const WmlPageSize(width: 320, height: 360),
      margins: const WmlPageMargins(
        top: 60,
        bottom: 60,
        left: 30,
        right: 30,
        header: 15,
        footer: 15,
      ),
      blocks: blocks,
      header: header,
    );

LaidOutDocument _layout(WmlDocument document) => WordLayoutEngine(
  font: null,
  measure: (cp, size, props) => PaintRunText.advanceOf(cp, size, props),
).layout(document, updateFields: false);

Future<RenderWordCanvas> _mount(
  WidgetTester tester,
  WmlDocument document,
  CaretEngine caret, {
  LaidOutDocument? layout,
  VirtualViewport? viewport,
  List<WmlParagraph>? storyParagraphs,
  bool editingHeader = false,
  bool editingFooter = false,
  int? selectedCommentId,
  VoidCallback? onChanged,
  ValueChanged<OfficeContextHit>? onContextMenu,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 540,
          height: 300,
          child: WordCanvas(
            document: document,
            laidOut: layout ?? _layout(document),
            caret: caret,
            viewport: viewport,
            config: const OfficeSurfaceConfig(showRulers: false),
            storyParagraphs: storyParagraphs,
            editingHeader: editingHeader,
            editingFooter: editingFooter,
            selectedCommentId: selectedCommentId,
            onChanged: onChanged,
            onContextMenu: onContextMenu,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return tester.renderObject<RenderWordCanvas>(find.byType(WordCanvas));
}

({int paragraph, int offset, int anchorParagraph, int anchor, bool visible})
_caretState(CaretEngine caret) => (
  paragraph: caret.paragraphIndex,
  offset: caret.logicalIndex,
  anchorParagraph: caret.selectionAnchorParagraph,
  anchor: caret.selectionAnchor,
  visible: caret.visible,
);

void main() {
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets('keyboard hit preserves source, selection, layout and viewport', (
    tester,
  ) async {
    final paragraph = _paragraph('One Feler after another.');
    final document = WmlDocument(
      sections: [
        _section([paragraph]),
      ],
    );
    final caret = CaretEngine()
      ..logicalIndex = 9
      ..selectionAnchor = 4
      ..visible = false;
    final viewport = VirtualViewport(scale: 1.25);
    var changes = 0;
    final canvas = await _mount(
      tester,
      document,
      caret,
      viewport: viewport,
      onChanged: () => changes++,
    );
    final beforeCaret = _caretState(caret);
    final beforeViewport = (viewport.origin, viewport.scale, viewport.extent);
    final beforeGlyphs = [
      for (final page in canvas.laidOut.pages)
        for (final line in page.lines)
          for (final glyph in line.glyphs)
            (glyph.x, glyph.advance, line.x, line.width),
    ];

    final normal = canvas.contextHitForCaret()!;
    final selected = canvas.contextHitForCaret(proofingOffset: 4)!;

    expect(normal.paragraph, same(paragraph));
    expect(normal.proofingOffset, 9);
    expect(selected.proofingOffset, 4);
    expect(selected.globalPosition, normal.globalPosition);
    expect(normal.kind, OfficeContextKind.document);
    expect(_caretState(caret), beforeCaret);
    expect((viewport.origin, viewport.scale, viewport.extent), beforeViewport);
    expect(paragraph.text, 'One Feler after another.');
    expect(changes, 0);
    expect([
      for (final page in canvas.laidOut.pages)
        for (final line in page.lines)
          for (final glyph in line.glyphs)
            (glyph.x, glyph.advance, line.x, line.width),
    ], beforeGlyphs);
    expect(
      tester.getRect(find.byType(WordCanvas)).contains(normal.globalPosition),
      isTrue,
    );
  });

  for (final rtl in [false, true]) {
    testWidgets(
      'keyboard hit follows the wrapped ${rtl ? 'RTL' : 'LTR'} caret',
      (tester) async {
        final paragraph = _paragraph(
          List<String>.filled(
            8,
            rtl ? 'كلمات عربية هنا ' : 'some words here ',
          ).join(),
        );
        paragraph.properties.rightToLeft = rtl;
        final document = WmlDocument(
          sections: [
            _section([paragraph]),
          ],
        );
        final layout = _layout(document);
        final lines = layout.pages.expand((page) => page.lines).toList();
        expect(lines.length, greaterThan(2));
        final target = lines[1];
        final caret = CaretEngine()
          ..logicalIndex = CaretEngine.logicalSpan(target).min + 1;
        final canvas = await _mount(tester, document, caret, layout: layout);
        final hit = canvas.contextHitForCaret()!;
        final local = canvas.globalToLocal(hit.globalPosition);
        final expectedX = PaintRunText.caretXOnLine(
          target,
          caret.logicalIndex,
          paragraph: paragraph.text,
          paragraphRtl: rtl,
        );
        final expected = canvas.windowForPagePoint(
          target.pageIndex,
          Offset(expectedX, target.y),
        );
        expect(local.dx, closeTo(expected.dx, .01));
        expect(local.dy, greaterThan(expected.dy));
        expect(local.dy, lessThan(expected.dy + target.height * 2));
        expect(hit.paragraph, same(paragraph));
        expect(hit.proofingOffset, caret.logicalIndex);
      },
    );
  }

  testWidgets('offscreen hit clamps its anchor without revealing the caret', (
    tester,
  ) async {
    final paragraph = _paragraph('The caret remains in this paragraph.');
    final document = WmlDocument(
      sections: [
        _section([paragraph]),
      ],
    );
    final caret = CaretEngine()..logicalIndex = 12;
    final viewport = VirtualViewport();
    final canvas = await _mount(tester, document, caret, viewport: viewport);
    final before = _caretState(caret);
    for (final origin in [
      const Offset(5000, 5000),
      const Offset(-5000, -5000),
    ]) {
      viewport.origin = origin;
      final hit = canvas.contextHitForCaret()!;
      expect(hit.paragraph, same(paragraph));
      expect(hit.proofingOffset, 12);
      expect(
        tester.getRect(find.byType(WordCanvas)).contains(hit.globalPosition),
        isTrue,
      );
      expect(viewport.origin, origin);
      expect(_caretState(caret), before);
    }
  });

  for (final footer in [false, true]) {
    testWidgets(
      'keyboard hit uses exact active ${footer ? 'footer' : 'header'}',
      (tester) async {
        final first = _paragraph('First story');
        final active = _paragraph('Active story');
        final sections = [
          _section([_paragraph('Body one')]),
          _section([_paragraph('Body two')]),
        ];
        if (footer) {
          sections[0].footer.add(first);
          sections[1].footer.add(active);
        } else {
          sections[0].header.add(first);
          sections[1].header.add(active);
        }
        final document = WmlDocument(sections: sections);
        final caret = CaretEngine()..logicalIndex = 3;
        final canvas = await _mount(
          tester,
          document,
          caret,
          storyParagraphs: [active],
          editingHeader: !footer,
          editingFooter: footer,
        );
        final hit = canvas.contextHitForCaret()!;
        expect(hit.paragraph, same(active));
        expect(hit.proofingOffset, 3);
        expect(hit.table, isNull);
        canvas.storyParagraphs = [_paragraph('Unrendered alternate story')];
        expect(canvas.contextHitForCaret(), isNull);
        canvas.storyParagraphs = null;
        expect(canvas.contextHitForCaret(), isNull);
      },
    );
  }

  testWidgets('repeated header anchors to its visible source occurrence', (
    tester,
  ) async {
    final header = _paragraph('Repeated header');
    final document = WmlDocument(
      sections: [
        _section(
          List<WmlBlock>.generate(
            50,
            (index) => _paragraph('Paragraph $index'),
          ),
          header: [header],
        ),
      ],
    );
    final layout = _layout(document);
    expect(layout.pages.length, greaterThan(2));
    final viewport = VirtualViewport();
    final canvas = await _mount(
      tester,
      document,
      CaretEngine()..logicalIndex = 3,
      layout: layout,
      viewport: viewport,
      storyParagraphs: [header],
      editingHeader: true,
    );
    viewport.origin = Offset(0, layout.pageStackTop(2, 96 / 72));
    final before = viewport.origin;
    final hit = canvas.contextHitForCaret()!;
    final local = canvas.globalToLocal(hit.globalPosition);
    expect(hit.paragraph, same(header));
    expect(local.dy, greaterThan(1));
    expect(local.dy, lessThan(80));
    expect(viewport.origin, before);
  });

  testWidgets('pointer hits respect TOC stacking and refresh on relayout', (
    tester,
  ) async {
    const link = WmlHyperlink(url: 'https://example.com/source');
    final document = WmlDocument(
      sections: [
        _section([
          WmlParagraph(
            inlines: [
              WmlRun(text: 'Source text', hyperlink: link, commentIds: [7]),
            ],
          ),
          _paragraph('First target'),
          _paragraph('Last target'),
        ]),
      ],
    );
    final layout = _layout(document);
    final page = layout.pages.single;
    final glyph = page.lines.first.glyphs.first;
    final point = Offset(glyph.x + 1, page.lines.first.y + 2);
    LaidOutBox entry(int target) => LaidOutBox(
      x: point.dx - 2,
      y: point.dy - 2,
      width: 4,
      height: 4,
      kind: LaidOutBoxKind.tocEntry,
      paragraphIndex: target,
    );
    LaidOutDocument withEntries(List<LaidOutBox> entries) => LaidOutDocument(
      isPreview: true,
      pageSize: layout.pageSize,
      pages: [
        LaidOutPage(
          index: 0,
          width: page.width,
          height: page.height,
          lines: page.lines,
          frames: entries,
        ),
      ],
    );
    final caret = CaretEngine();
    final hits = <OfficeContextHit>[];
    Future<OfficeContextHit> hit(LaidOutDocument current) async {
      final canvas = await _mount(
        tester,
        document,
        caret,
        layout: current,
        onContextMenu: hits.add,
      );
      final gesture = await tester.startGesture(
        canvas.localToGlobal(canvas.windowForPagePoint(0, point)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      return hits.last;
    }

    final toc = await hit(withEntries([entry(1), entry(2)]));
    expect(toc.link?.anchor, 'Last target');
    expect(toc.commentId, 7);
    final fallback = await hit(withEntries([entry(1), entry(100)]));
    expect(fallback.link, same(link));
    expect(fallback.commentId, 7);
    expect((await hit(withEntries([]))).link, same(link));
  });

  testWidgets('nested cell hit retains link and comment from its source run', (
    tester,
  ) async {
    const link = WmlHyperlink(url: 'https://example.com/source');
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(text: 'Linked comment', hyperlink: link, commentIds: [7]),
      ],
    );
    final inner = WmlTable(
      grid: [90, 90],
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(blocks: [_paragraph('Other cell')]),
            WmlTableCell(blocks: [paragraph]),
          ],
        ),
      ],
    );
    final outer = WmlTable(
      grid: [240],
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(blocks: [inner]),
          ],
        ),
      ],
    );
    final document = WmlDocument(
      sections: [
        _section([outer]),
      ],
      comments: [WmlComment(id: 7, text: 'Review this source.')],
    );
    final caret = CaretEngine()
      ..paragraphIndex = document.paragraphs.toList().indexOf(paragraph)
      ..logicalIndex = 3;
    final canvas = await _mount(tester, document, caret);
    final hit = canvas.contextHitForCaret()!;
    expect(hit.kind, OfficeContextKind.table);
    expect(hit.paragraph, same(paragraph));
    expect(hit.table, same(inner));
    expect(hit.tableRow, 0);
    expect(hit.tableCol, 1);
    expect(hit.link, same(link));
    expect(hit.commentId, 7);
  });

  testWidgets('context metadata follows the caret, without stale selection', (
    tester,
  ) async {
    const link = WmlHyperlink(url: 'https://example.com/source');
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(text: 'Link', hyperlink: link),
        WmlRun(text: ' comment', commentIds: [7]),
        WmlRun(text: ' plain'),
      ],
    );
    final document = WmlDocument(
      sections: [
        _section([paragraph]),
      ],
      comments: [WmlComment(id: 7, text: 'Review this source.')],
    );
    final caret = CaretEngine()..logicalIndex = 2;
    final canvas = await _mount(tester, document, caret, selectedCommentId: 7);
    final linked = canvas.contextHitForCaret()!;
    expect(linked.kind, OfficeContextKind.hyperlink);
    expect(linked.link, same(link));
    expect(linked.commentId, isNull);
    caret.logicalIndex = 6;
    final commented = canvas.contextHitForCaret(proofingOffset: 0)!;
    expect(commented.kind, OfficeContextKind.comment);
    expect(commented.link, isNull);
    expect(commented.commentId, 7);
    caret.logicalIndex = paragraph.text.length;
    final plain = canvas.contextHitForCaret()!;
    expect(plain.kind, OfficeContextKind.document);
    expect(plain.link, isNull);
    expect(plain.commentId, isNull);
  });

  testWidgets(
    'invalid indices and detached source do not target another paragraph',
    (tester) async {
      final paragraph = _paragraph('Source');
      final document = WmlDocument(
        sections: [
          _section([paragraph]),
        ],
      );
      final caret = CaretEngine();
      final canvas = await _mount(tester, document, caret);
      for (final index in [-1, 1, 200]) {
        caret.paragraphIndex = index;
        expect(canvas.contextHitForCaret(), isNull);
      }
      caret.paragraphIndex = 0;
      for (final offset in [-1, paragraph.text.length + 1]) {
        caret.logicalIndex = offset;
        expect(canvas.contextHitForCaret(), isNull);
      }
      caret.logicalIndex = 0;
      expect(canvas.contextHitForCaret(proofingOffset: -1), isNull);
      expect(canvas.contextHitForCaret(proofingOffset: 99), isNull);
      document.sections.single.blocks[0] = _paragraph('Source');
      expect(canvas.contextHitForCaret(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(canvas.contextHitForCaret(), isNull);
    },
  );

  testWidgets('empty paragraphs need an identity-bound layout line for a hit', (
    tester,
  ) async {
    final paragraph = _paragraph('');
    final document = WmlDocument(
      sections: [
        _section([paragraph]),
      ],
    );
    final canvas = await _mount(tester, document, CaretEngine());
    // The current body layout omits blank paragraph lines. Do not invent an
    // anchor from a different paragraph when that visual geometry is absent.
    expect(canvas.contextHitForCaret(), isNull);
    canvas.laidOut.pages.single.lines.add(
      LaidOutLine(
        glyphs: [],
        x: 30,
        y: 60,
        width: 0,
        height: 14,
        pageIndex: 0,
        justification: WmlJustification.left,
        sourceParagraph: paragraph,
      ),
    );
    final hit = canvas.contextHitForCaret()!;
    expect(hit.paragraph, same(paragraph));
    expect(hit.proofingOffset, 0);
    canvas.laidOut = LaidOutDocument(
      pages: [],
      pageSize: document.sections.single.pageSize,
    );
    expect(canvas.contextHitForCaret(), isNull);
  });
}
