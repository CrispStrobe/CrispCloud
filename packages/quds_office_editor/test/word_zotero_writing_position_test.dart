import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _documentId = 'zotero-writing-position';

ZoteroCitation _citation(String id, String text, {int noteIndex = 0}) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: text,
      noteIndex: noteIndex,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
        ),
      ],
    );

WordEditorController _controller(WmlDocument document) {
  final controller = WordEditorController(document: document);
  addTearDown(controller.dispose);
  return controller;
}

WmlDocument _inlineDocument() {
  final document = WmlDocument.empty(text: 'Before ');
  final paragraph = document.paragraphs.single;
  WordZotero.insertCitation(paragraph, _citation('a', '(A)'));
  paragraph.inlines.add(WmlRun(text: ' between '));
  WordZotero.insertCitation(paragraph, _citation('b', '(Babbage, 1843)'));
  paragraph.inlines.add(WmlRun(text: ' after'));
  return document;
}

Object? _invoke(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, [_documentId, ...arguments]);

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return _invoke(transaction.session, command, arguments);
}

WordZoteroTransaction _begin(WordEditorController controller) =>
    controller.beginZoteroTransaction(
      documentId: _documentId,
      command: ZoteroCitingCommand.refresh,
    );

List<String> _fieldIds(WordZoteroTransaction transaction) =>
    (_call(transaction, 'Document.getFields', ['Http']) as List<Object?>)
        .map((field) => (field as Map<String, Object?>)['id'] as String)
        .toList();

void _replace(
  WordZoteroTransaction transaction,
  String field,
  ZoteroCitation citation,
) {
  _call(transaction, 'Field.setCode', [
    field,
    'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
  ]);
  _call(transaction, 'Field.setText', [field, citation.plainCitation, false]);
}

void _apply(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
  transaction.apply();
}

List<int> _selection(WordEditorController controller) => [
  controller.caret.paragraphIndex,
  controller.caret.logicalIndex,
  controller.caret.selectionAnchorParagraph,
  controller.caret.selectionAnchor,
];

String _bibliographyHtml(int count) => List.generate(
  count,
  (index) => '<div class="csl-entry">Reference $index.</div>',
).join();

WmlDocument _bibliographyDocument() {
  final document = WmlDocument.empty(text: 'Introduction');
  document.sections.single.blocks.add(
    WmlParagraph(inlines: [WmlRun(text: 'Continue writing here')]),
  );
  final session = WordZoteroCitingSession(
    document: document,
    documentId: _documentId,
    insertionParagraph: document.paragraphs.first,
    insertionOffset: document.paragraphs.first.text.length,
  );
  final field =
      _invoke(session, 'Document.insertField', ['Http', 0])
          as Map<String, Object?>;
  _invoke(session, 'Field.setCode', [
    field['id'],
    'BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY',
  ]);
  _invoke(session, 'Field.setText', [field['id'], _bibliographyHtml(2), true]);
  _invoke(session, 'Document.complete');
  session.prepareReview();
  session.apply();
  return document;
}

({WmlDocument document, WmlNote note}) _authoredNote(bool endnote) {
  final paragraph = WmlParagraph(
    inlines: [
      WmlNoteMarker(
        endnote: endnote,
        properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
      ),
      WmlRun(text: ' Note '),
    ],
  );
  WordZotero.insertCitation(paragraph, _citation('a', '(A)', noteIndex: 1));
  paragraph.inlines.add(WmlRun(text: ' tail'));
  final note = WmlNote(
    id: 1,
    endnote: endnote,
    addReference: true,
    addReferenceSpace: true,
    paragraphs: [
      paragraph,
      WmlParagraph(inlines: [WmlRun(text: 'Later note prose')]),
    ],
  );
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          WmlParagraph(
            inlines: [
              WmlRun(text: 'Body '),
              WmlRun(text: '1', noteRefId: 1, noteRefEndnote: endnote),
              WmlRun(text: ' tail'),
            ],
          ),
        ],
      ),
    ],
    footnotes: endnote ? [] : [note],
    endnotes: endnote ? [note] : [],
  );
  return (document: document, note: note);
}

