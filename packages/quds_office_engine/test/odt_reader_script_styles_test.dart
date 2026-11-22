import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/word/serial/odt_reader_styles.dart';
import 'package:quds_office_engine/src/word/serial/odt_reader_text_style.dart';
import 'package:quds_office_engine/src/word/serial/word_property_io.dart';
import 'package:test/test.dart';

const _namespaces = '''
xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
xmlns:loext="urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0"
xmlns:xlink="http://www.w3.org/1999/xlink"''';
const _word = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _mixedProperties = '''
fo:font-family="Liberation Serif" fo:font-size="11pt" fo:language="en" fo:country="US"
style:font-family-complex="Amiri" style:font-size-complex="10pt"
style:font-weight-complex="bold" style:language-complex="hi" style:country-complex="IN"
style:font-family-asian="Noto Serif CJK SC" style:font-size-asian="14pt"
style:font-style-asian="italic" style:language-asian="zh" style:country-asian="CN"''';

String _textStyle(String name, String attributes, {String? parent}) =>
    '<style:style style:name="$name" style:family="text" '
    '${parent == null ? '' : 'style:parent-style-name="$parent"'}>'
    '<style:text-properties $attributes/></style:style>';

OdtReaderStyles _styles(String definitions) => OdtReaderStyles(
  XmlDocument.parse(
    '<office:document-content $_namespaces>'
    '<office:automatic-styles>$definitions</office:automatic-styles>'
    '</office:document-content>',
  ).root!,
);

Uint8List _odt(
  String body, {
  String properties = _mixedProperties,
  String textStyles = '',
}) {
  final writer = ZipWriter();
  writer.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  writer.addFile(
    'content.xml',
    utf8.encode(
      '<office:document-content $_namespaces>'
      '<office:automatic-styles>'
      '<style:style style:name="Base" style:family="paragraph">'
      '<style:text-properties $properties/></style:style>'
      '$textStyles'
      '</office:automatic-styles>'
      '<office:body><office:text><text:p text:style-name="Base">$body</text:p>'
      '</office:text></office:body></office:document-content>',
    ),
  );
  return writer.close();
}

XmlElement _native(WmlRun run) =>
    XmlDocument.parse(run.properties.sourcePropertiesXml!).root!;

String? _nativeValue(WmlRun run, String name) =>
    _native(run).firstChild(name, namespaceUri: _word)?.getAttribute('val');

WmlRun _runContaining(WmlDocument document, String text) => document
    .paragraphs
    .single
    .inlines
    .whereType<WmlRun>()
    .singleWhere((run) => run.text.contains(text));

