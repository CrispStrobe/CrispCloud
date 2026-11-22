import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/odt_reader_text_style.dart';
import 'package:test/test.dart';

// Synthetic conversion coverage, separate from installed-plugin acceptance.
const _namespaces = '''
xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
xmlns:xlink="http://www.w3.org/1999/xlink"''';
const _url = 'https://example.test/source';
const _mixed = '''
fo:color="#123456" fo:font-size="11pt" fo:font-family="Liberation Serif"
style:font-family-complex="Amiri" style:font-size-complex="10pt"
style:font-family-asian="Noto Serif CJK SC" style:font-size-asian="14pt"''';

String _style(String name, String properties, {String? parent}) =>
    '<style:style style:name="$name" style:family="text" '
    '${parent == null ? '' : 'style:parent-style-name="$parent"'}>'
    '<style:text-properties $properties/></style:style>';

String _link(String content) =>
    '<text:a xlink:href="$_url" text:style-name="Primary" '
    'text:visited-style-name="Visited">$content</text:a>';

Uint8List _package(
  String content, {
  String common = '',
  String primary = '',
  String visited = '',
  String extraStyles = '',
  bool missingVisited = false,
}) {
  final writer = ZipWriter()
    ..addFile(
      'mimetype',
      utf8.encode('application/vnd.oasis.opendocument.text'),
      store: true,
    )
    ..addFile(
      'content.xml',
      utf8.encode(
        '<office:document-content $_namespaces><office:automatic-styles>'
        '${_style('Shared', common)}'
        '${_style('Primary', primary, parent: 'Shared')}'
        '${missingVisited ? '' : _style('Visited', visited, parent: 'Shared')}'
        '$extraStyles</office:automatic-styles><office:body><office:text>'
        '<text:p>$content</text:p>'
        '</office:text></office:body></office:document-content>',
      ),
    );
  return writer.close();
}

List<WmlRun> _linked(WmlDocument document) => document.paragraphs.single.inlines
    .whereType<WmlRun>()
    .where((run) => run.hyperlink?.url == _url)
    .toList();

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

Matcher get _refused =>
    throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>()));

String _citation() {
  final data = {
    'citationID': 'linked-source-neighbor',
    'citationItems': [
      {
        'id': 1,
        'itemData': {'id': 1, 'type': 'book', 'title': 'Source'},
      },
    ],
    'properties': {'plainCitation': '(Source)', 'noteIndex': 0},
  };
  final name = encodeXmlAttribute(
    'ZOTERO_ITEM CSL_CITATION ${jsonEncode(data)} RND0123456789',
  );
  return '<text:reference-mark-start text:name="$name"/>(Source)'
      '<text:reference-mark-end text:name="$name"/>';
}

