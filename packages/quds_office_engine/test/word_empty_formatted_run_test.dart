import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;

OpcPackage _package(String body, {String? styles}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w"><w:body>$body<w:sectPr/></w:body></w:document>',
      );
  if (styles != null) {
    package.createPart(
      '/word/styles.xml',
      OfficeContentTypes.wordStyles,
      utf8.encode('<w:styles xmlns:w="$_w">$styles</w:styles>'),
    );
    package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.styles, target: 'styles.xml');
  }
  return package;
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

WmlRun _onlyRun(WmlDocument document) =>
    document.paragraphs.single.inlines.whereType<WmlRun>().single;

const _styles =
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="Inherited Sans" w:cs="Inherited Arabic"/>'
    '<w:sz w:val="24"/></w:rPr></w:rPrDefault></w:docDefaults>'
    '<w:style w:type="paragraph" w:styleId="Report">'
    '<w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>'
    '<w:style w:type="character" w:styleId="Emphasis">'
    '<w:rPr><w:i/><w:color w:val="335577"/></w:rPr></w:style>';

void main() {
  for (final native in <String>[
    '<w:r><w:rPr><w:b/><w:sz w:val="30"/></w:rPr><w:t/></w:r>',
    '<w:r><w:rPr><w:b/><w:sz w:val="30"/></w:rPr><w:t></w:t></w:r>',
    '<w:r><w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:r>',
  ]) {
    test('authored empty formatted run survives three cycles: $native', () {
      var document = WordDeserializer().read(_package('<w:p>$native</w:p>'));
      for (var cycle = 0; cycle < 3; cycle++) {
        final run = _onlyRun(document);
        expect(run.text, isEmpty);
        expect(run.properties.bold, isTrue);
        expect(run.properties.fontSizeHalfPoints, 30);
        expect(document.paragraphs.single.text, isEmpty);
        expect(
          WordLayoutEngine(font: null)
              .layout(document, updateFields: false)
              .pages
              .expand((page) => page.lines)
              .expand((line) => line.glyphs),
          isEmpty,
        );
        document = _reopen(document);
      }
    });
  }

  for (final native in <String>[
    '<w:r><w:t/></w:r>',
    '<w:r><w:rPr/><w:t/></w:r>',
    '<w:r><w:rPr/></w:r>',
  ]) {
    test(
      'empty run retains inherited formatting independently of mark: $native',
      () {
        var document = WordDeserializer().read(
          _package(
            '<w:p><w:pPr><w:pStyle w:val="Report"/>'
            '<w:rPr><w:sz w:val="72"/></w:rPr></w:pPr>$native</w:p>',
            styles: _styles,
          ),
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          final run = _onlyRun(document);
          expect(run.text, isEmpty);
          expect(run.properties.asciiFont, 'Inherited Sans');
          expect(run.properties.csFont, 'Inherited Arabic');
          expect(run.properties.bold, isTrue);
          expect(run.properties.fontSizeHalfPoints, 28);
          expect(
            document
                .paragraphs
                .single
                .properties
                .importedParagraphMark!
                .fontSizeHalfPoints,
            72,
          );
          document = _reopen(document);
        }
      },
    );
  }

  test('empty character-style run retains theme and complex-script slots', () {
    final package = _package(
      '<w:p><w:pPr><w:pStyle w:val="Report"/></w:pPr>'
      '<w:r><w:rPr><w:rStyle w:val="Emphasis"/>'
      '<w:rFonts w:asciiTheme="majorHAnsi" w:cs="Amiri"/>'
      '<w:rtl/><w:lang w:bidi="ar-SA"/><w:szCs w:val="36"/>'
      '</w:rPr><w:t/></w:r></w:p>',
      styles: _styles,
    );
    package.createPart(
      '/word/theme/theme1.xml',
      OfficeContentTypes.theme,
      utf8.encode(
        '<a:theme xmlns:a="${OfficeNamespaces.a}" name="Empty run">'
        '<a:themeElements><a:fontScheme name="Authored">'
        '<a:majorFont><a:latin typeface="Themed Sans"/><a:ea typeface=""/>'
        '<a:cs typeface="Theme Arabic"/></a:majorFont>'
        '<a:minorFont><a:latin typeface="Minor Sans"/><a:ea typeface=""/>'
        '<a:cs typeface="Minor Arabic"/></a:minorFont>'
        '</a:fontScheme></a:themeElements></a:theme>',
      ),
    );
    package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.theme, target: 'theme/theme1.xml');
    var document = WordDeserializer().read(package);
    for (var cycle = 0; cycle < 3; cycle++) {
      final run = _onlyRun(document);
      expect(run.text, isEmpty);
      expect(run.properties.styleId, 'Emphasis');
      expect(run.properties.asciiFont, 'Themed Sans');
      expect(run.properties.csFont, 'Amiri');
      expect(run.properties.bold, isTrue);
      expect(run.properties.italic, isTrue);
      expect(run.properties.color, '335577');
      expect(run.properties.fontSizeHalfPoints, 28);
      expect(run.properties.complexScript, isTrue);
      expect(run.properties.complexScriptLanguage, 'ar-SA');
      expect(run.properties.sourcePropertiesXml, contains('szCs'));
      expect(run.properties.sourcePropertiesXml, contains('36'));
      document = _reopen(document);
    }
  });

  test(
    'clearing and refilling a cell retains the original first-run style',
    () {
      var document = WordDeserializer().read(
        _package(
          '<w:tbl><w:tblGrid><w:gridCol w:w="3000"/></w:tblGrid><w:tr><w:tc>'
          '<w:p><w:pPr><w:pStyle w:val="Report"/></w:pPr>'
          '<w:r><w:rPr><w:rStyle w:val="Emphasis"/><w:sz w:val="32"/></w:rPr>'
          '<w:t>First</w:t></w:r>'
          '<w:r><w:rPr><w:b w:val="0"/><w:sz w:val="20"/></w:rPr>'
          '<w:t> second</w:t></w:r></w:p>'
          '</w:tc></w:tr></w:tbl>',
          styles: _styles,
        ),
      );
      final paragraph = document.paragraphs.single;
      WmlRunEdit.replaceRange(paragraph, 0, paragraph.text.length, '');
      for (var cycle = 0; cycle < 3; cycle++) {
        document = _reopen(document);
        final run = _onlyRun(document);
        expect(run.text, isEmpty);
        expect(run.properties.fontSizeHalfPoints, 32);
        expect(run.properties.bold, isTrue);
        expect(run.properties.italic, isTrue);
        expect(run.properties.styleId, 'Emphasis');
      }
      WmlRunEdit.replaceRange(document.paragraphs.single, 0, 0, 'Refilled');
      document = _reopen(document);
      final run = _onlyRun(document);
      expect(run.text, 'Refilled');
      expect(run.properties.fontSizeHalfPoints, 32);
      expect(run.properties.bold, isTrue);
      expect(run.properties.italic, isTrue);
      expect(run.properties.color, '335577');
    },
  );

  test('empty runs do not add text or merge adjacent rich-run formatting', () {
    var document = WordDeserializer().read(
      _package(
        '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>A</w:t></w:r>'
        '<w:r><w:rPr><w:i/></w:rPr><w:t/></w:r>'
        '<w:r><w:rPr><w:color w:val="112233"/></w:rPr><w:t>B</w:t></w:r></w:p>',
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      final runs = document.paragraphs.single.inlines
          .whereType<WmlRun>()
          .toList();
      expect(runs.map((run) => run.text), ['A', '', 'B']);
      expect(runs[0].properties.bold, isTrue);
      expect(runs[1].properties.italic, isTrue);
      expect(runs[2].properties.color, '112233');
      expect(document.paragraphs.single.text, 'AB');
      document = _reopen(document);
    }
  });

  for (final native in <String>['<w:r/>', '<w:r></w:r>', '<w:r>  </w:r>']) {
    test('contentless propertyless artifacts remain absent: $native', () {
      final document = WordDeserializer().read(_package('<w:p>$native</w:p>'));
      expect(document.paragraphs.single.inlines, isEmpty);
      expect(document.paragraphs.single.text, isEmpty);
    });
  }

  test('paragraph-mark formatting alone creates no ordinary run', () {
    var document = WordDeserializer().read(
      _package(
        '<w:p><w:pPr><w:rPr><w:b/><w:sz w:val="72"/></w:rPr></w:pPr></w:p>',
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(document.paragraphs.single.inlines, isEmpty);
      expect(
        document
            .paragraphs
            .single
            .properties
            .importedParagraphMark!
            .fontSizeHalfPoints,
        72,
      );
      document = _reopen(document);
    }
  });

  test('blank-line height follows the paragraph mark character style', () {
    var document = WordDeserializer().read(
      _package(
        '<w:p><w:pPr><w:pStyle w:val="Report"/><w:rPr>'
        '<w:rStyle w:val="Compact"/></w:rPr></w:pPr></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="Report"/><w:rPr>'
        '<w:rStyle w:val="Compact"/><w:sz w:val="16"/></w:rPr></w:pPr></w:p>'
        '<w:p><w:r><w:t>Following text</w:t></w:r></w:p>',
        styles:
            '$_styles'
            '<w:style w:type="character" w:styleId="CompactBase">'
            '<w:rPr><w:sz w:val="20"/></w:rPr></w:style>'
            '<w:style w:type="character" w:styleId="Compact">'
            '<w:basedOn w:val="CompactBase"/><w:rPr><w:i/></w:rPr></w:style>',
      ),
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      final paragraphs = document.paragraphs.toList();
      final marks = paragraphs.take(2).map((p) {
        expect(p.inlines, isEmpty);
        final mark = p.properties.importedParagraphMark!;
        expect(mark.bold, isTrue);
        expect(mark.italic, isTrue);
        expect(mark.styleId, 'Compact');
        return mark.fontSizePoints;
      });
      expect(marks, [10, 8]);
      final pages = WordLayoutEngine(font: null).layout(document).pages;
      final line = pages.single.lines.single;
      expect(
        line.y,
        closeTo(document.sections.single.margins.top + 23.76, 0.001),
      );
      expect(WmlRunEdit.propsAt(paragraphs.last, 0).fontSizePoints, 12);
      document = _reopen(document);
    }
  });

  test('formatted field markers produce no extra ordinary empty runs', () {
    final document = WordDeserializer().read(
      _package(
        '<w:p><w:r><w:rPr><w:b/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:r><w:rPr><w:b/></w:rPr><w:instrText>DATE</w:instrText></w:r>'
        '<w:r><w:rPr><w:b/></w:rPr><w:fldChar w:fldCharType="separate"/></w:r>'
        '<w:r><w:rPr><w:b/></w:rPr><w:fldChar w:fldCharType="end"/></w:r></w:p>',
      ),
    );
    final paragraph = document.paragraphs.single;
    expect(paragraph.inlines.whereType<WmlRun>(), isEmpty);
    expect(paragraph.inlines.whereType<WmlFieldBoundary>(), hasLength(4));
    expect(paragraph.text, isEmpty);
  });

  test('formatted note markers retain only the atomic marker', () {
    final document = WordDeserializer().read(
      _package(
        '<w:p><w:r><w:rPr><w:b/></w:rPr><w:footnoteReference w:id="2"/></w:r></w:p>',
      ),
    );
    final run = _onlyRun(document);
    expect(run.noteRefId, 2);
    expect(run.isAtomic, isTrue);
    expect(run.properties.bold, isTrue);
    expect(document.paragraphs.single.inlines, hasLength(1));
  });

  test(
    'formatted comment references and page breaks do not fabricate text',
    () {
      final document = WordDeserializer().read(
        _package(
          '<w:p><w:r><w:rPr><w:b/></w:rPr><w:commentReference w:id="2"/></w:r>'
          '<w:r><w:rPr><w:i/></w:rPr><w:br w:type="page"/></w:r></w:p>',
        ),
      );
      final paragraph = document.paragraphs.single;
      expect(paragraph.inlines.whereType<WmlRun>(), isEmpty);
      expect(paragraph.inlines.whereType<WmlBreak>(), hasLength(1));
      expect(paragraph.text, isEmpty);
    },
  );

  test('a formatted drawing run gains no extra ordinary run on reopen', () {
    final picture = WmlVisual(
      visual: OfficeVisual(
        kind: OfficeVisualKind.picture,
        imageBytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
        ),
        width: 12,
        height: 12,
      ),
    );
    var document = WmlDocument.empty();
    document.paragraphs.single.inlines = [
      WmlRun(text: 'A'),
      WmlRun(
        text: '\uFFFC',
        inlineVisual: picture,
        properties: WmlRunProps(bold: true),
      ),
      WmlRun(text: 'B'),
    ];
    for (var cycle = 0; cycle < 3; cycle++) {
      document = _reopen(document);
      final runs = document.paragraphs.single.inlines
          .whereType<WmlRun>()
          .toList();
      expect(runs, hasLength(3));
      expect(runs.map((run) => run.text), ['A', '\uFFFC', 'B']);
      expect(runs[1].inlineVisual, isNotNull);
      expect(runs[1].properties.bold, isTrue);
    }
  });
}