WmlDocument _soleNoteDocument(bool endnote) {
  final document = WmlDocument.empty(text: 'Before ');
  final paragraph = document.paragraphs.single;
  WordZotero.insertCitation(paragraph, _citation('a', '(A)'));
  paragraph.inlines.add(WmlRun(text: ' after'));
  final session = WordZoteroCitingSession(
    document: document,
    documentId: _documentId,
  );
  final field =
      (_invoke(session, 'Document.getFields', ['Http']) as List<Object?>).single
          as Map<String, Object?>;
  _invoke(session, 'Document.convert', [
    [field['id']],
    'Http',
    [endnote ? 2 : 1],
  ]);
  _invoke(session, 'Document.complete');
  session.prepareReview();
  session.apply();
  return document;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in ['frame', 'toc-title', 'toc-item']) {
    test(
      'bibliography growth preserves passive $kind selection and history',
      () {
        final document = _bibliographyDocument();
        final paragraph = WmlParagraph(
          inlines: [WmlRun(text: 'Passive paragraph')],
        );
        if (kind == 'toc-item') {
          paragraph.properties.headingLevel = 1;
          document.sections.single.blocks.add(paragraph);
        }
        final WmlBlock owner = switch (kind) {
          'frame' => WmlFrame(blocks: [paragraph]),
          'toc-title' => WmlToc(titleParagraph: paragraph),
          _ => WmlToc(),
        };
        document.sections.single.blocks.add(owner);
        final controller = _controller(document);
        final target = kind == 'toc-item'
            ? (owner as WmlToc).itemParagraphs.single
            : paragraph;
        final originalText = target.text;
        final originalIndex = document.paragraphs.toList().indexOf(target);
        expect(originalIndex, greaterThanOrEqualTo(0));
        controller.caret
          ..paragraphIndex = originalIndex
          ..logicalIndex = 3
          ..selectionAnchorParagraph = originalIndex
          ..selectionAnchor = 10;
        final transaction = _begin(controller);
        _call(transaction, 'Field.setText', [
          _fieldIds(transaction).single,
          _bibliographyHtml(4),
          true,
        ]);
        _apply(transaction);

        final updatedIndex = document.paragraphs.toList().indexOf(target);
        expect(updatedIndex, originalIndex + 2);
        expect(_selection(controller), [updatedIndex, 3, updatedIndex, 10]);
        expect(target.text, originalText);
        controller.undo();
        expect(_selection(controller), [originalIndex, 3, originalIndex, 10]);
        controller.redo();
        expect(_selection(controller), [updatedIndex, 3, updatedIndex, 10]);
        expect(target.text, originalText);
      },
    );
  }

  test(
    'refresh keeps typing in prose after expanded and shortened citations',
    () {
      final controller = _controller(_inlineDocument());
      final paragraph = controller.document.paragraphs.single;
      controller.caret
        ..logicalIndex = paragraph.text.indexOf(' after') + 3
        ..collapseSelection();
      final transaction = _begin(controller);
      final fields = _fieldIds(transaction);
      _replace(
        transaction,
        fields[0],
        _citation('a', '(A considerably longer cite)'),
      );
      _replace(transaction, fields[1], _citation('b', 'B'));
      _apply(transaction);

      expect(
        controller.caret.logicalIndex,
        paragraph.text.indexOf(' after') + 3,
      );
      expect(controller.caret.isCollapsed, isTrue);
      controller.insertText('X');
      expect(
        paragraph.text,
        'Before (A considerably longer cite) between B afXter',
      );
      expect(controller.zoteroFields.last.cachedText, 'B');
    },
  );

  test('refresh keeps prose position when a preceding citation is deleted', () {
    final controller = _controller(_inlineDocument());
    final paragraph = controller.document.paragraphs.single;
    controller.caret
      ..logicalIndex = paragraph.text.indexOf(' after') + 2
      ..collapseSelection();
    final transaction = _begin(controller);
    final fields = _fieldIds(transaction);
    _replace(transaction, fields[0], _citation('a', '(A longer cite)'));
    _call(transaction, 'Field.delete', [fields[1]]);
    _apply(transaction);

    expect(paragraph.text, 'Before (A longer cite) between  after');
    expect(controller.caret.logicalIndex, paragraph.text.indexOf(' after') + 2);
    controller.insertText('X');
    expect(paragraph.text, 'Before (A longer cite) between  aXfter');
  });

  for (final position in [
    (name: 'before the citation', offset: 3, expected: 3),
    (name: 'at its start', offset: 7, expected: 7),
    (name: 'inside its replaced text', offset: 8, expected: 22),
    (name: 'at its end', offset: 10, expected: 22),
    (name: 'in following prose', offset: 13, expected: 25),
  ]) {
    test('refresh maps a writing point ${position.name}', () {
      final controller = _controller(_inlineDocument());
      controller.caret
        ..logicalIndex = position.offset
        ..collapseSelection();
      final transaction = _begin(controller);
      _replace(
        transaction,
        _fieldIds(transaction).first,
        _citation('a', '(Expanded cite)'),
      );
      _apply(transaction);

      expect(controller.caret.logicalIndex, position.expected);
      expect(controller.caret.isCollapsed, isTrue);
      controller.undo();
      expect(_selection(controller), [0, position.offset, 0, position.offset]);
      controller.redo();
      expect(_selection(controller), [
        0,
        position.expected,
        0,
        position.expected,
      ]);
    });
  }

  for (final backward in [false, true]) {
    test(
      'refresh retains ${backward ? 'backward' : 'forward'} selection and exact history',
      () {
        final controller = _controller(_inlineDocument());
        final paragraph = controller.document.paragraphs.single;
        final trailing = paragraph.text.indexOf(' after') + 3;
        controller.caret
          ..logicalIndex = backward ? 2 : trailing
          ..selectionAnchor = backward ? trailing : 2
          ..selectionAnchorParagraph = 0;
        final before = _selection(controller);
        final originalText = paragraph.text;
        final transaction = _begin(controller);
        final fields = _fieldIds(transaction);
        _replace(transaction, fields[0], _citation('a', '(Expanded cite)'));
        _replace(transaction, fields[1], _citation('b', 'B'));
        _apply(transaction);

        final mappedTrailing = paragraph.text.indexOf(' after') + 3;
        final expected = [
          0,
          backward ? 2 : mappedTrailing,
          0,
          backward ? mappedTrailing : 2,
        ];
        expect(_selection(controller), expected);
        expect(controller.caret.isCollapsed, isFalse);
        final refreshedText = paragraph.text;
        for (var cycle = 0; cycle < 2; cycle++) {
          controller.undo();
          expect(paragraph.text, originalText);
          expect(_selection(controller), before);
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(paragraph.text, refreshedText);
          expect(_selection(controller), expected);
        }
      },
    );
  }

  test(
    'code-only refresh preserves a selection inside unchanged citation text',
    () {
      final controller = _controller(_inlineDocument());
      controller.caret
        ..logicalIndex = 8
        ..selectionAnchor = 9
        ..selectionAnchorParagraph = 0;
      final originalSelection = _selection(controller);
      final originalText = controller.document.paragraphs.single.text;
      final transaction = _begin(controller);
      final citation = <String, Object?>{..._citation('a', '(A)').toJson()};
      citation['properties'] = {
        ...(citation['properties'] as Map<String, Object?>),
        'custom': 'Preserved display',
      };
      _call(transaction, 'Field.setCode', [
        _fieldIds(transaction).first,
        'ITEM CSL_CITATION ${jsonEncode(citation)}',
      ]);
      _apply(transaction);

      expect(controller.document.paragraphs.single.text, originalText);
      expect(_selection(controller), originalSelection);
      controller.undo();
      expect(_selection(controller), originalSelection);
      controller.redo();
      expect(_selection(controller), originalSelection);
    },
  );

  for (final count in [1, 4]) {
    test(
      'bibliography refresh to $count entries preserves the writing paragraph',
      () {
        final controller = _controller(_bibliographyDocument());
        final paragraph = controller.document.paragraphs.last;
        final originalIndex = controller.document.paragraphs.length - 1;
        controller.caret
          ..paragraphIndex = originalIndex
          ..logicalIndex = 9
          ..collapseSelection();
        final transaction = _begin(controller);
        _call(transaction, 'Field.setText', [
          _fieldIds(transaction).single,
          _bibliographyHtml(count),
          true,
        ]);
        _apply(transaction);

        expect(
          controller.document.paragraphs.elementAt(
            controller.caret.paragraphIndex,
          ),
          same(paragraph),
        );
        expect(controller.caret.logicalIndex, 9);
        expect(controller.caret.isCollapsed, isTrue);
        controller.undo();
        expect(_selection(controller), [originalIndex, 9, originalIndex, 9]);
        controller.redo();
        expect(_selection(controller), [count + 1, 9, count + 1, 9]);
        controller.insertText('X');
        expect(paragraph.text, 'Continue Xwriting here');
      },
    );
  }

  test(
    'bibliography reflow retains both ends of a backward paragraph selection',
    () {
      final controller = _controller(_bibliographyDocument());
      final first = controller.document.paragraphs.first;
      final last = controller.document.paragraphs.last;
      controller.caret
        ..paragraphIndex = 0
        ..logicalIndex = 2
        ..selectionAnchorParagraph = 3
        ..selectionAnchor = 9;
      final before = _selection(controller);
      final transaction = _begin(controller);
      _call(transaction, 'Field.setText', [
        _fieldIds(transaction).single,
        _bibliographyHtml(4),
        true,
      ]);
      _apply(transaction);

      expect(_selection(controller), [0, 2, 5, 9]);
      expect(
        controller.document.paragraphs.elementAt(
          controller.caret.paragraphIndex,
        ),
        same(first),
      );
      expect(
        controller.document.paragraphs.elementAt(
          controller.caret.selectionAnchorParagraph,
        ),
        same(last),
      );
      controller.undo();
      expect(_selection(controller), before);
      controller.redo();
      expect(_selection(controller), [0, 2, 5, 9]);
    },
  );

  for (final endnote in [false, true]) {
    final kind = endnote ? 'endnote' : 'footnote';

    for (final selected in [false, true]) {
      test(
        '$kind refresh preserves ${selected ? 'backward selection' : 'writing point'} across note paragraphs',
        () {
          final (:document, :note) = _authoredNote(endnote);
          final controller = _controller(document);
          controller.caret
            ..logicalIndex = 2
            ..collapseSelection();
          final originalText = controller.noteEditText(note);
          final trailing = originalText.indexOf(' prose') + 3;
          final before = TextSelection(
            baseOffset: trailing,
            extentOffset: selected ? 2 : trailing,
            affinity: TextAffinity.upstream,
            isDirectional: selected,
          );
          controller.setNoteEditingTarget(note, before);
          final secondParagraph = note.paragraphs.last;
          final transaction = _begin(controller);
          _replace(
            transaction,
            _fieldIds(transaction).single,
            _citation('a', '(Expanded note citation)', noteIndex: 1),
          );
          _apply(transaction);

          final mappedTrailing =
              controller.noteEditText(note).indexOf(' prose') + 3;
          final expected = before.copyWith(
            baseOffset: mappedTrailing,
            extentOffset: selected ? 2 : mappedTrailing,
          );
          expect(controller.noteEditingTarget?.note, same(note));
          expect(controller.noteEditingTarget?.selection, expected);
          expect(note.paragraphs.last, same(secondParagraph));
          expect(_selection(controller), [0, 2, 0, 2]);
          controller.undo();
          expect(controller.noteEditText(note), originalText);
          expect(controller.noteEditingTarget?.selection, before);
          controller.redo();
          expect(controller.noteEditingTarget?.note, same(note));
          expect(controller.noteEditingTarget?.selection, expected);
          expect(_selection(controller), [0, 2, 0, 2]);
        },
      );
    }

    test(
      'inline-to-$kind conversion keeps the writing point beside its body marker',
      () {
        final controller = _controller(_inlineDocument());
        final paragraph = controller.document.paragraphs.single;
        controller.caret
          ..logicalIndex = 8
          ..collapseSelection();
        final before = _selection(controller);
        final transaction = _begin(controller);
        _call(transaction, 'Document.convert', [
          [_fieldIds(transaction).first],
          'Http',
          [endnote ? 2 : 1],
        ]);
        _apply(transaction);

        final afterMarker = paragraph.text.indexOf(' between ');
        expect(_selection(controller), [0, afterMarker, 0, afterMarker]);
        expect(controller.noteEditingTarget, isNull);
        expect(
          endnote
              ? controller.document.endnotes
              : controller.document.footnotes,
          hasLength(1),
        );
        controller.undo();
        expect(_selection(controller), before);
        controller.redo();
        expect(_selection(controller), [0, afterMarker, 0, afterMarker]);
        expect(controller.noteEditingTarget, isNull);
      },
    );

    test(
      '$kind-to-inline conversion returns a removed-note writing point to the citation',
      () {
        final controller = _controller(_soleNoteDocument(endnote));
        final note =
            (endnote
                    ? controller.document.endnotes
                    : controller.document.footnotes)
                .single;
        controller.caret
          ..logicalIndex = 2
          ..collapseSelection();
        final before = TextSelection.collapsed(
          offset: controller.noteEditText(note).length,
        );
        controller.setNoteEditingTarget(note, before);
        final transaction = _begin(controller);
        final field = _fieldIds(transaction).single;
        _call(transaction, 'Document.convert', [
          [field],
          'Http',
          [0],
        ]);
        _replace(
          transaction,
          field,
          _citation('a', '(Expanded inline citation)'),
        );
        _apply(transaction);

        final paragraph = controller.document.paragraphs.single;
        final afterCitation = paragraph.text.indexOf(' after');
        expect(paragraph.text, 'Before (Expanded inline citation) after');
        expect(controller.noteEditingTarget, isNull);
        expect(_selection(controller), [0, afterCitation, 0, afterCitation]);
        expect(
          endnote
              ? controller.document.endnotes
              : controller.document.footnotes,
          isEmpty,
        );
        controller.undo();
        expect(controller.noteEditingTarget?.note, same(note));
        expect(controller.noteEditingTarget?.selection, before);
        expect(_selection(controller), [0, 2, 0, 2]);
        controller.redo();
        expect(controller.noteEditingTarget, isNull);
        expect(_selection(controller), [0, afterCitation, 0, afterCitation]);
      },
    );
  }
}
