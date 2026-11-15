import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

ZoteroCitation _citation(String id, String text) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  items: <ZoteroCitationItem>[
    ZoteroCitationItem.fromCsl(
      itemData: <String, dynamic>{
        'id': 17,
        'type': 'book',
        'title': 'A source',
        'author': <Map<String, String>>[
          <String, String>{'family': 'Lovelace'},
        ],
        'issued': <String, dynamic>{
          'date-parts': <List<int>>[
            <int>[1843],
          ],
        },
      },
      uris: <String>['http://zotero.org/users/42/items/ABCD1234'],
      locator: '12',
      label: 'page',
    ),
  ],
);

WordEditorController _controller({
  WmlDocument? document,
  OfficeSurfaceConfig? config,
}) {
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: 'LeftRight'),
    config: config,
  );
  addTearDown(controller.dispose);
  return controller;
}

WmlDocument _twoFields() {
  final document = WmlDocument.empty(text: 'Before ');
  final paragraph = document.paragraphs.single;
  WordZotero.insertCitation(paragraph, _citation('a', '(A)'));
  paragraph.inlines.add(WmlRun(text: ' between '));
  WordZotero.insertCitation(paragraph, _citation('b', '(B)'));
  paragraph.inlines.add(WmlRun(text: ' after'));
  return document;
}

WmlRunProps _propertiesContaining(WmlZoteroField field, String text) => field
    .paragraph
    .inlines
    .whereType<WmlRun>()
    .singleWhere((run) => run.text.contains(text))
    .properties;

