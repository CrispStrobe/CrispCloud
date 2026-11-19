import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WmlDocument _document({
  String text = 'الفكرة جميلة',
  String flags = '<w:rtl/><w:cs w:val="0"/>',
  bool characterStyle = true,
  bool paragraphStyle = true,
  String? directBidi = 'ar-SA',
}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>
${paragraphStyle ? '<w:pPr><w:pStyle w:val="ParagraphChild"/></w:pPr>' : ''}
<w:r><w:rPr>
${characterStyle ? '<w:rStyle w:val="CharacterChild"/>' : ''}
<w:lang w:val="en-GB" w:eastAsia="ja-JP" ${directBidi == null ? '' : 'w:bidi="$directBidi"'}/>
$flags<w:spacing w:val="23"/>
</w:rPr><w:t>$text</w:t></w:r></w:p><w:sectPr/></w:body></w:document>''');
  package
      .createPart('/word/styles.xml', OfficeContentTypes.wordStyles)
      .writeText('''
<w:styles xmlns:w="${OfficeNamespaces.w}">
<w:docDefaults><w:rPrDefault><w:rPr><w:lang w:val="de-DE" w:bidi="ar-AE"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:styleId="ParagraphBase"><w:rPr><w:lang w:bidi="ar-EG"/><w:b/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ParagraphChild"><w:basedOn w:val="ParagraphBase"/></w:style>
<w:style w:type="character" w:styleId="CharacterBase"><w:rPr><w:lang w:bidi="ar-MA"/><w:i/></w:rPr></w:style>
<w:style w:type="character" w:styleId="CharacterChild"><w:basedOn w:val="CharacterBase"/></w:style>
</w:styles>''');
  package
      .relationshipsFor('/word/document.xml')
      .add(type: RelationshipTypes.styles, target: 'styles.xml');
  return WordDeserializer().read(package);
}

WordEditorController _controller(WmlDocument document) {
  final controller = WordEditorController(document: document);
  addTearDown(controller.dispose);
  return controller;
}

List<WmlRun> _runs(WordEditorController controller) =>
    controller.document.paragraphs.single.inlines.whereType<WmlRun>().toList();

WmlDocument _reload(WordEditorController controller) =>
    WordDeserializer().readBytes(controller.saveBytes());

void _expectMetadata(
  WmlDocument document, {
  required String? directBidi,
  required String? directLatin,
}) {
  final xml = XmlDocument.parse(
    document.package!.getPart('/word/document.xml')!.readText(),
  );
  final run = xml.root!.firstChild('body')!.firstChild('p')!.firstChild('r')!;
  final props = run.firstChild('rPr')!;
  final language = props.firstChild('lang')!;
  expect(language.getAttribute('val'), directLatin);
  expect(language.getAttribute('eastAsia'), 'ja-JP');
  expect(language.getAttribute('bidi'), directBidi);
  expect(props.firstChild('rtl'), isNotNull);
  expect(props.firstChild('cs')!.getAttribute('val'), '0');
  expect(props.firstChild('spacing')!.getAttribute('val'), '23');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final activeLanguageOnly in [false, true]) {
    for (final language in ['ar-DZ', 'en-GB']) {
      test(
        '${activeLanguageOnly ? 'active-only' : 'both-slot'} choosing $language updates the routed language and survives history',
        () {
          final controller = _controller(_document());
          expect(controller.textProofingTarget!.language, 'ar-SA');
          expect(
            controller.setTextProofingLanguage(
              language,
              target: controller.textProofingTarget!,
              activeLanguageOnly: activeLanguageOnly,
            ),
            isTrue,
          );
          expect(controller.textProofingTarget!.language, language);
          expect(
            _runs(controller).single.properties.proofingLanguage,
            activeLanguageOnly ? 'en-GB' : language,
          );
          expect(
            _runs(controller).single.properties.complexScriptLanguage,
            language,
          );
          expect(_runs(controller).single.properties.complexScript, isTrue);
          controller.undo();
          expect(controller.textProofingTarget!.language, 'ar-SA');
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(controller.textProofingTarget!.language, language);
          final loaded = _reload(controller);
          _expectMetadata(
            loaded,
            directBidi: language,
            directLatin: activeLanguageOnly ? 'en-GB' : language,
          );
          expect(_controller(loaded).textProofingTarget!.language, language);
        },
      );
    }

    for (final (name, characterStyle, paragraphStyle, inherited) in [
      ('character style', true, true, 'ar-MA'),
      ('paragraph style', false, true, 'ar-EG'),
      ('document default', false, false, 'ar-AE'),
    ]) {
      test(
        '${activeLanguageOnly ? 'active-only' : 'both-slot'} reset inherits $name through undo and DOCX without a direct bidi tag',
        () {
          final controller = _controller(
            _document(
              characterStyle: characterStyle,
              paragraphStyle: paragraphStyle,
            ),
          );
          expect(
            controller.setTextProofingLanguage(
              null,
              target: controller.textProofingTarget!,
              activeLanguageOnly: activeLanguageOnly,
            ),
            isTrue,
          );
          expect(controller.textProofingTarget!.language, inherited);
          expect(
            _runs(controller).single.properties.proofingLanguage,
            activeLanguageOnly ? 'en-GB' : null,
          );
          expect(_runs(controller).single.properties.complexScript, isTrue);
          final revision = controller.contentRevision;
          expect(
            controller.setTextProofingLanguage(
              null,
              target: controller.textProofingTarget!,
              activeLanguageOnly: activeLanguageOnly,
            ),
            isTrue,
          );
          expect(controller.contentRevision, revision);
          controller.undo();
          expect(controller.textProofingTarget!.language, 'ar-SA');
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(controller.textProofingTarget!.language, inherited);
          final loaded = _reload(controller);
          _expectMetadata(
            loaded,
            directBidi: null,
            directLatin: activeLanguageOnly ? 'en-GB' : null,
          );
          final reopened = _controller(loaded);
          expect(reopened.textProofingTarget!.language, inherited);
          if (!paragraphStyle) {
            expect(
              _runs(reopened).single.properties.complexScriptLanguage,
              isNull,
            );
            loaded.complexScriptLanguage = 'ar-QA';
            expect(reopened.textProofingTarget!.language, 'ar-QA');
          }
        },
      );
    }
  }

  test('partial Arabic selection keeps its chosen language separate', () {
    final controller = _controller(_document(flags: ''));
    controller.caret
      ..selectionAnchor = 0
      ..logicalIndex = 'الفكرة'.length;
    expect(
      controller.setTextProofingLanguage(
        'ar-DZ',
        target: controller.textProofingTarget!,
      ),
      isTrue,
    );
    expect(
      _runs(
        controller,
      ).map((run) => (run.text, run.properties.complexScriptLanguage)),
      [('الفكرة', 'ar-DZ'), (' جميلة', 'ar-SA')],
    );
    expect(controller.textProofingTarget!.language, 'ar-DZ');
    final loaded = _reload(controller);
    expect(
      loaded.paragraphs.single.inlines.whereType<WmlRun>().map(
        (run) => (run.text, run.properties.complexScriptLanguage),
      ),
      [('الفكرة', 'ar-DZ'), (' جميلة', 'ar-SA')],
    );
    controller.undo();
    expect(_runs(controller).single.text, 'الفكرة جميلة');
    expect(controller.textProofingTarget!.language, 'ar-SA');
  });

  test(
    'a Latin-only selection changes val without changing the Arabic tail',
    () {
      final controller = _controller(_document(text: 'Text فكرة', flags: ''));
      controller.caret
        ..selectionAnchor = 0
        ..logicalIndex = 4;
      expect(
        controller.setTextProofingLanguage(
          'de-DE',
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(
        _runs(controller).map(
          (run) => (
            run.text,
            run.properties.proofingLanguage,
            run.properties.complexScriptLanguage,
          ),
        ),
        [('Text', 'de-DE', 'ar-SA'), (' فكرة', 'en-GB', 'ar-SA')],
      );
      expect(controller.textProofingTarget!.language, 'de-DE');
    },
  );

  test(
    'explicit both-slot Latin selection changes both overrides without changing the Arabic tail',
    () {
      final controller = _controller(_document(text: 'Text فكرة', flags: ''));
      controller.caret
        ..selectionAnchor = 0
        ..logicalIndex = 4;
      expect(
        controller.setTextProofingLanguage(
          'de-DE',
          target: controller.textProofingTarget!,
          activeLanguageOnly: false,
        ),
        isTrue,
      );
      expect(
        _runs(controller).map(
          (run) => (
            run.text,
            run.properties.proofingLanguage,
            run.properties.complexScriptLanguage,
          ),
        ),
        [('Text', 'de-DE', 'de-DE'), (' فكرة', 'en-GB', 'ar-SA')],
      );
      expect(controller.textProofingTarget!.language, 'de-DE');
    },
  );

  test('active-only Latin text with an explicit cs marker uses bidi', () {
    final controller = _controller(_document(text: 'Latin', flags: '<w:cs/>'));
    expect(controller.textProofingTarget!.language, 'ar-SA');
    expect(
      controller.setTextProofingLanguage(
        'he-IL',
        target: controller.textProofingTarget!,
        activeLanguageOnly: true,
      ),
      isTrue,
    );
    expect(controller.textProofingTarget!.language, 'he-IL');
    expect(_runs(controller).single.properties.proofingLanguage, 'en-GB');
    expect(_runs(controller).single.properties.complexScriptLanguage, 'he-IL');
    final loaded = _reload(controller);
    final props = loaded.paragraphs.single.inlines
        .whereType<WmlRun>()
        .single
        .properties;
    expect(props.proofingLanguage, 'en-GB');
    expect(props.complexScriptLanguage, 'he-IL');
    expect(props.complexScript, isTrue);
    expect(props.sourcePropertiesXml, contains('ja-JP'));
  });

  test('a changed document bidi default makes a displayed target stale', () {
    final controller = _controller(
      _document(characterStyle: false, paragraphStyle: false, directBidi: null),
    );
    final target = controller.textProofingTarget!;
    expect(target.language, 'ar-AE');
    controller.document.complexScriptLanguage = 'ar-QA';
    expect(
      controller.setTextProofingLanguage('ar-DZ', target: target),
      isFalse,
    );
    expect(controller.canUndo, isFalse);
  });
  test(
    'choosing existing Latin metadata retains the selected script boundary through history and save',
    () {
      final controller = _controller(_document(text: 'Text فكرة', flags: ''));
      controller.caret
        ..selectionAnchor = 0
        ..logicalIndex = 4;
      expect(controller.textProofingTarget!.language, 'en-GB');
      expect(
        controller.setTextProofingLanguage(
          'en-GB',
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.textProofingTarget!.language, 'en-GB');
      expect(_runs(controller).map((run) => run.text), ['Text', ' فكرة']);
      for (final run in _runs(controller)) {
        expect(run.properties.proofingLanguage, 'en-GB');
        expect(run.properties.complexScriptLanguage, 'ar-SA');
        expect(run.properties.complexScript, isNot(isTrue));
      }
      final revision = controller.contentRevision;
      expect(
        controller.setTextProofingLanguage(
          'en-GB',
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.contentRevision, revision);
      controller.undo();
      expect(_runs(controller).single.text, 'Text فكرة');
      expect(controller.textProofingTarget!.language, 'en-GB');
      controller.redo();
      expect(controller.textProofingTarget!.language, 'en-GB');
      final loaded = _reload(controller);
      final loadedRuns = loaded.paragraphs.single.inlines
          .whereType<WmlRun>()
          .toList();
      expect(loadedRuns.map((run) => run.text), ['Text', ' فكرة']);
      for (final run in loadedRuns) {
        expect(run.properties.proofingLanguage, 'en-GB');
        expect(run.properties.complexScriptLanguage, 'ar-SA');
        expect(
          run.properties.sourcePropertiesXml,
          contains('eastAsia="ja-JP"'),
        );
        expect(run.properties.sourcePropertiesXml, contains('spacing'));
      }
      final reopened = _controller(loaded);
      reopened.caret
        ..selectionAnchor = 0
        ..logicalIndex = 4;
      expect(reopened.textProofingTarget!.language, 'en-GB');
    },
  );

  test(
    'resetting an already inherited Latin slot retains its selected script boundary',
    () {
      final document = WmlDocument.empty()..proofingLanguage = 'en-GB';
      document.paragraphs.single.inlines = [
        WmlRun(
          text: 'Text فكرة',
          properties: WmlRunProps(complexScriptLanguage: 'ar-SA'),
        ),
      ];
      final controller = _controller(document);
      controller.caret
        ..selectionAnchor = 0
        ..logicalIndex = 4;
      expect(controller.textProofingTarget!.language, 'en-GB');
      expect(
        controller.setTextProofingLanguage(
          null,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.textProofingTarget!.language, 'en-GB');
      expect(_runs(controller).map((run) => run.text), ['Text', ' فكرة']);
      for (final run in _runs(controller)) {
        expect(run.properties.proofingLanguage, isNull);
        expect(run.properties.complexScriptLanguage, 'ar-SA');
        expect(run.properties.complexScript, isNull);
      }
      final revision = controller.contentRevision;
      expect(
        controller.setTextProofingLanguage(
          null,
          target: controller.textProofingTarget!,
        ),
        isTrue,
      );
      expect(controller.contentRevision, revision);
      controller.undo();
      expect(_runs(controller).single.text, 'Text فكرة');
      expect(controller.textProofingTarget!.language, 'en-GB');
      controller.redo();
      expect(controller.textProofingTarget!.language, 'en-GB');
      final reopened = _controller(_reload(controller));
      reopened.caret
        ..selectionAnchor = 0
        ..logicalIndex = 4;
      expect(_runs(reopened).map((run) => run.text), ['Text', ' فكرة']);
      expect(reopened.textProofingTarget!.language, 'en-GB');
      expect(_runs(reopened).last.properties.complexScriptLanguage, 'ar-SA');
    },
  );
}
