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
