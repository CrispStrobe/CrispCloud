import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Untouched output of the recorded LibreOfficeDev file-save operation.
// The input was a synthetic Quds document; no installed Zotero plugin was used.
const _fixture = 'test/fixtures/zotero/odt/libreoffice-bibliography.odt';
const _sha = 'f2e940184bfe599a646ee9ff7931643f487767af6f0a6690dbcc8a4ad3c0d05f';
const _sectionStyle = '<style:style style:name="Sect1" style:family="section">';
const _properties = '<style:section-properties style:editable="false">';
const _columns = '<style:columns fo:column-count="1" fo:column-gap="0in"/>';
const _sessionId = 'libreoffice-bibliography-roundtrip';

Uint8List _bytes() {
  final bytes = File(_fixture).readAsBytesSync();
  expect(sha256.convert(bytes).toString(), _sha);
  return bytes;
}

String _replace(String xml, String from, String to) {
  expect(from.allMatches(xml), hasLength(1), reason: from);
  return xml.replaceFirst(from, to);
}

// Each guard is an explicitly modified copy. The retained fixture is never
// simplified to make it pass the reader.
Uint8List _variant(String Function(String) transform) {
  final zip = ZipReader.fromBytes(_bytes());
  final out = ZipWriter();
  for (final entry in zip.entries) {
    final bytes = zip.read(entry.fileName);
    out.addFile(
      entry.fileName,
      entry.fileName == 'content.xml'
          ? utf8.encode(transform(utf8.decode(bytes)))
          : bytes,
      store: entry.compressionMethod == zipMethodStore,
    );
  }
  return out.close();
}

