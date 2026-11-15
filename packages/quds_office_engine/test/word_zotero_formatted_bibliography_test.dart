import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _metadata = <String, dynamic>{
  'uncited': <dynamic>[],
  'omitted': <dynamic>[],
  'custom': <dynamic>[],
  'futureBibliography': <String, dynamic>{'retain': true},
};

ZoteroCitation _citation() => ZoteroCitation.fromJson({
  'citationID': 'rich-citation',
  'properties': {
    'plainCitation': 'E=mc2',
    'formattedCitation': r'E=mc{\super 2}',
    'futureProperty': 'preserved',
  },
  'futureRoot': {'keep': true},
  'citationItems': [
    {
      'id': 'http://zotero.org/users/42/items/ABCD1234',
      'uris': ['http://zotero.org/users/42/items/ABCD1234'],
      'itemData': {'id': 17, 'type': 'book', 'title': 'Physics'},
    },
  ],
});

List<(String, bool, bool, WmlUnderline, WmlVertAlign)> _runs(
  WmlParagraph paragraph,
) => [
  for (final run in paragraph.inlines.whereType<WmlRun>())
    (
      run.text,
      run.properties.bold,
      run.properties.italic,
      run.properties.underline,
      run.properties.vertAlign,
    ),
];

void main() {
  for (final isolate in <bool>[false, true]) {
    test(
      'rich bibliography retains styles and metadata through three ${isolate ? 'isolate' : 'direct'} saves',
      () async {
        final rich = ZoteroFormattedText.fromHtml(
          '<div class="csl-entry">Smith. <i>Book</i>. <b>Vol. 2</b>. H<sub>2</sub>O.</div>'
          '<div class="csl-entry">Jones. x<sup>3</sup>. <u>Underlined</u>.</div>',
        );
        var document = WmlDocument.empty(text: 'Surrounding body');
        document.sections.single.blocks.add(
          WordZotero.bibliography(
            text: rich.plainText,
            formattedText: rich,
            metadata: _metadata,
          ),
        );
        final before = _runs(document.paragraphs.last);
        expect(before.any((run) => run.$3), isTrue);
        expect(before.any((run) => run.$2), isTrue);
        expect(before.any((run) => run.$5 == WmlVertAlign.subscript), isTrue);
        expect(before.any((run) => run.$5 == WmlVertAlign.superscript), isTrue);
        expect(WordZotero.fields(document).single.wholeParagraph, isTrue);
        for (var cycle = 0; cycle < 3; cycle++) {
          WordFields.update(document);
          final bytes = isolate
              ? await OfficeIsolateSave.word(document)
              : WordSerializer().writeBytes(document);
          final package = OpcPackage.openBytes(bytes);
          final xml = package.getPart('/word/document.xml')!.readText();
          expect(xml, isNot(contains('fldSimple')));
          expect(xml, contains('w:vertAlign w:val="superscript"'));
          expect(xml, contains('w:vertAlign w:val="subscript"'));
          document = WordDeserializer().readBytes(bytes);
          final field = WordZotero.fields(document).single;
          expect(field.kind, ZoteroFieldKind.bibliography);
          expect(field.cachedText, rich.plainText);
          expect(field.metadata, _metadata);
          expect(field.canEdit, isTrue);
          expect(_runs(document.paragraphs.last), before);
          expect(document.paragraphs.first.text, 'Surrounding body');
        }
      },
    );
  }

  test(
    'existing sole-run bibliography upgrades to a paragraph-owned rich cache',
    () {
      final document = WmlDocument.empty(text: 'Before');
      final paragraph = WordZotero.bibliography(
        text: 'Old bibliography',
        metadata: _metadata,
      );
      document.sections.single.blocks.add(paragraph);
      final original = WordZotero.fields(document).single;
      expect(original.run, isNotNull);
      final rich = ZoteroFormattedText.fromHtml('New <i>Title</i>');
      WordZotero.updateBibliography(
        original,
        text: rich.plainText,
        formattedText: rich,
      );
      final field = WordZotero.fields(document).single;
      expect(field.wholeParagraph, isTrue);
      expect(field.run, isNull);
      expect(field.metadata, _metadata);
      expect(field.cachedText, 'New Title');
      expect(
        paragraph.inlines.whereType<WmlRun>().last.properties.italic,
        isTrue,
      );
      expect(paragraph.properties.styleId, 'Bibliography');
      expect(document.paragraphs.first.text, 'Before');
      WordZotero.unlink(field);
      expect(WordZotero.fields(document), isEmpty);
      expect(paragraph.text, 'New Title');
      expect(
        paragraph.inlines.whereType<WmlRun>().last.properties.italic,
        isTrue,
      );
    },
  );

  test(
    'rich update preserves a whole-paragraph field and accepts explicit plain fallback',
    () {
      final first = ZoteroFormattedText.fromHtml('First <b>Book</b>');
      final second = ZoteroFormattedText.fromHtml('Second <i>Book</i>');
      final document = WmlDocument.empty();
      document.sections.single.blocks.add(
        WordZotero.bibliography(
          text: first.plainText,
          formattedText: first,
          metadata: _metadata,
        ),
      );
      WordZotero.updateBibliography(
        WordZotero.fields(document).single,
        text: second.plainText,
        formattedText: second,
      );
      var field = WordZotero.fields(document).single;
      expect(field.wholeParagraph, isTrue);
      expect(field.cachedText, 'Second Book');
      expect(field.metadata, _metadata);
      expect(
        field.paragraph.inlines.whereType<WmlRun>().last.properties.italic,
        isTrue,
      );
      WordZotero.updateBibliography(field, text: 'Plain replacement');
      field = WordZotero.fields(document).single;
      expect(field.run, isNotNull);
      expect(field.cachedText, 'Plain replacement');
      expect(field.metadata, _metadata);
    },
  );

  test(
    'rich replacement of an inline bibliography refuses without touching its neighbors',
    () {
      final document = WmlDocument.empty();
      final paragraph = document.paragraphs.single;
      final source = WordZotero.bibliography(
        text: 'Old',
        metadata: _metadata,
      ).inlines.single;
      paragraph.inlines
        ..clear()
        ..addAll(<WmlInline>[
          WmlRun(text: 'Before', properties: WmlRunProps(bold: true)),
          source,
          WmlRun(text: 'After', properties: WmlRunProps(italic: true)),
        ]);
      final field = WordZotero.fields(document).single;
      final inlines = List<WmlInline>.of(paragraph.inlines);
      final rich = ZoteroFormattedText.fromHtml('<i>New</i>');
      expect(
        () => WordZotero.updateBibliography(
          field,
          text: rich.plainText,
          formattedText: rich,
        ),
        throwsUnsupportedError,
      );
      expect(paragraph.inlines, orderedEquals(inlines));
      expect(paragraph.text, 'BeforeOldAfter');
      expect(WordZotero.fields(document).single.instruction, field.instruction);
      WordZotero.updateBibliography(field, text: 'Plain');
      expect(paragraph.text, 'BeforePlainAfter');
    },
  );

  test(
    'a reopened full-paragraph complex bibliography supports another rich update',
    () {
      final first = ZoteroFormattedText.fromHtml('First <i>Title</i>');
      final second = ZoteroFormattedText.fromHtml('Second <b>Title</b>');
      var document = WmlDocument.empty();
      document.sections.single.blocks.add(
        WordZotero.bibliography(
          text: first.plainText,
          formattedText: first,
          metadata: _metadata,
        ),
      );
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final field = WordZotero.fields(document).single;
      expect(field.wholeParagraph, isFalse);
      expect(field.run, isNull);
      expect(field.start, 0);
      expect(field.end, field.paragraph.text.length);
      WordZotero.updateBibliography(
        field,
        text: second.plainText,
        formattedText: second,
      );
      var current = WordZotero.fields(document).single;
      expect(current.wholeParagraph, isTrue);
      expect(current.cachedText, second.plainText);
      expect(current.metadata, _metadata);
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      current = WordZotero.fields(document).single;
      expect(current.cachedText, second.plainText);
      expect(current.metadata, _metadata);
      expect(
        current.paragraph.inlines.whereType<WmlRun>().last.properties.bold,
        isTrue,
      );
    },
  );

  test(
    'zero-width wrappers outside a whole-text field prevent rich replacement',
    () {
      final rich = ZoteroFormattedText.fromHtml('Old <i>Title</i>');
      final replacement = ZoteroFormattedText.fromHtml('New <b>Title</b>');
      var document = WmlDocument.empty();
      document.sections.single.blocks.add(
        WordZotero.bibliography(
          text: rich.plainText,
          formattedText: rich,
          metadata: _metadata,
        ),
      );
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final paragraph = document.paragraphs.last;
      paragraph.inlines.insert(
        0,
        WmlBookmarkBoundary(id: '12', isStart: true, name: 'around'),
      );
      paragraph.inlines.add(WmlBookmarkBoundary(id: '12', isStart: false));
      final field = WordZotero.fields(document).single;
      expect(field.canEdit, isTrue);
      expect(field.start, 0);
      expect(field.end, paragraph.text.length);
      final original = List<WmlInline>.of(paragraph.inlines);
      expect(
        () => WordZotero.updateBibliography(
          field,
          text: replacement.plainText,
          formattedText: replacement,
        ),
        throwsUnsupportedError,
      );
      expect(paragraph.inlines, orderedEquals(original));
      expect(WordZotero.fields(document).single.instruction, field.instruction);
      expect(paragraph.text, rich.plainText);
    },
  );

  test(
    'text mismatch refuses both construction and replacement before mutation',
    () {
      final rich = ZoteroFormattedText.fromHtml('<i>Title</i>');
      expect(
        () => WordZotero.bibliography(text: 'Different', formattedText: rich),
        throwsArgumentError,
      );
      final document = WmlDocument.empty();
      final paragraph = WordZotero.bibliography(
        text: 'Old',
        metadata: _metadata,
      );
      document.sections.single.blocks.add(paragraph);
      final field = WordZotero.fields(document).single;
      final original = paragraph.inlines.single;
      expect(
        () => WordZotero.updateBibliography(
          field,
          text: 'Different',
          formattedText: rich,
        ),
        throwsArgumentError,
      );
      expect(identical(paragraph.inlines.single, original), isTrue);
      expect(WordZotero.fields(document).single.instruction, field.instruction);
      expect(paragraph.text, 'Old');
    },
  );

  test('rich replacement retains stale-handle and locked-field refusal', () {
    final rich = ZoteroFormattedText.fromHtml('<i>New</i>');
    final document = WmlDocument.empty();
    final paragraph = WordZotero.bibliography(text: 'Old');
    document.sections.single.blocks.add(paragraph);
    final stale = WordZotero.fields(document).single;
    WordZotero.updateBibliography(stale, text: 'Changed');
    expect(
      () => WordZotero.updateBibliography(
        stale,
        text: rich.plainText,
        formattedText: rich,
      ),
      throwsStateError,
    );
    (paragraph.inlines.single as WmlRun).fieldLocked = true;
    final locked = WordZotero.fields(document).single;
    expect(
      () => WordZotero.updateBibliography(
        locked,
        text: rich.plainText,
        formattedText: rich,
      ),
      throwsUnsupportedError,
    );
    expect(paragraph.text, 'Changed');
  });

  test(
    'same-text citation edit preserves complex result runs and foreign formatted metadata',
    () {
      final document = WmlDocument.empty();
      final paragraph = document.paragraphs.single;
      final citation = _citation();
      final code = citation.fieldInstruction;
      final italic = WmlRun(text: 'E', properties: WmlRunProps(italic: true));
      final bold = WmlRun(
        text: '=mc',
        properties: WmlRunProps(bold: true, color: '0000FF'),
      );
      final superscript = WmlRun(
        text: '2',
        properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
      );
      paragraph.inlines
        ..clear()
        ..addAll(<WmlInline>[
          WmlRun(text: 'Before '),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.begin,
            sourceXml:
                '<w:fldChar xmlns:w="${OfficeNamespaces.w}" w:fldCharType="begin" w:dirty="1"/>',
          ),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: code.substring(0, 20),
          ),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: code.substring(20),
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          italic,
          bold,
          superscript,
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          WmlRun(text: ' After'),
        ]);
      final field = WordZotero.fields(document).single;
      expect(field.canEdit, isTrue);
      final updatedItem = ZoteroCitationItem.fromJson({
        ...citation.items.single.toJson(),
        'locator': '15',
      });
      final updated = citation.withItems(
        [updatedItem],
        plainCitation: field.cachedText,
        formattedCitation: citation.formattedCitation,
      );
      WordZotero.updateCitation(field, updated);
      expect(paragraph.inlines.contains(italic), isTrue);
      expect(paragraph.inlines.contains(bold), isTrue);
      expect(paragraph.inlines.contains(superscript), isTrue);
      expect(paragraph.text, 'Before E=mc2 After');
      final current = WordZotero.fields(document).single;
      expect(current.citation!.items.single.locator, '15');
      expect(current.citation!.properties['futureProperty'], 'preserved');
      expect(current.citation!.toJson()['futureRoot'], {'keep': true});
      expect(current.citation!.formattedCitation, citation.formattedCitation);
      final begin = paragraph.inlines.whereType<WmlFieldBoundary>().first;
      expect(begin.sourceXml, isNot(contains('dirty')));
      expect(
        paragraph.inlines.whereType<WmlFieldBoundary>().where(
          (boundary) => boundary.kind == WmlFieldBoundaryKind.instruction,
        ),
        hasLength(1),
      );
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      final reopenedField = WordZotero.fields(reopened).single;
      expect(reopenedField.cachedText, 'E=mc2');
      expect(
        reopenedField.citation!.formattedCitation,
        citation.formattedCitation,
      );
      expect(_runs(reopened.paragraphs.single), _runs(paragraph));
    },
  );

  test('same-text whole-paragraph citation edits keep every result run', () {
    final citation = _citation();
    final document = WmlDocument.empty();
    final paragraph = document.paragraphs.single;
    paragraph.properties.fieldInstruction = citation.fieldInstruction;
    paragraph.inlines
      ..clear()
      ..addAll(<WmlInline>[
        WmlRun(text: 'E=mc', properties: WmlRunProps(italic: true)),
        WmlRun(
          text: '2',
          properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
        ),
      ]);
    final runs = List<WmlInline>.of(paragraph.inlines);
    final field = WordZotero.fields(document).single;
    expect(field.wholeParagraph, isTrue);
    WordZotero.updateCitation(
      field,
      citation.withItems(
        citation.items,
        plainCitation: field.cachedText,
        formattedCitation: citation.formattedCitation,
        noteIndex: 3,
      ),
    );
    expect(paragraph.inlines, orderedEquals(runs));
    expect(WordZotero.fields(document).single.citation!.noteIndex, 3);
    expect(_runs(paragraph).last.$5, WmlVertAlign.superscript);
  });
}
