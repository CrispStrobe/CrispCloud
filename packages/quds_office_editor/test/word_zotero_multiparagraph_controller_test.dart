import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _id = 'multiparagraph-research';
const _placeholder = '<a href="https://www.zotero.org/?FIRST1">(old)</a>';
const _citationText = '(Ada, 1843)';
const _html = '<p>Quote $_placeholder</p><p>Continuation</p>';

typedef _Target = ({
  WordEditorController controller,
  WmlNote? note,
  List<WmlParagraph> originals,
});

_Target _target(
  int noteType, {
  bool reverse = false,
  bool emptyMiddle = false,
}) {
  final paragraphs = [
    WmlParagraph(
      properties: WmlParagraphProps(styleId: 'Normal', spacingAfter: 6),
      inlines: [
        if (noteType != 0)
          WmlNoteMarker(
            endnote: noteType == 2,
            properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
          ),
        WmlRun(
          text: '${noteType == 0 ? '' : ' '}Before ',
          properties: WmlRunProps(bold: true),
        ),
        WmlRun(text: 'chosen-first'),
      ],
    ),
    WmlParagraph(inlines: [WmlRun(text: emptyMiddle ? '' : 'Selected middle')]),
    WmlParagraph(
      inlines: [
        WmlRun(text: 'chosen-last'),
        WmlRun(
          text: ' After',
          properties: WmlRunProps(italic: true),
          hyperlink: const WmlHyperlink(url: 'https://example.org/preserved'),
        ),
      ],
    ),
    WmlParagraph(inlines: [WmlRun(text: 'Unrelated')]),
  ];
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: noteType == 0
            ? <WmlBlock>[...paragraphs]
            : [
                WmlParagraph(inlines: [WmlRun(text: 'Body anchor')]),
              ],
      ),
    ],
  );
  final note = noteType == 0
      ? null
      : WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: noteType == 2,
        );
  note?.blocks
    ?..clear()
    ..addAll(paragraphs);
  final controller = WordEditorController(document: document);
  controller.proofing.enabled = false;
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  final target = (controller: controller, note: note, originals: paragraphs);
  _select(target, reverse: reverse);
  return target;
}

void _select(_Target target, {bool reverse = false}) {
  final controller = target.controller;
  final note = target.note;
  if (note != null) {
    final text = controller.noteEditText(note);
    final end = text.indexOf('chosen-last') + 'chosen-last'.length;
    controller.setNoteEditingTarget(
      note,
      TextSelection(
        baseOffset: reverse ? end : 7,
        extentOffset: reverse ? 7 : end,
      ),
    );
    return;
  }
  final paragraphs = controller.document.paragraphs.toList();
  final start = paragraphs.indexOf(target.originals.first);
  final end = paragraphs.indexOf(target.originals[2]);
  controller.caret
    ..paragraphIndex = reverse ? start : end
    ..logicalIndex = reverse ? 7 : 11
    ..selectionAnchorParagraph = reverse ? end : start
    ..selectionAnchor = reverse ? 11 : 7;
}

List<WmlBlock> _blocks(_Target target) =>
    target.note?.blocks ?? target.controller.document.sections.single.blocks;

String _visible(_Target target) => target.note == null
    ? target.controller.document.paragraphs.map((p) => p.text).join('\n')
    : target.controller.noteEditText(target.note!);

Object _selection(WordEditorController controller) => (
  paragraph: controller.caret.paragraphIndex,
  offset: controller.caret.logicalIndex,
  anchorParagraph: controller.caret.selectionAnchorParagraph,
  anchor: controller.caret.selectionAnchor,
  note: controller.noteEditingTarget,
);

Object _block(WmlBlock block) {
  if (block is WmlTable) {
    return [
      'table',
      block.grid,
      for (final row in block.rows)
        [
          row.height,
          row.cantSplit,
          for (final cell in row.cells)
            [
              cell.gridSpan,
              cell.vMerge.name,
              cell.width,
              cell.fillColor,
              for (final child in cell.blocks) _block(child),
            ],
        ],
    ];
  }
  if (block is WmlFrame) {
    return ['frame', for (final child in block.blocks) _block(child)];
  }
  if (block is WmlContentControlBlock) {
    return ['control', for (final child in block.blocks) _block(child)];
  }
  final paragraph = block as WmlParagraph;
  return [
    paragraph.text,
    paragraph.properties.styleId,
    paragraph.properties.spacingAfter,
    paragraph.properties.numId,
    paragraph.properties.listLabel,
    for (final inline in paragraph.inlines)
      if (inline is WmlRun)
        [
          inline.text,
          inline.properties.bold,
          inline.properties.italic,
          inline.hyperlink?.url,
          inline.fieldInstruction,
          inline.noteRefId,
          inline.commentIds,
        ]
      else if (inline is WmlNoteMarker)
        ['note-marker', inline.endnote]
      else if (inline is WmlBookmarkBoundary)
        ['bookmark', inline.id, inline.isStart]
      else if (inline is WmlFieldBoundary)
        ['field', inline.kind.name, inline.text]
      else
        inline.runtimeType.toString(),
  ];
}

String _state(WmlDocument document) => jsonEncode({
  'body': [
    for (final section in document.sections)
      [for (final block in section.blocks) _block(block)],
  ],
  'notes': [
    for (final note in [...document.footnotes, ...document.endnotes])
      [note.id, note.endnote, for (final block in note.blocks) _block(block)],
  ],
  'preferences': WordZoteroDocumentData.read(document),
});

