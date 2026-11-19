import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _styles = '''
<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="de-DE"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:styleId="ParagraphBase"><w:name w:val="Paragraph base"/><w:rPr><w:lang w:val="de-AT"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ParagraphChild"><w:basedOn w:val="ParagraphBase"/></w:style>
<w:style w:type="character" w:styleId="CharacterBase"><w:rPr><w:lang w:val="de-CH"/><w:noProof/></w:rPr></w:style>
<w:style w:type="character" w:styleId="CharacterChild"><w:basedOn w:val="CharacterBase"/></w:style>
<w:style w:type="table" w:styleId="TableLanguage"><w:rPr><w:lang w:val="de-AT"/></w:rPr>
<w:tblStylePr w:type="band1Horz"><w:rPr><w:lang w:val="de-CH"/></w:rPr></w:tblStylePr>
<w:tblStylePr w:type="firstRow"><w:rPr><w:lang w:val="en-US"/></w:rPr></w:tblStylePr>
</w:style>
''';

String _paragraph({String? language = 'en-GB', bool character = true}) =>
    '''
<w:p><w:pPr><w:pStyle w:val="ParagraphChild"/></w:pPr>
<w:r><w:rPr>${character ? '<w:rStyle w:val="CharacterChild"/>' : ''}
<w:spacing w:val="23"/><w:noProof w:val="0"/>
<w:lang ${language == null ? '' : 'w:val="$language"'} w:eastAsia="ja-JP" w:bidi="ar-SA"/>
</w:rPr><w:t>Alpha Beta</w:t></w:r></w:p>''';

WmlDocument _fixture(String body, {String? comments}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText(
    '''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>$body<w:sectPr/></w:body></w:document>''',
  );
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText(
        '<w:styles xmlns:w="${OfficeNamespaces.w}">$_styles</w:styles>',
      );
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  if (comments != null) {
    package
        .createPart('/word/comments.xml', OfficeContentTypes.wordComments)
        .writeText(
          '<w:comments xmlns:w="${OfficeNamespaces.w}"><w:comment w:id="1" w:author="Reviewer">$comments</w:comment></w:comments>',
        );
    package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.comments, target: 'comments.xml');
  }
  return WordDeserializer().read(package);
}

WmlRunProps _props(WmlParagraph paragraph) =>
    paragraph.inlines.whereType<WmlRun>().single.properties;

Map<String, List<int>> _parts(WmlDocument document) => {
  for (final part in document.package!.parts) part.uri: part.readBytes(),
};