WmlDocument _docx(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

WmlZoteroField _bibliography(WmlDocument document) => WordZotero.fields(
  document,
).singleWhere((field) => field.kind == ZoteroFieldKind.bibliography);

void _expectOriginal(WmlDocument document) {
  final fields = WordZotero.fields(document);
  expect(fields, hasLength(3));
  expect(fields.take(2).map((field) => field.citation!.citationId), [
    'first',
    'second',
  ]);
  for (final field in fields.take(2)) {
    expect(field.canEdit, isTrue);
    expect(field.cachedText, '(Source)');
    expect(
      field.citation!.items.single.toJson(),
      containsPair('locator', '12–14'),
    );
    expect(field.metadata, containsPair('futureCitation', [true, null, 42]));
  }
  final bibliography = _bibliography(document);
  expect(bibliography.cachedText, 'Alpha source.\n\nBeta source.');
  expect(bibliography.paragraphs.map((paragraph) => paragraph.text), [
    'Alpha source.',
    '',
    'Beta source.',
  ]);
  expect(
    WordZotero.canReplaceNativeBibliography(document, bibliography),
    isTrue,
  );
  expect(
    bibliography.metadata,
    containsPair('futureBibliography', {'keep': true}),
  );
  expect(
    bibliography.paragraphs.first.properties.indent.hanging,
    closeTo(36, 0.02),
  );
  expect(
    bibliography.paragraphs.first.properties.spacingAfter,
    closeTo(6, 0.02),
  );
  expect(
    bibliography.paragraphs.first.inlines
        .whereType<WmlRun>()
        .where((run) => run.text.isNotEmpty)
        .every((run) => run.properties.italic),
    isTrue,
  );
  expect(document.paragraphs.map((paragraph) => paragraph.text), [
    'First (Source)',
    'Second (Source)',
    'References',
    'Alpha source.',
    '',
    'Beta source.',
    'After references',
  ]);
}

Object? _call(
  WordZoteroCitingSession session,
  String name, [
  List<Object?> arguments = const [],
]) => session.handle(name, [_sessionId, ...arguments]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http']) as List<Object?>)
        .cast<Map<String, Object>>();

void _apply(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.prepareReview();
  session.apply();
}

void main() {
  test(
    'untouched LibreOffice bibliography reopens with active rich fields',
    () async {
      final original = _bytes();
      final originalMetadata = ZipReader.fromBytes(original).read('meta.xml');
      var document = await OdtDocumentReader.readBytes(original);
      final preferences = WordZoteroDocumentData.read(document);
      for (var cycle = 0; cycle < 3; cycle++) {
        _expectOriginal(document);
        expect(WordZoteroDocumentData.read(document), preferences);
        expect(
          document.package!
              .getPart('/customXml/qudsOdtMetadata.xml')!
              .readBytes(),
          originalMetadata,
        );
        document = _docx(document);
      }
      final copy = OdtDocumentWriter.writeEditableZoteroBytes(document);
      final inventory = await OdfZotero.inspect(copy);
      expect(inventory.fields, hasLength(3));
      expect(inventory.preferences.usesReferenceMarks, isTrue);
      document = await OdtDocumentReader.readBytes(copy);
      _expectOriginal(document);
      expect(sha256.convert(original).toString(), _sha);
    },
  );

  test(
    'imported actual bibliography supports staged refresh, edit and unlink',
    () async {
      var document = await OdtDocumentReader.readBytes(_bytes());
      final session = WordZoteroCitingSession(
        document: document,
        documentId: _sessionId,
        insertionParagraph: document.paragraphs.first,
      );
      final fields = _fields(session);
      final oldCitation = WordZotero.fields(document).first.citation!;
      final updated = oldCitation.withItems(
        oldCitation.items,
        plainCitation: '(Updated, 12–14)',
        formattedCitation: '<b>(Updated, 12–14)</b>',
      );
      _call(session, 'Field.setCode', [
        fields.first['id'],
        'ITEM CSL_CITATION ${jsonEncode(updated.toJson())}',
      ]);
      _call(session, 'Field.setText', [
        fields.first['id'],
        '<b>(Updated, 12–14)</b>',
        true,
      ]);
      final bibliography = fields.singleWhere(
        (field) => (field['code'] as String).startsWith('BIBL '),
      );
      _call(session, 'Field.setText', [
        bibliography['id'],
        '<div class="csl-entry">Changed <i>book</i>.</div>'
            '<div class="csl-entry">Another <b>source</b>.</div>',
        true,
      ]);
      _expectOriginal(
        document,
      ); // Native callbacks remain detached until complete.
      _apply(session);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(
          WordZotero.fields(document).first.cachedText,
          '(Updated, 12–14)',
        );
        expect(WordZotero.fields(document).first.citation!.citationId, 'first');
        expect(WordZotero.fields(document)[1].citation!.citationId, 'second');
        expect(
          _bibliography(document).cachedText,
          'Changed book.\nAnother source.',
        );
        expect(
          _bibliography(document).metadata,
          containsPair('futureBibliography', {'keep': true}),
        );
        document = _docx(
          await OdtDocumentReader.readBytes(
            OdtDocumentWriter.writeEditableZoteroBytes(document),
          ),
        );
      }
      final before = document.paragraphs
          .map((paragraph) => paragraph.text)
          .toList();
      final unlink = WordZoteroCitingSession(
        document: document,
        documentId: _sessionId,
        insertionParagraph: document.paragraphs.first,
      );
      for (final field in _fields(unlink)) {
        _call(unlink, 'Field.removeCode', [field['id']]);
      }
      expect(WordZotero.fields(document), hasLength(3));
      _apply(unlink);
      document = _docx(document);
      expect(WordZotero.fields(document), isEmpty);
      expect(document.paragraphs.map((paragraph) => paragraph.text), before);
    },
  );

  test(
    'section defaults and ancestor overrides resolve before qualification',
    () async {
      final bytes = _variant(
        (xml) => _replace(
          _replace(
            xml,
            _sectionStyle,
            '<style:style style:name="BaseSection" style:family="section">'
            '<style:section-properties style:editable="true" style:protect="true" fo:margin-left="1in">'
            '<style:columns fo:column-count="2" fo:column-gap="1in"/>'
            '</style:section-properties></style:style>'
            '<style:style style:name="Sect1" style:family="section" style:parent-style-name="BaseSection">',
          ),
          _properties,
          '<style:section-properties style:editable="false" style:protect="false" fo:margin-left="0pt" fo:background-color="transparent">',
        ),
      );
      _expectOriginal(await OdtDocumentReader.readBytes(bytes));
    },
  );

  for (final level in ['-00', '+100000000000000000000000000000']) {
    test(
      'unused sequence declaration keeps valid integer and Unicode syntax $level',
      () async {
        final bytes = _variant(
          (xml) => _replace(
            _replace(
              xml,
              _columns,
              '<style:columns fo:column-count=" +001 " fo:column-gap="0pt"/>',
            ),
            '<text:sequence-decl text:display-outline-level="0" text:name="Table"/>',
            '<text:sequence-decl text:display-outline-level="$level" text:name="Table" text:separation-character="😀"/>',
          ),
        );
        _expectOriginal(await OdtDocumentReader.readBytes(bytes));
      },
    );
  }

  final variants = <String, String Function(String)>{
    'missing section style': (xml) =>
        _replace(xml, 'text:style-name="Sect1"', 'text:style-name="Missing"'),
    'empty section style': (xml) =>
        _replace(xml, 'text:style-name="Sect1"', 'text:style-name=""'),
    'section protection': (xml) =>
        _replace(xml, '<text:section ', '<text:section text:protected="true" '),
    'section condition': (xml) => _replace(
      xml,
      '<text:section ',
      '<text:section text:condition="false()" ',
    ),
    'section hiding': (xml) =>
        _replace(xml, '<text:section ', '<text:section text:display="none" '),
    'section style protection': (xml) => _replace(
      xml,
      _properties,
      '<style:section-properties style:protect="true">',
    ),
    'read-only editing exception': (xml) => _replace(
      xml,
      _properties,
      '<style:section-properties style:editable="true">',
    ),
    'malformed editable flag': (xml) => _replace(
      xml,
      _properties,
      '<style:section-properties style:editable="maybe">',
    ),
    'active background': (xml) => _replace(
      xml,
      _properties,
      '<style:section-properties fo:background-color="#ff0000">',
    ),
    'active margin': (xml) => _replace(
      xml,
      _properties,
      '<style:section-properties fo:margin-right="12pt">',
    ),
    'active writing direction': (xml) => _replace(
      xml,
      _properties,
      '<style:section-properties style:writing-mode="rl-tb">',
    ),
    'unknown section property': (xml) => _replace(
      xml,
      _properties,
      '<style:section-properties style:unknown="false">',
    ),
    'missing column count': (xml) =>
        _replace(xml, _columns, '<style:columns fo:column-gap="0in"/>'),
    'zero columns': (xml) =>
        _replace(xml, _columns, '<style:columns fo:column-count="0"/>'),
    'non-XML column-count padding': (xml) => _replace(
      xml,
      _columns,
      '<style:columns fo:column-count="\u00a01\u00a0"/>',
    ),
    'multiple columns': (xml) =>
        _replace(xml, _columns, '<style:columns fo:column-count="2"/>'),
    'column gap': (xml) => _replace(
      xml,
      _columns,
      '<style:columns fo:column-count="1" fo:column-gap="1pt"/>',
    ),
    'column separator': (xml) => _replace(
      xml,
      _columns,
      '<style:columns fo:column-count="1"><style:column-sep/></style:columns>',
    ),
    'column text': (xml) => _replace(
      xml,
      _columns,
      '<style:columns fo:column-count="1">discarded</style:columns>',
    ),
    'duplicate columns': (xml) => _replace(xml, _columns, '$_columns$_columns'),
    'inherited active property': (xml) => _replace(
      xml,
      _sectionStyle,
      '<style:style style:name="Parent" style:family="section"><style:section-properties fo:margin-left="1in"/></style:style>'
      '<style:style style:name="Sect1" style:family="section" style:parent-style-name="Parent">',
    ),
    'default active property': (xml) => _replace(
      xml,
      '<office:automatic-styles>',
      '<office:automatic-styles><style:default-style style:family="section"><style:section-properties fo:background-color="#ffffff"/></style:default-style>',
    ),
    'cyclic section inheritance': (xml) => _replace(
      xml,
      _sectionStyle,
      '<style:style style:name="Sect1" style:family="section" style:parent-style-name="Sect1">',
    ),
    'sequence container text': (xml) => _replace(
      xml,
      '<text:sequence-decls>',
      '<text:sequence-decls>discarded',
    ),
    'sequence container attribute': (xml) => _replace(
      xml,
      '<text:sequence-decls>',
      '<text:sequence-decls text:unknown="lost">',
    ),
    'sequence declaration text': (xml) => _replace(
      xml,
      '<text:sequence-decl text:display-outline-level="0" text:name="Table"/>',
      '<text:sequence-decl text:display-outline-level="0" text:name="Table">discarded</text:sequence-decl>',
    ),
    'sequence declaration without outline level': (xml) => _replace(
      xml,
      '<text:sequence-decl text:display-outline-level="0" text:name="Table"/>',
      '<text:sequence-decl text:name="Table"/>',
    ),
    'sequence declaration with a malformed separator': (xml) => _replace(
      xml,
      '<text:sequence-decl text:display-outline-level="0" text:name="Table"/>',
      '<text:sequence-decl text:display-outline-level="0" text:name="Table" text:separation-character="ab"/>',
    ),
    'duplicate sequence identity': (xml) =>
        _replace(xml, 'text:name="Drawing"', 'text:name="Table"'),
    'active sequence field': (xml) => _replace(
      xml,
      'After references',
      '<text:sequence text:name="Table">1</text:sequence>',
    ),
  };
  for (final entry in variants.entries) {
    test('refuses ${entry.key} without modifying source bytes', () async {
      final bytes = _variant(entry.value);
      final digest = sha256.convert(bytes).toString();
      await expectLater(
        OdtDocumentReader.readBytes(bytes),
        throwsA(anyOf(isA<UnsupportedError>(), isA<FormatException>())),
      );
      expect(sha256.convert(bytes).toString(), digest);
    });
  }
}