String _preferences(int noteType) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'multiparagraph-research-session',
  'style': {'styleID': 'http://www.zotero.org/styles/apa', 'locale': 'en-US'},
  'prefs': {'fieldType': 'Http', 'noteType': noteType},
});

ZoteroCitation _citation({int noteIndex = 0, String id = 'research-source'}) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: _citationText,
      noteIndex: noteIndex,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {
            'id': 'ada-source',
            'type': 'book',
            'title': 'Research source',
          },
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
          locator: '4',
          label: 'page',
        ),
      ],
    );

WordZoteroTransaction _begin(
  _Target target, [
  ZoteroCitingCommand command = ZoteroCitingCommand.addNote,
]) =>
    target.controller.beginZoteroTransaction(documentId: _id, command: command);

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_id, ...arguments]);
}

void _stage(
  WordZoteroTransaction transaction,
  int noteType, {
  String html = _html,
}) {
  _call(transaction, 'Document.setDocumentData', [_preferences(noteType)]);
  final temporary =
      _call(transaction, 'Document.insertField', ['Http', noteType])!
          as Map<String, Object>;
  _call(transaction, 'Field.delete', [temporary['id']]);
  _call(transaction, 'Document.insertText', [html]);
  if (html.contains('FIRST1')) {
    // The actual Zotero integration caller sends placeholder IDs, note type,
    // and field type; HTTP wrapper parameter names are not its wire contract.
    final fields =
        (_call(transaction, 'Document.convertPlaceholdersToFields', [
                  ['FIRST1'],
                  noteType,
                  'Http',
                ])!
                as List<Object?>)
            .cast<Map<String, Object>>();
    final field = fields.single;
    _call(transaction, 'Field.setCode', [
      field['id'],
      'ITEM CSL_CITATION ${jsonEncode(_citation(noteIndex: field['noteIndex']! as int).toJson())}',
    ]);
    _call(transaction, 'Field.setText', [
      field['id'],
      '<i>$_citationText</i>',
      true,
    ]);
  }
}

