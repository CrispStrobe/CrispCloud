import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _x = 'urn:paragraph-shading-tests';
const _normal =
    '<w:style w:type="paragraph" w:styleId="Normal" w:default="1">'
    '<w:name w:val="Normal"/></w:style>';

Uint8List _fixture({
  String properties = '',
  String? body,
  String styles = _normal,
  String prefix = 'w',
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<$prefix:document xmlns:$prefix="$_w" xmlns:x="$_x" '
        'xmlns:mc="${OfficeNamespaces.mc}"><$prefix:body>'
        '${body ?? '<$prefix:p><$prefix:pPr>$properties</$prefix:pPr>'
                '<$prefix:r><$prefix:rPr><$prefix:i/></$prefix:rPr>'
                '<$prefix:t>Original</$prefix:t></$prefix:r></$prefix:p>'}'
        '<$prefix:sectPr/></$prefix:body></$prefix:document>',
      );
  package
      .getPart('/word/styles.xml')!
      .writeText(
        '<w:styles xmlns:w="$_w" xmlns:x="$_x" '
        'xmlns:mc="${OfficeNamespaces.mc}">$styles</w:styles>',
      );
  return package.save();
}

WmlDocument _read(Uint8List bytes) => WordDeserializer().readBytes(bytes);
Map<String, Object?> _step(Object? color, {int paragraph = 0}) => {
  'op': 'paragraphShading',
  'paragraph': paragraph,
  'color': color,
};
XmlElement _pPr(Uint8List bytes, {int paragraph = 0}) =>
    XmlDocument.parse(
          OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
        ).root!
        .firstChild('body', namespaceUri: _w)!
        .childrenNamed('p', namespaceUri: _w)
        .elementAt(paragraph)
        .firstChild('pPr', namespaceUri: _w)!;
XmlElement _shading(Uint8List bytes) =>
    _pPr(bytes).firstChild('shd', namespaceUri: _w)!;
Map<String, Uint8List> _parts(WmlDocument doc) => {
  for (final part in doc.package!.parts)
    part.uri: doc.package!.getPart(part.uri)!.readBytes(),
};

void _refuses(
  WmlDocument document,
  Map<String, Object?> step, {
  Matcher? matcher,
}) {
  final paragraph = document.paragraphs.first;
  final properties = paragraph.properties;
  final inlines = paragraph.inlines;
  final before = _parts(document);
  final source = properties.sourcePropertiesXml;
  final imported = Map<String, String>.of(properties.importedValues ?? {});
  expect(
    () => native.applyStep(document, step),
    matcher ?? throwsUnsupportedError,
  );
  expect(paragraph.properties, same(properties));
  expect(paragraph.inlines, same(inlines));
  expect(properties.sourcePropertiesXml, source);
  expect(properties.importedValues ?? {}, imported);
  expect(_parts(document), before);
}