void main() {
  test('absent language differs from a literal null language tag', () {
    final absent = OdtReaderTextStyle.from(
      WmlRunProps(complexScriptLanguage: 'ar', noProof: false),
    );
    absent.asian
      ..language = 'ja'
      ..languageSpecified = true;
    final literal = absent.copy()..proofingLanguage = 'null';
    expect(absent.hasSameResolvedFormattingAs(literal), isFalse);
  });

  test(
    'equal inherited link states retain all scripts over DOCX saves',
    () async {
      const linked = 'Aب漢😀';
      final bytes = _package(
        'Before ${_link(linked)} after',
        common: _mixed,
      );
      final original = Uint8List.fromList(bytes);
      var document = await OdtDocumentReader.readBytes(bytes);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(document.paragraphs.single.text, 'Before $linked after');
        final runs = _linked(document);
        expect(runs.map((run) => run.text), ['A', 'ب', '漢', '😀']);
        expect(runs.map((run) => run.properties.fontSizeHalfPoints), [
          22,
          20,
          28,
          22,
        ]);
        expect(runs.every((run) => run.properties.color == '123456'), isTrue);
        expect(runs[1].properties.csFont, 'Amiri');
        expect(runs[2].properties.asciiFont, 'Noto Serif CJK SC');
        document = _reopen(document);
      }
      expect(bytes, orderedEquals(original));
    },
  );

  test('equal parent state keeps descendant character formatting', () async {
    final document = await OdtDocumentReader.readBytes(
      _package(
        _link(
          '<text:span text:style-name="Bold">Aب</text:span>'
          '<text:span text:style-name="Italic">B漢</text:span>',
        ),
        common: 'fo:color="#234567"',
        extraStyles:
            '${_style('Bold', 'fo:font-weight="bold"')}'
            '${_style('Italic', 'fo:font-style="italic"')}',
      ),
    );
    for (final current in [document, _reopen(document)]) {
      expect(current.paragraphs.single.text, 'AبB漢');
      final runs = _linked(current);
      expect(runs.map((run) => run.text), ['A', 'ب', 'B', '漢']);
      expect(runs.take(2).every((run) => run.properties.bold), isTrue);
      expect(runs.skip(2).every((run) => run.properties.italic), isTrue);
      expect(runs.every((run) => run.properties.color == '234567'), isTrue);
    }
  });

  test('adjacent citation remains editable with exact Unicode offsets', () async {
    const linkText = 'Aب漢😀';
    const prefix = 'Before $linkText ';
    final bytes = _package(
      'Before ${_link(linkText)} ${_citation()} after',
      common: _mixed,
    );
    var document = await OdtDocumentReader.readBytes(bytes);
    for (var cycle = 0; cycle < 3; cycle++) {
      final cache = cycle == 0 ? '(Source)' : '(Updated source)';
      final field = WordZotero.fields(document).single;
      expect(field.canEdit, isTrue);
      expect(field.citation!.citationId, 'linked-source-neighbor');
      expect(field.start, prefix.length);
      expect(field.end, prefix.length + cache.length);
      expect(field.cachedText, cache);
      expect(document.paragraphs.single.text, '$prefix$cache after');
      expect(_linked(document).map((run) => run.text).join(), linkText);
      if (cycle == 0) {
        WordZotero.updateCitation(
          field,
          field.citation!.withItems(
            field.citation!.items,
            plainCitation: '(Updated source)',
          ),
        );
      }
      document = _reopen(document);
    }
  });

  for (final entry in <String, (String, String)>{
    'color': ('fo:color="#0000ff"', 'fo:color="#800080"'),
    'size': ('fo:font-size="11pt"', 'fo:font-size="16pt"'),
    'weight': ('fo:font-weight="normal"', 'fo:font-weight="bold"'),
    'italic': ('fo:font-style="normal"', 'fo:font-style="italic"'),
    'underline': (
      'style:text-underline-style="none"',
      'style:text-underline-style="solid"',
    ),
    'language': ('fo:language="en"', 'fo:language="fr"'),
    'kerning': (
      'style:letter-kerning="true"',
      'style:letter-kerning="false"',
    ),
    'complex size': (
      'style:font-size-complex="10pt"',
      'style:font-size-complex="16pt"',
    ),
    'complex weight': (
      'style:font-weight-complex="normal"',
      'style:font-weight-complex="bold"',
    ),
    'Asian size': (
      'style:font-size-asian="10pt"',
      'style:font-size-asian="16pt"',
    ),
    'Asian italic': (
      'style:font-style-asian="normal"',
      'style:font-style-asian="italic"',
    ),
  }.entries) {
    test(
      'different ${entry.key} in the visited state refuses atomically',
      () async {
        final bytes = _package(
          _link('Latin'),
          primary: entry.value.$1,
          visited: entry.value.$2,
        );
        final original = Uint8List.fromList(bytes);
        await expectLater(OdtDocumentReader.readBytes(bytes), _refused);
        expect(bytes, orderedEquals(original));
      },
    );
  }

  test(
    'equal current weights cannot conceal child-span fallback changes',
    () async {
      // Both link states initially project normal complex-script weight. Only
      // Primary inherits later Western weight, because Visited fixes that slot.
      final bytes = _package(
        _link('<text:span text:style-name="Bold">ب</text:span>'),
        common: 'fo:font-weight="normal"',
        visited: 'style:font-weight-complex="normal"',
        extraStyles: _style('Bold', 'fo:font-weight="bold"'),
      );
      await expectLater(OdtDocumentReader.readBytes(bytes), _refused);
    },
  );

  test('equal current fonts cannot conceal complex-font inheritance', () async {
    final bytes = _package(
      _link('<text:span text:style-name="Serif">ب</text:span>'),
      common: 'fo:font-family="Liberation Sans"',
      visited: 'style:font-family-complex="Liberation Sans"',
      extraStyles: _style('Serif', 'fo:font-family="Liberation Serif"'),
    );
    await expectLater(OdtDocumentReader.readBytes(bytes), _refused);
  });

  test(
    'different parent states remain refused even if a child masks color',
    () async {
      final bytes = _package(
        _link('<text:span text:style-name="Override">Text</text:span>'),
        primary: 'fo:color="#0000ff"',
        visited: 'fo:color="#800080"',
        extraStyles: _style('Override', 'fo:color="#123456"'),
      );
      await expectLater(OdtDocumentReader.readBytes(bytes), _refused);
    },
  );

  test('missing visited styles on ordinary text remain refused', () async {
    await expectLater(
      OdtDocumentReader.readBytes(
        _package(_link('Text'), missingVisited: true),
      ),
      _refused,
    );
  });

  test('unsupported properties on a visited style remain refused', () async {
    await expectLater(
      OdtDocumentReader.readBytes(
        _package(_link('Text'), visited: 'fo:text-shadow="1pt 1pt"'),
      ),
      _refused,
    );
  });
}
