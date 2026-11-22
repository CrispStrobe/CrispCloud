import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/odt_reader_styles.dart';
import 'package:test/test.dart';

const _namespaces = '''
xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0"
xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"
xmlns:xlink="http://www.w3.org/1999/xlink"''';

const _mixedProperties = '''
fo:font-family="Liberation Serif" fo:font-size="11pt"
style:font-family-complex="Amiri" style:font-size-complex="10pt"
style:font-weight-complex="bold"
style:font-family-asian="Noto Serif CJK SC" style:font-size-asian="14pt"
style:font-style-asian="italic"''';
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAF0lEQVR4nGP4z8DwHwwZ/v8HIyABZgEAqm8O8tH19KMAAAAASUVORK5CYII=';
const _prefix = '😀 before ';
const _cachePrefix = 'straße ﬃ ';
const _cacheNormal = 'Keep';
const _cacheSuffix = ' e\u0301 العربية 漢😀';
const _cache = '$_cachePrefix$_cacheNormal$_cacheSuffix';

String _style(
  String name,
  String properties, {
  String family = 'text',
  String? parent,
}) =>
    '<style:style style:name="$name" style:family="$family" '
    '${parent == null ? '' : 'style:parent-style-name="$parent"'}>'
    '<style:text-properties $properties/></style:style>';

OdtReaderStyles _styles(String definitions) => OdtReaderStyles(
  XmlDocument.parse(
    '<office:document-content $_namespaces>'
    '<office:styles>$definitions</office:styles>'
    '</office:document-content>',
  ).root!,
);

Map<String, Object?> _metadata(String id) => {
  'citationID': id,
  'citationItems': [
    {
      'id': 17,
      'uris': ['http://zotero.org/users/42/items/ABCD1234'],
      'locator': '12–14',
      'label': 'page',
      'prefix': 'see ',
      'suppress-author': true,
      'itemData': {'id': 17, 'type': 'book', 'title': 'Mixed case Straße ﬃ'},
      'futureItem': {'caseSensitive': 'KeepCase'},
    },
  ],
  'properties': {'plainCitation': _cache, 'noteIndex': 0},
  'futureRoot': ['KeepCase', 'العربية 😀', true, null],
};

String _citation(String id, String html) {
  final name = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION ${jsonEncode(_metadata(id))} '
    'RND${id.padRight(10, '0')}',
  );
  return '<text:reference-mark-start text:name="$name"/>$html'
      '<text:reference-mark-end text:name="$name"/>';
}

Uint8List _odt(String body, {required String styles, bool withImage = false}) {
  final preferences = jsonEncode({
    'dataVersion': 4,
    'sessionID': 'uppercase-session',
    'style': {'styleID': 'http://www.zotero.org/styles/apa', 'locale': 'de-DE'},
    'prefs': {'fieldType': 'ReferenceMark', 'noteType': 0},
    'futurePreference': 'KeepCase 😀',
  });
  final zip = ZipWriter()
    ..addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.text'),
      store: true,
    )
    ..addFile(
      'content.xml',
      utf8.encode(
        '<office:document-content $_namespaces>'
        '<office:automatic-styles>$styles</office:automatic-styles>'
        '<office:body><office:text>$body</office:text></office:body>'
        '</office:document-content>',
      ),
    )
    ..addFile(
      'meta.xml',
      utf8.encode(
        '<office:document-meta $_namespaces><office:meta>'
        '<meta:user-defined meta:name="ZOTERO_PREF_1" meta:value-type="string">'
        '${const HtmlEscape(HtmlEscapeMode.element).convert(preferences)}'
        '</meta:user-defined></office:meta></office:document-meta>',
      ),
    );
  if (withImage) zip.addFile('Pictures/figure.png', base64Decode(_pngBase64));
  return zip.close();
}

List<bool?> _capsByOffset(WmlParagraph paragraph) => [
  for (final run in paragraph.inlines.whereType<WmlRun>())
    for (var offset = 0; offset < run.text.length; offset++)
      run.inlineVisual == null ? run.properties.allCaps : null,
];