void main() {
  for (final color in ['000000', 'FFFFFF', '1A2B3C', 'FFFF00', 'auto']) {
    test('$color owns a native solid background through three reopens', () {
      final doc = _read(_fixture());
      final paragraph = doc.paragraphs.single;
      final inlines = paragraph.inlines;
      final run = inlines.single;
      native.applyStep(doc, _step(color));
      expect(paragraph.inlines, same(inlines));
      expect(paragraph.inlines.single, same(run));
      var saved = WordSerializer().writeBytes(doc);
      for (var i = 0; i < 3; i++) {
        final shading = _shading(saved);
        expect(shading.getAttribute('fill', namespaceUri: _w), color);
        expect(shading.getAttribute('val', namespaceUri: _w), 'clear');
        final reopened = _read(saved);
        expect(
          reopened.paragraphs.single.properties.shadingFill,
          color == 'auto' ? isNull : color,
        );
        expect(reopened.paragraphs.single.text, 'Original');
        expect(
          reopened.paragraphs.single.inlines
              .whereType<WmlRun>()
              .single
              .properties
              .italic,
          isTrue,
        );
        saved = WordSerializer().writeBytes(reopened);
      }
    });
  }

  for (final value in <Object?>[
    null,
    true,
    0,
    16777215,
    '',
    '#FFFFFF',
    'ffffff',
    'AUTO',
    'FFFFFFF',
    'ZZZZZZ',
  ]) {
    test('invalid native color $value is atomic', () {
      _refuses(_read(_fixture()), _step(value), matcher: throwsArgumentError);
    });
  }

  test('missing color and extra fields refuse without mutation', () {
    final doc = _read(_fixture());
    _refuses(doc, {
      'op': 'paragraphShading',
      'paragraph': 0,
    }, matcher: throwsArgumentError);
    _refuses(doc, {
      ..._step('FFFFFF'),
      'texture': 'clear',
    }, matcher: throwsArgumentError);
  });

  test('authored and imported empty paragraphs retain their structure', () {
    for (final doc in [
      WmlDocument(
        sections: [
          WmlSection(blocks: [WmlParagraph()]),
        ],
      ),
      _read(_fixture(body: '<w:p/>')),
    ]) {
      native.applyStep(doc, _step('123456'));
      expect(doc.paragraphs.single.inlines, isEmpty);
      var bytes = WordSerializer().writeBytes(doc);
      for (var cycle = 0; cycle < 2; cycle++) {
        final next = _read(bytes);
        expect(next.paragraphs.single.text, isEmpty);
        expect(next.paragraphs.single.inlines, isEmpty);
        expect(next.paragraphs.single.properties.shadingFill, '123456');
        bytes = WordSerializer().writeBytes(next);
      }
    }
  });

  for (final color in ['336699', 'auto']) {
    test('$color overrides inherited shading without pinning other properties', () {
      const styles =
          '<w:style w:type="paragraph" w:styleId="Normal" w:default="1">'
          '<w:name w:val="Normal"/><w:pPr><w:shd w:val="clear" w:fill="336699"/>'
          '<w:spacing w:after="180"/></w:pPr></w:style>';
      final doc = _read(_fixture(styles: styles));
      expect(doc.paragraphs.single.properties.shadingFill, '336699');
      native.applyStep(doc, _step(color));
      final bytes = WordSerializer().writeBytes(doc);
      expect(_pPr(bytes).firstChild('spacing', namespaceUri: _w), isNull);
      expect(_shading(bytes).getAttribute('fill', namespaceUri: _w), color);
      final package = OpcPackage.openBytes(bytes);
      package
          .getPart('/word/styles.xml')!
          .writeText(
            '<w:styles xmlns:w="$_w">${styles.replaceAll('336699', 'AA5500').replaceAll('180', '600')}</w:styles>',
          );
      final reopened = WordDeserializer().read(package);
      expect(
        reopened.paragraphs.single.properties.shadingFill,
        color == 'auto' ? isNull : color,
      );
      expect(reopened.paragraphs.single.properties.spacingAfter, 30);
      expect(
        _shading(
          WordSerializer().writeBytes(reopened),
        ).getAttribute('fill', namespaceUri: _w),
        color,
      );
    });
  }

  test(
    'native aliases and foreign attributes/children survive without rebinding',
    () {
      final doc = _read(
        _fixture(
          prefix: 'n',
          properties:
              '<n:shd xmlns:w="$_x" n:val="clear" n:fill="AABBCC" '
              'n:color="auto" x:fill="foreign-fill" x:token="keep">'
              '<w:metadata w:value="opaque"><n:shd n:val="pct25" n:fill="445566"/></w:metadata>'
              '</n:shd><x:shd n:fill="778899"/><n:keepNext x:token="keep-next"/>',
        ),
      );
      expect(doc.paragraphs.single.properties.shadingFill, 'AABBCC');
      native.applyStep(doc, _step('010203'));
      var saved = WordSerializer().writeBytes(doc);
      for (var i = 0; i < 3; i++) {
        final shading = _shading(saved);
        expect(shading.getAttribute('fill', namespaceUri: _w), '010203');
        expect(shading.getAttribute('color', namespaceUri: _w), 'auto');
        expect(shading.getAttribute('fill', namespaceUri: _x), 'foreign-fill');
        expect(shading.getAttribute('token', namespaceUri: _x), 'keep');
        final metadata = shading.firstChild('metadata', namespaceUri: _x)!;
        expect(metadata.getAttribute('value', namespaceUri: _x), 'opaque');
        expect(
          metadata
              .firstChild('shd', namespaceUri: _w)!
              .getAttribute('fill', namespaceUri: _w),
          '445566',
        );
        expect(_pPr(saved).firstChild('shd', namespaceUri: _x), isNotNull);
        expect(
          _pPr(saved)
              .firstChild('keepNext', namespaceUri: _w)!
              .getAttribute('token', namespaceUri: _x),
          'keep-next',
        );
        final reopened = _read(saved);
        expect(reopened.paragraphs.single.properties.shadingFill, '010203');
        saved = WordSerializer().writeBytes(reopened);
      }
    },
  );

  test(
    'source materialization preserves earlier pending paragraph and run edits',
    () {
      final doc = _read(
        _fixture(
          properties: '<w:shd w:val="clear" w:fill="AABBCC" x:token="keep"/>',
        ),
      );
      native.applyStep(doc, {
        'op': 'paragraphFormat',
        'paragraph': 0,
        'before': 18,
        'rtl': true,
      });
      native.applyStep(doc, {'op': 'runFormat', 'paragraph': 0, 'bold': true});
      native.applyStep(doc, {
        'op': 'replaceText',
        'paragraph': 0,
        'start': 0,
        'end': 0,
        'text': 'Ready: ',
      });
      native.applyStep(doc, _step('FFFF00'));
      native.applyStep(doc, {
        'op': 'paragraphFormat',
        'paragraph': 0,
        'after': 12,
      });
      final reopened = _read(WordSerializer().writeBytes(doc));
      final paragraph = reopened.paragraphs.single;
      expect(paragraph.text, 'Ready: Original');
      expect(paragraph.properties.spacingBefore, 18);
      expect(paragraph.properties.spacingAfter, 12);
      expect(paragraph.properties.rightToLeft, isTrue);
      expect(paragraph.properties.shadingFill, 'FFFF00');
      expect(
        paragraph.inlines.whereType<WmlRun>().every(
          (run) => run.properties.bold,
        ),
        isTrue,
      );
    },
  );

  test(
    'style assignment before and after shading preserves direct ownership',
    () {
      const styles =
          '$_normal<w:style w:type="paragraph" w:styleId="Target">'
          '<w:name w:val="Report"/><w:pPr><w:shd w:val="clear" w:fill="AABBCC"/>'
          '<w:spacing w:before="200"/></w:pPr></w:style>';
      final doc = _read(_fixture(styles: styles));
      native.applyStep(doc, {
        'op': 'paragraphStyle',
        'paragraph': 0,
        'name': 'Report',
      });
      native.applyStep(doc, _step('auto'));
      native.applyStep(doc, {
        'op': 'paragraphStyle',
        'paragraph': 0,
        'builtin': -1,
      });
      final bytes = WordSerializer().writeBytes(doc);
      expect(_shading(bytes).getAttribute('fill', namespaceUri: _w), 'auto');
      expect(_read(bytes).paragraphs.single.properties.shadingFill, isNull);
    },
  );

  test('unselected patterned paragraph and unrelated style remain unchanged', () {
    final doc = _read(
      _fixture(
        styles:
            '$_normal<w:style w:type="paragraph" w:styleId="Unused"><w:pPr>'
            '<w:shd w:val="pct25" w:themeFill="accent1"/></w:pPr></w:style>',
        body:
            '<w:p><w:r><w:t>Selected</w:t></w:r></w:p>'
            '<w:p><w:pPr><w:shd w:val="pct25" w:color="111111" w:fill="778899"/></w:pPr>'
            '<w:r><w:t>Untouched</w:t></w:r></w:p>',
      ),
    );
    native.applyStep(doc, _step('ABCDEF'));
    final bytes = WordSerializer().writeBytes(doc);
    expect(
      _pPr(bytes, paragraph: 1)
          .firstChild('shd', namespaceUri: _w)!
          .getAttribute('val', namespaceUri: _w),
      'pct25',
    );
    _refuses(doc, _step('123456', paragraph: 1));
  });

  for (final properties in [
    '<w:shd w:val="pct25" w:fill="123456"/>',
    '<w:shd w:val="nil" w:fill="123456"/>',
    '<w:shd w:val="solid" w:fill="123456"/>',
    '<w:shd w:val="clear" w:fill="123456" w:themeFill="accent1"/>',
    '<w:shd w:val="clear" w:fill="123456" w:themeColor="accent1"/>',
    '<w:shd w:val="clear" w:fill="123456" w:themeFillTint="80"/>',
    '<w:shd w:val="clear" w:fill="broken"/>',
    '<w:shd w:val="clear" w:color="broken"/>',
    '<w:shd w:val="clear" w:fill="123456"/><w:shd w:val="clear"/>',
    '<w:shd w:val="clear" w:fill="123456" xmlns:n="$_w" n:fill="654321"/>',
    '<w:shd w:val="clear"><w:color w:val="123456"/></w:shd>',
  ]) {
    test('unsupported direct source refuses atomically: $properties', () {
      _refuses(_read(_fixture(properties: properties)), _step('ABCDEF'));
    });
  }

  for (final shading in [
    '<w:shd w:val="pct25" w:fill="123456"/>',
    '<w:shd w:val="clear" w:themeFill="accent1" w:fill="123456"/>',
  ]) {
    test('inherited default and explicit style source refuse: $shading', () {
      final styles =
          '<w:style w:type="paragraph" w:styleId="Normal" w:default="1">'
          '<w:pPr>$shading</w:pPr></w:style>';
      _refuses(_read(_fixture(styles: styles)), _step('ABCDEF'));
      _refuses(
        _read(
          _fixture(
            styles:
                '$_normal<w:style w:type="paragraph" w:styleId="Base">'
                '<w:pPr>$shading</w:pPr></w:style><w:style w:type="paragraph" w:styleId="Child">'
                '<w:basedOn w:val="Base"/></w:style>',
            properties: '<w:pStyle w:val="Child"/>',
          ),
        ),
        _step('ABCDEF'),
      );
    });
  }

  test('native document defaults and selected table-style shading are guarded', () {
    _refuses(
      _read(
        _fixture(
          styles:
              '$_normal<w:docDefaults><w:pPrDefault><w:pPr>'
              '<w:shd w:val="pct25" w:fill="123456"/></w:pPr></w:pPrDefault></w:docDefaults>',
        ),
      ),
      _step('FFFFFF'),
    );
    _refuses(
      _read(
        _fixture(
          styles:
              '$_normal<w:style w:type="table" w:styleId="T">'
              '<w:pPr><w:shd w:val="clear" w:themeFill="accent1"/></w:pPr></w:style>',
          body:
              '<w:tbl><w:tblPr><w:tblStyle w:val="T"/></w:tblPr><w:tblGrid><w:gridCol w:w="4000"/></w:tblGrid>'
              '<w:tr><w:tc><w:p><w:r><w:t>Cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>',
        ),
      ),
      _step('FFFFFF'),
    );
  });

  for (final styles in [
    '$_normal$_normal',
    '<w:style w:styleId="A"><w:basedOn w:val="B"/></w:style><w:style w:styleId="B"><w:basedOn w:val="A"/></w:style>',
    '<w:style w:styleId="A"><w:basedOn w:val="Missing"/></w:style>',
    '<w:style w:type="character" w:styleId="A"/><w:style w:styleId="B"><w:basedOn w:val="A"/></w:style>',
    '<w:style w:styleId="A" w:default="1"/><w:style w:styleId="B" w:default="true"/>',
  ]) {
    test('ambiguous style graph refuses before changing source: $styles', () {
      _refuses(_read(_fixture(styles: styles)), _step('ABCDEF'));
    });
  }

  test('missing and wrong-type paragraph style references refuse', () {
    _refuses(
      _read(_fixture(properties: '<w:pStyle w:val="Missing"/>')),
      _step('ABCDEF'),
    );
    _refuses(
      _read(
        _fixture(
          properties: '<w:pStyle w:val="Character"/>',
          styles: '$_normal<w:style w:type="character" w:styleId="Character"/>',
        ),
      ),
      _step('ABCDEF'),
    );
  });

  test(
    'uncommitted modeled style removal and ambiguous relationship refuse',
    () {
      final doc = _read(_fixture());
      doc.styles.clear();
      _refuses(doc, _step('ABCDEF'));
      final other = _read(_fixture());
      other.package!
          .relationshipsFor('/word/document.xml')
          .add(type: RelationshipTypes.styles, target: 'styles.xml');
      _refuses(other, _step('ABCDEF'));
    },
  );

  for (final body in [
    '<w:p><w:pPr/><w:pPr><w:shd w:val="clear"/></w:pPr><w:r><w:t>Duplicate</w:t></w:r></w:p>',
    '<w:p><w:pPr><mc:AlternateContent><mc:Choice Requires="x"><w:shd w:val="clear" w:fill="123456"/></mc:Choice>'
        '<mc:Fallback><w:shd w:val="clear" w:fill="654321"/></mc:Fallback></mc:AlternateContent></w:pPr>'
        '<w:r><w:t>Alternative</w:t></w:r></w:p>',
  ]) {
    test('ambiguous native property ownership refuses: $body', () {
      _refuses(_read(_fixture(body: body)), _step('ABCDEF'));
    });
  }

  test(
    'shared paragraph identity refuses and shared properties detach safely',
    () {
      final doc = _read(_fixture());
      final paragraph = doc.paragraphs.single;
      doc.sections.single.blocks.add(paragraph);
      _refuses(doc, _step('ABCDEF'), matcher: throwsStateError);
      doc.sections.single.blocks.removeLast();
      final original = paragraph.properties;
      final neighbor = WmlParagraph(
        properties: original,
        inlines: [WmlRun(text: 'Neighbor')],
      );
      doc.sections.single.blocks.add(neighbor);
      native.applyStep(doc, _step('ABCDEF'));
      expect(neighbor.properties, same(original));
      expect(neighbor.properties.shadingFill, isNull);
      expect(paragraph.properties, isNot(same(original)));
    },
  );

  test('solid fill produces layout shading and automatic removes it', () {
    final doc = _read(_fixture());
    final layout = WordLayoutEngine(font: null);
    native.applyStep(doc, _step('123456'));
    final colored = layout.layout(doc, updateFields: false);
    final boxes = colored.pages
        .expand((page) => page.frames)
        .where((box) => box.kind == LaidOutBoxKind.paragraphShade)
        .toList();
    expect(boxes, hasLength(1));
    expect(boxes.single.fillColor, '123456');
    native.applyStep(doc, _step('auto'));
    final reopened = _read(WordSerializer().writeBytes(doc));
    expect(
      layout
          .layout(reopened, updateFields: false)
          .pages
          .expand((page) => page.frames)
          .where((box) => box.kind == LaidOutBoxKind.paragraphShade),
      isEmpty,
    );
  });
}
