import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const String _w = OfficeNamespaces.w;

const String _lorem =
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod '
    'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim '
    'veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea '
    'commodo consequat. Duis aute irure dolor in reprehenderit in voluptate '
    'velit esse cillum dolore eu fugiat nulla pariatur.';

const String _a4 =
    '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
    '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>'
    '</w:sectPr>';

WmlDocument _open(String body, {String? styles, String? numbering}) {
  final OpcPackage package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="$_w"><w:body>$body$_a4</w:body></w:document>',
      );
  if (styles != null) {
    package.createPart(
      '/word/styles.xml',
      OfficeContentTypes.wordStyles,
      utf8.encode('<w:styles xmlns:w="$_w">$styles</w:styles>'),
    );
  }
  if (numbering != null) {
    package.createPart(
      '/word/numbering.xml',
      OfficeContentTypes.wordNumbering,
      utf8.encode('<w:numbering xmlns:w="$_w">$numbering</w:numbering>'),
    );
  }
  return WordDeserializer().read(package);
}

List<LaidOutLine> _lines(LaidOutDocument laid, int paragraphIndex) =>
    <LaidOutLine>[
      for (final LaidOutPage page in laid.pages)
        for (final LaidOutLine line in page.lines)
          if (line.paragraphIndex == paragraphIndex) line,
    ];

const String _bulletNumbering =
    '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0">'
    '<w:numFmt w:val="bullet"/><w:lvlText w:val="•"/>'
    '<w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>'
    '</w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>';