List<Object?> _cacheStyles(WmlZoteroField field) => <Object?>[
  for (final run in field.paragraph.inlines.whereType<WmlRun>())
    <Object?>[
      run.text,
      run.properties.bold,
      run.properties.italic,
      run.properties.underline,
      run.properties.strike,
      run.properties.vertAlign,
      run.properties.color,
      run.properties.fontSizeHalfPoints,
      run.properties.asciiFont,
    ],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'citation insertion, undo and redo preserve source and advance save revisions',
    () {
      final controller = _controller();
      final paragraph = controller.document.paragraphs.single;
      paragraph.inlines.whereType<WmlRun>().single.properties.bold = true;
      controller.caret.logicalIndex = 4;
      controller.caret.collapseSelection();
      final initialRevision = controller.contentRevision;
      controller.insertZoteroCitation(_citation('inserted', '(Ada)'));
      expect(paragraph.text, 'Left(Ada)Right');
      expect(controller.caret.logicalIndex, 9);
      expect(controller.isDirty, isTrue);
      expect(controller.contentRevision, greaterThan(initialRevision));
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(controller.zoteroFields.single.citation!.citationId, 'inserted');
        expect(
          controller.zoteroFields.single.citation!.items.single.locator,
          '12',
        );
        expect(controller.zoteroFields.single.run!.properties.bold, isTrue);
        final insertedRevision = controller.contentRevision;
        controller.undo();
        expect(paragraph.text, 'LeftRight');
        expect(controller.zoteroFields, isEmpty);
        expect(controller.contentRevision, greaterThan(insertedRevision));
        controller.redo();
        expect(paragraph.text, 'Left(Ada)Right');
      }
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      expect(
        WordZotero.fields(reopened).single.citation!.citationId,
        'inserted',
      );
    },
  );

  test('editing and unlinking are independent repeatable undo steps', () {
    final controller = _controller(document: _twoFields());
    var first = controller.zoteroFields.first;
    controller.updateZoteroCitation(
      first,
      first.citation!.withItems(
        first.citation!.items,
        plainCitation: '(Ada, 1843, p. 12)',
      ),
    );
    expect(
      controller.document.paragraphs.single.text,
      'Before (Ada, 1843, p. 12) between (B) after',
    );
    first = controller.zoteroFields.first;
    controller.unlinkZoteroField(first);
    expect(
      controller.zoteroFields.map((field) => field.citation!.citationId),
      <String>['b'],
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      controller.undo();
      expect(controller.zoteroFields, hasLength(2));
      expect(controller.zoteroFields.first.cachedText, '(Ada, 1843, p. 12)');
      controller.undo();
      expect(
        controller.document.paragraphs.single.text,
        'Before (A) between (B) after',
      );
      controller.redo();
      controller.redo();
      expect(controller.zoteroFields, hasLength(1));
      expect(
        controller.document.paragraphs.single.text,
        'Before (Ada, 1843, p. 12) between (B) after',
      );
    }
  });

  test(
    'batch refresh updates variable-length fields in one atomic undo step',
    () {
      final controller = _controller(document: _twoFields());
      controller.refreshZoteroCitations(<String, ZoteroCitation>{
        'a': _citation('a', '(A much longer citation)'),
        'b': _citation('b', '(B short)'),
      });
      expect(
        controller.document.paragraphs.single.text,
        'Before (A much longer citation) between (B short) after',
      );
      controller.undo();
      expect(
        controller.document.paragraphs.single.text,
        'Before (A) between (B) after',
      );
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(
        controller.document.paragraphs.single.text,
        'Before (A much longer citation) between (B short) after',
      );
    },
  );

  test(
    'failed refresh leaves all text, save revisions and undo history unchanged',
    () {
      final controller = _controller(document: _twoFields());
      controller.zoteroFields.last.run!.fieldLocked = true;
      final before = controller.document.paragraphs.single.text;
      final revision = controller.contentRevision;
      expect(
        () => controller.refreshZoteroCitations(<String, ZoteroCitation>{
          'a': _citation('a', '(Changed)'),
          'b': _citation('b', '(Changed too)'),
        }),
        throwsUnsupportedError,
      );
      expect(controller.document.paragraphs.single.text, before);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
      expect(
        () => controller.refreshZoteroCitations(<String, ZoteroCitation>{
          'missing': _citation('missing', '(Missing)'),
        }),
        throwsUnsupportedError,
      );
      expect(controller.contentRevision, revision);
    },
  );

  test(
    'foreign fields, stale handles and duplicate identities are rejected',
    () {
      final controller = _controller(document: _twoFields());
      final foreign = WordZotero.fields(_twoFields()).first;
      expect(() => controller.unlinkZoteroField(foreign), throwsStateError);
      expect(
        () => controller.insertZoteroCitation(_citation('a', '(Duplicate)')),
        throwsArgumentError,
      );
      final stale = controller.zoteroFields.first;
      controller.updateZoteroCitation(stale, _citation('a', '(Changed)'));
      expect(
        () => controller.updateZoteroCitation(
          stale,
          _citation('a', '(Outdated)'),
        ),
        throwsStateError,
      );
      expect(controller.zoteroFields.first.cachedText, '(Changed)');
      final fresh = controller.zoteroFields.first;
      expect(
        () => controller.updateZoteroCitation(
          fresh,
          _citation('different-id', '(Wrong identity)'),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'bibliography creation and replacement retain field metadata through history',
    () {
      final controller = _controller();
      controller.insertZoteroBibliography(
        text: 'First bibliography',
        metadata: <String, dynamic>{
          'uncited': <dynamic>[],
          'omitted': <dynamic>[],
          'custom': <dynamic>[],
          'extension': 'keep',
        },
      );
      expect(controller.zoteroFields.single.kind, ZoteroFieldKind.bibliography);
      controller.updateZoteroBibliography(
        controller.zoteroFields.single,
        text: 'Updated bibliography',
      );
      expect(controller.zoteroFields.single.cachedText, 'Updated bibliography');
      expect(controller.zoteroFields.single.metadata!['extension'], 'keep');
      controller.undo();
      expect(controller.zoteroFields.single.cachedText, 'First bibliography');
      controller.undo();
      expect(controller.zoteroFields, isEmpty);
      controller.redo();
      controller.redo();
      expect(controller.zoteroFields.single.cachedText, 'Updated bibliography');
    },
  );

  test(
    'rich bibliography insertion and replacement survive history and DOCX save',
    () {
      final controller = _controller();
      final original = ZoteroFormattedText.fromHtml(
        '<div class="csl-entry"><i>Analytical Engine</i>. 1843.</div>',
      );
      final replacement = ZoteroFormattedText.fromHtml(
        '<div class="csl-entry"><b>Lovelace</b>. H<sub>2</sub>O'
        '<br><u>Notes</u>.</div>',
      );
      final metadata = <String, dynamic>{
        'uncited': <dynamic>[],
        'omitted': <dynamic>[],
        'custom': <dynamic>[],
        'extension': <String, dynamic>{
          'owner': 'keep',
          'nested': <dynamic>[1, true],
        },
      };
      final initialRevision = controller.contentRevision;
      controller.insertZoteroBibliography(
        text: original.plainText,
        formattedText: original,
        metadata: metadata,
      );
      expect(controller.contentRevision, greaterThan(initialRevision));
      expect(controller.zoteroFields.single.cachedText, original.plainText);
      expect(
        _propertiesContaining(
          controller.zoteroFields.single,
          'Analytical',
        ).italic,
        isTrue,
      );
      controller.updateZoteroBibliography(
        controller.zoteroFields.single,
        text: replacement.plainText,
        formattedText: replacement,
      );

      void expectReplacement(WmlZoteroField field) {
        expect(field.cachedText, 'Lovelace. H2O\nNotes.');
        expect(field.metadata, metadata);
        expect(_propertiesContaining(field, 'Lovelace').bold, isTrue);
        expect(
          _propertiesContaining(field, '2').vertAlign,
          WmlVertAlign.subscript,
        );
        expect(
          _propertiesContaining(field, 'Notes').underline,
          WmlUnderline.single,
        );
      }

      for (var cycle = 0; cycle < 2; cycle++) {
        expectReplacement(controller.zoteroFields.single);
        controller.undo();
        expect(controller.zoteroFields.single.cachedText, original.plainText);
        expect(
          _propertiesContaining(
            controller.zoteroFields.single,
            'Analytical',
          ).italic,
          isTrue,
        );
        expect(controller.zoteroFields.single.metadata, metadata);
        controller.undo();
        expect(controller.zoteroFields, isEmpty);
        expect(controller.document.paragraphs.single.text, 'LeftRight');
        expect(controller.canUndo, isFalse);
        controller.redo();
        controller.redo();
      }
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      expectReplacement(WordZotero.fields(reopened).single);
      final restored = _controller(document: reopened);
      restored.updateZoteroBibliography(
        restored.zoteroFields.single,
        text: original.plainText,
        formattedText: original,
      );
      expect(restored.zoteroFields.single.cachedText, original.plainText);
      expect(
        _propertiesContaining(
          restored.zoteroFields.single,
          'Analytical',
        ).italic,
        isTrue,
      );
      restored.undo();
      expectReplacement(restored.zoteroFields.single);
      expect(restored.canUndo, isFalse);
      restored.redo();
      final savedAgain = WordDeserializer().readBytes(restored.saveBytes());
      final finalField = WordZotero.fields(savedAgain).single;
      expect(finalField.cachedText, original.plainText);
      expect(finalField.metadata, metadata);
      expect(_propertiesContaining(finalField, 'Analytical').italic, isTrue);
    },
  );

  test(
    'mismatched rich bibliography insertion preserves redo and revision',
    () {
      final controller = _controller();
      controller.insertZoteroCitation(_citation('recoverable', '(Saved)'));
      controller.undo();
      final before = controller.document.paragraphs
          .map((paragraph) => paragraph.text)
          .toList();
      final revision = controller.contentRevision;
      final caret = controller.caret.logicalIndex;
      expect(controller.canRedo, isTrue);
      expect(
        () => controller.insertZoteroBibliography(
          text: 'The edited preview',
          formattedText: ZoteroFormattedText.fromHtml('<i>Stale preview</i>'),
        ),
        throwsArgumentError,
      );
      expect(
        controller.document.paragraphs.map((paragraph) => paragraph.text),
        before,
      );
      expect(controller.zoteroFields, isEmpty);
      expect(controller.contentRevision, revision);
      expect(controller.caret.logicalIndex, caret);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);
      controller.redo();
      expect(
        controller.zoteroFields.single.citation!.citationId,
        'recoverable',
      );
    },
  );

  test(
    'mismatched rich bibliography update retains cache, metadata and history',
    () {
      final controller = _controller();
      final original = ZoteroFormattedText.fromHtml('<i>First source</i>');
      final replacement = ZoteroFormattedText.fromHtml('<b>Second source</b>');
      controller.insertZoteroBibliography(
        text: original.plainText,
        formattedText: original,
        metadata: <String, dynamic>{'extension': 'keep'},
      );
      controller.updateZoteroBibliography(
        controller.zoteroFields.single,
        text: replacement.plainText,
        formattedText: replacement,
      );
      controller.undo();
      final before = _cacheStyles(controller.zoteroFields.single);
      final revision = controller.contentRevision;
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isTrue);
      expect(
        () => controller.updateZoteroBibliography(
          controller.zoteroFields.single,
          text: 'User-edited replacement',
          formattedText: replacement,
          metadata: <String, dynamic>{'extension': 'must not replace'},
        ),
        throwsArgumentError,
      );
      expect(_cacheStyles(controller.zoteroFields.single), before);
      expect(controller.zoteroFields.single.cachedText, original.plainText);
      expect(controller.zoteroFields.single.metadata!['extension'], 'keep');
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isTrue);
      controller.redo();
      expect(controller.zoteroFields.single.cachedText, replacement.plainText);
      expect(
        _propertiesContaining(controller.zoteroFields.single, 'Second').bold,
        isTrue,
      );
      controller.undo();
      expect(_cacheStyles(controller.zoteroFields.single), before);
    },
  );

  for (final viewing in <bool>[true, false]) {
    test(
      '${viewing ? 'viewing' : 'tracked'} mode protects rich bibliography operations',
      () {
        final original = ZoteroFormattedText.fromHtml('<i>Existing source</i>');
        final replacement = ZoteroFormattedText.fromHtml('<b>New source</b>');
        final document = WmlDocument.empty(text: 'Body');
        document.sections.single.blocks.add(
          WordZotero.bibliography(
            text: original.plainText,
            formattedText: original,
            metadata: <String, dynamic>{'extension': 'keep'},
          ),
        );
        document.trackRevisions = !viewing;
        final controller = _controller(
          document: document,
          config: viewing
              ? const OfficeSurfaceConfig(mode: OfficeInteractionMode.viewing)
              : null,
        );
        final before = _cacheStyles(controller.zoteroFields.single);
        final revision = controller.contentRevision;
        final outcome = viewing ? returnsNormally : throwsUnsupportedError;
        expect(
          () => controller.insertZoteroBibliography(
            text: replacement.plainText,
            formattedText: replacement,
          ),
          outcome,
        );
        expect(
          () => controller.updateZoteroBibliography(
            controller.zoteroFields.single,
            text: replacement.plainText,
            formattedText: replacement,
          ),
          outcome,
        );
        expect(controller.zoteroFields, hasLength(1));
        expect(_cacheStyles(controller.zoteroFields.single), before);
        expect(controller.zoteroFields.single.metadata!['extension'], 'keep');
        expect(document.paragraphs.map((p) => p.text), <String>[
          'Body',
          original.plainText,
        ]);
        expect(document.revisions, isEmpty);
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, isFalse);
        expect(controller.canRedo, isFalse);
      },
    );
  }

  test(
    'same-text citation metadata edits retain imported rich cache styles',
    () {
      final base = _citation('rich-import', 'Ada 1843');
      final citation = ZoteroCitation.fromJson(<String, dynamic>{
        ...base.toJson(),
        'futureCitationSetting': <String, dynamic>{'preserve': true},
        'properties': <String, dynamic>{
          ...base.properties,
          'formattedCitation': '<i>Ada</i> <sup>1843</sup>',
          'futureProperty': 'keep',
        },
      });
      final paragraph = WmlParagraph(
        inlines: <WmlInline>[
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: citation.fieldInstruction,
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlRun(
            text: 'Ada',
            properties: WmlRunProps(italic: true, color: '123456'),
          ),
          WmlRun(text: ' '),
          WmlRun(
            text: '1843',
            properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
        ],
      );
      final controller = _controller(
        document: WmlDocument(
          sections: <WmlSection>[
            WmlSection(blocks: <WmlBlock>[paragraph]),
          ],
        ),
      );
      final before = _cacheStyles(controller.zoteroFields.single);
      final item = citation.items.single;
      final updated = citation.withItems(
        <ZoteroCitationItem>[
          ZoteroCitationItem.fromJson(<String, dynamic>{
            ...item.toJson(),
            'locator': '29',
          }),
        ],
        plainCitation: citation.plainCitation,
        formattedCitation: citation.formattedCitation,
      );
      controller.updateZoteroCitation(controller.zoteroFields.single, updated);
      expect(_cacheStyles(controller.zoteroFields.single), before);
      expect(
        controller.zoteroFields.single.citation!.items.single.locator,
        '29',
      );
      controller.undo();
      expect(_cacheStyles(controller.zoteroFields.single), before);
      expect(
        controller.zoteroFields.single.citation!.items.single.locator,
        '12',
      );
      controller.redo();
      expect(_cacheStyles(controller.zoteroFields.single), before);
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      final field = WordZotero.fields(reopened).single;
      expect(field.cachedText, citation.plainCitation);
      expect(field.citation!.items.single.locator, '29');
      expect(field.citation!.items.single.uris, item.uris);
      expect(
        field.citation!.toJson()['futureCitationSetting'],
        <String, dynamic>{'preserve': true},
      );
      expect(field.citation!.properties['futureProperty'], 'keep');
      expect(_propertiesContaining(field, 'Ada').italic, isTrue);
      expect(_propertiesContaining(field, 'Ada').color, '123456');
      expect(
        _propertiesContaining(field, '1843').vertAlign,
        WmlVertAlign.superscript,
      );
    },
  );

  test('viewing mode does not mutate Zotero fields or history', () {
    final controller = _controller(
      document: _twoFields(),
      config: const OfficeSurfaceConfig(mode: OfficeInteractionMode.viewing),
    );
    final before = controller.document.paragraphs.single.text;
    final revision = controller.contentRevision;
    final field = controller.zoteroFields.first;
    controller.insertZoteroCitation(_citation('new', '(New)'));
    controller.updateZoteroCitation(field, _citation('a', '(Updated)'));
    controller.unlinkZoteroField(field);
    controller.insertZoteroBibliography(text: 'References');
    expect(controller.document.paragraphs.single.text, before);
    expect(controller.zoteroFields, hasLength(2));
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
  });

  test(
    'tracked mode never silently bypasses revision history for Zotero edits',
    () {
      final document = _twoFields()..trackRevisions = true;
      document.sections.single.blocks.add(
        WordZotero.bibliography(text: 'References'),
      );
      final controller = _controller(document: document);
      final before = document.paragraphs
          .map((paragraph) => paragraph.text)
          .toList();
      final revision = controller.contentRevision;
      final field = controller.zoteroFields.first;
      expect(
        () => controller.insertZoteroCitation(_citation('new', '(New)')),
        throwsUnsupportedError,
      );
      expect(
        () =>
            controller.updateZoteroCitation(field, _citation('a', '(Changed)')),
        throwsUnsupportedError,
      );
      expect(() => controller.unlinkZoteroField(field), throwsUnsupportedError);
      expect(
        () => controller.refreshZoteroCitations(<String, ZoteroCitation>{
          'a': _citation('a', '(Refreshed)'),
        }),
        throwsUnsupportedError,
      );
      expect(
        () => controller.insertZoteroBibliography(text: 'New references'),
        throwsUnsupportedError,
      );
      expect(
        () => controller.updateZoteroBibliography(
          controller.zoteroFields.last,
          text: 'Updated references',
        ),
        throwsUnsupportedError,
      );
      expect(document.paragraphs.map((paragraph) => paragraph.text), before);
      expect(document.revisions, isEmpty);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
    },
  );

  test('citation insertion cannot enter a bibliography middle paragraph', () {
    final instruction = WordZotero.bibliography(
      text: 'unused',
    ).inlines.whereType<WmlRun>().single.fieldInstruction!;
    final document = WmlDocument(
      sections: <WmlSection>[
        WmlSection(
          blocks: <WmlBlock>[
            WmlParagraph(
              inlines: <WmlInline>[
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
                WmlFieldBoundary(
                  kind: WmlFieldBoundaryKind.instruction,
                  text: instruction,
                ),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
                WmlRun(text: 'First source'),
              ],
            ),
            WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Middle source')]),
            WmlParagraph(
              inlines: <WmlInline>[
                WmlRun(text: 'Last source'),
                WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
              ],
            ),
          ],
        ),
      ],
    );
    final controller = _controller(document: document);
    expect(controller.zoteroFields.single.paragraphs, hasLength(3));
    controller.jumpToParagraph(1);
    controller.caret.logicalIndex = 3;
    controller.caret.collapseSelection();
    final revision = controller.contentRevision;
    expect(
      () => controller.insertZoteroCitation(_citation('nested', '(Nested)')),
      throwsUnsupportedError,
    );
    expect(document.paragraphs.elementAt(1).text, 'Middle source');
    expect(controller.zoteroFields, hasLength(1));
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
  });

  test(
    'pending revisions protect affected paragraphs even when tracking is off',
    () {
      final document = _twoFields();
      final paragraph = document.paragraphs.single;
      final change = WmlRevision(
        id: 1,
        kind: WmlRevisionKind.insert,
        paragraphIndex: 0,
        targetParagraph: paragraph,
        start: 0,
        end: 6,
        text: 'Before',
      );
      document.revisions.add(change);
      final controller = _controller(document: document);
      final before = paragraph.text;
      final revision = controller.contentRevision;
      final field = controller.zoteroFields.first;
      expect(document.trackRevisions, isFalse);
      expect(
        () =>
            controller.updateZoteroCitation(field, _citation('a', '(Changed)')),
        throwsUnsupportedError,
      );
      expect(() => controller.unlinkZoteroField(field), throwsUnsupportedError);
      expect(
        () => controller.insertZoteroCitation(_citation('new', '(New)')),
        throwsUnsupportedError,
      );
      expect(paragraph.text, before);
      expect(document.revisions.single, same(change));
      expect(change.start, 0);
      expect(change.end, 6);
      expect(controller.contentRevision, revision);
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'pending changes in other paragraphs do not block an independent citation edit',
    () {
      final document = _twoFields();
      final other = WmlParagraph(
        inlines: <WmlInline>[WmlRun(text: 'Other change')],
      );
      document.sections.single.blocks.add(other);
      document.revisions.add(
        WmlRevision(
          id: 2,
          kind: WmlRevisionKind.insert,
          paragraphIndex: 1,
          targetParagraph: other,
          start: 0,
          end: 5,
          text: 'Other',
        ),
      );
      final controller = _controller(document: document);
      final field = controller.zoteroFields.first;
      controller.updateZoteroCitation(field, _citation('a', '(Changed)'));
      expect(controller.zoteroFields.first.cachedText, '(Changed)');
      expect(document.revisions.single.targetParagraph, same(other));
      expect(document.revisions.single.end, 5);
      controller.undo();
      expect(controller.zoteroFields.first.cachedText, '(A)');
      expect(document.revisions.single.end, 5);
    },
  );
}
