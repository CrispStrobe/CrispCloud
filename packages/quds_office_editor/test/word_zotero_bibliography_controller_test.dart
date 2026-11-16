import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _id = 'bibliography-controller-test';
const _code =
    'BIBL {"uncited":[],"omitted":[],"custom":[],"future":"keep"} CSL_BIBLIOGRAPHY';
const _html =
    '<div class="csl-bib-body">'
    '<div class="csl-entry">Alpha <i>Book</i>.<br/>Second line.</div>'
    '<div class="csl-entry"><b>Beta</b> Book.</div></div>';
const _text = 'Alpha Book.\nSecond line.\nBeta Book.';

String _prefs() => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'retain-session',
  'style': {
    'styleID': 'http://www.zotero.org/styles/chicago-notes-bibliography',
    'locale': 'de-DE',
    'bibliographyStyleHasBeenSet': true,
    'future': 'retain-style',
  },
  'prefs': {'fieldType': 'Http', 'noteType': 0, 'future': 'retain-prefs'},
});

Object? _invoke(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, [_id, ...arguments]);

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return _invoke(transaction.session, command, arguments);
}

void _stageInsertion(WordZoteroCitingSession session) {
  final inserted = _invoke(session, 'Document.insertField', ['Http', 0]) as Map;
  _invoke(session, 'Document.setBibliographyStyle', [
    -720,
    720,
    480,
    240,
    <int>[720],
    1,
  ]);
  _invoke(session, 'Field.setCode', [inserted['id'], _code]);
  _invoke(session, 'Field.setText', [inserted['id'], _html, true]);
  _invoke(session, 'Document.setDocumentData', [_prefs()]);
}

