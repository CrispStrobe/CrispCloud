import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlParagraph _paragraph(String text) => WmlParagraph(
  properties: WmlParagraphProps(spacingAfter: 0, lineSpacing: 1),
  inlines: [WmlRun(text: text)],
);

WmlFrame _frame(
  WmlFrameWrap wrap, {
  double x = 0,
  double width = 100,
  double height = 72,
}) => WmlFrame(
  x: x,
  y: 0,
  width: width,
  height: height,
  anchor: WmlFrameAnchor.margin,
  wrap: wrap,
  blocks: [_paragraph('Frame')],
);

WmlDocument _document(
  List<WmlBlock> blocks, {
  int columns = 1,
  double height = 280,
}) => WmlDocument(
  sections: [
    WmlSection(
      pageSize: WmlPageSize(width: 360, height: height),
      margins: const WmlPageMargins(left: 24, right: 24, top: 24, bottom: 24),
      columnCount: columns,
      columnSpace: 16,
      blocks: blocks,
    ),
  ],
);

const _body =
    'Alpha beta gamma delta epsilon zeta eta theta iota kappa '
    'lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega. '
    'Another sentence leaves the frame behind and returns to full width. '
    'The text must retain every source character through changing line widths.';

List<LaidOutLine> _lines(LaidOutDocument laid, int paragraph) => laid.pages
    .expand((p) => p.lines)
    .where((l) => l.paragraphIndex == paragraph)
    .toList();

void _expectNoLostText(List<LaidOutLine> lines, String text) {
  final indices =
      lines
          .expand((l) => l.glyphs)
          .where((g) => !g.glyph.isSpace)
          .map((g) => g.glyph.logicalIndex)
          .toList()
        ..sort();
  final expected = <int>[];
  var offset = 0;
  for (final cp in text.runes) {
    if (cp != 32 && cp != 10 && cp != 13) expected.add(offset);
    offset += cp > 0xffff ? 2 : 1;
  }
  expect(indices, expected, reason: 'Each original nonspace appears once');
}