void main() {
  group('Word body layout', () {
    test('body text uses fallbackWidthFactor, not the table-cell em', () {
      final WmlDocument doc = _open('<w:p><w:r><w:t>$_lorem</w:t></w:r></w:p>');
      final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
      final LaidOutGlyph o = _lines(
        laid,
        0,
      ).first.glyphs.firstWhere((LaidOutGlyph g) => g.glyph.codePoint == 0x6F);
      expect(o.advance, closeTo(11 * 0.5, 0.01));
    });

    test('paragraph indents are subtracted once', () {
      final WmlDocument doc = _open(
        '<w:p><w:pPr><w:ind w:left="1440" w:right="1440"/></w:pPr>'
        '<w:r><w:t>$_lorem $_lorem</w:t></w:r></w:p>',
      );
      final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
      final double column = doc.sections.first.contentWidth - 72 - 72;
      final double widest = _lines(laid, 0)
          .map((LaidOutLine l) => l.width)
          .reduce((double a, double b) => a > b ? a : b);
      expect(widest, lessThanOrEqualTo(column + 0.01));
      expect(widest, greaterThan(column - 40));
      expect(_lines(laid, 0).first.x, closeTo(72 + 72, 0.01));
    });

    test('a host measure drives the line breaks', () {
      final WmlDocument doc = _open('<w:p><w:r><w:t>$_lorem</w:t></w:r></w:p>');
      final List<int> asked = <int>[];
      final LaidOutDocument laid = WordLayoutEngine(
        font: null,
        measure: (int cp, double size, WmlRunProps props) {
          asked.add(cp);
          return size * 0.25;
        },
      ).layout(doc);
      final LaidOutGlyph o = _lines(
        laid,
        0,
      ).first.glyphs.firstWhere((LaidOutGlyph g) => g.glyph.codePoint == 0x6F);
      expect(o.advance, closeTo(11 * 0.25, 0.01));
      expect(asked, contains(0x6F));
      final LaidOutDocument fallback = WordLayoutEngine(font: null).layout(doc);
      expect(_lines(laid, 0).length, lessThan(_lines(fallback, 0).length));
    });

    test('table cells keep the wider em so text stays inside the border', () {
      final WmlDocument doc = _open(
        '<w:tbl><w:tblGrid><w:gridCol w:w="4000"/></w:tblGrid>'
        '<w:tr><w:tc><w:p><w:r><w:t>$_lorem</w:t></w:r></w:p></w:tc></w:tr>'
        '</w:tbl>',
      );
      final LaidOutDocument laid = WordLayoutEngine(font: null).layout(doc);
      final LaidOutGlyph o = _lines(
        laid,
        0,
      ).first.glyphs.firstWhere((LaidOutGlyph g) => g.glyph.codePoint == 0x6F);
      expect(o.advance, closeTo(11 * 0.72, 0.01));
    });
  });

  group('Word styles', () {
    const String listBullet =
        '<w:style w:type="paragraph" w:styleId="ListParagraph">'
        '<w:name w:val="List Paragraph"/>'
        '<w:pPr><w:ind w:left="720"/></w:pPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="ListBullet">'
        '<w:name w:val="List Bullet"/><w:basedOn w:val="ListParagraph"/>'
        '<w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr></w:style>';

    test('numbering defined in a paragraph style gives a list marker', () {
      final WmlDocument doc = _open(
        '<w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr>'
        '<w:r><w:t>Alpha</w:t></w:r></w:p>',
        styles: listBullet,
        numbering: _bulletNumbering,
      );
      final WmlParagraphProps props = doc.paragraphs.first.properties;
      expect(props.numId, 1);
      expect(props.listLabel, isNotNull);
      expect(props.indent.left, 36);
    });

    test('a direct numId 0 switches the style list off', () {
      final WmlDocument doc = _open(
        '<w:p><w:pPr><w:pStyle w:val="ListBullet"/>'
        '<w:numPr><w:numId w:val="0"/></w:numPr></w:pPr>'
        '<w:r><w:t>Plain</w:t></w:r></w:p>',
        styles: listBullet,
        numbering: _bulletNumbering,
      );
      expect(doc.paragraphs.first.properties.listLabel, isNull);
    });

    test('paragraph w:start / w:end indents are read', () {
      final WmlDocument doc = _open(
        '<w:p><w:pPr><w:ind w:start="720" w:end="360"/></w:pPr>'
        '<w:r><w:t>Indented</w:t></w:r></w:p>',
      );
      final WmlIndent indent = doc.paragraphs.first.properties.indent;
      expect(indent.left, 36);
      expect(indent.right, 18);
    });
  });

  group('Word table styles', () {
    const String tableStyles =
        '<w:style w:type="table" w:styleId="TableNormal">'
        '<w:name w:val="Normal Table"/></w:style>'
        '<w:style w:type="table" w:styleId="LightGrid-Accent1">'
        '<w:name w:val="Light Grid Accent 1"/><w:basedOn w:val="TableNormal"/>'
        '<w:tblPr><w:tblBorders>'
        '<w:top w:val="single" w:sz="8" w:color="4F81BD"/>'
        '<w:left w:val="single" w:sz="8" w:color="4F81BD"/>'
        '<w:insideH w:val="single" w:sz="8" w:color="4F81BD"/>'
        '</w:tblBorders></w:tblPr>'
        '<w:tblStylePr w:type="firstRow"><w:rPr><w:b/></w:rPr>'
        '<w:tcPr><w:shd w:val="clear" w:fill="DBE5F1"/></w:tcPr></w:tblStylePr>'
        '<w:tblStylePr w:type="band1Horz">'
        '<w:tcPr><w:shd w:val="clear" w:fill="EEF3FA"/></w:tcPr></w:tblStylePr>'
        '</w:style>'
        '<w:style w:type="table" w:styleId="PlainTable">'
        '<w:name w:val="Plain Table"/><w:tblPr><w:tblBorders>'
        '<w:top w:val="nil"/><w:insideH w:val="none"/>'
        '</w:tblBorders></w:tblPr></w:style>';

    String table(String style, {String extra = ''}) =>
        '<w:tbl><w:tblPr><w:tblStyle w:val="$style"/>'
        '<w:tblLook w:val="04A0"/>$extra</w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid>'
        '${'<w:tr><w:tc><w:p><w:r><w:t>x</w:t></w:r></w:p></w:tc></w:tr>' * 4}'
        '</w:tbl>';

    WmlTable only(WmlDocument doc) =>
        doc.sections.first.blocks.whereType<WmlTable>().single;

    test('borders and region shading come from the style', () {
      final WmlTable t = only(
        _open(table('LightGrid-Accent1'), styles: tableStyles),
      );
      expect(t.properties.borderColor, '4F81BD');
      expect(t.properties.borderWidth, 1.0);
      expect(t.properties.borders, isTrue);
      expect(
        <String?>[for (final WmlTableRow r in t.rows) r.cells.first.fillColor],
        <String?>['DBE5F1', 'EEF3FA', null, 'EEF3FA'],
      );
    });

    test('direct tblBorders win over the style', () {
      final WmlTable t = only(
        _open(
          table(
            'LightGrid-Accent1',
            extra:
                '<w:tblBorders><w:top w:val="single" w:sz="16" '
                'w:color="FF0000"/></w:tblBorders>',
          ),
          styles: tableStyles,
        ),
      );
      expect(t.properties.borderColor, 'FF0000');
      expect(t.properties.borderWidth, 2.0);
    });

    test('a style whose borders are all nil draws no borders', () {
      final WmlTable t = only(_open(table('PlainTable'), styles: tableStyles));
      expect(t.properties.borders, isFalse);
    });

    test('a style missing from styles.xml falls back to the id guess', () {
      final WmlTable t = only(_open(table('TableGrid'), styles: tableStyles));
      expect(t.properties.borderColor, '000000');
      expect(t.properties.borderWidth, 0.5);
    });
  });

  group('files saved by LibreOffice', () {
    // Writer ties every heading style to an outline list whose levels print
    // nothing (`numFmt="none"`, empty `lvlText`).
    const String outline =
        '<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0">'
        '<w:start w:val="1"/><w:numFmt w:val="none"/>'
        '<w:suff w:val="nothing"/><w:lvlText w:val=""/></w:lvl>'
        '</w:abstractNum><w:abstractNum w:abstractNumId="2">'
        '<w:lvl w:ilvl="0"><w:numFmt w:val="none"/>'
        '<w:lvlText w:val="Part %1"/></w:lvl></w:abstractNum>'
        '<w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num>'
        '<w:num w:numId="2"><w:abstractNumId w:val="2"/></w:num>';
    const String headingStyles =
        '<w:style w:type="paragraph" w:styleId="Heading">'
        '<w:name w:val="Heading"/><w:rPr><w:i/><w:color w:val="1F3864"/>'
        '</w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading1">'
        '<w:name w:val="heading 1"/><w:basedOn w:val="Heading"/>'
        '<w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>'
        '<w:outlineLvl w:val="0"/></w:pPr>'
        '<w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Quiet">'
        '<w:name w:val="Quiet"/><w:rPr><w:b w:val="false"/></w:rPr></w:style>';

    test('a "none" outline level adds no label', () {
      final WmlDocument doc = _open(
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
        '<w:r><w:t>1. Highlights</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/>'
        '</w:numPr></w:pPr><w:r><w:t>Intro</w:t></w:r></w:p>',
        styles: headingStyles,
        numbering: outline,
      );
      expect(doc.paragraphs.first.properties.listLabel, isNull);
      expect(doc.paragraphs.elementAt(1).properties.listLabel, 'Part ');
    });

    test('runs inherit bold, italic, and color from the style chain', () {
      final WmlRun run = _open(
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
        '<w:r><w:t>Title</w:t></w:r></w:p>',
        styles: headingStyles,
        numbering: outline,
      ).paragraphs.first.inlines.whereType<WmlRun>().first;
      expect(run.properties.bold, isTrue);
      expect(run.properties.italic, isTrue);
      expect(run.properties.color, '1F3864');
      expect(run.properties.fontSizePoints, 18);
    });

    test('a run that turns bold off keeps it off', () {
      final List<WmlRun> runs = _open(
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
        '<w:r><w:rPr><w:b w:val="0"/></w:rPr><w:t>plain</w:t></w:r>'
        '<w:r><w:rPr><w:b w:val="false"/><w:i w:val="off"/></w:rPr>'
        '<w:t>plainer</w:t></w:r></w:p>',
        styles: headingStyles,
        numbering: outline,
      ).paragraphs.first.inlines.whereType<WmlRun>().toList();
      expect(runs[0].properties.bold, isFalse);
      expect(runs[0].properties.italic, isTrue);
      expect(runs[1].properties.bold, isFalse);
      expect(runs[1].properties.italic, isFalse);
    });

    test('a style with w:b="false" is not bold', () {
      final WmlRun run = _open(
        '<w:p><w:pPr><w:pStyle w:val="Quiet"/></w:pPr>'
        '<w:r><w:t>calm</w:t></w:r></w:p>',
        styles: headingStyles,
      ).paragraphs.first.inlines.whereType<WmlRun>().first;
      expect(run.properties.bold, isFalse);
    });
  });
}
