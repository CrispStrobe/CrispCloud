import 'dart:io';
import 'dart:typed_data';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  // Required shipped assets, not optional OS fonts or mocks.
  final sans = _font('LiberationSans-Regular');
  final bold = _font('LiberationSans-Bold');
  final italic = _font('LiberationSans-Italic');
  final boldItalic = _font('LiberationSans-BoldItalic');
  final serif = _font('LiberationSerif-Regular');
  final serifItalic = _font('LiberationSerif-Italic');
  final arabic = _font('NotoNaskhArabic-Regular');
  OfficeFontSet set([OfficeFontDiagnostics? diagnostics]) => OfficeFontSet(
    defaultFamily: 'Liberation Sans',
    diagnostics: diagnostics,
    faces: [
      OfficeFontFace(font: sans, family: 'Liberation Sans', aliases: ['Arial']),
      OfficeFontFace(
        font: bold,
        family: 'Liberation Sans',
        weight: 700,
        aliases: ['Arial'],
      ),
      OfficeFontFace(
        font: italic,
        family: 'Liberation Sans',
        italic: true,
        aliases: ['Arial'],
      ),
      OfficeFontFace(
        font: boldItalic,
        family: 'Liberation Sans',
        weight: 700,
        italic: true,
        aliases: ['Arial'],
      ),
      OfficeFontFace(
        font: serif,
        family: 'Liberation Serif',
        aliases: ['Times New Roman'],
      ),
      OfficeFontFace(
        font: serifItalic,
        family: 'Liberation Serif',
        italic: true,
        aliases: ['Times New Roman'],
      ),
      OfficeFontFace(font: arabic, family: 'Noto Naskh Arabic'),
    ],
  );
  test('family aliases resolve real regular, bold and italic cuts', () {
    final fonts = set();
    expect(fonts.faceFor(0x57, family: 'Arial'), same(sans));
    expect(fonts.faceFor(0x57, family: 'arial', weight: 700), same(bold));
    expect(fonts.faceFor(0x57, family: 'Arial', italic: true), same(italic));
    expect(
      fonts.faceFor(0x57, family: 'Arial', weight: 700, italic: true),
      same(boldItalic),
    );
    expect(fonts.faceFor(0x57, family: 'Times New Roman'), same(serif));
    expect(fonts.faceFor(0x57, family: 'Unavailable', weight: 700), same(bold));
    expect(
      OfficeFontSet(primary: serif, fallbacks: [sans]).faceFor(0x57),
      same(serif),
    );
  });
  test('Hebrew and Arabic use covering faces; absent Unicode is explicit', () {
    final fonts = set();
    expect(fonts.faceFor(0x05D0, family: 'Arial'), same(sans));
    expect(fonts.faceFor(0x0645, family: 'Arial'), same(arabic));
    expect(fonts.faceFor(0x10FFFF, family: 'Arial'), isNull);
  });
  test('Word measures each run before wrapping with real face and size', () {
    final properties = [
      WmlRunProps(asciiFont: 'Arial', fontSizeHalfPoints: 20),
      WmlRunProps(asciiFont: 'Times New Roman', fontSizeHalfPoints: 28),
      WmlRunProps(asciiFont: 'Arial', bold: true, fontSizeHalfPoints: 40),
      WmlRunProps(asciiFont: 'Arial', italic: true, fontSizeHalfPoints: 24),
    ];
    final expected = [sans, serif, bold, italic];
    final doc = _doc([
      for (final props in properties) WmlRun(text: 'W', properties: props),
    ]);
    final glyphs = WordLayoutEngine(
      font: sans,
      fonts: set(),
    ).layout(doc).pages.single.lines.single.glyphs;
    expect(glyphs, hasLength(4));
    for (var i = 0; i < glyphs.length; i++) {
      final advance = FontMetrics(
        font: expected[i],
        fontSizePoints: properties[i].fontSizePoints,
      ).characterWidth(0x57);
      expect(glyphs[i].advance, closeTo(advance, 1e-8));
      expect(
        glyphs[i].glyph.advance,
        closeTo(advance, 1e-8),
        reason: 'Wrapping and painting must share advances',
      );
      expect(glyphs[i].glyph.glyphId, expected[i].glyphIdFor(0x57));
      expect(glyphs[i].fontFamily, properties[i].asciiFont);
      if (i > 0) {
        expect(
          glyphs[i].x,
          closeTo(glyphs[i - 1].x + glyphs[i - 1].advance, 1e-8),
        );
      }
    }
    final narrow = _doc([
      WmlRun(text: 'a ', properties: WmlRunProps(fontSizeHalfPoints: 16)),
      WmlRun(
        text: 'WW WW WW',
        properties: WmlRunProps(
          asciiFont: 'Times New Roman',
          fontSizeHalfPoints: 40,
        ),
      ),
    ], width: 80);
    final lines = WordLayoutEngine(
      font: sans,
      fonts: set(),
    ).layout(narrow).pages.expand((p) => p.lines).toList();
    expect(lines.length, greaterThan(1));
    for (final line in lines) {
      expect(
        line.glyphs.last.x + line.glyphs.last.advance - line.x,
        lessThanOrEqualTo(80.001),
      );
    }
  });
  test('PDF embeds requested outlines without double bold or slant', () {
    final props = [
      WmlRunProps(asciiFont: 'Arial'),
      WmlRunProps(asciiFont: 'Times New Roman'),
      WmlRunProps(asciiFont: 'Arial', bold: true),
      WmlRunProps(asciiFont: 'Arial', italic: true),
      WmlRunProps(asciiFont: 'Arial', bold: true, italic: true),
    ];
    final doc = _doc([for (final p in props) WmlRun(text: 'W', properties: p)]);
    final pdf = PdfFile.open(OfficePdfExport.word(doc, fonts: set()));
    final painted = pdf.displayList(0).ops.whereType<PdfDrawText>().toList();
    expect(painted, hasLength(5), reason: 'Real bold outlines need one pass');
    final expected = [sans, serif, bold, italic, boldItalic];
    for (var i = 0; i < painted.length; i++) {
      expect(painted[i].fontBytes, isNotNull);
      final embedded = SfntFont.parse(painted[i].fontBytes!);
      expect(_outline(embedded, 0x57), _outline(expected[i], 0x57));
      expect(
        painted[i].italic,
        isFalse,
        reason: 'Real italic is not sheared again',
      );
    }
    expect(props.map((p) => p.asciiFont), [
      'Arial',
      'Times New Roman',
      'Arial',
      'Arial',
      'Arial',
    ]);
    expect(PdfExtract.pageText(pdf, 0), 'WWWWW');
  });
  test(
    'only painted substitutions are diagnosed and missing text draws boxes',
    () {
      final diagnostics = OfficeFontDiagnostics();
      final fonts = set(diagnostics);
      fonts.resolve(0x57, family: 'Probe only');
      expect(diagnostics.substitutions, isEmpty);
      final doc = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlParagraph(
                inlines: [
                  WmlRun(
                    text: 'A\u{10FFFF}Z',
                    properties: WmlRunProps(asciiFont: 'Missing family'),
                  ),
                ],
              ),
              WmlParagraph(
                properties: WmlParagraphProps(pageBreakBefore: true),
                inlines: [
                  WmlRun(
                    text: 'Hidden',
                    properties: WmlRunProps(asciiFont: 'Unpainted family'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final pdf = PdfFile.open(
        OfficePdfExport.word(doc, fonts: fonts, pageTo: 1),
      );
      expect(diagnostics.missingCodePoints, {0x10FFFF});
      expect(diagnostics.substitutions, [
        const OfficeFontSubstitution('Missing family', 'Liberation Sans'),
      ]);
      expect(pdf.displayList(0).ops.whereType<PdfStrokePath>(), isNotEmpty);
      expect(PdfExtract.pageText(pdf, 0), contains('A'));
      expect(PdfExtract.pageText(pdf, 0), contains('Z'));
    },
  );
  test('diagnostics bound hostile names and code point collections', () {
    final d = OfficeFontDiagnostics();
    for (var i = 0; i < 400; i++) {
      d.reportMissing(0x1000 + i);
      d.reportSubstitution('Font $i${'x' * 300}', 'Fallback');
    }
    expect(d.missingCodePoints, hasLength(256));
    expect(d.substitutions, hasLength(128));
    expect(d.substitutions.first.requestedFamily.length, 256);
    expect(d.truncated, isTrue);
  });
  test(
    'spreadsheet PDF reads retained native family and italic without edits',
    () {
      final styles = SmlStyleSheet.parse(
        '''
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="1"><font><name val="Times New Roman"/><sz val="11"/><i/></font></fonts>
<fills count="1"><fill><patternFill patternType="none"/></fill></fills>
<cellXfs count="1"><xf fontId="0" fillId="0" numFmtId="0"/></cellXfs></styleSheet>''',
      );
      expect(styles.familyAt(0), 'Times New Roman');
      expect(styles.italicAt(0), isTrue);
      final before = styles.toXml();
      final sheet = SmlWorksheet(name: 'Sheet', sheetId: 1);
      sheet.cellA1('A1').value = 'W';
      final pdf = PdfFile.open(
        OfficePdfExport.workbook(
          SmlWorkbook(sheets: [sheet], styles: styles),
          fonts: set(),
          options: const PdfSheetPrintOptions(showHeadings: false),
        ),
      );
      final painted = pdf
          .displayList(0)
          .ops
          .whereType<PdfDrawText>()
          .singleWhere((op) => op.text == 'W');
      expect(
        _outline(SfntFont.parse(painted.fontBytes!), 0x57),
        _outline(serifItalic, 0x57),
      );
      expect(styles.toXml(), before);
    },
  );
  test('mixed Hebrew and Arabic PDF uses covering embedded glyphs', () {
    final d = OfficeFontDiagnostics();
    final pdf = PdfFile.open(
      OfficePdfExport.word(
        _doc([
          WmlRun(
            text: 'A שלום مرحبا',
            properties: WmlRunProps(asciiFont: 'Arial', csFont: 'Arial'),
          ),
        ]),
        fonts: set(d),
      ),
    );
    final painted = pdf.displayList(0).ops.whereType<PdfDrawText>().toList();
    expect(painted.every((op) => op.fontBytes != null), isTrue);
    expect(
      painted.map((op) => SfntFont.parse(op.fontBytes!).familyName).toSet(),
      containsAll(['Liberation Sans', 'Noto Naskh Arabic']),
    );
    expect(d.missingCodePoints, isEmpty);
  });
}

SfntFont _font(String name) => SfntFont.parse(
  File('../quds_office_editor/fonts/$name.ttf').readAsBytesSync(),
);
Uint8List _outline(SfntFont font, int cp) {
  final gid = font.glyphIdFor(cp);
  return Uint8List.sublistView(
    font.tableBytes('glyf'),
    font.glyphOffsets[gid],
    font.glyphOffsets[gid + 1],
  );
}

WmlDocument _doc(List<WmlInline> runs, {double width = 460}) => WmlDocument(
  sections: [
    WmlSection(
      pageSize: WmlPageSize(width: width + 40, height: 700),
      margins: const WmlPageMargins(left: 20, right: 20, top: 20, bottom: 20),
      blocks: [WmlParagraph(inlines: runs)],
    ),
  ],
);
