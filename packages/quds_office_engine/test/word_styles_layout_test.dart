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
  test('cached paragraph baselines remain independently editable', () {
    final document = _open(
      '<w:p><w:r><w:t>First</w:t></w:r></w:p>'
      '<w:p><w:r><w:t>Second</w:t></w:r></w:p>'
      '<w:p><w:r><w:t>Third</w:t></w:r></w:p>',
      styles:
          '<w:docDefaults><w:pPrDefault><w:pPr>'
          '<w:spacing w:after="120"/>'
          '</w:pPr></w:pPrDefault></w:docDefaults>',
    );
    final properties = document.paragraphs.map((p) => p.properties).toList();
    final original = Map<String, String>.of(properties[0].importedValues!);
    expect(original, isNotEmpty);
    expect(properties[1].importedValues, original);
    expect(properties[2].importedValues, original);

    properties[0].importedValues!['spacing:after'] = '42';
    final editedCopy = properties[0].copy();
    properties[0].importedValues!.clear();
    expect(editedCopy.importedValues!['spacing:after'], '42');
    expect(properties[1].importedValues, original);
    expect(properties[2].importedValues, original);
  });

  test('cached direct properties preserve text on either side of rPr', () {
    final doc = _open(
      '<w:p><w:r><w:rPr><w:sz w:val="34"/></w:rPr>'
      '<w:t>first</w:t></w:r>'
      '<w:r><w:t>sec</w:t><w:rPr><w:sz w:val="34"/></w:rPr>'
      '<w:t>ond</w:t></w:r>'
      '<w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t>third</w:t></w:r>'
      '<w:r><w:rPr><w:sz w:val="34"/></w:rPr><w:t>fourth</w:t></w:r></w:p>',
    );
    final runs = doc.paragraphs.single.inlines.whereType<WmlRun>().toList();
    expect(runs.map((run) => run.text), ['first', 'second', 'third', 'fourth']);
    expect(
      runs.map((run) => run.properties.fontSizeHalfPoints),
      [34, 34, 18, 34],
    );
    runs.first.properties.fontSizeHalfPoints = 24;
    expect(runs[1].properties.fontSizeHalfPoints, 34);
    expect(runs.last.properties.fontSizeHalfPoints, 34);
  });

  test('cached run snapshots keep hyperlink defaults and edits local', () {
    final doc = _open(
      '<w:p>'
      '<w:r><w:t>plain</w:t></w:r>'
      '<w:hyperlink w:anchor="bookmark">'
      '<w:r><w:t>link</w:t></w:r></w:hyperlink>'
      '<w:r><w:t>another</w:t></w:r>'
      '</w:p>',
      styles: '<w:docDefaults><w:rPrDefault><w:rPr>'
          '<w:sz w:val="28"/>'
          '</w:rPr></w:rPrDefault></w:docDefaults>',
    );
    final runs = doc.paragraphs.single.inlines.whereType<WmlRun>().toList();
    final plain = runs[0].properties.importedValues!;
    final link = runs[1].properties.importedValues!;
    final unopenedCopy = runs[2].properties.copy();
    expect(plain['sz'], '28');
    expect(link['color'], WordLink.color);
    expect(link['u'], '${WmlUnderline.single}');
    expect(unopenedCopy.importedValues, plain);
    expect(unopenedCopy.importedValues!['u'], isNot(link['u']));
    unopenedCopy.importedValues!.remove('color');
    final editedCopy = unopenedCopy.copy();
    expect(editedCopy.importedValues, isNot(contains('color')));
    editedCopy.importedValues!['color'] = '123456';
    expect(unopenedCopy.importedValues, isNot(contains('color')));
    expect(plain, contains('color'));
    expect(runs[2].properties.importedValues, contains('color'));
  });

  test('reused rPr output preserves native order and per-run edits', () {
    const direct = '<w:rPr><w:sz w:val="34"/>'
        '<w:color w:val="112233"/><w:b/></w:rPr>';
    final doc = _open(
      '<w:p><w:r>$direct<w:t>one</w:t></w:r>'
      '<w:r>$direct<w:t>two</w:t></w:r>'
      '<w:r>$direct<w:t>three</w:t></w:r></w:p>',
    );
    final runs = doc.paragraphs.single.inlines.whereType<WmlRun>().toList();
    runs[1].properties.color = 'CC0000';
    final part = WordSerializer().write(doc).getPart('/word/document.xml')!;
    final properties = XmlDocument.parse(part.readText())
        .root!
        .firstChild('body')!
        .firstChild('p')!
        .childrenNamed('r')
        .map((run) => run.firstChild('rPr')!)
        .toList();
    expect(properties, hasLength(3));
    for (final property in properties) {
      expect(property.childElements.map((child) => child.localName), [
        'b',
        'color',
        'sz',
      ]);
    }
    expect(
      properties.map((p) => p.firstChild('color')!.getAttribute('val')),
      ['112233', 'CC0000', '112233'],
    );
  });

  test('unchanged paragraph output retains native order and local edits', () {
    const direct = '<w:pPr><w:jc w:val="right"/>'
        '<w:spacing w:before="120" w:after="80"/></w:pPr>';
    final doc = _open(
      '<w:p>$direct<w:r><w:t>one</w:t></w:r></w:p>'
      '<w:p>$direct<w:r><w:t>two</w:t></w:r></w:p>'
      '<w:p>$direct<w:r><w:t>three</w:t></w:r></w:p>',
    );
    doc.paragraphs.elementAt(1).properties.spacingAfter = 12;
    final part = WordSerializer().write(doc).getPart('/word/document.xml')!;
    final properties = XmlDocument.parse(part.readText())
        .root!
        .firstChild('body')!
        .childrenNamed('p')
        .map((paragraph) => paragraph.firstChild('pPr')!)
        .toList();
    expect(properties, hasLength(3));
    for (final property in properties) {
      expect(property.childElements.map((child) => child.localName), [
        'spacing',
        'jc',
      ]);
      expect(property.firstChild('spacing')!.getAttribute('before'), '120');
    }
    expect(
      properties.map((p) => p.firstChild('spacing')!.getAttribute('after')),
      ['80', '240', '80'],
    );
  });

  test('repeated paragraph projections own their tabs and bookmarks', () {
    final doc = _open(
      [
        for (final (i, name) in ['one', 'two'].indexed)
          '<w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/>'
          '</w:tabs></w:pPr><w:bookmarkStart w:id="$i" w:name="$name"/>'
          '<w:r><w:t>$name</w:t></w:r><w:bookmarkEnd w:id="$i"/></w:p>',
      ].join(),
      styles: '<w:docDefaults><w:pPrDefault><w:pPr>'
          '<w:spacing w:after="120"/>'
          '</w:pPr></w:pPrDefault></w:docDefaults>',
    );
    final paragraphs = doc.paragraphs.toList();
    expect(paragraphs.map((p) => p.properties.spacingAfter), [6, 6]);
    expect(WordBookmarks.textByName(doc, 'one'), 'one');
    expect(WordBookmarks.textByName(doc, 'two'), 'two');
    expect(paragraphs.first.properties.tabs, hasLength(1));
    paragraphs.first.properties.tabs.clear();
    expect(paragraphs.last.properties.tabs, hasLength(1));
    final firstSnapshot = paragraphs.first.properties.importedValues!;
    final lastSnapshot = paragraphs.last.properties.importedValues!;
    expect(firstSnapshot, lastSnapshot);
    firstSnapshot.remove('tabs');
    expect(lastSnapshot['tabs'], isNotEmpty);
  });

  test('cyclic styles retain precedence for each requested style', () {
    final doc = _open(
      [
        for (final style in ['A', 'B', 'A', 'B'])
          '<w:p><w:pPr><w:pStyle w:val="$style"/></w:pPr>'
          '<w:r><w:t>Body</w:t></w:r></w:p>',
      ].join(),
      styles:
          '<w:style w:type="paragraph" w:styleId="A"><w:basedOn w:val="B"/>'
          '<w:rPr><w:color w:val="CC0000"/></w:rPr></w:style>'
          '<w:style w:type="paragraph" w:styleId="B"><w:basedOn w:val="A"/>'
          '<w:rPr><w:color w:val="0000CC"/></w:rPr></w:style>',
    );
    expect(
      doc.paragraphs.map(
        (paragraph) => (paragraph.inlines.single as WmlRun).properties.color,
      ),
      ['CC0000', '0000CC', 'CC0000', '0000CC'],
    );
  });

  test('empty direct paragraph flags enable settings disabled by a style', () {
    final doc = _open(
      '<w:p><w:pPr><w:pStyle w:val="Disabled"/>'
      '<w:keepNext/><w:keepLines/><w:widowControl/><w:contextualSpacing/></w:pPr>'
      '<w:r><w:t>Paragraph</w:t></w:r></w:p>',
      styles:
          '<w:style w:type="paragraph" w:styleId="Disabled">'
          '<w:name w:val="Disabled"/><w:pPr><w:keepNext w:val="0"/><w:keepLines w:val="0"/>'
          '<w:widowControl w:val="false"/><w:contextualSpacing w:val="off"/>'
          '</w:pPr></w:style>',
    );
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(doc),
    );
    for (final sample in [doc, reopened]) {
      final properties = sample.paragraphs.single.properties;
      expect(properties.keepTogether, isTrue);
      expect(properties.keepWithNext, isTrue);
      expect(properties.widowControl, isTrue);
      expect(properties.contextualSpacing, isTrue);
    }
  });

  test(
    'save retains the effective color of a missing native heading style',
    () {
      final document = _open(
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
        '<w:r><w:t>Existing heading</w:t></w:r></w:p>',
        styles:
            '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
            '<w:name w:val="Normal"/><w:rPr><w:color w:val="000000"/>'
            '</w:rPr></w:style>',
      );
      final heading = document.paragraphs.single;
      expect(heading.properties.styleId, 'Heading1');
      expect(
        heading.inlines.whereType<WmlRun>().single.properties.color,
        '000000',
      );

      final encoded = WordSerializer().writeBytes(document);
      final saved = OpcPackage.openBytes(encoded);
      expect(
        saved.getPart('/word/styles.xml')!.readText(),
        isNot(contains('Heading1')),
      );
      final reopened = WordDeserializer().readBytes(encoded).paragraphs.single;
      expect(reopened.properties.styleId, 'Heading1');
      expect(
        reopened.inlines.whereType<WmlRun>().single.properties.color,
        '000000',
      );
    },
  );

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

  test('inherited numbering skips an empty section-break paragraph', () {
    const chapter = '<w:pStyle w:val="Chapter"/>';
    final doc = _open(
      '<w:p><w:pPr>$chapter$_a4</w:pPr></w:p>'
      '<w:p><w:pPr>$chapter</w:pPr><w:r><w:t>First chapter</w:t></w:r></w:p>'
      '<w:p><w:r><w:t>Next chapter</w:t></w:r></w:p>',
      styles:
          '<w:style w:type="paragraph" w:styleId="Chapter">'
          '<w:name w:val="Imported chapter"/>'
          '<w:pPr><w:keepNext/><w:outlineLvl w:val="0"/>'
          '<w:numPr><w:numId w:val="1"/></w:numPr></w:pPr>'
          '<w:rPr><w:sz w:val="28"/></w:rPr></w:style>',
      numbering:
          '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0">'
          '<w:start w:val="1"/><w:numFmt w:val="upperRoman"/>'
          '<w:lvlText w:val="%1."/></w:lvl></w:abstractNum>'
          '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>',
    );
    expect(doc.paragraphs.map((p) => p.properties.listLabel), [
      null, 'I. ', null,
    ]);
    final last = doc.paragraphs.last;
    expect(WordHeadingIo.applyImportedStyles(doc, [last], 'Chapter'), isTrue);
    expect(last.properties.styleId, 'Chapter');
    expect(last.properties.headingLevel, 1);
    expect(last.properties.keepWithNext, isTrue);
    expect(last.properties.listLabel, 'II. ');
    expect(last.inlines.whereType<WmlRun>().single.properties.fontSizePoints, 14);
    final reopened = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
    expect(reopened.paragraphs.map((p) => p.properties.listLabel), [
      null, 'I. ', 'II. ',
    ]);
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

    List<WmlRun> headerRuns(String runs) =>
        only(
              _open(
                '<w:tbl><w:tblPr><w:tblStyle w:val="ColoredHeader"/>'
                '<w:tblLook w:val="04A0"/></w:tblPr>'
                '<w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid>'
                '<w:tr><w:tc><w:p>$runs</w:p></w:tc></w:tr></w:tbl>',
                styles:
                    '<w:style w:type="table" w:styleId="ColoredHeader">'
                    '<w:tblStylePr w:type="firstRow">'
                    '<w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr>'
                    '<w:tcPr><w:shd w:val="clear" w:fill="112233"/></w:tcPr>'
                    '</w:tblStylePr></w:style>',
              ),
            ).rows.first.cells.first.blocks
            .whereType<WmlParagraph>()
            .single
            .inlines
            .whereType<WmlRun>()
            .toList();

    test('first-row table style preserves direct run colors', () {
      final runs = headerRuns(
        '<w:r><w:t>Inherited</w:t></w:r>'
        '<w:r><w:rPr><w:color w:val="C04020"/></w:rPr>'
        '<w:t>Direct color</w:t></w:r>'
        '<w:r><w:rPr><w:color w:val="000000"/></w:rPr>'
        '<w:t>Explicit default color</w:t></w:r>',
      );
      expect(runs.map((run) => run.properties.color), [
        'FFFFFF',
        'C04020',
        '000000',
      ]);
      expect(runs.map((run) => run.properties.bold), everyElement(isTrue));
    });

    test('first-row table style preserves directly disabled bold', () {
      final runs = headerRuns(
        '<w:r><w:t>Inherited</w:t></w:r>'
        '<w:r><w:rPr><w:b w:val="0"/></w:rPr>'
        '<w:t>Direct zero</w:t></w:r>'
        '<w:r><w:rPr><w:b w:val="false"/></w:rPr>'
        '<w:t>Direct false</w:t></w:r>',
      );
      expect(runs.map((run) => run.properties.bold), [true, false, false]);
      expect(runs.map((run) => run.properties.color), everyElement('FFFFFF'));
    });

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
