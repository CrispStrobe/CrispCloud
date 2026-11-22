import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _text = '(Citation 😀)';
const _w = OfficeNamespaces.w;

String get _data => jsonEncode({
  'dataVersion': 4,
  'style': {'styleID': 'http://www.zotero.org/styles/apa'},
  'prefs': {'fieldType': 'Field', 'noteType': 0},
});

String get _instruction => ZoteroCitation.fromJson({
  'citationID': 'position-guard',
  'citationItems': [
    {
      'id': 1,
      'itemData': {'id': 1, 'type': 'book', 'title': 'Source'},
    },
  ],
  'properties': {'plainCitation': _text},
}).fieldInstruction;

WmlDocument _document({int position = 0}) => WmlDocument(
  zoteroDocumentData: _data,
  sections: [
    WmlSection(
      blocks: [
        WmlParagraph(
          inlines: [
            WmlRun(
              text: _text,
              fieldInstruction: _instruction,
              properties: WmlRunProps(positionHalfPoints: position),
            ),
          ],
        ),
      ],
    ),
  ],
);

WmlDocument _native({
  String run = '',
  String paragraph = '',
  required String styles,
}) {
  final package = OpcPackage.openBytes(
    (DocxDocumentBuilder()..paragraph('Template')).build(),
  );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="$_w"><w:body><w:p><w:pPr>$paragraph</w:pPr>'
        '<w:r><w:rPr>$run</w:rPr><w:t>$_text</w:t></w:r></w:p>'
        '<w:sectPr/></w:body></w:document>',
      );
  package
      .getPart('/word/styles.xml')!
      .writeText('<w:styles xmlns:w="$_w">$styles</w:styles>');
  final document = WordDeserializer().read(package);
  document.zoteroDocumentData = _data;
  _run(document).fieldInstruction = _instruction;
  return document;
}

WmlRun _run(WmlDocument document) =>
    document.paragraphs.single.inlines.whereType<WmlRun>().single;

Map<String, List<int>> _parts(WmlDocument document) => {
  for (final part in document.package?.parts ?? <PackagePart>[])
    part.uri: part.readBytes().toList(),
};

void _expectRefusal(WmlDocument document) {
  final paragraph = document.paragraphs.single;
  final inlines = paragraph.inlines.toList();
  final run = _run(document);
  final properties = run.properties;
  final position = properties.positionHalfPoints;
  final source = properties.sourcePropertiesXml;
  final instruction = run.fieldInstruction;
  final data = document.zoteroDocumentData;
  final parts = _parts(document);
  expect(
    () => OdtDocumentWriter.writeEditableZoteroBytes(document),
    throwsA(
      isA<UnsupportedError>().having(
        (error) => error.message,
        'message',
        contains('raised or lowered text'),
      ),
    ),
  );
  expect(document.paragraphs.single, same(paragraph));
  expect(paragraph.inlines, orderedEquals(inlines));
  expect(run.properties, same(properties));
  expect(properties.positionHalfPoints, position);
  expect(properties.sourcePropertiesXml, source);
  expect(run.text, _text);
  expect(run.fieldInstruction, instruction);
  expect(document.zoteroDocumentData, data);
  expect(_parts(document), parts);
}

void main() {
  for (final position in [-7, 6]) {
    test(
      'refuses direct $position half-point citation position atomically',
      () {
        _expectRefusal(_document(position: position));
      },
    );
  }

  final inherited = <String, ({String paragraph, String run, String styles})>{
    'document default': (
      paragraph: '',
      run: '',
      styles:
          '<w:docDefaults><w:rPrDefault><w:rPr><w:position w:val="-3"/>'
          '</w:rPr></w:rPrDefault></w:docDefaults>',
    ),
    'paragraph style chain': (
      paragraph: '<w:pStyle w:val="Child"/>',
      run: '',
      styles:
          '<w:style w:type="paragraph" w:styleId="Parent"><w:rPr>'
          '<w:position w:val="-3"/></w:rPr></w:style>'
          '<w:style w:type="paragraph" w:styleId="Child">'
          '<w:basedOn w:val="Parent"/></w:style>',
    ),
    'character style chain': (
      paragraph: '',
      run: '<w:rStyle w:val="Child"/>',
      styles:
          '<w:style w:type="character" w:styleId="Parent"><w:rPr>'
          '<w:position w:val="-3"/></w:rPr></w:style>'
          '<w:style w:type="character" w:styleId="Child">'
          '<w:basedOn w:val="Parent"/></w:style>',
    ),
  };
  for (final entry in inherited.entries) {
    test(
      'refuses effective position from ${entry.key} without source edits',
      () {
        final document = _native(
          paragraph: entry.value.paragraph,
          run: entry.value.run,
          styles: entry.value.styles,
        );
        expect(_run(document).properties.positionHalfPoints, -3);
        _expectRefusal(document);
      },
    );
  }

  test('refuses positioned paragraph mark even when visible run is zero', () {
    final document = _native(
      paragraph: '<w:rPr><w:position w:val="4"/></w:rPr>',
      styles: '',
    );
    expect(_run(document).properties.positionHalfPoints, 0);
    expect(
      document
          .paragraphs
          .single
          .properties
          .importedParagraphMark
          ?.positionHalfPoints,
      4,
    );
    _expectRefusal(document);
  });

  test('refuses positioned note marker without changing the anchored note', () {
    final document = _document();
    final note = WordNotes.insert(
      document,
      document.paragraphs.single,
      endnote: true,
      text: 'Note',
    );
    final marker = WmlNoteMarker(
      endnote: true,
      properties: WmlRunProps(positionHalfPoints: 2),
    );
    note.paragraphs.single.inlines.insert(0, marker);
    final inlines = note.paragraphs.single.inlines.toList();
    expect(
      () => OdtDocumentWriter.writeEditableZoteroBytes(document),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('raised or lowered text'),
        ),
      ),
    );
    expect(note.paragraphs.single.inlines, orderedEquals(inlines));
    expect(marker.properties.positionHalfPoints, 2);
    expect(document.endnotes.single, same(note));
  });

  for (final entry in inherited.entries) {
    test(
      'exports explicit zero over ${entry.key} with citation intact',
      () async {
        final document = _native(
          paragraph:
              '${entry.value.paragraph}'
              '<w:rPr><w:position w:val="0"/></w:rPr>',
          run: '${entry.value.run}<w:position w:val="0"/>',
          styles: entry.value.styles,
        );
        expect(_run(document).properties.positionHalfPoints, 0);
        final parts = _parts(document);
        final bytes = OdtDocumentWriter.writeEditableZoteroBytes(document);
        final reopened = await OdtDocumentReader.readBytes(bytes);
        expect(
          WordZotero.fields(reopened).single.citation!.citationId,
          'position-guard',
        );
        expect(reopened.paragraphs.single.text, _text);
        expect(_run(reopened).properties.positionHalfPoints, 0);
        expect(_parts(document), parts);
      },
    );
  }

  test(
    'zero position keeps supported superscript and subscript separate',
    () async {
      final document = _document();
      final run = _run(document);
      for (final align in [WmlVertAlign.superscript, WmlVertAlign.subscript]) {
        run.properties.vertAlign = align;
        final reopened = await OdtDocumentReader.readBytes(
          OdtDocumentWriter.writeEditableZoteroBytes(document),
        );
        expect(_run(reopened).properties.positionHalfPoints, 0);
        expect(_run(reopened).properties.vertAlign, align);
        expect(WordZotero.fields(reopened).single.cachedText, _text);
      }
    },
  );
}
