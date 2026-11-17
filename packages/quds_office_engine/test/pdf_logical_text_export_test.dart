import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/pdf_alias_fixture.dart';

final _renderOutput = Platform.environment['QUDS_LOGICAL_RENDER_OUTPUT'] ?? '';

void main() {
  final latin = _font('LiberationSans-Regular');
  final arabic = _font('NotoNaskhArabic-Regular');
  final fonts = OfficeFontSet(primary: latin, fallbacks: [arabic]);

  for (final text in [
    'مرحبا',
    'لا لَا لأ لإ لآ',
    'English (مرحبا 123) end',
    '\ufefb لا \ufef7 لأ',
    '\u2067مرحبا (ABC)\u2069',
  ]) {
    test('Word PDF retains logical source ${_scalars(text)}', () {
      final bytes = OfficePdfExport.word(
        WmlDocument.empty(text: text),
        fonts: fonts,
      );
      final file = PdfFile.open(bytes);
      expect(PdfExtract.pageText(file, 0), text);
      expect(
        OfficeFind.inPdf(file, OfficeFindOptions(query: text)),
        hasLength(1),
      );
      _expectUnchangedPainting(
        file,
        fixture: text.startsWith('English') ? 'word-logical-source' : null,
      );
    });
  }

  test('worksheet PDF retains logical Arabic and mixed bidi text', () {
    const text = 'Report (مرحبا لا) 123';
    final book = SmlWorkbook();
    book.firstSheet.cellA1('A1').value = text;
    final file = PdfFile.open(OfficePdfExport.workbook(book, fonts: fonts));
    expect(PdfExtract.pageText(file, 0), contains(text));
    _expectUnchangedPainting(file, fixture: 'worksheet-logical-source');
  });

  test('presentation PDF retains logical Arabic and mixed bidi text', () {
    const text = 'Report (مرحبا لا) 123';
    final file = PdfFile.open(
      OfficePdfExport.presentation(_deck(text), fonts: fonts),
    );
    expect(PdfExtract.pageText(file, 0), text);
    _expectUnchangedPainting(file);
  });

  test(
    'rotated presentation preserves source without repainting replacements',
    () {
      const text = 'Rotated (مرحبا لا) 123';
      final file = PdfFile.open(
        OfficePdfExport.presentation(
          _deck(text, rotation: 30 * 60000),
          fonts: fonts,
        ),
      );
      expect(PdfExtract.pageText(file, 0), text);
      expect(
        file
            .displayList(0)
            .ops
            .whereType<PdfDrawText>()
            .any((op) => op.angle.abs() > 0.1),
        isTrue,
      );
      _expectUnchangedPainting(file, fixture: 'rotated-slide-logical-source');
    },
  );

  test('wrapped Word lines retain source order and separating spaces', () {
    const text = 'مرحبا لا مرحبا لا مرحبا لا مرحبا';
    final document = _narrowWord(text);
    final laid = WordLayoutEngine(font: latin, fonts: fonts).layout(document);
    expect(laid.pages.expand((page) => page.lines).length, greaterThan(1));
    final file = PdfFile.open(
      OfficePdfExport.word(document, fonts: fonts, laidOut: laid),
    );
    expect(PdfExtract.documentText(file).replaceAll('\n', ''), text);
    _expectUnchangedPainting(file);
  });

  test('wrapped worksheet lines retain source separators', () {
    const text = 'قبل before لا after بعد';
    final book = SmlWorkbook();
    book.firstSheet.cellA1('A1').value = text;
    final file = PdfFile.open(OfficePdfExport.workbook(book, fonts: fonts));
    expect(PdfExtract.pageText(file, 0), contains(text));
    _expectUnchangedPainting(file);
  });

  test('wrapped presentation lines retain source separators', () {
    const text = 'قبل before لا after بعد';
    final file = PdfFile.open(
      OfficePdfExport.presentation(_deck(text, width: 1400000), fonts: fonts),
    );
    final lines = file
        .displayList(0)
        .ops
        .whereType<PdfDrawText>()
        .map((op) => op.y)
        .toSet();
    expect(lines.length, greaterThan(1));
    expect(PdfExtract.pageText(file, 0), text);
    _expectUnchangedPainting(file);
  });

  test('sparse Word lines never borrow unpainted visible source', () {
    const text = 'مUNRELATEDب';
    final document = WmlDocument.empty(text: text);
    final laid = WordLayoutEngine(font: latin, fonts: fonts).layout(document);
    final line = laid.pages.single.lines.single;
    line.glyphs.removeWhere(
      (glyph) =>
          glyph.glyph.logicalIndex > 0 &&
          glyph.glyph.logicalIndex < text.length - 1,
    );
    final file = PdfFile.open(
      OfficePdfExport.word(document, fonts: fonts, laidOut: laid),
    );
    expect(PdfExtract.pageText(file, 0), 'مب');
    expect(PdfExtract.pageText(file, 0), isNot(contains('UNRELATED')));
    _expectUnchangedPainting(file);
  });

  test('omitted controls and unselected soft hyphens retain owned source', () {
    final text = 'A${'\u200e' * 12}B\u00adC\u2060D';
    final file = PdfFile.open(
      OfficePdfExport.word(WmlDocument.empty(text: text), fonts: fonts),
    );
    expect(PdfExtract.pageText(file, 0), text);
    _expectUnchangedPainting(file);
  });

  test(
    'mixed bidi source preserves supplementary Unicode without splitting',
    () {
      const text = 'A\u{1f600} (مرحبا لا) \u{20000}Z';
      final aliases = OfficeFontSet(
        primary: withSharedGlyphAliases(latin),
        fallbacks: [arabic],
      );
      final file = PdfFile.open(
        OfficePdfExport.word(WmlDocument.empty(text: text), fonts: aliases),
      );
      expect(PdfExtract.pageText(file, 0), text);
      for (final query in ['\u{1f600}', '\u{20000}', 'مرحبا لا']) {
        expect(
          OfficeFind.inPdf(file, OfficeFindOptions(query: query)),
          hasLength(1),
        );
      }
      _expectUnchangedPainting(file);
    },
  );

  test('mixed small-cap displays and Arabic retain the same authored line', () {
    const text = 'Straße ﬃ (مرحبا لا)';
    final document = WmlDocument.empty(text: text);
    document.paragraphs.single.inlines.whereType<WmlRun>().single.properties =
        WmlRunProps(smallCaps: true);
    final file = PdfFile.open(OfficePdfExport.word(document, fonts: fonts));
    expect(PdfExtract.pageText(file, 0), text);
    final painted = file
        .displayList(0)
        .ops
        .whereType<PdfDrawText>()
        .map((op) => op.text)
        .join();
    expect(painted, contains('STRASSE'));
    expect(painted, contains('FFI'));
    _expectUnchangedPainting(file);
  });

  test('explicit soft hyphens copy once across wrapped Word lines', () {
    const text = 'con\u00adten\u00adta\u00adtion';
    final document = _narrowWord(text);
    document.paragraphs.single.inlines.whereType<WmlRun>().single.properties =
        WmlRunProps(fontSizeHalfPoints: 40);
    final laid = WordLayoutEngine(font: latin, fonts: fonts).layout(document);
    expect(
      laid.pages
          .expand((p) => p.lines)
          .expand((l) => l.glyphs)
          .any((g) => g.glyph.isDiscretionaryHyphen),
      isTrue,
    );
    final file = PdfFile.open(
      OfficePdfExport.word(document, fonts: fonts, laidOut: laid),
    );
    expect(PdfExtract.documentText(file).replaceAll('\n', ''), text);
    _expectUnchangedPainting(file);
  });

  test(
    'Word table, header, footer and generated note label keep logical text',
    () {
      final document = WmlDocument.empty(text: 'متن');
      final paragraph = document.paragraphs.single;
      paragraph.inlines.add(
        WmlRun(
          text: '42',
          noteRefId: 42,
          properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
        ),
      );
      document.footnotes.add(
        WmlNote(
          id: 42,
          endnote: false,
          paragraphs: [
            WmlParagraph(inlines: [WmlRun(text: 'حاشية لا')]),
          ],
        ),
      );
      final section = document.sections.single;
      section.header.add(WmlParagraph(inlines: [WmlRun(text: 'عنوان لا')]));
      section.footer.add(WmlParagraph(inlines: [WmlRun(text: 'تذييل لا')]));
      section.blocks.add(
        WmlTable(
          grid: [160],
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(
                  blocks: [
                    WmlParagraph(inlines: [WmlRun(text: 'خلية لا')]),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      final file = PdfFile.open(OfficePdfExport.word(document, fonts: fonts));
      final text = PdfExtract.documentText(file);
      for (final expected in [
        'متن1',
        'حاشية لا',
        'عنوان لا',
        'تذييل لا',
        'خلية لا',
      ]) {
        expect(text, contains(expected));
      }
      expect(text, isNot(contains('42')));
      _expectUnchangedPainting(file);
    },
  );
}

SfntFont _font(String name) => SfntFont.parse(
  File('../quds_office_editor/fonts/$name.ttf').readAsBytesSync(),
);

String _scalars(String text) =>
    text.runes.map((cp) => cp.toRadixString(16)).join(' ');

WmlDocument _narrowWord(String text) {
  final document = WmlDocument.empty(text: text);
  document.sections.single.pageSize = const WmlPageSize(width: 92, height: 300);
  document.sections.single.margins = const WmlPageMargins(
    left: 10,
    right: 10,
    top: 10,
    bottom: 10,
  );
  return document;
}

PmlPresentation _deck(String text, {int rotation = 0, int width = 6000000}) =>
    PmlPresentation(
      slides: [
        PmlSlide(
          id: 256,
          shapes: [
            PmlShape(
              id: 2,
              name: 'Logical text',
              text: text,
              fontSizePt: 16,
              transform: PmlTransform(
                x: 200000,
                y: 200000,
                cx: width,
                cy: 2400000,
                rot: rotation,
              ),
            ),
          ],
        ),
      ],
    );

void _expectUnchangedPainting(PdfFile file, {String? fixture}) {
  final expected = _paintedText(file);
  expect(expected, isNotEmpty);
  final originalText = PdfExtract.documentText(file);
  final strippedContents = <Uint8List>[];
  for (var page = 0; page < file.pageCount; page++) {
    final dict = file.pageRec(page).dict;
    final bytes = PdfPageIo.pageContent(file.store, dict);
    final plain = latin1
        .decode(bytes)
        .replaceAll(
          RegExp(r'/Span << /ActualText <[0-9A-Fa-f]*> >> BDC\s*'),
          '',
        )
        .replaceAll(RegExp(r'\bEMC\s*'), '');
    final raw = Uint8List.fromList(latin1.encode(plain));
    strippedContents.add(raw);
    file.pageRec(page).pendingContent = raw;
  }
  // Grafting writes each replacement as an indirect content stream and keeps
  // its page resources. An inline PdfCosStream in /Contents is not valid PDF;
  // incremental annotation saving does not allocate existing-page streams.
  final controlBytes = file.extractPages([
    for (var page = 0; page < file.pageCount; page++) page,
  ]);
  final control = PdfFile.open(controlBytes);
  expect(control.pageCount, file.pageCount);
  for (var page = 0; page < file.pageCount; page++) {
    final originalPage = file.pageAt(page);
    final controlPage = control.pageAt(page);
    expect(
      (controlPage.width, controlPage.height, controlPage.rotate),
      (originalPage.width, originalPage.height, originalPage.rotate),
    );
    final contents = control.pageDict(page)['Contents'];
    expect(contents, isA<PdfCosRef>());
    expect(control.store.deref(contents), isA<PdfCosStream>());
    expect(
      control.store.streamBytes(contents),
      orderedEquals(strippedContents[page]),
    );
  }
  expect(_paintedText(control), expected);
  if (_renderOutput.isNotEmpty && fixture != null) {
    Directory(_renderOutput).createSync(recursive: true);
    File('$_renderOutput/$fixture.pdf').writeAsBytesSync(file.originalBytes);
    File(
      '$_renderOutput/$fixture-paint-control.pdf',
    ).writeAsBytesSync(controlBytes);
    File('$_renderOutput/$fixture-source.txt').writeAsStringSync(originalText);
  }
}

List<(String, double, double, double, double, String, bool, bool)> _paintedText(
  PdfFile file,
) => [
  for (var page = 0; page < file.pageCount; page++)
    for (final op in file.displayList(page).ops.whereType<PdfDrawText>())
      (
        op.text,
        op.x,
        op.y,
        op.size,
        op.angle,
        op.fontFamily,
        op.italic,
        op.bold,
      ),
];