void main() {
  test(
    'uppercase and explicit none cascade without mutating inherited style',
    () {
      final styles = _styles(
        '<style:default-style style:family="paragraph">'
        '<style:text-properties fo:text-transform="uppercase"/>'
        '</style:default-style>'
        '${_style('P', 'fo:font-style="italic"', family: 'paragraph')}'
        '${_style('Upper', 'fo:text-transform="uppercase"')}'
        '${_style('Inherited', 'fo:font-weight="bold"', parent: 'Upper')}'
        '${_style('Normal', 'fo:text-transform="none"', parent: 'Inherited')}'
        '${_style('Reenabled', 'fo:text-transform="uppercase"', parent: 'Normal')}',
      );
      final paragraph = styles.paragraphRunProperties('P');
      expect(paragraph.allCaps, isTrue);
      expect(paragraph.italic, isTrue);
      expect(styles.runProperties('Inherited').allCaps, isTrue);
      final normal = styles.runProperties('Normal', inherited: paragraph);
      expect(normal.allCaps, isFalse);
      expect(normal.bold, isTrue);
      expect(normal.italic, isTrue);
      expect(normal.explicitProperties, contains('allCaps'));
      expect(styles.runProperties('Reenabled').allCaps, isTrue);
      expect(paragraph.allCaps, isTrue);
      expect(styles.runProperties(null, inherited: normal).allCaps, isFalse);
      expect(styles.runProperties('Upper', inherited: normal).allCaps, isTrue);
    },
  );

  test('uppercase retains raw Unicode across independent script slots', () {
    final style = _styles(
      _style('Upper', '$_mixedProperties fo:text-transform="uppercase"'),
    ).runProperties('Upper');
    const raw = 'straße ﬃ e\u0301ب漢😀';
    final runs = style.materialize(raw).toList();
    expect(runs.map((run) => run.text).join(), raw);
    expect(runs.every((run) => run.properties.allCaps), isTrue);
    expect(runs.every((run) => !run.properties.smallCaps), isTrue);
    final complex = runs.singleWhere((run) => run.text == 'ب').properties;
    expect(complex.fontSizeHalfPoints, 20);
    expect(complex.csFont, 'Amiri');
    expect(complex.bold, isTrue);
    final asian = runs.singleWhere((run) => run.text == '漢').properties;
    expect(asian.fontSizeHalfPoints, 28);
    expect(asian.asciiFont, 'Noto Serif CJK SC');
    expect(asian.italic, isTrue);
    final copy = style.copy()..allCaps = false;
    expect(copy.materialize(raw).every((r) => !r.properties.allCaps), isTrue);
    expect(style.allCaps, isTrue);
  });

  test('ambiguous caps variants refuse only after effective inheritance', () {
    final styles = _styles(
      '${_style('Both', 'fo:text-transform="uppercase" fo:font-variant="small-caps"')}'
      '${_style('UpperOnly', 'fo:font-variant="normal"', parent: 'Both')}'
      '${_style('SmallOnly', 'fo:text-transform="none"', parent: 'Both')}'
      '${_style('Normal', 'fo:text-transform="none" fo:font-variant="normal"', parent: 'Both')}',
    );
    final ambiguous = styles.runProperties('Both');
    expect(() => ambiguous.materialize('Ab').toList(), throwsUnsupportedError);
    expect(ambiguous.nativeProperties, throwsUnsupportedError);
    final upper = styles.runProperties('UpperOnly').materialize('Ab').single;
    expect(
      (upper.properties.allCaps, upper.properties.smallCaps),
      (true, false),
    );
    final small = styles.runProperties('SmallOnly').materialize('Ab').single;
    expect(
      (small.properties.allCaps, small.properties.smallCaps),
      (false, true),
    );
    final normal = styles.runProperties('Normal').materialize('Ab').single;
    expect(
      (normal.properties.allCaps, normal.properties.smallCaps),
      (false, false),
    );
  });

  test(
    'lowercase, capitalization and malformed transforms remain unsupported',
    () {
      for (final transform in [
        'lowercase',
        'capitalize',
        'Uppercase',
        'inherit',
        '',
      ]) {
        expect(
          () => _styles(
            _style('Bad', 'fo:text-transform="$transform"'),
          ).runProperties('Bad'),
          throwsUnsupportedError,
          reason: transform,
        );
      }
    },
  );

  test(
    'native uppercase affects display while explicit none keeps authored case',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _odt(
          '<text:p text:style-name="Upper">Ab '
          '<text:span text:style-name="Normal">Cd</text:span> ef</text:p>',
          styles:
              '${_style('Upper', 'fo:text-transform="uppercase"', family: 'paragraph')}'
              '${_style('Normal', 'fo:text-transform="none"')}',
        ),
      );
      final line = WordLayoutEngine(
        font: null,
      ).layout(document).pages.single.lines.single;
      expect(
        String.fromCharCodes(line.glyphs.map((g) => g.glyph.codePoint)),
        'AB Cd EF',
      );
      expect(document.paragraphs.single.text, 'Ab Cd ef');
    },
  );

  test(
    'active citations and pictures retain raw offsets through ODT and DOCX cycles',
    () async {
      final bytes = _odt(
        '<text:p text:style-name="Upper">$_prefix'
        '${_citation('first', '$_cachePrefix<text:span text:style-name="Normal">$_cacheNormal</text:span>$_cacheSuffix')}'
        '<draw:frame text:anchor-type="as-char" svg:width="24pt" svg:height="16pt">'
        '<draw:image xlink:href="Pictures/figure.png" xlink:type="simple"/>'
        '<svg:title>KeepCase Figure</svg:title></draw:frame>'
        '<text:span text:style-name="Normal">${_citation('second', _cache)}</text:span>'
        ' tail</text:p>',
        styles:
            '${_style('Upper', '$_mixedProperties fo:text-transform="uppercase"', family: 'paragraph')}'
            '${_style('Normal', 'fo:text-transform="none"')}',
        withImage: true,
      );
      var document = await OdtDocumentReader.readBytes(bytes);
      final expectedCaps = <bool?>[
        ...List.filled(_prefix.length + _cachePrefix.length, true),
        ...List.filled(_cacheNormal.length, false),
        ...List.filled(_cacheSuffix.length, true),
        null,
        ...List.filled(_cache.length, false),
        ...List.filled(' tail'.length, true),
      ];
      void verify() {
        final paragraph = document.paragraphs.single;
        expect(paragraph.text, '$_prefix$_cache\uFFFC$_cache tail');
        expect(_capsByOffset(paragraph), expectedCaps);
        final fields = WordZotero.fields(document);
        expect(fields, hasLength(2));
        expect(fields.every((field) => field.canEdit), isTrue);
        expect(fields.map((field) => field.metadata), [
          _metadata('first'),
          _metadata('second'),
        ]);
        expect(fields.map((field) => field.cachedText), [_cache, _cache]);
        expect(fields.map((field) => field.start), [
          _prefix.length,
          _prefix.length + _cache.length + 1,
        ]);
        expect(fields.map((field) => field.end), [
          _prefix.length + _cache.length,
          _prefix.length + _cache.length * 2 + 1,
        ]);
        final picture = paragraph.inlines
            .whereType<WmlRun>()
            .singleWhere((run) => run.inlineVisual != null)
            .inlineVisual!
            .visual;
        expect(picture.imageBytes, orderedEquals(base64Decode(_pngBase64)));
        expect(picture.picture.altTitle, 'KeepCase Figure');
        expect(picture.width, 24);
        expect(picture.height, 16);
        final preferences =
            jsonDecode(WordZoteroDocumentData.read(document))
                as Map<String, Object?>;
        expect(preferences['futurePreference'], 'KeepCase 😀');
        expect(
          (preferences['style'] as Map<String, Object?>)['locale'],
          'de-DE',
        );
      }

      for (var cycle = 0; cycle < 3; cycle++) {
        verify();
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        verify();
        final exported = OdtDocumentWriter.writeEditableZoteroBytes(document);
        verify(); // Export must not normalize the live document's authored text.
        document = await OdtDocumentReader.readBytes(exported);
      }
      verify();
      final session = WordZoteroCitingSession(
        document: document,
        documentId: 'uppercase-wire',
        insertionParagraph: document.paragraphs.single,
      );
      final fields =
          (session.handle('Document.getFields', ['uppercase-wire', 'Http'])
                  as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(fields.map((field) => field['text']), [_cache, _cache]);
      expect(fields.map((field) => field['code']), [
        for (final id in ['first', 'second'])
          'ITEM CSL_CITATION ${jsonEncode(_metadata(id))}',
      ]);
    },
  );
}
