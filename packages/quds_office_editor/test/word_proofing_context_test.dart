import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

OfficeProofingFinding _finding(WmlParagraph paragraph, int start, int end) =>
    OfficeProofingFinding.forRequest(
      OfficeProofingRequest(
        documentId: 'document',
        blockId: 'paragraph',
        revision: 1,
        text: paragraph.text,
      ),
      providerId: 'test',
      start: start,
      end: end,
      ruleId: 'spelling.test',
      message: 'Check this word.',
      category: OfficeProofingCategory.spelling,
    );

Future<({RenderWordCanvas render, List<OfficeContextHit> hits})> _canvas(
  WidgetTester tester,
  WmlDocument document,
  Map<WmlParagraph, List<OfficeProofingFinding>> findings,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1100);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final hits = <OfficeContextHit>[];
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 1100,
          height: 1050,
          child: WordCanvas(
            document: document,
            laidOut: WordLayoutEngine(font: null).layout(document),
            caret: CaretEngine(),
            config: const OfficeSurfaceConfig(showRulers: false),
            proofingFindings: findings,
            onContextMenu: hits.add,
          ),
        ),
      ),
    ),
  );
  return (
    render: tester.renderObject<RenderWordCanvas>(find.byType(WordCanvas)),
    hits: hits,
  );
}

Future<void> _rightClick(
  WidgetTester tester,
  RenderWordCanvas render,
  Offset pagePoint,
) async {
  final point = render.localToGlobal(render.windowForPagePoint(0, pagePoint));
  await tester.tapAt(point, buttons: kSecondaryMouseButton);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  testWidgets(
    'right half of final misspelled glyph keeps its context finding',
    (tester) async {
      final document = WmlDocument.empty(text: 'Ein Feler.');
      final paragraph = document.paragraphs.single;
      final issue = _finding(paragraph, 4, 9);
      final surface = await _canvas(tester, document, {
        paragraph: [issue],
      });
      final line = surface.render.laidOut.pages.single.lines.single;
      final last = line.glyphs.singleWhere((g) => g.glyph.logicalIndex == 8);
      await _rightClick(
        tester,
        surface.render,
        Offset(last.x + last.advance * .9, line.y + line.height / 2),
      );
      expect(surface.hits.single.paragraph, same(paragraph));
      expect(surface.hits.single.proofingOffset, issue.start);
      expect(surface.hits.single.kind, OfficeContextKind.document);
    },
  );

  testWidgets('neighboring whitespace does not borrow the next word finding', (
    tester,
  ) async {
    final document = WmlDocument.empty(text: 'Ein Feler.');
    final paragraph = document.paragraphs.single;
    final surface = await _canvas(tester, document, {
      paragraph: [_finding(paragraph, 4, 9)],
    });
    final line = surface.render.laidOut.pages.single.lines.single;
    final space = line.glyphs.singleWhere((g) => g.glyph.logicalIndex == 3);
    await _rightClick(
      tester,
      surface.render,
      Offset(space.x + space.advance * .9, line.y + line.height / 2),
    );
    expect(surface.hits.single.proofingOffset, isNull);
    expect(surface.hits.single.kind, OfficeContextKind.document);
  });

  for (final alignment in [WmlJustification.right, WmlJustification.center]) {
    testWidgets(
      '${alignment.name} header uses painted proportional text bounds',
      (tester) async {
        const source = '  😀 WWWWW Feler iii  ';
        final header = WmlParagraph(
          inlines: [WmlRun(text: source)],
          properties: WmlParagraphProps(justification: alignment),
        );
        final document = WmlDocument.empty(text: 'Body');
        document.sections.single.header.add(header);
        final start = source.indexOf('WWWWW');
        final issue = _finding(header, start, start + 5);
        final surface = await _canvas(tester, document, {
          header: [issue],
        });
        final line = surface.render.laidOut.pages.single.header.single;
        final text = line.overlayText!;
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: line.overlaySize,
              fontFamily: PaintRunText.familyFor(text: text),
              fontFamilyFallback: PaintRunText.fallbacksFor(text),
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final left = alignment == WmlJustification.right
            ? document.sections.single.pageSize.width -
                  document.sections.single.margins.right -
                  painter.width
            : (document.sections.single.pageSize.width - painter.width) / 2;
        final paintedWord = painter
            .getBoxesForSelection(
              TextSelection(
                baseOffset: text.indexOf('WWWWW'),
                extentOffset: text.indexOf('WWWWW') + 5,
              ),
            )
            .single;
        await _rightClick(
          tester,
          surface.render,
          Offset(
            left + paintedWord.left + .5,
            line.y + paintedWord.toRect().center.dy,
          ),
        );
        expect(surface.hits.single.paragraph, same(header));
        expect(surface.hits.single.proofingOffset, start);
      },
    );
  }

  testWidgets('stale source findings cannot supply a correction context', (
    tester,
  ) async {
    final document = WmlDocument.empty(text: 'Ein Feler.');
    final paragraph = document.paragraphs.single;
    final surface = await _canvas(tester, document, {
      paragraph: [_finding(paragraph, 4, 9)],
    });
    final line = surface.render.laidOut.pages.single.lines.single;
    final glyph = line.glyphs.singleWhere((g) => g.glyph.logicalIndex == 5);
    // A host-supplied stale map must not be enough to expose a source edit,
    // even before its next widget update supplies the refreshed map/layout.
    (paragraph.inlines.single as WmlRun).text = 'Ein Fehler.';
    await _rightClick(
      tester,
      surface.render,
      Offset(glyph.x + glyph.advance / 2, line.y + line.height / 2),
    );
    expect(surface.hits.single.proofingOffset, isNull);
  });

  testWidgets(
    'note labels stay generated and following text maps to original source',
    (tester) async {
      final body = WmlParagraph(
        inlines: [
          WmlRun(text: 'Before '),
          WmlRun(text: '999', noteRefId: 999),
          WmlRun(text: ' Feler'),
        ],
      );
      final noteText = WmlParagraph(inlines: [WmlRun(text: 'Feler')]);
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [body]),
        ],
        footnotes: [
          WmlNote(id: 999, endnote: false, paragraphs: [noteText]),
        ],
      );
      final surface = await _canvas(tester, document, {
        body: [_finding(body, 11, 16)],
        noteText: [_finding(noteText, 0, 5)],
      });
      final page = surface.render.laidOut.pages.single;
      final bodyLine = page.lines.single;
      final bodyLast = bodyLine.glyphs.last;
      await _rightClick(
        tester,
        surface.render,
        Offset(
          bodyLast.x + bodyLast.advance * .9,
          bodyLine.y + bodyLine.height / 2,
        ),
      );
      expect(surface.hits.last.paragraph, same(body));
      expect(surface.hits.last.proofingOffset, 11);

      final noteLine = page.notes.firstWhere(
        (l) => identical(l.sourceParagraph, noteText),
      );
      final label = noteLine.glyphs.first;
      expect(noteLine.proofingOffsetAt(label.glyph.logicalIndex), isNull);
      await _rightClick(
        tester,
        surface.render,
        Offset(label.x + label.advance / 2, noteLine.y + noteLine.height / 2),
      );
      expect(surface.hits.last.proofingOffset, isNull);

      final noteLast = noteLine.glyphs.last;
      await _rightClick(
        tester,
        surface.render,
        Offset(
          noteLast.x + noteLast.advance * .9,
          noteLine.y + noteLine.height / 2,
        ),
      );
      expect(surface.hits.last.paragraph, same(noteText));
      expect(surface.hits.last.proofingOffset, 0);
    },
  );
}
