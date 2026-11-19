import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _imported({bool styled = false}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>
<w:r><w:rPr>${styled ? '<w:rStyle w:val="Child"/>' : ''}<w:lang w:val="de-DE" w:bidi="ar-SA" w:eastAsia="ja-JP"/><w:rtl/></w:rPr><w:t>عربي</w:t></w:r>
<w:r><w:t>نص</w:t></w:r>
</w:p><w:sectPr/></w:body></w:document>''');
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="en-US" w:bidi="ar-EG"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="character" w:styleId="Parent"><w:rPr><w:lang w:val="fr-FR" w:bidi="he-IL"/></w:rPr></w:style>
<w:style w:type="character" w:styleId="Child"><w:basedOn w:val="Parent"/></w:style>
</w:styles>''');
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  return WordDeserializer().read(package);
}

String? _language(WmlDocument document, WmlRun run) => wordRunProofingLanguage(
  run,
  document.paragraphs.single,
  documentLanguage: document.proofingLanguage,
  documentComplexScriptLanguage: document.complexScriptLanguage,
);

void main() {
  for (final marker in ['rtl', 'cs']) {
    for (final inherited in [false, true]) {
      for (final direct in [false, true]) {
        test('$marker direct $direct overrides inherited $inherited', () {
          final package = OpcPackage.create(OpcPackageKind.word);
          package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>
<w:r><w:rPr><w:rStyle w:val="Marker"/><w:$marker${direct ? '' : ' w:val="0"'}/></w:rPr><w:t>Latin123</w:t></w:r>
</w:p><w:sectPr/></w:body></w:document>''');
          package
              .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
              .writeText('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="en-US" w:bidi="ar-SA"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="character" w:styleId="Marker"><w:rPr><w:$marker w:val="${inherited ? 1 : 0}"/></w:rPr></w:style>
</w:styles>''');
          package
              .relationshipsFor('/word/document.xml')
              .add(type: RelationshipTypes.styles, target: 'styles.xml');
          final document = WordDeserializer().read(package);
          final run = document.paragraphs.single.inlines
              .whereType<WmlRun>()
              .single;
          expect(run.properties.complexScript, direct);
          expect(_language(document, run), direct ? 'ar-SA' : 'en-US');
          final reopened = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          final saved = reopened.paragraphs.single.inlines
              .whereType<WmlRun>()
              .single;
          expect(saved.properties.complexScript, direct);
          expect(_language(reopened, saved), direct ? 'ar-SA' : 'en-US');
        });
      }
    }
  }

  for (final entry in <String, String>{
    'Arabic letter': 'aعb',
    'Hebrew letter': 'aאb',
    'Arabic presentation letter': 'a\uFE8Db',
    'Hebrew presentation letter': 'a\uFB1Db',
    'supplementary Arabic letter': 'a\u{1EE00}b',
  }.entries) {
    test('${entry.key} selects the complex-script language', () {
      expect(wordTextHasComplexScriptLetter(entry.value), isTrue);
      final run = WmlRun(
        text: entry.value,
        properties: WmlRunProps(
          proofingLanguage: 'en-US',
          complexScriptLanguage: 'ar-SA',
        ),
      );
      expect(wordRunProofingLanguage(run, WmlParagraph()), 'ar-SA');
    });
  }

  for (final entry in <String, String>{
    'Latin letters': 'Latin',
    'Arabic-Indic digit': 'Latin١',
    'Persian digit': 'Latin۱',
    'Arabic comma': 'Latin،',
    'Arabic question mark': 'Latin؟',
    'Arabic combining mark': 'Latin\u064E',
    'Hebrew combining mark': 'Latin\u05B0',
    'Hebrew punctuation': 'Latin\u05BE',
    'byte-order mark': 'Latin\uFEFF',
    'supplementary non-Arabic letter': 'Latin\u{10400}',
  }.entries) {
    test('${entry.key} keeps the Latin language', () {
      expect(wordTextHasComplexScriptLetter(entry.value), isFalse);
      final run = WmlRun(
        text: entry.value,
        properties: WmlRunProps(
          proofingLanguage: 'en-US',
          complexScriptLanguage: 'ar-SA',
        ),
      );
      expect(wordRunProofingLanguage(run, WmlParagraph()), 'en-US');
    });
  }

  test('explicit complex-script formatting still selects its language', () {
    final run = WmlRun(
      text: '123',
      properties: WmlRunProps(
        proofingLanguage: 'en-US',
        complexScriptLanguage: 'ar-SA',
        complexScript: true,
      ),
    );
    expect(wordRunProofingLanguage(run, WmlParagraph()), 'ar-SA');
  });

  for (final entry in [
    (text: 'Latin عربي', marker: null, latin: true, complex: true),
    (text: 'عربي', marker: null, latin: false, complex: true),
    (text: 'עברית', marker: null, latin: false, complex: true),
    (text: '١٢٣؟', marker: null, latin: true, complex: false),
    (text: 'Latin عربي', marker: true, latin: false, complex: true),
    (text: 'Latin عربي', marker: false, latin: true, complex: true),
  ]) {
    test('language slots for ${entry.text} with marker ${entry.marker}', () {
      final run = WmlRun(
        text: entry.text,
        properties: WmlRunProps(complexScript: entry.marker),
      );
      expect(wordRunUsesLatinScriptLanguage(run), entry.latin);
      expect(wordRunUsesComplexScriptLanguage(run), entry.complex);
    });
  }

  test('document complex-script default stays live after import and clone', () {
    final document = _imported();
    final inherited = document.paragraphs.single.inlines
        .whereType<WmlRun>()
        .last;
    expect(inherited.properties.complexScriptLanguage, isNull);
    expect(_language(document, inherited), 'ar-EG');
    document.complexScriptLanguage = 'he-IL';
    expect(_language(document, inherited), 'he-IL');
    expect(
      _language(
        document,
        WmlClone.paragraph(
          document.paragraphs.single,
        ).inlines.whereType<WmlRun>().last,
      ),
      'he-IL',
    );
  });

  for (final styled in [false, true]) {
    test(
      'reset both languages restores ${styled ? 'style' : 'document'} inheritance',
      () {
        final document = _imported(styled: styled);
        final paragraph = document.paragraphs.single;
        final preview = WmlClone.paragraph(paragraph);
        expect(
          WordDeserializer().clearRunProofingLanguage(
            document,
            paragraph,
            preview,
            0,
            4,
            includeComplexScript: true,
          ),
          isTrue,
        );
        final run = preview.inlines.whereType<WmlRun>().first;
        expect(run.properties.proofingLanguage, styled ? 'fr-FR' : null);
        expect(run.properties.complexScriptLanguage, styled ? 'he-IL' : null);
        expect(_language(document, run), styled ? 'he-IL' : 'ar-EG');
        expect(run.properties.sourcePropertiesXml, contains('ja-JP'));
        expect(run.properties.sourcePropertiesXml, isNot(contains('ar-SA')));
        expect(run.properties.sourcePropertiesXml, contains('rtl'));
        paragraph.inlines = preview.inlines;
        final reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        final saved = reopened.paragraphs.single.inlines
            .whereType<WmlRun>()
            .first;
        expect(_language(reopened, saved), styled ? 'he-IL' : 'ar-EG');
        expect(saved.properties.sourcePropertiesXml, isNot(contains('he-IL')));
        expect(saved.properties.sourcePropertiesXml, contains('ja-JP'));
      },
    );
  }

  test('new and imported run language attributes serialize independently', () {
    final document = _imported();
    final paragraph = document.paragraphs.single;
    final imported = paragraph.inlines.whereType<WmlRun>().first;
    imported.properties.complexScriptLanguage = 'he-IL';
    paragraph.inlines.add(
      WmlRun(
        text: 'חדש',
        properties: WmlRunProps(complexScriptLanguage: 'he-IL'),
      ),
    );
    final reopened = WordDeserializer().readBytes(
      WordSerializer().writeBytes(document),
    );
    final runs = reopened.paragraphs.single.inlines
        .whereType<WmlRun>()
        .toList();
    expect(runs.first.properties.proofingLanguage, 'de-DE');
    expect(runs.first.properties.complexScriptLanguage, 'he-IL');
    expect(runs.first.properties.sourcePropertiesXml, contains('ja-JP'));
    expect(runs.first.properties.complexScript, isTrue);
    expect(runs.last.properties.proofingLanguage, isNull);
    expect(runs.last.properties.complexScriptLanguage, 'he-IL');
  });

  for (final differentMarker in [false, true]) {
    test(
      'run formatting retains distinct complex-script ${differentMarker ? 'markers' : 'languages'}',
      () {
        final paragraph = WmlParagraph(
          inlines: [
            WmlRun(
              text: 'one',
              properties: WmlRunProps(
                proofingLanguage: 'en-US',
                complexScriptLanguage: 'ar-SA',
                complexScript: differentMarker ? true : null,
              ),
            ),
            WmlRun(
              text: 'two',
              properties: WmlRunProps(
                proofingLanguage: 'en-US',
                complexScriptLanguage: differentMarker ? 'ar-SA' : 'he-IL',
                complexScript: differentMarker ? false : null,
              ),
            ),
          ],
        );
        WmlRunEdit.applyRange(paragraph, 0, 6, (props) => props.bold = true);
        final runs = paragraph.inlines.whereType<WmlRun>().toList();
        expect(runs.map((run) => run.text), ['one', 'two']);
        expect(runs.every((run) => run.properties.bold == true), isTrue);
        expect(runs.first.properties.complexScriptLanguage, 'ar-SA');
        expect(
          runs.last.properties.complexScriptLanguage,
          differentMarker ? 'ar-SA' : 'he-IL',
        );
        expect(
          runs.first.properties.complexScript,
          differentMarker ? true : null,
        );
        expect(
          runs.last.properties.complexScript,
          differentMarker ? false : null,
        );
      },
    );
  }
}
