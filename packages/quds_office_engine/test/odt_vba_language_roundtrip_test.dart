import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Independently authored ODF reference-mark input. This checks the combined
// importer and public VBA adapter; it does not claim installed-host acceptance.
const _namespaces =
    'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
    'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0"';
const _prefix = '😀 Before ';
const _cache = '(Book العربية, 2026)';
const _suffix = ' after';
const _latinFont = 'Liberation Serif';
const _complexFont = 'Amiri';
const _normalLanguage = 'en-GB';
const _complexLanguage = 'ar-SA';
const _metadata = <String, Object?>{
  'citationID': 'odt-language-interop',
  'citationItems': <Object?>[
    <String, Object?>{
      'id': 'http://zotero.org/users/42/items/ABCD1234',
      'uris': <Object?>['http://zotero.org/users/42/items/ABCD1234'],
      'locator': '12–14',
      'label': 'page',
      'itemData': <String, Object?>{
        'id': 17,
        'type': 'book',
        'title': 'Book العربية',
        'unknownItem': <Object?>[true, 9],
      },
    },
  ],
  'properties': <String, Object?>{
    'plainCitation': _cache,
    'noteIndex': 0,
    'unknownProperty': 'preserve',
  },
  'unknownRoot': <String, Object?>{'retain': true},
};

String get _logicalCode => 'ITEM CSL_CITATION ${jsonEncode(_metadata)}';

String get _instruction => ' ADDIN ZOTERO_$_logicalCode ';

Uint8List _nativeOdt() {
  final mark = encodeXmlAttribute('ZOTERO_$_logicalCode RND0123456789');
  final content =
      '''
<office:document-content $_namespaces>
  <office:font-face-decls>
    <style:font-face style:name="LatinFace" svg:font-family="$_latinFont"/>
    <style:font-face style:name="ArabicFace" svg:font-family="$_complexFont"/>
  </office:font-face-decls>
  <office:automatic-styles>
    <style:style style:name="Emphasis" style:family="text">
      <style:text-properties fo:font-style="italic" fo:color="#123456"/>
    </style:style>
  </office:automatic-styles>
  <office:body><office:text>
    <text:p text:style-name="Base">Unchanged before</text:p>
    <text:p text:style-name="Base">$_prefix<text:reference-mark-start text:name="$mark"/>(<text:span text:style-name="Emphasis">Book العربية</text:span>, 2026)<text:reference-mark-end text:name="$mark"/>$_suffix</text:p>
    <text:p text:style-name="Base">Unchanged after</text:p>
  </office:text></office:body>
</office:document-content>''';
  const styles =
      '''
<office:document-styles $_namespaces>
  <office:styles>
    <style:style style:name="Base" style:family="paragraph">
      <style:paragraph-properties fo:margin-bottom="6pt"/>
      <style:text-properties style:font-name="LatinFace"
        style:font-name-complex="ArabicFace" fo:font-size="12pt"
        fo:language="en" fo:country="GB"
        style:language-complex="ar" style:country-complex="SA"/>
    </style:style>
  </office:styles>
</office:document-styles>''';
  final writer = ZipWriter();
  writer.addFile(
    'mimetype',
    utf8.encode('application/vnd.oasis.opendocument.text'),
    store: true,
  );
  writer.addFile('content.xml', utf8.encode(content));
  writer.addFile('styles.xml', utf8.encode(styles));
  return writer.close();
}