void main() {
  test('square frames exclude nearby lines then restore full body width', () {
    final doc = _document([_frame(WmlFrameWrap.square), _paragraph(_body)]);
    final laid = WordLayoutEngine(font: null).layout(doc);
    final lines = _lines(laid, 1);
    expect(lines.first.x, 124);
    expect(lines.first.y, 24);
    expect(lines.where((l) => l.y < 96).every((l) => l.x >= 124), isTrue);
    expect(lines.any((l) => l.y >= 96 && l.x == 24), isTrue);
    _expectNoLostText(lines, _body);
  });

  for (final wrap in WmlFrameWrap.values) {
    test('$wrap keeps its distinct native and layout meaning', () async {
      final source = OpcPackage.create(OpcPackageKind.word);
      source
          .getPart('/word/document.xml')!
          .writeText(
            File(
              'test/fixtures/fidelity/frame_wrap_source.xml',
            ).readAsStringSync(),
          );
      var doc = WordDeserializer().read(source);
      doc.sections.single.blocks.whereType<WmlFrame>().single.wrap = wrap;
      for (var cycle = 0; cycle < 4; cycle++) {
        final lines = _lines(WordLayoutEngine(font: null).layout(doc), 1);
        expect(lines.first.x, wrap == WmlFrameWrap.square ? 124 : 24);
        expect(lines.first.y, wrap == WmlFrameWrap.topBottom ? 96 : 24);
        _expectNoLostText(lines, _body);
        if (cycle == 3) break;
        final package = OpcPackage.openBytes(await OfficeIsolateSave.word(doc));
        final directory = Directory('build/fidelity-frame-wrap')
          ..createSync(recursive: true);
        File(
          '${directory.path}/${wrap.name}-${cycle + 1}.docx',
        ).writeAsBytesSync(package.save());
        final xml = package.getPart('/word/document.xml')!.readText();
        expect(
          xml,
          contains(switch (wrap) {
            WmlFrameWrap.none => '<wp:wrapNone',
            WmlFrameWrap.square => '<wp:wrapSquare',
            WmlFrameWrap.topBottom => '<wp:wrapTopAndBottom',
          }),
        );
        if (wrap == WmlFrameWrap.topBottom) {
          expect(xml, contains('type="topAndBottom"'));
        }
        doc = WordDeserializer().read(package);
        expect(
          doc.sections.single.blocks.whereType<WmlFrame>().single.wrap,
          wrap,
        );
      }
    });
  }

  test(
    'several exclusions choose a free interval and keep Unicode offsets',
    () {
      const text =
          'One 😀 two\r\n\r\nthree 🧭 four five six seven eight nine ten.';
      final doc = _document([
        _frame(WmlFrameWrap.square, width: 72),
        _frame(WmlFrameWrap.square, x: 230, width: 82),
        _paragraph(text),
      ]);
      final lines = _lines(WordLayoutEngine(font: null).layout(doc), 2);
      expect(lines.first.x, 96);
      for (final line in lines.where((l) => l.y < 96)) {
        expect(line.x, greaterThanOrEqualTo(96));
        expect(line.x + line.width, lessThanOrEqualTo(254.01));
      }
      expect(lines.where((l) => l.glyphs.isEmpty), hasLength(1));
      _expectNoLostText(lines, text);
    },
  );

  test('a frame in another column does not exclude this column', () {
    final doc = _document([
      _frame(WmlFrameWrap.topBottom, x: 164),
      _paragraph('Body remains here'),
    ], columns: 2);
    final line = _lines(WordLayoutEngine(font: null).layout(doc), 1).first;
    expect(line.x, 24);
    expect(line.y, 24);
  });

  test(
    'full-column exclusion advances and does not leak into the next page',
    () {
      final text = List.filled(8, _body).join(' ');
      final doc = _document([
        _frame(WmlFrameWrap.square, width: 312, height: 235),
        _paragraph(text),
      ]);
      final laid = WordLayoutEngine(font: null).layout(doc);
      final lines = _lines(laid, 1);
      expect(lines.first.pageIndex, 1);
      expect(lines.first.y, 24);
      expect(lines.first.x, 24);
      _expectNoLostText(lines, text);
    },
  );

  test('unbreakable words clear a frame before using full-width overflow', () {
    final doc = _document([
      _frame(WmlFrameWrap.square, width: 280),
      _paragraph('UnbreakableWordAndAnotherWord'),
    ]);
    final line = _lines(WordLayoutEngine(font: null).layout(doc), 1).single;
    expect(line.y, 96);
    expect(line.x, 24);
  });

  test('TOCs use the same exclusions as following body paragraphs', () {
    final heading = _paragraph('Chapter');
    WordToc.applyHeading(heading, 1);
    final toc = WmlToc();
    final doc = _document([_frame(WmlFrameWrap.topBottom), toc, heading]);
    WordToc.refresh(toc, doc);
    final lines = _lines(WordLayoutEngine(font: null).layout(doc), 1);
    expect(lines.first.y, greaterThanOrEqualTo(96));
  });

  test(
    'RTL flow chooses the right equal-width band without losing offsets',
    () {
      const text = 'مرحبا بالعالم وهذه فقرة لاختبار التفاف النص 123 نهاية';
      final paragraph = _paragraph(text)..properties.rightToLeft = true;
      final doc = _document([_frame(WmlFrameWrap.square, x: 106), paragraph]);
      final lines = _lines(WordLayoutEngine(font: null).layout(doc), 1);
      expect(lines.first.x, 230);
      _expectNoLostText(lines, text);
    },
  );

  test('note reservation retries the wrapped line on its new page', () {
    final paragraph = _paragraph(_body);
    final doc = _document([
      _frame(WmlFrameWrap.square, height: 220),
      paragraph,
    ]);
    WordNotes.insert(
      doc,
      paragraph,
      endnote: false,
      text: 'Footnote stays with its marker',
    );
    final laid = WordLayoutEngine(font: null).layout(doc);
    final lines = _lines(laid, 1);
    final marker = lines.singleWhere(
      (line) =>
          line.glyphs.any((glyph) => glyph.glyph.logicalIndex == _body.length),
    );
    final notePage = laid.pages.singleWhere(
      (page) => page.notes.any((line) => line.text.contains('Footnote stays')),
    );
    expect(marker.pageIndex, notePage.index);
    expect(marker.pageIndex, 1);
    expect(marker.x, 24);
    _expectNoLostText(lines, paragraph.text);
  });
}