void _complete(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

WmlTable _table(List<WmlBlock> blocks) => WmlTable(
  rows: [
    WmlTableRow(
      cells: [
        WmlTableCell(blocks: <WmlBlock>[...blocks]),
      ],
    ),
  ],
);

typedef _CellTarget = ({
  _Target target,
  WmlTable table,
  WmlTable rootTable,
  WmlTableCell cell,
  WmlTableCell neighbor,
});

_CellTarget _cellTarget({String shape = 'plain', bool reverse = false}) {
  final target = _target(0);
  final merged = shape == 'merged';
  final cell = WmlTableCell(
    blocks: <WmlBlock>[...target.originals],
    gridSpan: merged ? 2 : 1,
    vMerge: merged ? WmlVMerge.restart : WmlVMerge.none,
    width: 240,
    fillColor: 'EEF2F7',
  );
  final neighbor = WmlTableCell(
    blocks: [
      WmlParagraph(inlines: [WmlRun(text: 'Neighbor')]),
    ],
    width: 120,
  );
  final table = WmlTable(
    grid: merged ? [120, 120, 120] : [240, 120],
    rows: [
      WmlTableRow(cells: [cell, neighbor]),
      if (merged)
        WmlTableRow(
          cells: [
            WmlTableCell(
              gridSpan: 2,
              vMerge: WmlVMerge.cont,
              width: 240,
              blocks: [WmlParagraph()],
            ),
            WmlTableCell(
              width: 120,
              blocks: [
                WmlParagraph(inlines: [WmlRun(text: 'Lower neighbor')]),
              ],
            ),
          ],
        ),
    ],
  );
  final rootTable = shape == 'nested'
      ? _table([
          WmlParagraph(inlines: [WmlRun(text: 'Outer before')]),
          table,
          WmlParagraph(inlines: [WmlRun(text: 'Outer after')]),
        ])
      : table;
  target.controller.document.sections.single.blocks
    ..clear()
    ..addAll([
      WmlParagraph(inlines: [WmlRun(text: 'Outside before')]),
      rootTable,
      WmlParagraph(inlines: [WmlRun(text: 'Outside after')]),
    ]);
  _select(target, reverse: reverse);
  return (
    target: target,
    table: table,
    rootTable: rootTable,
    cell: cell,
    neighbor: neighbor,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final command in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    for (final noteType in [0, 1, 2]) {
      final story = ['body', 'footnote', 'endnote'][noteType];
      for (final reverse in [false, true]) {
        test(
          '${command.name} replaces $story paragraphs with ${reverse ? 'backward' : 'forward'} selection history',
          () {
            final target = _target(noteType, reverse: reverse);
            final controller = target.controller;
            final document = controller.document;
            final before = _state(document);
            final beforeSelection = _selection(controller);
            final transaction = _begin(target, command);
            expect(
              transaction.session.insertionParagraph,
              same(target.originals.first),
            );
            expect(
              transaction.session.insertionEndParagraph,
              same(target.originals[2]),
            );
            expect(transaction.session.insertionOffset, noteType == 0 ? 7 : 8);
            expect(transaction.session.insertionEndOffset, 11);
            _stage(transaction, noteType);
            _complete(transaction);
            expect(_state(document), before);
            transaction.apply();
            expect(
              _visible(target),
              'Before Quote $_citationText\nContinuation After\nUnrelated',
            );
            expect(_blocks(target).first, same(target.originals.first));
            expect(_blocks(target).last, same(target.originals.last));
            expect(_blocks(target), isNot(contains(same(target.originals[1]))));
            expect(_blocks(target), isNot(contains(same(target.originals[2]))));
            final runs = WordTree.paragraphs(
              _blocks(target),
            ).expand((p) => p.inlines.whereType<WmlRun>()).toList();
            expect(
              runs
                  .firstWhere((r) => r.text.endsWith('Before '))
                  .properties
                  .bold,
              isTrue,
            );
            final suffix = runs.firstWhere((r) => r.text == ' After');
            expect(suffix.properties.italic, isTrue);
            expect(suffix.hyperlink?.url, 'https://example.org/preserved');
            expect(controller.zoteroFields.single.cachedText, _citationText);
            expect(
              controller.zoteroFields.single.citation!.items.single.locator,
              '4',
            );
            if (target.note case final note?) {
              expect(controller.noteEditingTarget?.note, same(note));
              expect(
                controller.noteEditingTarget?.selection,
                TextSelection.collapsed(
                  offset: 'Before Quote $_citationText\nContinuation'.length,
                ),
              );
              expect(
                note.allParagraphs.first.inlines.whereType<WmlNoteMarker>(),
                hasLength(1),
              );
              expect(document.footnotes, hasLength(noteType == 1 ? 1 : 0));
              expect(document.endnotes, hasLength(noteType == 2 ? 1 : 0));
            } else {
              expect(controller.caret.paragraphIndex, 1);
              expect(controller.caret.logicalIndex, 'Continuation'.length);
              expect(controller.caret.isCollapsed, isTrue);
            }
            final after = _state(document);
            final afterSelection = _selection(controller);
            controller.undo();
            expect(_state(document), before);
            expect(_selection(controller), beforeSelection);
            expect(_blocks(target), orderedEquals(target.originals));
            expect(controller.canUndo, isFalse);
            controller.redo();
            expect(_state(document), after);
            expect(_selection(controller), afterSelection);
            final reopened = WordDeserializer().readBytes(
              WordSerializer().writeBytes(document),
            );
            final reopenedText = noteType == 0
                ? reopened.paragraphs.map((p) => p.text).join('\n')
                : WordNotes.editableText(
                    (noteType == 1 ? reopened.footnotes : reopened.endnotes)
                        .single,
                  );
            expect(reopenedText, _visible(target));
            expect(
              WordZotero.fields(reopened).single.cachedText,
              _citationText,
            );
            expect(WordFieldSpans.unbalanced(reopened), isEmpty);
          },
        );
      }
    }
  }

  for (final noteType in [0, 1, 2]) {
    final story = ['body', 'footnote', 'endnote'][noteType];
    test(
      '$story paragraph-separator endpoints map to their native boundaries',
      () {
        final target = _target(noteType);
        final controller = target.controller;
        final first = target.originals.first;
        final before = _state(controller.document);
        if (target.note case final note?) {
          final firstLength = first.text.length - 1;
          controller.setNoteEditingTarget(
            note,
            TextSelection(
              baseOffset: firstLength,
              extentOffset:
                  firstLength + 1 + target.originals[1].text.length + 1,
            ),
          );
        } else {
          controller.caret
            ..paragraphIndex = 2
            ..logicalIndex = 0
            ..selectionAnchorParagraph = 0
            ..selectionAnchor = first.text.length;
        }
        final selection = _selection(controller);
        final transaction = _begin(target);
        expect(transaction.session.insertionParagraph, same(first));
        expect(transaction.session.insertionOffset, first.text.length);
        expect(
          transaction.session.insertionEndParagraph,
          same(target.originals[2]),
        );
        expect(transaction.session.insertionEndOffset, 0);
        _stage(transaction, noteType, html: '<p>Replacement</p>');
        _complete(transaction);
        transaction.apply();
        expect(
          _visible(target),
          'Before chosen-firstReplacementchosen-last After\nUnrelated',
        );
        controller.undo();
        expect(_state(controller.document), before);
        expect(_selection(controller), selection);
      },
    );

    for (final emptyEndpoints in [false, true]) {
      test(
        '$story replacement of ${emptyEndpoints ? 'empty' : 'whole'} endpoint paragraphs retains one selection history',
        () {
          final target = _target(noteType);
          final controller = target.controller;
          if (emptyEndpoints) {
            target.originals.first.inlines.removeWhere(
              (inline) => inline is WmlRun,
            );
            target.originals.first.inlines.add(
              WmlRun(text: noteType == 0 ? '' : ' '),
            );
            target.originals[2].inlines
              ..clear()
              ..add(WmlRun(text: ''));
          }
          if (target.note case final note?) {
            final end = controller
                .noteEditText(note)
                .lastIndexOf('\nUnrelated');
            controller.setNoteEditingTarget(
              note,
              TextSelection(baseOffset: end, extentOffset: 0),
            );
          } else {
            controller.caret
              ..paragraphIndex = 0
              ..logicalIndex = 0
              ..selectionAnchorParagraph = 2
              ..selectionAnchor = target.originals[2].text.length;
          }
          final before = _state(controller.document);
          final selection = _selection(controller);
          final transaction = _begin(target);
          _stage(transaction, noteType, html: '<p>Replacement</p>');
          _complete(transaction);
          transaction.apply();
          expect(_visible(target), 'Replacement\nUnrelated');
          expect(_blocks(target).last, same(target.originals.last));
          controller.undo();
          expect(_state(controller.document), before);
          expect(_selection(controller), selection);
          expect(controller.canUndo, isFalse);
        },
      );
    }

    test('$story replacement supports empty intervening paragraphs', () {
      final target = _target(noteType, emptyMiddle: true);
      final transaction = _begin(target);
      _stage(transaction, noteType, html: '<p>Replacement</p>');
      _complete(transaction);
      transaction.apply();
      expect(_visible(target), 'Before Replacement After\nUnrelated');
    });

    test(
      '$story research blocks preserve native owners after spanning replacement',
      () {
        final target = _target(noteType);
        final before = _state(target.controller.document);
        final transaction = _begin(target, ZoteroCitingCommand.addAnnotation);
        _stage(
          transaction,
          noteType,
          html:
              '<ol start="3"><li>Listed $_placeholder</li></ol>'
              '<table><tr><td><p>Cell</p></td></tr></table>',
        );
        _complete(transaction);
        transaction.apply();
        final blocks = _blocks(target);
        expect(blocks.map((b) => b.runtimeType), [
          WmlParagraph,
          WmlParagraph,
          WmlTable,
          WmlParagraph,
          WmlParagraph,
        ]);
        final list = blocks[1] as WmlParagraph;
        expect(list.text, 'Listed $_citationText');
        expect(list.properties.listLabel?.trim(), '3.');
        expect(target.controller.zoteroFields.single.paragraph, same(list));
        expect(
          WordTree.paragraphs([(blocks[2] as WmlTable)]).single.text,
          'Cell',
        );
        expect((blocks[3] as WmlParagraph).text, ' After');
        expect(blocks.last, same(target.originals.last));
        final after = _state(target.controller.document);
        target.controller.undo();
        expect(_state(target.controller.document), before);
        target.controller.redo();
        expect(_state(target.controller.document), after);
      },
    );

    test(
      '$story ordinary citation commands keep multi-paragraph selections non-insertable',
      () {
        final target = _target(noteType);
        final transaction = _begin(target, ZoteroCitingCommand.addEditCitation);
        expect(transaction.session.insertionParagraph, isNull);
        expect(
          _call(transaction, 'Document.canInsertField', ['Http']),
          isFalse,
        );
        expect(
          () => _call(transaction, 'Document.insertField', ['Http', noteType]),
          throwsUnsupportedError,
        );
        expect(target.controller.canUndo, isFalse);
      },
    );

    for (final change in [
      'start endpoint',
      'end endpoint',
      'composition',
      'content revision',
    ]) {
      test(
        '$story $change change refuses a completed replacement without partial application',
        () {
          final target = _target(noteType);
          final controller = target.controller;
          final transaction = _begin(target);
          _stage(transaction, noteType);
          _complete(transaction);
          if (target.note case final note?) {
            final selection = controller.noteEditingTarget!.selection;
            switch (change) {
              case 'start endpoint':
                controller.setNoteEditingTarget(
                  note,
                  selection.copyWith(baseOffset: selection.baseOffset + 1),
                );
              case 'end endpoint':
                controller.setNoteEditingTarget(
                  note,
                  selection.copyWith(extentOffset: selection.extentOffset - 1),
                );
              case 'composition':
                controller.setNoteEditingTarget(
                  note,
                  selection,
                  composing: const TextRange(start: 0, end: 2),
                );
              case 'content revision':
                controller.setNoteText(
                  note,
                  controller
                      .noteEditText(note)
                      .replaceFirst('Selected middle', 'Edited middle'),
                );
            }
          } else {
            switch (change) {
              case 'start endpoint':
                controller.caret.selectionAnchor =
                    controller.caret.selectionAnchor + 1;
              case 'end endpoint':
                controller.caret.logicalIndex--;
              case 'composition':
                controller.input.setValue(
                  TextEditingValue(
                    text: target.originals[2].text,
                    selection: const TextSelection.collapsed(offset: 11),
                    composing: const TextRange(start: 0, end: 2),
                  ),
                );
              case 'content revision':
                controller.insertText('Typed');
            }
          }
          final current = _state(controller.document);
          final selection = _selection(controller);
          final revision = controller.contentRevision;
          expect(transaction.apply, throwsStateError);
          expect(_state(controller.document), current);
          expect(_selection(controller), selection);
          expect(controller.contentRevision, revision);
          expect(controller.zoteroFields, isEmpty);
        },
      );
    }

    for (final unsafe in [
      'citation',
      'native field',
      'comment',
      'bookmark',
      'content control',
    ]) {
      test('$story spanning selection refuses a protected $unsafe', () {
        final target = _target(noteType);
        final middle = target.originals[1];
        switch (unsafe) {
          case 'citation':
            WordZotero.insertCitation(middle, _citation());
          case 'native field':
            middle.inlines
              ..insert(0, WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin))
              ..insert(
                1,
                WmlFieldBoundary(
                  kind: WmlFieldBoundaryKind.instruction,
                  text: ' DATE ',
                ),
              )
              ..insert(2, WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate))
              ..add(WmlFieldBoundary(kind: WmlFieldBoundaryKind.end));
          case 'comment':
            middle.inlines.whereType<WmlRun>().single.commentIds.add(7);
          case 'bookmark':
            middle.inlines
              ..insert(
                0,
                WmlBookmarkBoundary(id: '7', isStart: true, name: 'Protected'),
              )
              ..add(WmlBookmarkBoundary(id: '7', isStart: false));
          case 'content control':
            final blocks = _blocks(target);
            blocks[1] = WmlContentControlBlock(
              control: WmlContentControlData(
                xml:
                    '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr/><w:sdtContent/></w:sdt>',
                sourcePartUri: noteType == 0
                    ? '/word/document.xml'
                    : noteType == 1
                    ? '/word/footnotes.xml'
                    : '/word/endnotes.xml',
                relationships: const [],
              ),
              blocks: [middle],
            );
        }
        _select(target);
        final before = _state(target.controller.document);
        expect(() => _begin(target), throwsUnsupportedError);
        expect(_state(target.controller.document), before);
        expect(target.controller.canUndo, isFalse);
      });
    }
  }

  for (final noteType in [1, 2]) {
    for (final payload in ['plain', 'heading', 'table']) {
      test(
        'authored note $noteType visible start preserves its marker before $payload research',
        () {
          final target = _target(noteType);
          final controller = target.controller;
          final note = target.note!;
          final selection = controller.noteEditingTarget!.selection.copyWith(
            baseOffset: 0,
          );
          controller.setNoteEditingTarget(note, selection);
          final before = _state(controller.document);
          final body = controller.document.paragraphs
              .map((p) => p.text)
              .toList();
          final transaction = _begin(target);
          expect(transaction.session.insertionOffset, 1);
          _stage(
            transaction,
            noteType,
            html: switch (payload) {
              'heading' => '<h2>Replacement</h2>',
              'table' => '<table><tr><td><p>Replacement</p></td></tr></table>',
              _ => '<p>Replacement</p>',
            },
          );
          _complete(transaction);
          transaction.apply();
          final first = note.blocks.first as WmlParagraph;
          expect(first.inlines.first, isA<WmlNoteMarker>());
          expect(first.text, startsWith(' '));
          expect(
            note.allParagraphs.expand(
              (p) => p.inlines.whereType<WmlNoteMarker>(),
            ),
            hasLength(1),
          );
          expect(controller.document.paragraphs.map((p) => p.text), body);
          expect(controller.noteEditingTarget?.note, same(note));
          switch (payload) {
            case 'heading':
              expect(first.properties.headingLevel, 2);
              expect(_visible(target), 'Replacement\n After\nUnrelated');
            case 'table':
              expect(first.text, ' ');
              expect(note.blocks[1], isA<WmlTable>());
              expect(_visible(target), '\n After\nUnrelated');
            default:
              expect(_visible(target), 'Replacement After\nUnrelated');
          }
          final after = _state(controller.document);
          controller.undo();
          expect(_state(controller.document), before);
          expect(controller.noteEditingTarget?.selection, selection);
          controller.redo();
          expect(_state(controller.document), after);
        },
      );
    }
  }

  test(
    'a reopened DOCX supports another spanning replacement between untouched citations',
    () {
      final target = _target(0);
      final beforeCitation = WmlParagraph();
      final afterCitation = WmlParagraph();
      WordZotero.insertCitation(beforeCitation, _citation(id: 'before'));
      WordZotero.insertCitation(afterCitation, _citation(id: 'after'));
      final blocks = _blocks(target);
      blocks
        ..insert(0, beforeCitation)
        ..removeLast()
        ..add(afterCitation);
      _select(target);
      final first = _begin(target);
      _stage(first, 0, html: '<p>First replacement</p><p>Second segment</p>');
      _complete(first);
      first.apply();
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(target.controller.document),
      );
      final existing = WordZotero.fields(reopened)
          .map(
            (field) => (
              field.citation!.citationId,
              field.instruction,
              field.cachedText,
            ),
          )
          .toList();
      final controller = WordEditorController(document: reopened);
      controller.proofing.enabled = false;
      addTearDown(controller.dispose);
      controller.caret
        ..paragraphIndex = 2
        ..logicalIndex = 'Second segment'.length
        ..selectionAnchorParagraph = 1
        ..selectionAnchor = 7;
      final before = _state(reopened);
      final selection = _selection(controller);
      final second = controller.beginZoteroTransaction(
        documentId: _id,
        command: ZoteroCitingCommand.addAnnotation,
      );
      _stage(second, 0);
      _complete(second);
      second.apply();
      expect(reopened.paragraphs.map((p) => p.text), [
        _citationText,
        'Before Quote $_citationText',
        'Continuation After',
        _citationText,
      ]);
      final fields = controller.zoteroFields;
      expect(fields.map((field) => field.citation!.citationId), [
        'before',
        'research-source',
        'after',
      ]);
      expect(
        [fields.first, fields.last].map(
          (field) =>
              (field.citation!.citationId, field.instruction, field.cachedText),
        ),
        existing,
      );
      controller.undo();
      expect(_state(reopened), before);
      expect(_selection(controller), selection);
      controller.redo();
      final finalDocument = WordDeserializer().readBytes(
        WordSerializer().writeBytes(reopened),
      );
      expect(
        WordZotero.fields(
          finalDocument,
        ).map((field) => field.citation!.citationId),
        ['before', 'research-source', 'after'],
      );
      expect(WordFieldSpans.unbalanced(finalDocument), isEmpty);
    },
  );

  for (final command in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    for (final shape in ['plain', 'merged', 'nested']) {
      for (final reverse in [false, true]) {
        test(
          '${command.name} replaces $shape table-cell paragraphs with ${reverse ? 'backward' : 'forward'} selection history',
          () {
            final fixture = _cellTarget(shape: shape, reverse: reverse);
            final target = fixture.target;
            final controller = target.controller;
            final document = controller.document;
            final cell = fixture.cell;
            final originalList = cell.blocks;
            final before = _state(document);
            final selection = _selection(controller);
            final neighbor = _block(fixture.neighbor.blocks.single);
            final transaction = _begin(target, command);
            _stage(transaction, 0);
            _complete(transaction);
            expect(_state(document), before);
            transaction.apply();
            expect(cell.blocks, same(originalList));
            expect(cell.blocks.first, same(target.originals.first));
            expect(cell.blocks.last, same(target.originals.last));
            expect(WordTree.paragraphs(cell.blocks).map((p) => p.text), [
              'Before Quote $_citationText',
              'Continuation After',
              'Unrelated',
            ]);
            expect(_block(fixture.neighbor.blocks.single), neighbor);
            expect(document.sections.single.blocks[1], same(fixture.rootTable));
            expect(
              (document.sections.single.blocks.first as WmlParagraph).text,
              'Outside before',
            );
            expect(
              (document.sections.single.blocks.last as WmlParagraph).text,
              'Outside after',
            );
            expect(cell.gridSpan, shape == 'merged' ? 2 : 1);
            expect(
              cell.vMerge,
              shape == 'merged' ? WmlVMerge.restart : WmlVMerge.none,
            );
            expect(cell.width, 240);
            expect(cell.fillColor, 'EEF2F7');
            final field = controller.zoteroFields.single;
            expect(field.paragraph, same(cell.blocks.first));
            expect(field.cachedText, _citationText);
            expect(field.citation!.items.single.locator, '4');
            expect(
              controller.caret.paragraphIndex,
              document.paragraphs.toList().indexOf(
                cell.blocks[1] as WmlParagraph,
              ),
            );
            expect(controller.caret.logicalIndex, 'Continuation'.length);
            expect(controller.caret.isCollapsed, isTrue);
            final after = _state(document);
            controller.undo();
            expect(_state(document), before);
            expect(_selection(controller), selection);
            expect(cell.blocks, same(originalList));
            expect(cell.blocks, orderedEquals(target.originals));
            expect(controller.canUndo, isFalse);
            controller.redo();
            expect(_state(document), after);
            final reopened = WordDeserializer().readBytes(
              WordSerializer().writeBytes(document),
            );
            final reopenedCell =
                WordTree.descendants(reopened.sections.single.blocks)
                    .whereType<WmlTable>()
                    .expand((table) => table.rows)
                    .expand((row) => row.cells)
                    .singleWhere(
                      (cell) => cell.blocks.whereType<WmlParagraph>().any(
                        (paragraph) =>
                            paragraph.text == 'Before Quote $_citationText',
                      ),
                    );
            expect(reopenedCell.gridSpan, cell.gridSpan);
            expect(reopenedCell.vMerge, cell.vMerge);
            expect(reopenedCell.fillColor, cell.fillColor);
            expect(
              WordZotero.fields(reopened).single.paragraph,
              same(reopenedCell.blocks.first),
            );
            expect(WordFieldSpans.unbalanced(reopened), isEmpty);
          },
        );
      }
    }
  }

  for (final payload in [
    '<h2>Heading</h2><p>Paragraph</p>',
    '<ol start="3"><li>First</li><li>Second</li></ol>',
  ]) {
    test(
      'cell replacement retains heading or list structure and cell owners: $payload',
      () {
        final fixture = _cellTarget();
        final transaction = _begin(fixture.target);
        final before = _state(fixture.target.controller.document);
        _stage(transaction, 0, html: payload);
        _complete(transaction);
        transaction.apply();
        final paragraphs = fixture.cell.blocks.cast<WmlParagraph>();
        if (payload.startsWith('<h2>')) {
          expect(
            paragraphs
                .singleWhere((p) => p.text == 'Heading')
                .properties
                .headingLevel,
            2,
          );
        } else {
          expect(
            paragraphs
                .singleWhere((p) => p.text == 'First')
                .properties
                .listLabel
                ?.trim(),
            '3.',
          );
          expect(
            paragraphs
                .singleWhere((p) => p.text == 'Second')
                .properties
                .listLabel
                ?.trim(),
            '4.',
          );
        }
        expect(fixture.neighbor.blocks.single, isA<WmlParagraph>());
        final after = _state(fixture.target.controller.document);
        fixture.target.controller.undo();
        expect(_state(fixture.target.controller.document), before);
        fixture.target.controller.redo();
        expect(_state(fixture.target.controller.document), after);
      },
    );
  }

  test('cell paragraph-separator endpoints retain the unselected suffix', () {
    final fixture = _cellTarget();
    final target = fixture.target;
    final controller = target.controller;
    final paragraphs = controller.document.paragraphs.toList();
    controller.caret
      ..paragraphIndex = paragraphs.indexOf(target.originals[2])
      ..logicalIndex = 0
      ..selectionAnchorParagraph = paragraphs.indexOf(target.originals.first)
      ..selectionAnchor = target.originals.first.text.length;
    final before = _state(controller.document);
    final selection = _selection(controller);
    final transaction = _begin(target);
    _stage(transaction, 0, html: '<p>Replacement</p>');
    _complete(transaction);
    transaction.apply();
    expect(
      (fixture.cell.blocks.first as WmlParagraph).text,
      'Before chosen-firstReplacementchosen-last After',
    );
    expect(fixture.cell.blocks.last, same(target.originals.last));
    controller.undo();
    expect(_state(controller.document), before);
    expect(_selection(controller), selection);
  });

  for (final html in [
    '<h2>Heading</h2><p>Paragraph</p>',
    '<ol><li>First</li><li>Second</li></ol>',
  ]) {
    test('a typed paragraph cell accepts rich paragraph blocks: $html', () {
      final fixture = _cellTarget();
      fixture.cell.blocks = List<WmlParagraph>.of(
        fixture.cell.blocks.cast<WmlParagraph>(),
      );
      final typedList = fixture.cell.blocks;
      final controller = fixture.target.controller;
      final before = _state(controller.document);
      final selection = _selection(controller);
      final transaction = _begin(fixture.target);
      _stage(transaction, 0, html: html);
      _complete(transaction);
      transaction.apply();
      expect(fixture.cell.blocks, same(typedList));
      expect(fixture.cell.blocks, isA<List<WmlParagraph>>());
      final after = _state(controller.document);
      controller.undo();
      expect(_state(controller.document), before);
      expect(_selection(controller), selection);
      expect(fixture.cell.blocks, same(typedList));
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_state(controller.document), after);
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(controller.document),
      );
      expect(
        reopened.paragraphs.map((p) => p.text),
        controller.document.paragraphs.map((p) => p.text),
      );
    });
  }

  for (final change in ['cell', 'row', 'table', 'block list', 'continuation']) {
    test(
      'completed cell replacement rejects changed $change ownership without a revision',
      () {
        final fixture = _cellTarget();
        final target = fixture.target;
        final controller = target.controller;
        final transaction = _begin(target);
        _stage(transaction, 0);
        _complete(transaction);
        final revision = controller.contentRevision;
        final visible = _visible(target);
        switch (change) {
          case 'cell':
            fixture.table.rows.single.cells[0] = WmlTableCell(
              blocks: fixture.cell.blocks,
            );
          case 'row':
            fixture.table.rows[0] = WmlTableRow(
              cells: fixture.table.rows.single.cells,
            );
          case 'table':
            controller.document.sections.single.blocks[1] = WmlTable(
              grid: fixture.table.grid,
              rows: fixture.table.rows,
            );
          case 'block list':
            fixture.cell.blocks = List<WmlBlock>.of(fixture.cell.blocks);
          case 'continuation':
            fixture.cell.vMerge = WmlVMerge.cont;
        }
        expect(controller.contentRevision, revision);
        expect(_visible(target), visible);
        final current = _state(controller.document);
        expect(
          transaction.apply,
          throwsA(anyOf(isA<StateError>(), isA<UnsupportedError>())),
        );
        expect(_state(controller.document), current);
        expect(controller.canUndo, isFalse);
        expect(controller.zoteroFields, isEmpty);
      },
    );
  }

  for (final unsafe in [
    'different cell',
    'different row',
    'body to cell',
    'outer to inner cell',
    'shared cell list',
    'shared table',
    'continuation',
    'control ancestor',
    'frame ancestor',
    'selected table band',
  ]) {
    test('table-cell range refuses $unsafe before publishing changes', () {
      final fixture = _cellTarget(
        shape: unsafe == 'outer to inner cell' ? 'nested' : 'plain',
      );
      final target = fixture.target;
      final controller = target.controller;
      switch (unsafe) {
        case 'different cell':
          fixture.cell.blocks.removeRange(2, 4);
          fixture.neighbor.blocks.insertAll(0, target.originals.skip(2));
        case 'different row':
          fixture.cell.blocks.removeRange(2, 4);
          fixture.table.rows.add(
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: <WmlBlock>[...target.originals.skip(2)]),
              ],
            ),
          );
        case 'shared cell list':
          fixture.neighbor.blocks = fixture.cell.blocks;
        case 'shared table':
          controller.document.sections.single.blocks.add(fixture.table);
        case 'continuation':
          fixture.cell.vMerge = WmlVMerge.cont;
        case 'control ancestor':
          controller
              .document
              .sections
              .single
              .blocks[1] = WmlContentControlBlock(
            control: WmlContentControlData(
              xml:
                  '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr/><w:sdtContent/></w:sdt>',
              sourcePartUri: '/word/document.xml',
              relationships: const [],
            ),
            blocks: [fixture.table],
          );
        case 'frame ancestor':
          controller.document.sections.single.blocks[1] = WmlFrame(
            blocks: [fixture.table],
          );
        case 'selected table band':
          controller.selectedTableBand = (
            table: fixture.table,
            column: false,
            from: 0,
            to: 0,
          );
      }
      _select(target);
      if (unsafe == 'body to cell' || unsafe == 'outer to inner cell') {
        controller.caret
          ..selectionAnchorParagraph = unsafe == 'body to cell' ? 0 : 1
          ..selectionAnchor = 0;
      }
      final before = _state(controller.document);
      expect(() => _begin(target), throwsUnsupportedError);
      expect(_state(controller.document), before);
      expect(controller.canUndo, isFalse);
    });
  }

  test(
    'table-containing payload refuses inside a cell without leaking staged preferences',
    () {
      final fixture = _cellTarget();
      final target = fixture.target;
      final before = _state(target.controller.document);
      final transaction = _begin(target);
      expect(
        () => _stage(
          transaction,
          0,
          html: '<table><tr><td><p>Nested</p></td></tr></table>',
        ),
        throwsUnsupportedError,
      );
      expect(_state(target.controller.document), before);
      expect(target.controller.canUndo, isFalse);
      expect(target.controller.isDirty, isFalse);
    },
  );

  for (final unsafe in ['section boundary', 'different table cells']) {
    test('body spanning selection refuses $unsafe', () {
      final target = _target(0);
      final document = target.controller.document;
      if (unsafe == 'section boundary') {
        document.sections.single.blocks.removeRange(2, 4);
        document.sections.add(
          WmlSection(blocks: target.originals.skip(2).toList()),
        );
      } else {
        document.sections.single.blocks
          ..clear()
          ..add(
            WmlTable(
              rows: [
                WmlTableRow(
                  cells: [
                    WmlTableCell(
                      blocks: <WmlBlock>[...target.originals.take(2)],
                    ),
                    WmlTableCell(
                      blocks: <WmlBlock>[...target.originals.skip(2)],
                    ),
                  ],
                ),
              ],
            ),
          );
      }
      _select(target);
      final before = _state(document);
      expect(() => _begin(target), throwsUnsupportedError);
      expect(_state(document), before);
      expect(target.controller.canUndo, isFalse);
    });
  }

  for (final command in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    for (final cancel in [false, true]) {
      testWidgets(
        'direct ${command.name} ${cancel ? 'cancels' : 'replaces'} a cell-local selection',
        (tester) async {
          final fixture = _cellTarget(reverse: true);
          final target = fixture.target;
          final controller = target.controller;
          final before = _state(controller.document);
          final selection = _selection(controller);
          final desktop = _Desktop(0, cancel: cancel);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1200, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => showWordZoteroDialog(
                      context,
                      controller: controller,
                      localTransport: desktop.send,
                      initialCommand: command,
                      closeAfterCommand: true,
                    ),
                    child: const Text('Insert cell research'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Insert cell research'));
          await tester.pumpAndSettle();
          expect(desktop.command, command.name);
          expect(desktop.requests, cancel ? 6 : 7);
          expect(
            find.byKey(const ValueKey<String>('zotero-direct-command')),
            findsNothing,
          );
          if (cancel) {
            expect(_state(controller.document), before);
            expect(_selection(controller), selection);
            expect(controller.canUndo, isFalse);
            expect(controller.isDirty, isFalse);
          } else {
            expect(
              WordTree.paragraphs(fixture.cell.blocks).map((p) => p.text),
              ['Before Replacement After', 'Unrelated'],
            );
            controller.undo();
            expect(_state(controller.document), before);
            expect(_selection(controller), selection);
            expect(controller.canUndo, isFalse);
          }
        },
      );
    }
  }

  for (final noteType in [0, 1, 2]) {
    for (final cancel in [false, true]) {
      testWidgets(
        'direct research command ${cancel ? 'cancels' : 'replaces'} a multi-paragraph target in story $noteType',
        (tester) async {
          final target = _target(noteType, reverse: true);
          final controller = target.controller;
          final before = _state(controller.document);
          final selection = _selection(controller);
          final desktop = _Desktop(noteType, cancel: cancel);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1200, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => showWordZoteroDialog(
                      context,
                      controller: controller,
                      localTransport: desktop.send,
                      initialCommand: ZoteroCitingCommand.addAnnotation,
                      closeAfterCommand: true,
                    ),
                    child: const Text('Insert research'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Insert research'));
          await tester.pumpAndSettle();
          expect(desktop.command, 'addAnnotation');
          expect(desktop.requests, cancel ? 6 : 7);
          expect(
            find.byKey(const ValueKey<String>('zotero-direct-command')),
            findsNothing,
          );
          if (cancel) {
            expect(_state(controller.document), before);
            expect(_selection(controller), selection);
            expect(controller.canUndo, isFalse);
            expect(controller.isDirty, isFalse);
          } else {
            expect(_visible(target), 'Before Replacement After\nUnrelated');
            controller.undo();
            expect(_state(controller.document), before);
            expect(_selection(controller), selection);
            expect(controller.canUndo, isFalse);
          }
        },
      );
    }
  }
}

class _Desktop {
  _Desktop(this.noteType, {required this.cancel});
  final int noteType;
  final bool cancel;
  int requests = 0;
  String documentId = '';
  String fieldId = '';
  String command = '';

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    final index = requests++;
    final decoded = jsonDecode(request.body!);
    if (index == 0) {
      final payload = decoded as Map<String, Object?>;
      documentId = payload['docId']! as String;
      command = payload['command']! as String;
    } else if (decoded case {'id': final String id}) {
      fieldId = id;
    }
    final (name, arguments) = switch (index) {
      0 => ('Application.getActiveDocument', <Object?>[]),
      1 => ('Document.getDocumentData', <Object?>[documentId]),
      2 => (
        'Document.setDocumentData',
        <Object?>[documentId, _preferences(noteType)],
      ),
      3 => ('Document.insertField', <Object?>[documentId, 'Http', noteType]),
      4 => ('Field.delete', <Object?>[documentId, fieldId]),
      5 when !cancel => (
        'Document.insertText',
        <Object?>[documentId, '<p>Replacement</p>'],
      ),
      _ => ('Document.complete', <Object?>[documentId]),
    };
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode({'command': name, 'arguments': arguments}),
    );
  }
}