void _expectDocument(
  WmlDocument document, {
  String targetLanguage = _normalLanguage,
  String targetComplexFont = _complexFont,
  bool targetAllCaps = false,
}) {
  final paragraphs = document.paragraphs.toList();
  expect(paragraphs.map((paragraph) => paragraph.text), [
    'Unchanged before',
    '$_prefix$_cache$_suffix',
    'Unchanged after',
  ]);
  final field = WordZotero.fields(document).single;
  expect(field.kind, ZoteroFieldKind.citation);
  expect(field.isValid, isTrue);
  expect(field.canEdit, isTrue);
  expect(field.paragraph, same(paragraphs[1]));
  expect(field.start, _prefix.length);
  expect(field.end, _prefix.length + _cache.length);
  expect(field.cachedText, _cache);
  expect(field.instruction, _instruction);
  expect(field.metadata, _metadata);
  expect(field.citation!.citationId, 'odt-language-interop');
  expect(field.citation!.items.single.locator, '12–14');

  for (var index = 0; index < paragraphs.length; index++) {
    final paragraph = paragraphs[index];
    expect(paragraph.properties.spacingAfter, 6);
    var offset = 0;
    for (final run in paragraph.inlines.whereType<WmlRun>()) {
      final properties = run.properties;
      expect(properties.asciiFont, _latinFont);
      expect(properties.csFont, index == 1 ? targetComplexFont : _complexFont);
      expect(
        properties.proofingLanguage,
        index == 1 ? targetLanguage : _normalLanguage,
      );
      expect(properties.complexScriptLanguage, _complexLanguage);
      expect(properties.fontSizeHalfPoints, 24);
      expect(properties.noProof, isFalse);
      expect(properties.allCaps, index == 1 && targetAllCaps);
      expect(properties.smallCaps, isFalse);
      final emphasisStart = _prefix.length + 1;
      final emphasisEnd = emphasisStart + 'Book العربية'.length;
      final emphasized =
          index == 1 &&
          offset < emphasisEnd &&
          offset + run.text.length > emphasisStart;
      expect(properties.italic, emphasized);
      if (emphasized) {
        expect(offset, greaterThanOrEqualTo(emphasisStart));
        expect(offset + run.text.length, lessThanOrEqualTo(emphasisEnd));
        expect(properties.color, '123456');
      }
      offset += run.text.length;
    }
  }
  expect(
    paragraphs[1].inlines
        .whereType<WmlRun>()
        .where((run) => run.properties.italic)
        .map((run) => run.text)
        .join(),
    'Book العربية',
  );
}

void main() {
  for (final change in [
    (
      name: 'normal language',
      statement: 'LanguageID = wdGerman',
      language: 'de-DE',
      complexFont: _complexFont,
      allCaps: false,
    ),
    (
      name: 'complex font',
      statement: 'Font.NameBi = "Noto Naskh Arabic"',
      language: _normalLanguage,
      complexFont: 'Noto Naskh Arabic',
      allCaps: false,
    ),
    (
      name: 'all capitals',
      statement: 'Font.AllCaps = True',
      language: _normalLanguage,
      complexFont: _complexFont,
      allCaps: true,
    ),
  ]) {
    test(
      'ODT citation survives isolated ${change.name} VBA edit and repeated DOCX saves',
      () async {
        final odt = _nativeOdt();
        final original = Uint8List.fromList(odt);
        final document = await OdtDocumentReader.readBytes(odt);
        _expectDocument(document);
        final input = WordSerializer().writeBytes(document);
        _expectDocument(WordDeserializer().readBytes(input));
        final plan = OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: 'vba-word',
            format: OfficeMacroFormat.docx,
            moduleName: 'ImportedOdtCitation',
            source:
                '''
Sub Main()
  ActiveDocument.Paragraphs(2).Range.${change.statement}
End Sub
''',
          ),
        );
        expect(plan.steps, hasLength(1));
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        final validation = await session.validate(plan);
        expect(validation.validatedOnly, isTrue);
        expect(session.bytes, input);
        expect(session.revision, 0);
        await session.run(plan);
        expect(session.revision, 1);
        var saved = session.bytes;
        for (var cycle = 0; cycle < 3; cycle++) {
          final reopened = WordDeserializer().readBytes(saved);
          _expectDocument(
            reopened,
            targetLanguage: change.language,
            targetComplexFont: change.complexFont,
            targetAllCaps: change.allCaps,
          );
          if (cycle < 2) saved = WordSerializer().writeBytes(reopened);
        }
        expect(odt, original);
      },
    );
  }
}