WmlDocument _reload(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

bool _clear(
  WmlDocument document,
  WmlParagraph source,
  WmlParagraph preview, {
  int start = 0,
  int? end,
}) => WordDeserializer().clearRunProofingLanguage(
  document,
  source,
  preview,
  start,
  end ?? source.text.length,
);

void main() {
  for (final selection in [
    (name: 'Latin', start: 0, end: 5, latin: 'de-CH', complex: 'ar-SA'),
    (name: 'Arabic', start: 6, end: 10, latin: 'en-GB', complex: null),
    (name: 'mixed', start: 0, end: 10, latin: 'de-CH', complex: null),
  ]) {
    test(
      'active-only ${selection.name} reset preserves inactive metadata even with includeComplexScript',
      () {
        final document = _fixture(
          _paragraph().replaceFirst('Alpha Beta', 'Latin عربي'),
        );
        final source = document.paragraphs.single;
        final originalParts = _parts(document);
        final preview = WmlClone.paragraph(source);
        expect(
          WordDeserializer().clearRunProofingLanguage(
            document,
            source,
            preview,
            selection.start,
            selection.end,
            includeComplexScript: true,
            activeLanguageOnly: true,
          ),
          isTrue,
        );
        final selected = preview.inlines
            .whereType<WmlRun>()
            .toList()[selection.start == 0 ? 0 : 1];
        expect(selected.properties.proofingLanguage, selection.latin);
        expect(selected.properties.complexScriptLanguage, selection.complex);
        expect(selected.properties.noProof, isFalse);
        expect(selected.properties.sourcePropertiesXml, contains('ja-JP'));
        expect(selected.properties.sourcePropertiesXml, contains('spacing'));
        expect(
          selected.properties.importedValues!['lang:bidi'],
          '${selection.complex}',
        );
        expect(_props(source).proofingLanguage, 'en-GB');
        expect(_props(source).complexScriptLanguage, 'ar-SA');
        expect(_parts(document), originalParts);
        source.inlines = preview.inlines;
        final saved = _reload(document).paragraphs.single.inlines
            .whereType<WmlRun>()
            .toList()[selection.start == 0 ? 0 : 1];
        expect(saved.properties.proofingLanguage, selection.latin);
        expect(saved.properties.complexScriptLanguage, selection.complex);
        expect(saved.properties.sourcePropertiesXml, contains('ja-JP'));
        expect(saved.properties.sourcePropertiesXml, contains('spacing'));
        expect(saved.properties.noProof, isFalse);
      },
    );
  }

  for (final character in [false, true]) {
    test(
      'clearing a direct override restores ${character ? 'character' : 'paragraph'} style live and after save',
      () {
        final document = _fixture(_paragraph(character: character));
        final source = document.paragraphs.single;
        final originalParts = _parts(document);
        final originalXml = _props(source).sourcePropertiesXml;
        final preview = WmlClone.paragraph(source);
        expect(_clear(document, source, preview), isTrue);
        final expected = character ? 'de-CH' : 'de-AT';
        expect(_props(preview).proofingLanguage, expected);
        expect(_props(source).proofingLanguage, 'en-GB');
        expect(_props(source).sourcePropertiesXml, originalXml);
        expect(_parts(document), originalParts);
        source.inlines = preview.inlines;
        final reopened = _reload(document);
        expect(_props(reopened.paragraphs.single).proofingLanguage, expected);
        final xml = WordSerializer().runPropertiesXml(_props(source));
        expect(xml, contains('eastAsia="ja-JP"'));
        expect(xml, contains('bidi="ar-SA"'));
        expect(xml, isNot(contains('val="$expected"')));
        expect(xml, isNot(contains('val="en-GB"')));
      },
    );
  }

  test(
    'partial reset preserves other runs, pending formatting, unknown XML and explicit noProof',
    () {
      final document = _fixture(_paragraph());
      final source = document.paragraphs.single;
      _props(source)
        ..bold = true
        ..color = 'AB1234';
      final originalParts = _parts(document);
      final preview = WmlClone.paragraph(source);
      expect(_clear(document, source, preview, start: 6, end: 10), isTrue);
      final runs = preview.inlines.whereType<WmlRun>().toList();
      expect(runs.map((run) => run.text), ['Alpha ', 'Beta']);
      expect(runs.map((run) => run.properties.proofingLanguage), [
        'en-GB',
        'de-CH',
      ]);
      for (final run in runs) {
        expect(run.properties.bold, isTrue);
        expect(run.properties.color, 'AB1234');
        expect(run.properties.noProof, isFalse);
        expect(run.properties.sourcePropertiesXml, contains('spacing'));
      }
      expect(_props(source).proofingLanguage, 'en-GB');
      expect(_parts(document), originalParts);
      source.inlines = preview.inlines;
      final reopened = _reload(
        document,
      ).paragraphs.single.inlines.whereType<WmlRun>().toList();
      expect(reopened.map((run) => run.properties.proofingLanguage), [
        'en-GB',
        'de-CH',
      ]);
      for (final run in reopened) {
        expect(run.properties.bold, isTrue);
        expect(run.properties.color, 'AB1234');
        expect(run.properties.noProof, isFalse);
        expect(run.properties.sourcePropertiesXml, contains('spacing'));
      }
    },
  );

  test(
    'already inherited text is a no-op but equal direct overrides are removed',
    () {
      final document = _fixture(_paragraph(language: null));
      final source = document.paragraphs.single;
      final preview = WmlClone.paragraph(source);
      final before = preview.inlines;
      expect(_props(source).proofingLanguage, 'de-CH');
      expect(_clear(document, source, preview, start: 2, end: 4), isFalse);
      expect(preview.inlines, same(before));

      final explicitDocument = _fixture(_paragraph(language: 'de-CH'));
      final explicit = explicitDocument.paragraphs.single;
      final reset = WmlClone.paragraph(explicit);
      expect(_clear(explicitDocument, explicit, reset), isTrue);
      expect(_props(reset).proofingLanguage, 'de-CH');
      expect(
        WordSerializer().runPropertiesXml(_props(reset)),
        isNot(contains('val="de-CH"')),
      );
    },
  );

  test(
    'a pending unsaved override is removed without changing inherited formatting',
    () {
      final document = _fixture(_paragraph(language: null));
      final source = document.paragraphs.single;
      _props(source).proofingLanguage = 'en-US';
      final preview = WmlClone.paragraph(source);
      expect(_clear(document, source, preview), isTrue);
      expect(_props(preview).proofingLanguage, 'de-CH');
      expect(
        WordSerializer().runPropertiesXml(_props(preview)),
        isNot(contains('val="en-US"')),
      );
      expect(_props(source).proofingLanguage, 'en-US');
    },
  );

  test('document and explicit paragraph defaults remain live after reset', () {
    for (final paragraphLanguage in [null, 'de-AT']) {
      final document = _fixture(
        '''<w:p>${paragraphLanguage == null ? '' : '<w:pPr><w:rPr><w:lang w:val="$paragraphLanguage"/></w:rPr></w:pPr>'}
<w:r><w:rPr><w:lang w:val="en-GB"/></w:rPr><w:t>Plain text</w:t></w:r></w:p>''',
      );
      final source = document.paragraphs.single;
      final preview = WmlClone.paragraph(source);
      expect(_clear(document, source, preview), isTrue);
      expect(_props(preview).proofingLanguage, isNull);
      source.inlines = preview.inlines;
      document.proofingLanguage = 'en-US';
      final reopened = _reload(document);
      final paragraph = reopened.paragraphs.single;
      expect(
        _props(paragraph).proofingLanguage ??
            paragraph.properties.proofingLanguage ??
            reopened.proofingLanguage,
        paragraphLanguage ?? 'en-US',
      );
    }
  });

  test(
    'newly authored language resets after an earlier save without sparse import metadata',
    () {
      final source = WmlParagraph(
        inlines: [
          WmlRun(
            text: 'New document',
            properties: WmlRunProps(proofingLanguage: 'en-GB', noProof: true),
          ),
        ],
      );
      final document = WmlDocument(
        proofingLanguage: 'de-DE',
        sections: [
          WmlSection(blocks: [source]),
        ],
      );
      WordSerializer().writeBytes(document);
      expect(_props(source).importedValues, isNull);
      final preview = WmlClone.paragraph(source);
      expect(_clear(document, source, preview), isTrue);
      expect(_props(preview).proofingLanguage, isNull);
      expect(
        WordSerializer().runPropertiesXml(_props(preview)),
        isNot(contains('en-GB')),
      );
      _props(preview).noProof = false;
      source.inlines = preview.inlines;
      final loaded = _reload(document);
      expect(
        _props(loaded.paragraphs.single).proofingLanguage ??
            loaded.proofingLanguage,
        'de-DE',
      );
      expect(_props(loaded.paragraphs.single).noProof, isFalse);
    },
  );

  for (final setting in [
    (look: '<w:tblLook w:firstRow="1" w:noHBand="0"/>', expected: 'en-US'),
    (look: '<w:tblLook w:firstRow="0" w:noHBand="0"/>', expected: 'de-CH'),
    (look: '<w:tblLook w:firstRow="0" w:noHBand="1"/>', expected: 'de-AT'),
  ]) {
    test(
      'table condition ${setting.expected} is restored with source tblLook',
      () {
        final document = _fixture(
          '''<w:tbl><w:tblPr><w:tblStyle w:val="TableLanguage"/>${setting.look}</w:tblPr>
<w:tblGrid><w:gridCol w:w="5000"/></w:tblGrid><w:tr><w:tc><w:p>
<w:r><w:rPr><w:lang w:val="en-GB"/></w:rPr><w:t>Cell text</w:t></w:r>
</w:p></w:tc></w:tr></w:tbl>''',
        );
        final source = document.paragraphs.single;
        final preview = WmlClone.paragraph(source);
        expect(_clear(document, source, preview), isTrue);
        expect(_props(preview).proofingLanguage, setting.expected);
        source.inlines = preview.inlines;
        expect(
          _props(_reload(document).paragraphs.single).proofingLanguage,
          setting.expected,
        );
      },
    );
  }

  test(
    'comment inheritance uses its exact story without touching body text',
    () {
      final document = _fixture(
        '<w:p><w:r><w:t>Body</w:t></w:r></w:p>',
        comments: _paragraph(),
      );
      final source = document.comments.single.paragraphs.single;
      final body = document.paragraphs.single;
      final bodyXml = WordSerializer().runPropertiesXml(_props(body));
      final preview = WmlClone.paragraph(source);
      expect(_clear(document, source, preview), isTrue);
      expect(_props(preview).proofingLanguage, 'de-CH');
      expect(WordSerializer().runPropertiesXml(_props(body)), bodyXml);
      source.inlines = preview.inlines;
      expect(
        _props(
          _reload(document).comments.single.paragraphs.single,
        ).proofingLanguage,
        'de-CH',
      );
    },
  );

  test('shallow detached previews cannot mutate live source properties', () {
    final document = _fixture(_paragraph());
    final source = document.paragraphs.single;
    final sourceRun = source.inlines.single;
    final preview = WmlParagraph(
      properties: source.properties,
      inlines: source.inlines,
    );
    expect(_clear(document, source, preview), isTrue);
    expect(source.inlines.single, same(sourceRun));
    expect(_props(source).proofingLanguage, 'en-GB');
    expect(_props(preview).proofingLanguage, 'de-CH');
  });

  test(
    'live, detached-source and invalid-range requests leave source unchanged',
    () {
      final document = _fixture(_paragraph());
      final source = document.paragraphs.single;
      final before = _parts(document);
      final preview = WmlClone.paragraph(source);
      expect(() => _clear(document, source, source), throwsArgumentError);
      expect(
        () => _clear(document, WmlClone.paragraph(source), preview),
        throwsStateError,
      );
      expect(
        () => _clear(document, source, preview, start: -1),
        throwsRangeError,
      );
      expect(_props(source).proofingLanguage, 'en-GB');
      expect(_props(preview).proofingLanguage, 'en-GB');
      expect(_parts(document), before);
    },
  );
}