void _complete(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

WordZoteroTransaction _begin(WordEditorController controller) =>
    controller.beginZoteroTransaction(documentId: _id);

String _fieldId(WordZoteroTransaction transaction, {int index = 0}) =>
    ((_call(transaction, 'Document.getFields', ['Http']) as List)[index]
            as Map)['id']
        as String;

WordEditorController _controller(WmlDocument document) {
  final controller = WordEditorController(document: document);
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return controller;
}

WmlDocument _empty() {
  final document = WmlDocument.empty(text: 'LeftRight');
  document.sections.single.blocks.add(
    WmlParagraph(inlines: [WmlRun(text: 'After bibliography')]),
  );
  return document;
}

WmlDocument _existing() {
  final document = _empty();
  final session = WordZoteroCitingSession(
    document: document,
    documentId: _id,
    insertionParagraph: document.paragraphs.first,
    insertionOffset: 4,
  );
  _stageInsertion(session);
  _invoke(session, 'Document.complete');
  session.prepareReview();
  session.apply();
  return document;
}

List<Object?> _runs(WmlParagraph paragraph) => [
  for (final run in paragraph.inlines.whereType<WmlRun>())
    [
      run.text,
      run.properties.bold,
      run.properties.italic,
      run.properties.smallCaps,
      run.properties.fontSizeHalfPoints,
      run.fieldInstruction,
      run.fieldLocked,
    ],
];

List<Object?> _layout(WmlParagraph paragraph) {
  final props = paragraph.properties;
  return [
    props.styleId,
    props.indent.left,
    props.indent.right,
    props.indent.firstLine,
    props.indent.hanging,
    props.explicitIndent,
    props.lineSpacing,
    props.lineSpacingRule.name,
    props.explicitLineSpacing,
    props.spacingBefore,
    props.spacingAfter,
    props.explicitSpacingBefore,
    props.explicitSpacingAfter,
    for (final tab in props.tabs) tab.position,
  ];
}

String _state(WmlDocument document) => jsonEncode({
  'paragraphs': [
    for (final paragraph in document.paragraphs)
      [
        paragraph.text,
        _layout(paragraph),
        _runs(paragraph),
        for (final inline in paragraph.inlines)
          if (inline is WmlFieldBoundary) [inline.kind.name, inline.text],
      ],
  ],
  'data': WordZoteroDocumentData.read(document),
});

void _expectLayout(WmlZoteroField field, {bool reset = false}) {
  for (final paragraph in field.paragraphs) {
    final props = paragraph.properties;
    expect(props.indent.left, reset ? 0 : 36);
    expect(props.indent.firstLine, 0);
    expect(props.indent.hanging, reset ? 0 : 36);
    expect(props.lineSpacing, reset ? 1 : 2);
    expect(props.lineSpacingRule, WmlLineSpacingRule.auto);
    expect(props.spacingBefore, 0);
    expect(props.spacingAfter, reset ? 0 : 12);
    expect(props.tabs.map((tab) => tab.position), reset ? <int>[] : [36]);
  }
}

void _expectMetadata(WmlDocument document, {String future = 'keep'}) {
  final field = WordZotero.fields(document).single;
  expect(field.metadata!['future'], future);
  final data = jsonDecode(WordZoteroDocumentData.read(document)) as Map;
  expect(data['sessionID'], 'retain-session');
  expect((data['style'] as Map)['locale'], 'de-DE');
  expect((data['style'] as Map)['future'], 'retain-style');
  expect((data['prefs'] as Map)['future'], 'retain-prefs');
  expect((data['prefs'] as Map)['fieldType'], 'Field');
  expect(WordFieldSpans.unbalanced(document), isEmpty);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('entry insertion is staged, saved and undone as one transaction', () {
    final controller = _controller(_empty());
    final document = controller.document;
    final beforeParagraphs = document.paragraphs.toList();
    controller.caret
      ..logicalIndex = 4
      ..collapseSelection();
    final before = _state(document);
    final transaction = _begin(controller);
    _stageInsertion(transaction.session);
    _complete(transaction);
    expect(_state(document), before);
    expect(controller.canUndo, isFalse);
    expect(transaction.session.formattingWarnings, isEmpty);

    transaction.apply();
    final field = controller.zoteroFields.single;
    final entries = field.paragraphs.toList();
    final after = _state(document);
    expect(document.paragraphs.map((p) => p.text), [
      'LeftRight',
      'Alpha Book.\nSecond line.',
      'Beta Book.',
      'After bibliography',
    ]);
    expect(document.paragraphs.first, same(beforeParagraphs.first));
    expect(document.paragraphs.last, same(beforeParagraphs.last));
    expect(field.canEdit, isFalse);
    expect(WordZotero.canReplaceNativeBibliography(document, field), isTrue);
    expect(controller.caret.paragraphIndex, 2);
    expect(controller.caret.logicalIndex, entries.last.text.length);
    expect(controller.caret.isCollapsed, isTrue);
    _expectLayout(field);
    _expectMetadata(document);

    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(WordZotero.fields(reopened).single.cachedText, _text);
    expect(WordZotero.fields(reopened).single.paragraphs, hasLength(2));
    _expectLayout(WordZotero.fields(reopened).single);
    _expectMetadata(reopened);
    expect(
      WordZotero.fields(reopened).single.paragraph.inlines
          .whereType<WmlRun>()
          .any((run) => run.text.trim() == 'Book' && run.properties.italic),
      isTrue,
    );

    controller.undo();
    expect(_state(document), before);
    expect(document.paragraphs.first, same(beforeParagraphs.first));
    expect(document.paragraphs.last, same(beforeParagraphs.last));
    expect(controller.caret.paragraphIndex, 0);
    expect(controller.caret.logicalIndex, 4);
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(_state(document), after);
    expect(
      controller.zoteroFields.single.paragraphs.first,
      same(entries.first),
    );
    expect(controller.zoteroFields.single.paragraphs.last, same(entries.last));
  });

  for (final count in [1, 4]) {
    test('refresh to $count entries preserves range identity and undo', () {
      final controller = _controller(_existing());
      final document = controller.document;
      final before = _state(document);
      final originals = controller.zoteroFields.single.paragraphs.toList();
      final afterParagraph = document.paragraphs.last;
      final transaction = _begin(controller);
      final data =
          jsonDecode(_call(transaction, 'Document.getDocumentData') as String)
              as Map;
      expect((data['style'] as Map)['bibliographyStyleHasBeenSet'], isTrue);
      _call(transaction, 'Field.setText', [
        _fieldId(transaction),
        List.generate(
          count,
          (i) => '<div class="csl-entry">Entry <i>$i</i>.</div>',
        ).join(),
        true,
      ]);
      _complete(transaction);
      expect(_state(document), before);
      transaction.apply();
      final field = controller.zoteroFields.single;
      final updated = field.paragraphs.toList();
      final after = _state(document);
      expect(updated, hasLength(count));
      expect(updated.first, same(originals.first));
      if (count > 1) expect(updated[1], same(originals[1]));
      expect(document.paragraphs.last, same(afterParagraph));
      expect(document.paragraphs.length, count + 2);
      _expectLayout(field);
      _expectMetadata(document);
      controller.undo();
      expect(_state(document), before);
      expect(controller.canUndo, isFalse);
      for (var i = 0; i < originals.length; i++) {
        expect(
          controller.zoteroFields.single.paragraphs[i],
          same(originals[i]),
        );
      }
      controller.redo();
      expect(_state(document), after);
      for (var i = 0; i < updated.length; i++) {
        expect(controller.zoteroFields.single.paragraphs[i], same(updated[i]));
      }
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      final savedField = WordZotero.fields(reopened).single;
      expect(savedField.paragraphs, hasLength(count));
      expect(
        savedField.cachedText,
        List.generate(count, (i) => 'Entry $i.').join('\n'),
      );
      _expectLayout(savedField);
      _expectMetadata(reopened);
    });
  }

  test('style-only reset has one undo and survives a DOCX roundtrip', () {
    final imported = WordDeserializer().readBytes(
      WordSerializer().writeBytes(_existing()),
    );
    final controller = _controller(imported);
    final document = controller.document;
    final before = _state(document);
    final paragraphs = controller.zoteroFields.single.paragraphs.toList();
    final originalRuns = paragraphs.map(_runs).toList();
    final transaction = _begin(controller);
    _call(transaction, 'Document.setBibliographyStyle', [
      0,
      0,
      240,
      0,
      <int>[],
      0,
    ]);
    _complete(transaction);
    expect(transaction.session.hasChanges, isTrue);
    expect(_state(document), before);
    transaction.apply();
    final after = _state(document);
    _expectLayout(controller.zoteroFields.single, reset: true);
    expect(controller.zoteroFields.single.cachedText, _text);
    expect(controller.zoteroFields.single.paragraphs.map(_runs), originalRuns);
    _expectMetadata(document);
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    _expectLayout(WordZotero.fields(reopened).single, reset: true);
    _expectMetadata(reopened);
    controller.undo();
    expect(_state(document), before);
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(_state(document), after);
    for (var i = 0; i < paragraphs.length; i++) {
      expect(controller.zoteroFields.single.paragraphs[i], same(paragraphs[i]));
    }
  });

  test(
    'code-only metadata refresh preserves rich results and entry properties',
    () {
      final controller = _controller(_existing());
      final document = controller.document;
      final before = _state(document);
      final original = controller.zoteroFields.single;
      final paragraphs = original.paragraphs.toList();
      final runs = paragraphs.map(_runs).toList();
      final layouts = paragraphs.map(_layout).toList();
      final transaction = _begin(controller);
      _call(transaction, 'Field.setCode', [
        _fieldId(transaction),
        _code.replaceFirst('"keep"', '"updated"'),
      ]);
      _complete(transaction);
      transaction.apply();
      final after = _state(document);
      final field = controller.zoteroFields.single;
      expect(field.cachedText, _text);
      expect(field.paragraphs.map(_runs), runs);
      expect(field.paragraphs.map(_layout), layouts);
      for (var i = 0; i < paragraphs.length; i++) {
        expect(field.paragraphs[i], same(paragraphs[i]));
      }
      _expectMetadata(document, future: 'updated');
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      _expectMetadata(reopened, future: 'updated');
      expect(WordZotero.fields(reopened).single.cachedText, _text);
      _expectLayout(WordZotero.fields(reopened).single);
      controller.undo();
      expect(_state(document), before);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_state(document), after);
    },
  );

  for (final command in ['Field.delete', 'Field.removeCode']) {
    test(
      '$command preserves neighbors and restores the complete field in one undo',
      () {
        final controller = _controller(_existing());
        final document = controller.document;
        final before = _state(document);
        final original = controller.zoteroFields.single;
        final entries = original.paragraphs.toList();
        final beforeParagraph = document.paragraphs.first;
        final afterParagraph = document.paragraphs.last;
        final transaction = _begin(controller);
        _call(transaction, command, [_fieldId(transaction)]);
        _complete(transaction);
        transaction.apply();
        final after = _state(document);
        expect(controller.zoteroFields, isEmpty);
        expect(document.paragraphs.first, same(beforeParagraph));
        expect(document.paragraphs.last, same(afterParagraph));
        expect(document.paragraphs.elementAt(1), same(entries.first));
        if (command == 'Field.delete') {
          expect(document.paragraphs.map((p) => p.text), [
            'LeftRight',
            '',
            'After bibliography',
          ]);
        } else {
          expect(document.paragraphs.map((p) => p.text), [
            'LeftRight',
            'Alpha Book.\nSecond line.',
            'Beta Book.',
            'After bibliography',
          ]);
          expect(document.paragraphs.elementAt(2), same(entries.last));
          expect(
            entries.first.inlines.whereType<WmlRun>().any(
              (r) => r.properties.italic,
            ),
            isTrue,
          );
        }
        expect(
          document.paragraphs
              .expand((p) => p.inlines)
              .whereType<WmlFieldBoundary>(),
          isEmpty,
        );
        final reopened = WordDeserializer().readBytes(controller.saveBytes());
        expect(WordZotero.fields(reopened), isEmpty);
        expect(
          reopened.paragraphs.map((p) => p.text),
          document.paragraphs.map((p) => p.text),
        );
        controller.undo();
        expect(_state(document), before);
        expect(controller.canUndo, isFalse);
        _expectMetadata(document);
        for (var i = 0; i < entries.length; i++) {
          expect(
            controller.zoteroFields.single.paragraphs[i],
            same(entries[i]),
          );
        }
        controller.redo();
        expect(_state(document), after);
      },
    );
  }

  test('refresh and unlink preserve the replacement as one undo step', () {
    final controller = _controller(_existing());
    final document = controller.document;
    final before = _state(document);
    final entries = controller.zoteroFields.single.paragraphs.toList();
    final afterParagraph = document.paragraphs.last;
    final transaction = _begin(controller);
    final field = _fieldId(transaction);
    _call(transaction, 'Field.setText', [
      field,
      '<div class="csl-entry">New <i>first</i>.</div>'
          '<div class="csl-entry">New second.</div>'
          '<div class="csl-entry">New third.</div>',
      true,
    ]);
    _call(transaction, 'Field.removeCode', [field]);
    _complete(transaction);
    transaction.apply();
    final after = _state(document);
    final newThird = document.paragraphs.elementAt(3);
    expect(controller.zoteroFields, isEmpty);
    expect(document.paragraphs.map((p) => p.text), [
      'LeftRight',
      'New first.',
      'New second.',
      'New third.',
      'After bibliography',
    ]);
    expect(document.paragraphs.elementAt(1), same(entries.first));
    expect(document.paragraphs.elementAt(2), same(entries.last));
    expect(document.paragraphs.last, same(afterParagraph));
    expect(WordFieldSpans.unbalanced(document), isEmpty);
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(WordZotero.fields(reopened), isEmpty);
    expect(
      reopened.paragraphs.map((p) => p.text),
      document.paragraphs.map((p) => p.text),
    );
    expect(
      reopened.paragraphs
          .elementAt(1)
          .inlines
          .whereType<WmlRun>()
          .any((run) => run.text.trim() == 'first' && run.properties.italic),
      isTrue,
    );
    controller.undo();
    expect(_state(document), before);
    expect(controller.canUndo, isFalse);
    _expectMetadata(document);
    controller.redo();
    expect(_state(document), after);
    expect(document.paragraphs.elementAt(3), same(newThird));
  });

  test(
    'typing at the insertion caret stays outside the bibliography field',
    () {
      final controller = _controller(_empty());
      final insertion = _begin(controller);
      _stageInsertion(insertion.session);
      _complete(insertion);
      insertion.apply();
      final inserted = _state(controller.document);
      final original = controller.zoteroFields.single;
      final last = original.paragraphs.last;
      expect(controller.caret.paragraphIndex, 2);
      expect(controller.caret.logicalIndex, last.text.length);
      controller.insertText(' Outside field.');
      final typed = _state(controller.document);
      final field = controller.zoteroFields.single;
      expect(field.cachedText, _text);
      expect(last.text, 'Beta Book. Outside field.');
      expect(last.inlines.last, isA<WmlRun>());
      expect(WordFieldSpans.unbalanced(controller.document), isEmpty);
      expect(
        WordZotero.canReplaceNativeBibliography(controller.document, field),
        isFalse,
      );
      expect(() => _begin(controller), throwsUnsupportedError);
      expect(_state(controller.document), typed);
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      expect(WordZotero.fields(reopened).single.cachedText, _text);
      expect(
        reopened.paragraphs.elementAt(2).text,
        'Beta Book. Outside field.',
      );
      expect(WordFieldSpans.unbalanced(reopened), isEmpty);
      controller.undo();
      expect(_state(controller.document), inserted);
      final refresh = _begin(controller);
      _complete(refresh);
      refresh.apply();
      expect(_state(controller.document), inserted);
      controller.redo();
      expect(_state(controller.document), typed);
    },
  );

  for (final change in ['caret', 'revision', 'field range']) {
    test(
      '$change invalidates a pending bibliography refresh without mutation',
      () {
        final controller = _controller(_existing());
        final document = controller.document;
        final transaction = _begin(controller);
        _call(transaction, 'Field.setText', [
          _fieldId(transaction),
          '<div class="csl-entry">Never applied.</div>',
          true,
        ]);
        _complete(transaction);
        switch (change) {
          case 'caret':
            controller.caret.logicalIndex = 1;
          case 'revision':
            controller.insertText('User edit. ');
          case 'field range':
            document.sections.single.blocks.insert(
              2,
              WmlParagraph(inlines: [WmlRun(text: 'Inserted later')]),
            );
        }
        final current = _state(document);
        final revision = controller.contentRevision;
        final hadUndo = controller.canUndo;
        expect(() => transaction.apply(), throwsStateError);
        expect(_state(document), current);
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, hadUndo);
        expect(WordFieldSpans.unbalanced(document), isEmpty);
      },
    );
  }

  test('late bibliography refusal rolls back a preceding citation update', () {
    final document = _existing();
    final citationParagraph = document.paragraphs.last;
    final citation = ZoteroCitation(
      citationId: 'persistent-citation',
      plainCitation: '(Original)',
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {'id': 'source', 'type': 'book', 'title': 'Catalog source'},
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
          locator: '34',
          label: 'page',
        ),
      ],
    );
    WordZotero.insertCitation(citationParagraph, citation);
    final controller = _controller(document);
    final before = _state(document);
    final revision = controller.contentRevision;
    final originalParagraphs = document.paragraphs.toList();
    final transaction = _begin(controller);
    _call(transaction, 'Field.setText', [
      _fieldId(transaction),
      List.filled(10001, 'Entry').join('\n'),
      false,
    ]);
    _call(transaction, 'Field.setText', [
      _fieldId(transaction, index: 1),
      'Applied before the bibliography fails',
      false,
    ]);
    _call(transaction, 'Document.setDocumentData', [
      _prefs().replaceFirst('de-DE', 'en-US'),
    ]);
    _complete(transaction);
    expect(() => transaction.apply(), throwsFormatException);
    expect(_state(document), before);
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
    expect(controller.isDirty, isFalse);
    for (var i = 0; i < originalParagraphs.length; i++) {
      expect(document.paragraphs.elementAt(i), same(originalParagraphs[i]));
    }
    final saved = WordDeserializer().readBytes(controller.saveBytes());
    final savedCitation = WordZotero.fields(saved).last.citation!;
    expect(savedCitation.citationId, 'persistent-citation');
    expect(savedCitation.items.single.uris, [
      'http://zotero.org/users/42/items/ABCD1234',
    ]);
    expect(savedCitation.items.single.locator, '34');
    expect(WordZotero.fields(saved).first.cachedText, _text);
    expect(WordFieldSpans.unbalanced(saved), isEmpty);
  });
}
