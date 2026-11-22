import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_headers_footers_smoke.dart' as stories;
import '../tool/macros/web_vba_word_styles_alternate_smoke.dart' as portable;

const _w = OfficeNamespaces.w;
const _x = 'urn:style-test';
const _styles = '''
<w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val="20"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:styleId="Normal" w:type="paragraph" w:default="1"><w:name w:val="Normal"/></w:style>
<w:style w:styleId="ReportHeading" w:type="paragraph"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="240"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:color w:val="456789"/></w:rPr></w:style>
<w:style w:styleId="Custom" w:type="paragraph" w:customStyle="1"><w:name w:val="Report Body"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="160"/></w:pPr></w:style>
<w:style w:styleId="Character" w:type="character"><w:name w:val="Character"/><w:rPr><w:i/><w:color w:val="AA0000"/></w:rPr></w:style>
<w:style w:styleId="OuterTable" w:type="table"><w:name w:val="Outer table"/><w:rPr><w:color w:val="0000AA"/></w:rPr></w:style>
<w:style w:styleId="InnerTable" w:type="table"><w:name w:val="Inner table"/><w:rPr><w:i/><w:color w:val="00AA00"/></w:rPr></w:style>
''';

Uint8List _fixture({
  String styles = _styles,
  String? body,
  String properties = '',
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Start')).build(),
  );
  package
      .getPart('/word/styles.xml')!
      .writeText(
        '<w:styles xmlns:w="$_w" xmlns:x="$_x" xmlns:mc="${OfficeNamespaces.mc}">$styles</w:styles>',
      );
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="$_w" xmlns:x="$_x" xmlns:mc="${OfficeNamespaces.mc}"><w:body>
${body ?? '<w:p><w:pPr>$properties</w:pPr><w:r><w:t>Selected</w:t></w:r></w:p><w:p><w:r><w:t>Untouched</w:t></w:r></w:p>'}
<w:sectPr/></w:body></w:document>''');
  return package.save();
}

WmlDocument _read(Uint8List bytes) => WordDeserializer().readBytes(bytes);
Map<String, Object?> _step({String? name, int? builtin}) => {
  'op': 'paragraphStyle',
  'paragraph': 0,
  'name': ?name,
  'builtin': ?builtin,
};
Map<String, Uint8List> _parts(WmlDocument document) => {
  for (final part in document.package!.parts)
    part.uri: document.package!.getPart(part.uri)!.readBytes(),
};
void _refuses(
  WmlDocument document,
  Map<String, Object?> step, {
  Matcher? matcher,
}) {
  final paragraph = document.paragraphs.first;
  final props = paragraph.properties;
  final inline = paragraph.inlines;
  final before = _parts(document);
  final source = props.sourcePropertiesXml;
  final imported = Map<String, String>.of(props.importedValues ?? {});
  expect(
    () => native.applyStep(document, step),
    matcher ?? throwsUnsupportedError,
  );
  expect(identical(paragraph.properties, props), isTrue);
  expect(identical(paragraph.inlines, inline), isTrue);
  expect(props.sourcePropertiesXml, source);
  expect(props.importedValues ?? {}, imported);
  expect(_parts(document), before);
}

void main() {
  test('pending style assignment retains original native marker metadata', () {
    final document = _read(portable.wordStylesInput());
    final paragraph = document.paragraphs.first;
    final inlines = paragraph.inlines;
    final run = inlines.first;
    paragraph.properties.styleId = 'ReportBody';
    native.applyStep(document, _step(builtin: -2));
    expect(paragraph.inlines, same(inlines));
    expect(paragraph.inlines.first, same(run));
    final properties = XmlDocument.parse(
      paragraph.properties.sourcePropertiesXml!,
    ).root!;
    final style = properties.firstChild('pStyle', namespaceUri: _w)!;
    expect(style.getAttribute('val', namespaceUri: _w), 'ReportHeadingOne');
    expect(
      style.getAttribute('token', namespaceUri: 'urn:word-style-example'),
      'keep-style',
    );
    expect(
      style.getAttribute('val', namespaceUri: 'urn:word-style-example'),
      'foreign-style',
    );
    expect(
      style.firstChild('metadata', namespaceUri: 'urn:word-style-example'),
      isNotNull,
    );
  });

  test('style-linked numbering refuses even without an effective numId', () {
    final package = OpcPackage.openBytes(_fixture());
    (package.getPart('/word/numbering.xml') ??
            package.createPart(
              '/word/numbering.xml',
              OfficeContentTypes.wordNumbering,
            ))
        .writeText(
          '<w:numbering xmlns:w="$_w"><w:abstractNum w:abstractNumId="1">'
          '<w:lvl w:ilvl="0"><w:pStyle w:val="ReportHeading"/></w:lvl>'
          '</w:abstractNum></w:numbering>',
        );
    final relationships = package.relationshipsFor('/word/document.xml');
    if (relationships.firstByType(RelationshipTypes.numbering) == null) {
      relationships.add(
        type: RelationshipTypes.numbering,
        target: 'numbering.xml',
      );
    }
    final document = _read(package.save());
    expect(document.paragraphs.first.properties.numId, isNull);
    _refuses(document, _step(builtin: -2));
  });

  test('effective property aliases remain consistent across native reopens', () {
    final definitions =
        '$_styles<w:style xmlns:s="$_w" w:styleId="Aliased" w:type="paragraph">'
        '<w:name w:val="Aliased"/><s:rPr><s:b/><s:sz s:val="50"/></s:rPr></w:style>';
    var document = _read(_fixture(styles: definitions));
    native.applyStep(document, _step(name: 'Aliased'));
    for (var cycle = 0; cycle < 3; cycle++) {
      final target = document.paragraphs.first;
      expect(target.properties.styleId, 'Aliased');
      final properties = (target.inlines.single as WmlRun).properties;
      expect(properties.bold, isTrue);
      expect(properties.fontSizeHalfPoints, 50);
      document = _read(WordSerializer().writeBytes(document));
    }
  });

  test('synchronized native style edits remain usable in the same plan', () {
    final document = _read(_fixture());
    native.applyStep(document, {
      'op': 'styleDefinition',
      'style': 'ReportHeading',
      'type': 'paragraph',
      'rPr': {
        'i': <String, Object?>{},
        'sz': {'val': 50},
      },
    });
    native.applyStep(document, _step(builtin: -2));
    final props = document.paragraphs.first.inlines
        .whereType<WmlRun>()
        .single
        .properties;
    expect(props.italic, isTrue);
    expect(props.fontSizeHalfPoints, 50);
    final reopened = _read(WordSerializer().writeBytes(document));
    expect(
      reopened.paragraphs.first.inlines
          .whereType<WmlRun>()
          .single
          .properties
          .italic,
      isTrue,
    );
    expect(
      reopened.paragraphs.first.inlines
          .whereType<WmlRun>()
          .single
          .properties
          .fontSizeHalfPoints,
      50,
    );
  });
  for (final (label, properties, bold) in [
    ('foreign bold', '<w:rPr><x:b/></w:rPr>', false),
    ('foreign toggle value', '<w:rPr><w:b x:val="0"/></w:rPr>', true),
    ('foreign outline', '<w:pPr><x:outlineLvl w:val="0"/></w:pPr>', false),
    ('nested bold', '<w:rPr><x:metadata><w:b/></x:metadata></w:rPr>', false),
  ]) {
    test('$label stays opaque with consistent live/reopened formatting', () {
      final definitions =
          '$_styles<w:style w:styleId="Metadata" w:type="paragraph">'
          '<w:name w:val="Metadata"/>$properties</w:style>';
      var document = _read(_fixture(styles: definitions));
      final source = XmlDocument.parse(
        document.package!.getPart('/word/styles.xml')!.readText(),
      ).toXmlString(declaration: false);
      final other = document.paragraphs.last;
      final otherProperties = other.properties;
      final otherRun = (other.inlines.single as WmlRun).properties;
      native.applyStep(document, _step(name: 'Metadata'));
      expect(other.properties, same(otherProperties));
      expect((other.inlines.single as WmlRun).properties, same(otherRun));
      for (var cycle = 0; cycle < 3; cycle++) {
        final paragraph = document.paragraphs.first;
        expect(paragraph.properties.styleId, 'Metadata');
        expect(paragraph.properties.headingLevel, isNull);
        expect((paragraph.inlines.single as WmlRun).properties.bold, bold);
        expect(document.paragraphs.last.properties.headingLevel, isNull);
        expect(
          (document.paragraphs.last.inlines.single as WmlRun).properties.bold,
          isFalse,
        );
        final bytes = WordSerializer().writeBytes(document);
        expect(
          XmlDocument.parse(
            OpcPackage.openBytes(bytes).getPart('/word/styles.xml')!.readText(),
          ).toXmlString(declaration: false),
          source,
        );
        document = _read(bytes);
      }
    });
  }
  for (final kind in ['replace', 'remove']) {
    test('pending model style $kind refuses before source mutation', () {
      final document = _read(_fixture());
      final index = document.styles.indexWhere(
        (style) => style.id == 'ReportHeading',
      );
      if (kind == 'replace') {
        document.styles[index] = const WmlStyle(
          id: 'ReportHeading',
          name: 'Changed',
          nameAr: 'Changed',
          italic: true,
          fontSizePoints: 25,
        );
      } else {
        document.styles.removeAt(index);
      }
      _refuses(document, _step(builtin: -2));
    });
  }
  test('table restyling clears old inherited spacing when new style omits it', () {
    final definitions =
        '$_styles<w:style w:styleId="OldSpacing" w:type="paragraph">'
        '<w:name w:val="Old spacing"/><w:pPr><w:spacing w:after="240" w:line="480" w:lineRule="auto"/></w:pPr></w:style>';
    final document = _read(
      _fixture(
        styles: definitions,
        body:
            '<w:tbl><w:tblPr><w:tblStyle w:val="OuterTable"/></w:tblPr><w:tblGrid><w:gridCol w:w="6000"/></w:tblGrid>'
            '<w:tr><w:tc><w:p><w:pPr><w:pStyle w:val="OldSpacing"/></w:pPr><w:r><w:t>Selected</w:t></w:r></w:p></w:tc></w:tr></w:tbl>',
      ),
    );
    expect(document.paragraphs.single.properties.spacingAfter, 12);
    expect(document.paragraphs.single.properties.lineSpacing, 2);
    native.applyStep(document, _step(builtin: -1));
    expect(document.paragraphs.single.properties.spacingAfter, 0);
    expect(document.paragraphs.single.properties.lineSpacing, 1);
    final reopened = _read(WordSerializer().writeBytes(document));
    expect(reopened.paragraphs.single.properties.spacingAfter, 0);
    expect(reopened.paragraphs.single.properties.lineSpacing, 1);
  });
  const builtins = <int, String>{
    -1: 'Normal',
    -2: 'heading 1',
    -3: 'heading 2',
    -4: 'heading 3',
    -5: 'heading 4',
    -6: 'heading 5',
    -7: 'heading 6',
    -8: 'heading 7',
    -9: 'heading 8',
    -10: 'heading 9',
    -35: 'caption',
    -63: 'Title',
    -75: 'Subtitle',
  };
  for (final entry in builtins.entries) {
    test('native built-in ${entry.key} selects existing ${entry.value}', () {
      final definitions = [
        for (final value in builtins.entries)
          '<w:style w:type="paragraph" w:styleId="Native${-value.key}" '
              '${value.key == -1 ? 'w:default="true"' : ''}>'
              '<w:name w:val="${value.value}"/><w:pPr>'
              '<w:spacing w:before="${-value.key * 20}"/></w:pPr></w:style>',
      ].join();
      final document = _read(_fixture(styles: definitions));
      native.applyStep(document, _step(builtin: entry.key));
      expect(
        document.paragraphs.first.properties.styleId,
        'Native${-entry.key}',
      );
      expect(document.paragraphs.first.properties.spacingBefore, -entry.key);
      final reopened = _read(WordSerializer().writeBytes(document));
      expect(
        reopened.paragraphs.first.properties.styleId,
        'Native${-entry.key}',
      );
      expect(reopened.paragraphs.first.properties.spacingBefore, -entry.key);
    });
  }
  test('direct outline level does not require an inferred catalog style', () {
    final document = _read(_fixture(properties: '<w:outlineLvl w:val="0"/>'));
    native.applyStep(document, _step(name: 'Report Body'));
    expect(document.paragraphs.first.properties.styleId, 'Custom');
    expect(document.paragraphs.first.properties.headingLevel, 1);
    final reopened = _read(WordSerializer().writeBytes(document));
    expect(reopened.paragraphs.first.properties.styleId, 'Custom');
    expect(reopened.paragraphs.first.properties.headingLevel, 1);
  });
  test('unbalanced fields refuse atomically before style assignment', () {
    final document = _read(
      _fixture(
        body:
            '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>'
            '<w:r><w:instrText> REF unfinished </w:instrText></w:r>'
            '<w:r><w:t>Selected</w:t></w:r></w:p>',
      ),
    );
    _refuses(document, _step(builtin: -2));
  });
  test('builtins resolve canonical primary names rather than style IDs', () {
    final document = _read(_fixture());
    native.applyStep(document, _step(builtin: -2));
    final target = document.paragraphs.first;
    expect(target.properties.styleId, 'ReportHeading');
    expect(target.properties.spacingBefore, 12);
    expect(target.properties.headingLevel, 1);
    expect(target.inlines.whereType<WmlRun>().single.properties.bold, isTrue);
    final reopened = _read(WordSerializer().writeBytes(document));
    expect(reopened.paragraphs.first.properties.styleId, 'ReportHeading');
    expect(reopened.paragraphs.first.properties.spacingBefore, 12);
  });

  test(
    'direct pPr/rPr and foreign native-marker metadata survive restyling',
    () {
      final document = _read(portable.wordStylesInput());
      final untouched = document.paragraphs.last;
      final props = untouched.properties;
      final inlines = untouched.inlines;
      final source = props.sourcePropertiesXml;
      final styles = document.package!.getPart('/word/styles.xml')!.readBytes();
      native.applyStep(document, _step(builtin: -2));
      final target = document.paragraphs.first;
      expect(target.properties.spacingBefore, 12);
      expect(target.properties.spacingAfter, 9);
      expect(target.properties.justification, WmlJustification.right);
      final run = target.inlines.whereType<WmlRun>().single;
      expect(run.properties.bold, isTrue);
      expect(run.properties.italic, isFalse);
      expect(run.properties.color, '112233');
      expect(run.properties.fontSizeHalfPoints, 22);
      expect(identical(untouched.properties, props), isTrue);
      expect(identical(untouched.inlines, inlines), isTrue);
      expect(props.sourcePropertiesXml, source);
      expect(
        document.package!.getPart('/word/styles.xml')!.readBytes(),
        styles,
      );
      final normalizedStyles = XmlDocument.parse(
        document.package!.getPart('/word/styles.xml')!.readText(),
      ).toXmlString();
      var bytes = WordSerializer().writeBytes(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        final xml = portable
            .wordStylesParagraphXml(bytes, 0)
            .firstChild('pPr', namespaceUri: _w)!;
        final style = xml.firstChild('pStyle', namespaceUri: _w)!;
        expect(style.getAttribute('val', namespaceUri: _w), 'ReportHeadingOne');
        expect(
          style.getAttribute('val', namespaceUri: 'urn:word-style-example'),
          'foreign-style',
        );
        expect(
          style.getAttribute('token', namespaceUri: 'urn:word-style-example'),
          'keep-style',
        );
        expect(
          style.firstChild('metadata', namespaceUri: 'urn:word-style-example'),
          isNotNull,
        );
        expect(
          xml
              .firstChild('spacing', namespaceUri: _w)!
              .getAttribute('before', namespaceUri: _w),
          isNull,
        );
        expect(
          XmlDocument.parse(
            OpcPackage.openBytes(bytes).getPart('/word/styles.xml')!.readText(),
          ).toXmlString(),
          normalizedStyles,
        );
        bytes = WordSerializer().writeBytes(_read(bytes));
      }
    },
  );

  test('name lookup is case-insensitive and preserves exact whitespace', () {
    final document = _read(_fixture());
    native.applyStep(document, _step(name: 'rEpOrT bOdY'));
    expect(document.paragraphs.first.properties.styleId, 'Custom');
    _refuses(
      document,
      _step(name: ' Report Body'),
      matcher: throwsArgumentError,
    );
  });

  test('same default value becomes explicit without freezing inheritance', () {
    final document = _read(_fixture());
    native.applyStep(document, _step(builtin: -1));
    final bytes = WordSerializer().writeBytes(document);
    final pPr = portable
        .wordStylesParagraphXml(bytes, 0)
        .firstChild('pPr', namespaceUri: _w)!;
    expect(
      pPr
          .firstChild('pStyle', namespaceUri: _w)!
          .getAttribute('val', namespaceUri: _w),
      'Normal',
    );
    expect(
      pPr.childElements
          .where((node) => node.namespaceUri == _w)
          .map((node) => node.localName),
      ['pStyle'],
    );
  });

  test('pending direct edits and explicit false survive targeted cascade', () {
    final document = _read(_fixture());
    native.applyStep(document, {
      'op': 'paragraphFormat',
      'paragraph': 0,
      'after': 7,
    });
    native.applyStep(document, {
      'op': 'runFormat',
      'paragraph': 0,
      'bold': false,
      'color': '123456',
    });
    native.applyStep(document, _step(builtin: -2));
    final target = document.paragraphs.first;
    expect(target.properties.spacingAfter, 7);
    expect(target.inlines.whereType<WmlRun>().single.properties.bold, isFalse);
    expect(
      target.inlines.whereType<WmlRun>().single.properties.color,
      '123456',
    );
    final reopened = _read(WordSerializer().writeBytes(document));
    expect(reopened.paragraphs.first.properties.spacingAfter, 7);
    expect(
      reopened.paragraphs.first.inlines
          .whereType<WmlRun>()
          .single
          .properties
          .bold,
      isFalse,
    );
  });

  test('direct character style remains above new paragraph inheritance', () {
    final document = _read(
      _fixture(
        body:
            '<w:p><w:r><w:rPr><w:rStyle w:val="Character"/></w:rPr><w:t>Text</w:t></w:r></w:p>',
      ),
    );
    native.applyStep(document, _step(builtin: -2));
    final props = document.paragraphs.single.inlines
        .whereType<WmlRun>()
        .single
        .properties;
    expect(props.styleId, 'Character');
    expect(props.color, 'AA0000');
    expect(props.italic, isTrue);
    expect(props.bold, isTrue);
  });

  test(
    'nested table applies nearest owner style without touching siblings',
    () {
      final document = _read(
        _fixture(
          body: '''
<w:tbl><w:tblPr><w:tblStyle w:val="OuterTable"/></w:tblPr><w:tblGrid><w:gridCol w:w="6000"/></w:tblGrid><w:tr><w:tc>
<w:p><w:r><w:t>Outer</w:t></w:r></w:p>
<w:tbl><w:tblPr><w:tblStyle w:val="InnerTable"/></w:tblPr><w:tblGrid><w:gridCol w:w="5000"/></w:tblGrid><w:tr><w:tc><w:p><w:r><w:t>Inner</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
<w:p><w:r><w:t>After</w:t></w:r></w:p></w:tc></w:tr></w:tbl>''',
        ),
      );
      final paragraphs = document.paragraphs.toList();
      expect(paragraphs.map((p) => p.text), ['Outer', 'Inner', 'After']);
      final outer = paragraphs.first.properties;
      native.applyStep(document, {
        ..._step(name: 'Report Body'),
        'paragraph': 1,
      });
      final props = paragraphs[1].inlines.whereType<WmlRun>().single.properties;
      expect(props.color, '00AA00');
      expect(props.italic, isTrue);
      expect(paragraphs[1].properties.spacingAfter, 8);
      expect(identical(paragraphs.first.properties, outer), isTrue);
      expect(
        _read(WordSerializer().writeBytes(document)).paragraphs
            .elementAt(1)
            .inlines
            .whereType<WmlRun>()
            .single
            .properties
            .color,
        '00AA00',
      );
    },
  );

  for (final story in stories.wordHeaderFooterStories) {
    test('routes independent $story and preserves other stories', () {
      final package = OpcPackage.openBytes(stories.wordHeadersFootersInput());
      package
          .getPart('/word/styles.xml')!
          .writeText('<w:styles xmlns:w="$_w">$_styles</w:styles>');
      final document = _read(package.save());
      final body = document.paragraphs.first.properties;
      native.applyStep(document, {
        ..._step(builtin: -2),
        'story': story,
        'section': 1,
        'paragraph': 1,
      });
      final target = stories.wordHeaderFooterParagraphs(
        document.sections[1],
        story,
      )[1];
      expect(target.properties.styleId, 'ReportHeading');
      expect(identical(document.paragraphs.first.properties, body), isTrue);
      final saved = _read(WordSerializer().writeBytes(document));
      expect(
        stories
            .wordHeaderFooterParagraphs(saved.sections[1], story)[1]
            .properties
            .styleId,
        'ReportHeading',
      );
      expect(
        stories
            .wordHeaderFooterParagraphs(saved.sections[0], story)[1]
            .properties
            .styleId,
        isNull,
      );
    });
  }

  test('linked header refusal still applies before style mutation', () {
    final package = OpcPackage.openBytes(stories.wordHeadersFootersInput());
    package
        .getPart('/word/styles.xml')!
        .writeText('<w:styles xmlns:w="$_w">$_styles</w:styles>');
    final main = package.getPart('/word/document.xml')!;
    final xml = XmlDocument.parse(main.readText());
    final body = xml.root!.firstChild('body', namespaceUri: _w)!;
    final sections = [
      for (final p in body.childrenNamed('p', namespaceUri: _w))
        ...?p
            .firstChild('pPr', namespaceUri: _w)
            ?.childrenNamed('sectPr', namespaceUri: _w),
    ];
    final reference = sections[1]
        .childrenNamed('headerReference', namespaceUri: _w)
        .firstWhere(
          (r) => r.getAttribute('type', namespaceUri: _w) == 'default',
        );
    sections[1].children.remove(reference);
    main.writeText(xml.toXmlString());
    final document = _read(package.save());
    _refuses(document, {
      ..._step(builtin: -2),
      'story': 'header',
      'section': 1,
    });
  });

  for (final selector in [
    <String, Object?>{},
    {'name': 'Normal', 'builtin': -1},
    {'name': null},
    {'name': true},
    {'name': ''},
    {'name': '   '},
    {'name': 'bad\u0000'},
    {'builtin': true},
    {'builtin': -1.5},
    {'builtin': 0},
    {'builtin': -11},
    {'name': 'Report Body', 'extra': 1},
  ]) {
    test('invalid selector $selector fails atomically', () {
      _refuses(_read(_fixture()), {
        'op': 'paragraphStyle',
        'paragraph': 0,
        ...selector,
      }, matcher: throwsArgumentError);
    });
  }
  for (final name in ['Missing', 'Character', 'Outer table']) {
    test('does not create, guess or coerce $name', () {
      _refuses(
        _read(_fixture()),
        _step(name: name),
        matcher: throwsArgumentError,
      );
    });
  }
  for (final (label, styles) in [
    (
      'duplicate IDs',
      '$_styles<w:style w:styleId="Normal"><w:name w:val="Other"/></w:style>',
    ),
    (
      'duplicate names',
      '$_styles<w:style w:styleId="Other"><w:name w:val="REPORT BODY"/></w:style>',
    ),
    (
      'missing basedOn',
      _styles.replaceFirst(
        'w:val="Normal"/><w:pPr>',
        'w:val="Absent"/><w:pPr>',
      ),
    ),
    (
      'cyclic basedOn',
      _styles.replaceFirst(
        'w:val="Normal"/><w:pPr>',
        'w:val="ReportHeading"/><w:pPr>',
      ),
    ),
    (
      'duplicate name property',
      _styles.replaceFirst(
        '<w:name w:val="heading 1"/>',
        '<w:name w:val="heading 1"/><w:name w:val="heading 2"/>',
      ),
    ),
    (
      'custom builtin',
      _styles.replaceFirst(
        'w:styleId="ReportHeading"',
        'w:styleId="ReportHeading" w:customStyle="true"',
      ),
    ),
  ]) {
    test('$label refused without changing model or package', () {
      _refuses(_read(_fixture(styles: styles)), _step(builtin: -2));
    });
  }
  for (final (label, properties) in [
    (
      'duplicate pStyle',
      '<w:pStyle w:val="Normal"/><w:pStyle w:val="Normal"/>',
    ),
    (
      'alternative pStyle',
      '<mc:AlternateContent><mc:Choice Requires="x"><w:pStyle w:val="Normal"/></mc:Choice><mc:Fallback><w:pStyle w:val="Normal"/></mc:Fallback></mc:AlternateContent>',
    ),
  ]) {
    test('$label refuses sparse source ambiguity', () {
      _refuses(_read(_fixture(properties: properties)), _step(builtin: -2));
    });
  }

  test('nested pStyle remains opaque while the direct native style changes', () {
    var document = _read(
      _fixture(
        properties:
            '<x:extension x:token="keep"><w:pStyle w:val="Normal"/></x:extension>',
      ),
    );
    native.applyStep(document, _step(builtin: -2));
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(document.paragraphs.first.properties.styleId, 'ReportHeading');
      final bytes = WordSerializer().writeBytes(document);
      final properties = portable
          .wordStylesParagraphXml(bytes, 0)
          .firstChild('pPr', namespaceUri: _w)!;
      expect(
        properties
            .firstChild('pStyle', namespaceUri: _w)!
            .getAttribute('val', namespaceUri: _w),
        'ReportHeading',
      );
      final metadata = properties.firstChild('extension', namespaceUri: _x)!;
      expect(metadata.getAttribute('token', namespaceUri: _x), 'keep');
      expect(
        metadata
            .firstChild('pStyle', namespaceUri: _w)!
            .getAttribute('val', namespaceUri: _w),
        'Normal',
      );
      document = _read(bytes);
    }
  });

  test('foreign pStyle cannot become effective through same local name', () {
    final document = _read(
      _fixture(
        properties:
            '<w:pStyle w:val="Normal"/><x:pStyle w:val="Custom" x:token="preserved"/>',
      ),
    );
    native.applyStep(document, _step(builtin: -2));
    var bytes = WordSerializer().writeBytes(document);
    for (var i = 0; i < 2; i++) {
      final root = portable
          .wordStylesParagraphXml(bytes, 0)
          .firstChild('pPr', namespaceUri: _w)!;
      expect(
        root
            .firstChild('pStyle', namespaceUri: _x)!
            .getAttribute('token', namespaceUri: _x),
        'preserved',
      );
      final reopened = _read(bytes);
      expect(reopened.paragraphs.first.properties.styleId, 'ReportHeading');
      bytes = WordSerializer().writeBytes(reopened);
    }
  });

  test('missing native styles never falls back to global style catalog', () {
    final package = OpcPackage.openBytes(_fixture());
    final rels = package.relationshipsFor('/word/document.xml');
    rels.removeById(rels.firstByType(RelationshipTypes.styles)!.id);
    _refuses(_read(package.save()), _step(builtin: -1));
  });

  test('duplicate styles relationships are refused', () {
    final package = OpcPackage.openBytes(_fixture());
    package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.styles, target: 'styles.xml');
    _refuses(_read(package.save()), _step(builtin: -1));
  });

  for (final kind in ['paragraph', 'inlines', 'run']) {
    test('shared mutable $kind cannot alias selected target', () {
      final document = _read(_fixture());
      final paragraphs = document.paragraphs.toList();
      switch (kind) {
        case 'paragraph':
          document.sections.first.blocks.add(paragraphs.first);
        case 'inlines':
          paragraphs.last.inlines = paragraphs.first.inlines;
        case 'run':
          paragraphs.last.inlines[0] = paragraphs.first.inlines[0];
      }
      _refuses(document, _step(builtin: -2), matcher: throwsStateError);
    });
  }
  for (final kind in ['properties', 'run properties']) {
    test('shared $kind are detached without changing the other paragraph', () {
      final document = _read(_fixture());
      final target = document.paragraphs.first;
      final other = document.paragraphs.last;
      final targetRun = target.inlines.single as WmlRun;
      final otherRun = other.inlines.single as WmlRun;
      if (kind == 'properties') {
        other.properties = target.properties;
      } else {
        otherRun.properties = targetRun.properties;
      }
      final otherProperties = other.properties;
      final otherRunProperties = otherRun.properties;
      final otherSource = otherProperties.sourcePropertiesXml;
      final otherRunSource = otherRunProperties.sourcePropertiesXml;
      final otherImported = Map<String, String>.of(
        otherProperties.importedValues ?? {},
      );
      final otherRunImported = Map<String, String>.of(
        otherRunProperties.importedValues ?? {},
      );
      native.applyStep(document, _step(builtin: -2));
      expect(target.properties.styleId, 'ReportHeading');
      expect(targetRun.properties.bold, isTrue);
      expect(other.properties, same(otherProperties));
      expect(otherRun.properties, same(otherRunProperties));
      expect(target.properties, isNot(same(otherProperties)));
      expect(targetRun.properties, isNot(same(otherRunProperties)));
      expect(otherProperties.sourcePropertiesXml, otherSource);
      expect(otherRunProperties.sourcePropertiesXml, otherRunSource);
      expect(otherProperties.importedValues ?? {}, otherImported);
      expect(otherRunProperties.importedValues ?? {}, otherRunImported);
      expect(otherProperties.styleId, isNull);
      expect(otherRunProperties.bold, isFalse);
      final reopened = _read(WordSerializer().writeBytes(document));
      expect(reopened.paragraphs.first.properties.styleId, 'ReportHeading');
      expect(reopened.paragraphs.last.properties.styleId, isNull);
      expect(
        (reopened.paragraphs.last.inlines.single as WmlRun).properties.bold,
        isFalse,
      );
    });
  }
  test('unchanged numbering retains labels and pending direct formatting', () {
    final package = OpcPackage.openBytes(
      _fixture(
        properties:
            '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>',
      ),
    );
    final numbering =
        package.getPart('/word/numbering.xml') ??
        package.createPart(
          '/word/numbering.xml',
          OfficeContentTypes.wordNumbering,
        );
    numbering.writeText(
      '<w:numbering xmlns:w="$_w"><w:abstractNum w:abstractNumId="0">'
      '<w:lvl w:ilvl="0"><w:start w:val="3"/><w:numFmt w:val="decimal"/>'
      '<w:lvlText w:val="%1."/></w:lvl></w:abstractNum>'
      '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>',
    );
    final relationships = package.relationshipsFor('/word/document.xml');
    if (relationships.byType(RelationshipTypes.numbering).isEmpty) {
      relationships.add(
        type: RelationshipTypes.numbering,
        target: 'numbering.xml',
      );
    }
    String xml(XmlElement node) =>
        XmlDocument(root: node.copy()).toXmlString(declaration: false);
    final sourceNumbering = XmlDocument.parse(numbering.readText()).root!;
    final sourceDefinition = xml(
      sourceNumbering.firstChild('abstractNum', namespaceUri: _w)!,
    );
    final sourceInstance = xml(
      sourceNumbering.firstChild('num', namespaceUri: _w)!,
    );
    var document = _read(package.save());
    expect(document.paragraphs.first.properties.listLabel, '3. ');
    final other = document.paragraphs.last.properties;
    native.applyStep(document, {
      'op': 'paragraphFormat',
      'paragraph': 0,
      'after': 7,
    });
    native.applyStep(document, _step(builtin: -2));
    expect(document.paragraphs.last.properties, same(other));
    for (var cycle = 0; cycle < 3; cycle++) {
      final properties = document.paragraphs.first.properties;
      expect(properties.styleId, 'ReportHeading');
      expect(properties.spacingAfter, 7);
      expect(properties.numId, 1);
      expect(properties.ilvl, 0);
      expect(properties.listLabel, '3. ');
      expect(document.paragraphs.last.properties.listLabel, isNull);
      final bytes = WordSerializer().writeBytes(document);
      final savedNumbering = XmlDocument.parse(
        OpcPackage.openBytes(bytes).getPart('/word/numbering.xml')!.readText(),
      ).root!;
      // The ordinary exporter may add its unused fallback list definitions.
      // The selected native instance and its operative definition stay intact.
      expect(
        xml(
          savedNumbering
              .childrenNamed('abstractNum', namespaceUri: _w)
              .singleWhere(
                (node) =>
                    node.getAttribute('abstractNumId', namespaceUri: _w) == '0',
              ),
        ),
        sourceDefinition,
      );
      expect(
        xml(
          savedNumbering
              .childrenNamed('num', namespaceUri: _w)
              .singleWhere(
                (node) => node.getAttribute('numId', namespaceUri: _w) == '1',
              ),
        ),
        sourceInstance,
      );
      document = _read(bytes);
    }
  });
  test('style introducing numbering is refused before publication', () {
    final styles = _styles.replaceFirst(
      '<w:spacing w:before="240"/>',
      '<w:spacing w:before="240"/><w:numPr><w:numId w:val="1"/></w:numPr>',
    );
    _refuses(_read(_fixture(styles: styles)), _step(builtin: -2));
  });
}