void main() {
  test(
    'cascades script sizes against their own parent and keeps native copies',
    () {
      final styles = _styles(
        '${_textStyle('Parent', _mixedProperties)}'
        '${_textStyle('Child', 'fo:font-size="200%" style:font-size-complex="150%" style:font-size-asian="50%" style:font-weight-complex="normal"', parent: 'Parent')}',
      );
      final inherited = styles.runProperties('Parent');
      final child = styles.runProperties('Child');
      final runs = child.materialize('Aب漢').toList();
      expect(runs.map((run) => run.text), ['A', 'ب', '漢']);
      expect(runs.map((run) => run.properties.fontSizeHalfPoints), [
        44,
        30,
        14,
      ]);
      expect(runs.map((run) => run.properties.bold), [false, false, false]);
      expect(runs.map((run) => run.properties.italic), [false, false, true]);
      expect(
        runs.every((run) => run.properties is! OdtReaderTextStyle),
        isTrue,
      );
      expect(
        inherited.materialize('ب').single.properties.fontSizeHalfPoints,
        20,
      );
      final copied = child.copy();
      copied.complex.size = 40;
      expect(child.materialize('ب').single.properties.fontSizeHalfPoints, 30);
    },
  );

  test('uses Asian slots for supplementary Kana, Tangut and Khitan', () async {
    // Kana Supplement/Extended-A/Small Kana, Tangut, Khitan, and Hangul
    // Extended-A/B are outside the older ODF Unicode block table.
    final asian = String.fromCharCodes([
      0x1b000,
      0x1b100,
      0x1b150,
      0x17000,
      0x18b00,
      0xa960,
      0xd7b0,
    ]);
    final original = 'A$asian😀';
    var document = await OdtDocumentReader.readBytes(_odt(original));
    for (var cycle = 0; cycle < 3; cycle++) {
      final runs = document.paragraphs.single.inlines
          .whereType<WmlRun>()
          .toList();
      expect(runs.map((run) => run.text), ['A', asian, '😀']);
      expect(runs.map((run) => run.text).join(), original);
      expect(runs.map((run) => run.properties.fontSizeHalfPoints), [
        22,
        28,
        22,
      ]);
      expect(runs[1].properties.asciiFont, 'Noto Serif CJK SC');
      expect(runs[1].properties.proofingLanguage, 'zh-CN');
      expect(runs[1].properties.italic, isTrue);
      if (cycle > 0) {
        expect(
          _native(runs[1]).firstChild('rFonts')?.getAttribute('eastAsia'),
          'Noto Serif CJK SC',
        );
        expect(
          _native(runs[1]).firstChild('lang')?.getAttribute('eastAsia'),
          'zh-CN',
        );
      }
      if (cycle < 2) {
        document = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
      }
    }
  });

  for (final scenario in [
    (
      name: 'Devanagari font-only',
      text: 'हिन्दी',
      font: 'Noto Serif Devanagari',
      language: 'en',
      country: 'US',
      editedFont: 'Noto Sans Devanagari',
    ),
    (
      name: 'Thai language-only',
      text: 'ภาษาไทย',
      font: 'Liberation Serif',
      language: 'th',
      country: 'TH',
      editedFont: 'Noto Sans Thai',
    ),
  ]) {
    test(
      '${scenario.name} selects the complex slots at equal sizes after edits',
      () async {
        const prefix = '😀 before ';
        final cache = '${scenario.text} / Latin';
        final metadata = {
          'citationID': 'complex-route',
          'citationItems': [
            {
              'id': 1,
              'itemData': {'id': 1, 'type': 'book', 'title': cache},
            },
          ],
          'properties': {'plainCitation': cache, 'noteIndex': 0},
        };
        final name = encodeXmlAttribute(
          'ZOTERO_ITEM CSL_CITATION ${jsonEncode(metadata)} RND0123456789',
        );
        var document = await OdtDocumentReader.readBytes(
          _odt(
            '$prefix<text:reference-mark-start text:name="$name"/>$cache'
            '<text:reference-mark-end text:name="$name"/> after',
            properties:
                'fo:font-family="Liberation Serif" fo:font-size="11pt" '
                'fo:language="en" fo:country="US" '
                'style:font-family-complex="${scenario.font}" '
                'style:font-size-complex="11pt" '
                'style:language-complex="${scenario.language}" style:country-complex="${scenario.country}"',
          ),
        );
        for (var cycle = 0; cycle < 4; cycle++) {
          final paragraph = document.paragraphs.single;
          final run = _runContaining(document, scenario.text);
          final font = cycle > 1 ? scenario.editedFont : scenario.font;
          expect(run.properties.fontSizeHalfPoints, 22);
          expect(run.properties.complexScript, isTrue);
          expect(run.properties.asciiFont, 'Liberation Serif');
          expect(run.properties.csFont, font);
          expect(
            OfficeTypeface.familyForRun(
              run.properties,
              scenario.text.runes.first,
            ),
            font,
          );
          expect(
            wordRunProofingLanguage(run, paragraph),
            '${scenario.language}-${scenario.country}',
          );
          final field = WordZotero.fields(document).single;
          expect(field.canEdit, isTrue);
          expect(field.start, prefix.length);
          expect(field.end, prefix.length + cache.length);
          expect(field.cachedText, cache);
          expect(field.metadata, metadata);
          expect(_nativeValue(run, 'cs'), '1');
          if (cycle > 0) {
            expect(
              _native(run).firstChild('rFonts')?.getAttribute('ascii'),
              'Liberation Serif',
            );
            expect(_native(run).firstChild('rFonts')?.getAttribute('cs'), font);
            expect(
              _native(run).firstChild('lang')?.getAttribute('val'),
              'en-US',
            );
            expect(
              _native(run).firstChild('lang')?.getAttribute('bidi'),
              '${scenario.language}-${scenario.country}',
            );
          }
          if (cycle == 1) run.properties.csFont = scenario.editedFont;
          if (cycle < 3) {
            document = WordDeserializer().readBytes(
              WordSerializer().writeBytes(document),
            );
          }
        }
      },
    );
  }

  test(
    'initially equal script slots retain edit ownership through DOCX saves',
    () async {
      const prefix = '😀 same ';
      const cache = 'हिन्दी漢字';
      final metadata = {
        'citationID': 'initially-equal-slots',
        'citationItems': [
          {
            'id': 1,
            'itemData': {'id': 1, 'type': 'book', 'title': cache},
          },
        ],
        'properties': {'plainCitation': cache, 'noteIndex': 0},
      };
      final name = encodeXmlAttribute(
        'ZOTERO_ITEM CSL_CITATION ${jsonEncode(metadata)} RND0123456789',
      );
      var document = await OdtDocumentReader.readBytes(
        _odt(
          '$prefix<text:reference-mark-start text:name="$name"/>$cache'
          '<text:reference-mark-end text:name="$name"/> tail',
          properties:
              'fo:font-family="Liberation Serif" fo:font-size="12pt" '
              'fo:language="en" fo:country="US" '
              'style:font-family-complex="Liberation Serif" style:font-size-complex="12pt" '
              'style:language-complex="en" style:country-complex="US" '
              'style:font-family-asian="Liberation Serif" style:font-size-asian="12pt" '
              'style:language-asian="en" style:country-asian="US"',
        ),
      );
      for (var cycle = 0; cycle < 4; cycle++) {
        final edited = cycle > 1;
        final paragraph = document.paragraphs.single;
        expect(paragraph.text, '$prefix$cache tail');
        final indic = _runContaining(document, 'हिन्दी');
        final asian = _runContaining(document, '漢字');
        final indicFont = edited ? 'Noto Sans Devanagari' : 'Liberation Serif';
        final asianFont = edited ? 'Noto Sans CJK JP' : 'Liberation Serif';
        final asianLanguage = edited ? 'ja-JP' : 'en-US';
        expect(indic.properties.complexScript, isTrue);
        expect(indic.properties.asciiFont, 'Liberation Serif');
        expect(indic.properties.csFont, indicFont);
        expect(
          OfficeTypeface.familyForRun(indic.properties, 'ह'.runes.single),
          indicFont,
        );
        expect(indic.properties.fontSizeHalfPoints, 24);
        expect(asian.properties.asciiFont, asianFont);
        expect(asian.properties.csFont, 'Liberation Serif');
        expect(asian.properties.fontSizeHalfPoints, 24);
        expect(wordRunProofingLanguage(asian, paragraph), asianLanguage);
        expect(_nativeValue(indic, 'cs'), '1');
        final field = WordZotero.fields(document).single;
        expect(field.canEdit, isTrue);
        expect(field.start, prefix.length);
        expect(field.end, prefix.length + cache.length);
        expect(field.cachedText, cache);
        expect(field.metadata, metadata);
        if (cycle > 0) {
          expect(
            _native(indic).firstChild('rFonts')?.getAttribute('cs'),
            indicFont,
          );
          expect(
            _native(indic).firstChild('rFonts')?.getAttribute('ascii'),
            'Liberation Serif',
          );
          expect(
            _native(asian).firstChild('rFonts')?.getAttribute('eastAsia'),
            asianFont,
          );
          expect(
            _native(asian).firstChild('rFonts')?.getAttribute('ascii'),
            asianFont,
          );
          expect(
            _native(asian).firstChild('lang')?.getAttribute('eastAsia'),
            asianLanguage,
          );
          expect(
            _native(asian).firstChild('lang')?.getAttribute('bidi'),
            'en-US',
          );
        }
        if (cycle == 1) {
          indic.properties.csFont = 'Noto Sans Devanagari';
          asian.properties
            ..asciiFont = 'Noto Sans CJK JP'
            ..proofingLanguage = 'ja-JP';
        }
        if (cycle < 3) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
      }
    },
  );

  test(
    'retains mark script across spans, fields, hyperlinks and equal formatting',
    () async {
      const variation = '\u{E0100}';
      final context = OdtReaderScriptContext();
      OdtReaderTextStyle.from(
        WmlRunProps(),
      ).materialize('漢', context: context).toList();
      final distinct = _styles(
        _textStyle('Asian', 'style:font-size-asian="14pt"'),
      ).runProperties('Asian');
      expect(
        distinct
            .materialize(variation, context: context)
            .single
            .properties
            .fontSizeHalfPoints,
        28,
      );

      const prefix = '😀 ';
      const cache = '漢$variation';
      final metadata = {
        'citationID': 'mark-context',
        'citationItems': [
          {
            'id': 1,
            'itemData': {'id': 1, 'type': 'book', 'title': cache},
          },
        ],
        'properties': {'plainCitation': cache, 'noteIndex': 0},
      };
      final name = encodeXmlAttribute(
        'ZOTERO_ITEM CSL_CITATION ${jsonEncode(metadata)} RND0123456789',
      );
      var document = await OdtDocumentReader.readBytes(
        _odt(
          '$prefix<text:reference-mark-start text:name="$name"/>漢'
          '<text:span text:style-name="ColorOnly">$variation</text:span>'
          '<text:reference-mark-end text:name="$name"/> 漢'
          '<text:a xlink:href="https://example.org/mark">'
          '<text:span text:style-name="ColorOnly">$variation</text:span></text:a>',
          textStyles: _textStyle('ColorOnly', 'fo:color="#ff0000"'),
        ),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(document.paragraphs.single.text, '$prefix$cache $cache');
        final marks = document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .where((run) => run.text == variation)
            .toList();
        expect(marks, hasLength(2));
        for (final run in marks) {
          expect(run.properties.fontSizeHalfPoints, 28);
          expect(run.properties.asciiFont, 'Noto Serif CJK SC');
          expect(run.properties.proofingLanguage, 'zh-CN');
          expect(run.properties.color, 'FF0000');
        }
        expect(marks.first.hyperlink, isNull);
        expect(marks.last.hyperlink?.url, 'https://example.org/mark');
        final field = WordZotero.fields(document).single;
        expect(field.start, prefix.length);
        expect(field.end, prefix.length + cache.length);
        expect(field.cachedText, cache);
        if (cycle < 2) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
      }
    },
  );

  test(
    'keeps Unicode, hyperlink, citation offsets and active slots over DOCX edits',
    () async {
      const prefix = '😀 e\u0301 ';
      const cache = 'العَرَبية\u200d 漢\u{E0100}𠀀 👩‍💻';
      const linked = 'بَ漢😀';
      const suffix = ' $linked tail';
      final metadata = {
        'citationID': 'script-projection',
        'citationItems': [
          {
            'id': 1,
            'itemData': {'id': 1, 'type': 'book', 'title': cache},
          },
        ],
        'properties': {'plainCitation': cache, 'noteIndex': 0},
        'unknown': {'retain': true},
      };
      final code =
          'ZOTERO_ITEM CSL_CITATION ${jsonEncode(metadata)} RND0123456789';
      final name = encodeXmlAttribute(code);
      final odt = _odt(
        '$prefix<text:reference-mark-start text:name="$name"/>'
        '$cache<text:reference-mark-end text:name="$name"/> '
        '<text:a xlink:href="https://example.org/source">$linked</text:a> tail',
      );
      final original = Uint8List.fromList(odt);
      var document = await OdtDocumentReader.readBytes(odt);
      for (var cycle = 0; cycle < 4; cycle++) {
        final edited = cycle > 1;
        expect(document.paragraphs.single.text, '$prefix$cache$suffix');
        final field = WordZotero.fields(document).single;
        expect(field.isValid, isTrue);
        expect(field.start, prefix.length);
        expect(field.end, prefix.length + cache.length);
        expect(field.cachedText, cache);
        expect(field.metadata, metadata);
        final arabic = _runContaining(document, 'العَرَبية\u200d');
        expect(arabic.properties.fontSizeHalfPoints, edited ? 32 : 20);
        expect(arabic.properties.bold, !edited);
        expect(arabic.properties.italic, edited);
        expect(
          arabic.properties.csFont,
          edited ? 'Noto Naskh Arabic' : 'Amiri',
        );
        expect(arabic.properties.complexScriptLanguage, 'hi-IN');
        expect(arabic.hyperlink, isNull);
        final asian = _runContaining(document, '漢\u{E0100}𠀀');
        expect(asian.properties.fontSizeHalfPoints, 28);
        expect(asian.properties.italic, isTrue);
        expect(
          asian.properties.asciiFont,
          edited ? 'Noto Sans CJK JP' : 'Noto Serif CJK SC',
        );
        expect(asian.properties.proofingLanguage, edited ? 'ja-JP' : 'zh-CN');
        expect(asian.hyperlink, isNull);
        final emoji = _runContaining(document, '👩‍💻');
        expect(emoji.properties.fontSizeHalfPoints, 22);
        expect(emoji.hyperlink, isNull);
        final linkedRuns = document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .where((run) => run.hyperlink != null)
            .toList();
        expect(linkedRuns.map((run) => run.text).join(), linked);
        expect(linkedRuns.map((run) => run.properties.fontSizeHalfPoints), [
          20,
          28,
          22,
        ]);
        expect(
          linkedRuns.every(
            (run) => run.hyperlink?.url == 'https://example.org/source',
          ),
          isTrue,
        );
        expect(
          document.paragraphs.single.inlines.whereType<WmlRun>().every(
            (run) => run.properties is! OdtReaderTextStyle,
          ),
          isTrue,
        );
        if (cycle > 0) {
          expect(_nativeValue(arabic, 'sz'), edited ? '32' : '20');
          expect(_nativeValue(arabic, 'szCs'), edited ? '32' : '20');
          expect(_nativeValue(arabic, 'bCs'), edited ? '0' : '1');
          expect(_nativeValue(arabic, 'iCs'), edited ? '1' : '0');
          expect(
            _native(asian).firstChild('rFonts')?.getAttribute('eastAsia'),
            asian.properties.asciiFont,
          );
          expect(
            _native(asian).firstChild('lang')?.getAttribute('eastAsia'),
            asian.properties.proofingLanguage,
          );
        }
        if (cycle == 1) {
          arabic.properties
            ..fontSizeHalfPoints = 32
            ..bold = false
            ..italic = true
            ..csFont = 'Noto Naskh Arabic';
          asian.properties
            ..asciiFont = 'Noto Sans CJK JP'
            ..proofingLanguage = 'ja-JP';
        }
        if (cycle < 3) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
        }
      }
      expect(odt, original);
    },
  );

  test(
    'Latin runs synchronize shared scalars and preserve independent font/language edits',
    () async {
      final document = await OdtDocumentReader.readBytes(
        _odt(
          'Latin words',
          properties:
              'fo:font-size="12pt" fo:font-family="Liberation Serif" '
              'fo:language="en" style:language-complex="en"',
        ),
      );
      final run = document.paragraphs.single.inlines.whereType<WmlRun>().single;
      expect(run.text, 'Latin words');
      run.properties
        ..fontSizeHalfPoints = 30
        ..bold = true
        ..italic = true;
      var reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      for (var cycle = 0; cycle < 2; cycle++) {
        final native = reopened.paragraphs.single.inlines
            .whereType<WmlRun>()
            .single;
        expect(_nativeValue(native, 'szCs'), '30');
        expect(_nativeValue(native, 'bCs'), '1');
        expect(_nativeValue(native, 'iCs'), '1');
        expect(
          native.properties.asciiFont,
          cycle == 0 ? 'Liberation Serif' : 'Liberation Sans',
        );
        expect(native.properties.csFont, 'Liberation Serif');
        expect(native.properties.proofingLanguage, cycle == 0 ? 'en' : 'de-DE');
        expect(native.properties.complexScriptLanguage, 'en');
        if (cycle == 0) {
          native.properties
            ..asciiFont = 'Liberation Sans'
            ..proofingLanguage = 'de-DE';
        }
        reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(reopened),
        );
      }
    },
  );

  test(
    'leaves ordinary and foreign-lookalike native complex slots independent',
    () {
      for (final marker in [
        '',
        'xmlns:fake="urn:foreign" fake:script="complex"',
      ]) {
        final props = WmlRunProps();
        final imported = WordPropertyIo.runValues(props);
        props
          ..fontSizeHalfPoints = 32
          ..bold = true
          ..italic = true;
        final result = WordPropertyIo.preserve(
          XmlDocument.parse(
            '<w:rPr xmlns:w="$_word"><w:b w:val="1"/><w:i w:val="1"/><w:sz w:val="32"/></w:rPr>',
          ).root!,
          '<w:rPr xmlns:w="$_word" $marker><w:bCs w:val="0"/><w:iCs w:val="0"/><w:szCs w:val="18"/></w:rPr>',
          imported,
          WordPropertyIo.runValues(props),
        );
        expect(result.firstChild('bCs')?.getAttribute('val'), '0');
        expect(result.firstChild('iCs')?.getAttribute('val'), '0');
        expect(result.firstChild('szCs')?.getAttribute('val'), '18');
      }
    },
  );

  test('validates effective defaults after supported overrides', () {
    final defaults = _textStyle(
      'Default',
      'style:use-window-font-color="true" loext:opacity="0%" fo:hyphenate="true"',
    );
    final styles = _styles(
      '$defaults${_textStyle('Normal', 'fo:color="#112233" loext:opacity="100%" fo:hyphenate="false" '
          'fo:hyphenation-remain-char-count="2" fo:hyphenation-push-char-count="2" '
          'loext:hyphenation-no-caps="false" loext:hyphenation-no-last-word="false" '
          'loext:hyphenation-word-char-count="5" loext:hyphenation-zone="no-limit" '
          'loext:hyphenation-compound-remain-char-count="2" loext:hyphenation-compound-push-char-count="2" '
          'fo:text-transform="none" loext:font-optical-sizing="auto"', parent: 'Default')}',
    );
    expect(
      styles
          .runProperties('Normal')
          .materialize('Visible')
          .single
          .properties
          .color,
      '112233',
    );
    for (final attributes in [
      'style:use-window-font-color="true"',
      'loext:opacity="50%"',
      'fo:hyphenate="true"',
    ]) {
      final active = _styles(
        _textStyle('Active', attributes),
      ).runProperties('Active');
      expect(
        () => active.materialize('Visible').toList(),
        throwsUnsupportedError,
      );
      expect(active.nativeProperties, throwsUnsupportedError);
    }
  });

  test('refuses malformed and still unsupported active text properties', () {
    for (final attributes in [
      'loext:opacity="101%"',
      'loext:opacity="NaN%"',
      'fo:hyphenation-remain-char-count="-1"',
      'fo:hyphenate="maybe"',
      'style:font-size-complex="10.1pt"',
      'style:font-family-generic="roman"',
      'fo:text-transform="lowercase"',
      'fo:text-transform="capitalize"',
      'loext:font-optical-sizing="none"',
    ]) {
      expect(
        () => _styles(_textStyle('Bad', attributes)).runProperties('Bad'),
        throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())),
      );
    }
  });
}
