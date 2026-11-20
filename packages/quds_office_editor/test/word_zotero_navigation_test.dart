import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

ZoteroCitation _citation(String id) => ZoteroCitation(
  citationId: id,
  plainCitation: '($id)',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlParagraph _cited(String id) {
  final paragraph = _paragraph('Before ');
  WordZotero.insertCitation(paragraph, _citation(id));
  paragraph.inlines.add(WmlRun(text: ' after'));
  return paragraph;
}

WordEditorController _controller(
  WmlDocument document, {
  OfficeInteractionMode mode = OfficeInteractionMode.editing,
}) {
  final controller = WordEditorController(
    document: document,
    config: OfficeSurfaceConfig(mode: mode),
  );
  controller.proofing.enabled = false;
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return controller;
}

List<Object?> _selection(WordEditorController c) => [
  c.caret.paragraphIndex,
  c.caret.logicalIndex,
  c.caret.selectionAnchorParagraph,
  c.caret.selectionAnchor,
  c.noteEditingTarget,
];

void _clean(WordEditorController c) {
  expect(c.canUndo, isFalse);
  expect(c.canRedo, isFalse);
  expect(c.isDirty, isFalse);
  expect(c.contentRevision, 0);
}

List<WmlParagraph> _bibliography() => WordZotero.nativeBibliographyParagraphs(
  instruction:
      ' ADDIN ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY ',
  text: 'First entry.\nSecond entry.',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'body navigation selects the citation and leaves contents and history',
    () {
      final paragraph = _cited('body');
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [_paragraph('Other'), paragraph]),
        ],
      );
      final controller = _controller(document);
      final field = controller.zoteroFields.single;
      final inlines = List<WmlInline>.of(paragraph.inlines);
      final text = paragraph.text;
      var focusRequests = 0;
      controller.onRequestFocus = () => focusRequests++;

      expect(controller.canRevealZoteroField(field), isTrue);
      expect(controller.revealZoteroField(field), isTrue);
      expect(controller.caret.normalizedRange, (
        startPara: 1,
        startIdx: field.start,
        endPara: 1,
        endIdx: field.end,
      ));
      expect(controller.zoteroFieldAtCaret?.citation?.citationId, 'body');
      expect(paragraph.inlines, orderedEquals(inlines));
      expect(paragraph.text, text);
      expect(focusRequests, 1);
      _clean(controller);
    },
  );

  test('locked citations remain navigable in read-only selecting mode', () {
    final paragraph = _cited('locked');
    paragraph.inlines
            .whereType<WmlRun>()
            .firstWhere((run) => run.fieldInstruction != null)
            .fieldLocked =
        true;
    final controller = _controller(
      WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      ),
      mode: OfficeInteractionMode.selecting,
    );
    final field = controller.zoteroFields.single;
    expect(field.locked, isTrue);
    expect(field.canEdit, isFalse);
    expect(controller.revealZoteroField(field), isTrue);
    expect(controller.caret.isCollapsed, isFalse);
    expect(controller.input.isAttached, isFalse);
    _clean(controller);
  });

  test('view-only mode refuses navigation and keyboard focus', () {
    final controller = _controller(
      WmlDocument(
        sections: [
          WmlSection(blocks: [_cited('view')]),
        ],
      ),
      mode: OfficeInteractionMode.viewing,
    );
    final before = _selection(controller);
    var focusRequests = 0;
    controller.onRequestFocus = () => focusRequests++;
    expect(
      controller.canRevealZoteroField(controller.zoteroFields.single),
      isFalse,
    );
    expect(
      controller.revealZoteroField(controller.zoteroFields.single),
      isFalse,
    );
    controller.requestEditingFocus();
    expect(_selection(controller), before);
    expect(focusRequests, 0);
    _clean(controller);
  });

  test('stale citation handles cannot select replacement text', () {
    final paragraph = _cited('old');
    final controller = _controller(
      WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      ),
    );
    final stale = controller.zoteroFields.single;
    controller.updateZoteroCitation(
      stale,
      stale.citation!.withItems(
        stale.citation!.items,
        plainCitation: '(changed)',
      ),
    );
    final before = _selection(controller);
    final revision = controller.contentRevision;
    expect(controller.revealZoteroField(stale), isFalse);
    expect(_selection(controller), before);
    expect(controller.contentRevision, revision);
    expect(
      controller.revealZoteroField(controller.zoteroFields.single),
      isTrue,
    );
  });

  test('identically reinserted citations do not revive a stale run handle', () {
    final paragraph = _cited('same');
    final controller = _controller(
      WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      ),
    );
    final stale = controller.zoteroFields.single;
    paragraph.inlines
      ..clear()
      ..addAll(_cited('same').inlines);
    final before = _selection(controller);
    expect(controller.revealZoteroField(stale), isFalse);
    expect(_selection(controller), before);
    expect(
      controller.revealZoteroField(controller.zoteroFields.single),
      isTrue,
    );
    _clean(controller);
  });

  test('removed paragraphs and fields from another document are rejected', () {
    final removed = _cited('removed');
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [_paragraph('Body'), removed]),
      ],
    );
    final controller = _controller(document);
    final stale = controller.zoteroFields.single;
    document.sections.single.blocks.remove(removed);
    final foreign = WordZotero.fields(
      WmlDocument(
        sections: [
          WmlSection(blocks: [_cited('foreign')]),
        ],
      ),
    ).single;
    final before = _selection(controller);
    for (final field in [stale, foreign]) {
      expect(controller.canRevealZoteroField(field), isFalse);
      expect(controller.revealZoteroField(field), isFalse);
    }
    expect(_selection(controller), before);
    _clean(controller);
  });

  test('body table cells use their actual flattened paragraph index', () {
    final paragraph = _cited('table');
    final table = WmlTable(
      rows: [
        WmlTableRow(
          cells: [
            WmlTableCell(blocks: [_paragraph('First cell')]),
            WmlTableCell(blocks: [paragraph]),
          ],
        ),
      ],
    );
    final controller = _controller(
      WmlDocument(
        sections: [
          WmlSection(blocks: [_paragraph('Body'), table]),
        ],
      ),
    );
    final field = controller.zoteroFields.single;
    expect(controller.revealZoteroField(field), isTrue);
    expect(controller.caret.normalizedRange, (
      startPara: 2,
      startIdx: field.start,
      endPara: 2,
      endIdx: field.end,
    ));
    _clean(controller);
  });

  for (final inCell in [false, true]) {
    test(
      'complete bibliography range is selected across paragraphs in cell $inCell',
      () {
        final entries = _bibliography();
        final List<WmlBlock> blocks = inCell
            ? [
                WmlTable(
                  rows: [
                    WmlTableRow(cells: [WmlTableCell(blocks: entries)]),
                  ],
                ),
              ]
            : entries;
        final controller = _controller(
          WmlDocument(
            sections: [
              WmlSection(
                blocks: [_paragraph('Before'), ...blocks, _paragraph('After')],
              ),
            ],
          ),
        );
        final field = controller.zoteroFields.single;
        expect(field.paragraphs, hasLength(2));
        expect(controller.revealZoteroField(field), isTrue);
        expect(controller.caret.normalizedRange, (
          startPara: 1,
          startIdx: 0,
          endPara: 2,
          endIdx: 'Second entry.'.length,
        ));
        _clean(controller);
      },
    );
  }

  test('bibliography spanning unrelated table cells is not selectable', () {
    final entries = _bibliography();
    final controller = _controller(
      WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlTable(
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(blocks: [entries.first]),
                      WmlTableCell(blocks: [entries.last]),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    final field = controller.zoteroFields.single;
    expect(field.paragraphs, hasLength(2));
    final before = _selection(controller);
    expect(controller.revealZoteroField(field), isFalse);
    expect(_selection(controller), before);
    _clean(controller);
  });

  for (final endnote in [false, true]) {
    for (final secondParagraph in [false, true]) {
      test(
        'note $endnote paragraph $secondParagraph maps hidden reference-space offsets',
        () {
          final document = WmlDocument.empty(text: 'Body');
          final note = WordNotes.insert(
            document,
            document.paragraphs.single,
            endnote: endnote,
            text: 'Before ',
          );
          if (secondParagraph) note.paragraphs.add(_paragraph('Second '));
          WordZotero.insertCitation(note.paragraphs.last, _citation('note'));
          note.paragraphs.last.inlines.add(WmlRun(text: ' after'));
          final controller = _controller(
            document,
            mode: OfficeInteractionMode.selecting,
          );
          final parked = _selection(controller);
          final beforeText = controller.noteEditText(note);
          final field = controller.zoteroFields.single;
          expect(controller.revealZoteroField(field), isTrue);
          final start = beforeText.indexOf('(note)');
          expect(controller.noteEditingTarget?.note, same(note));
          expect(
            controller.noteEditingTarget?.selection,
            TextSelection(
              baseOffset: start,
              extentOffset: start + '(note)'.length,
            ),
          );
          expect(_selection(controller).take(4), parked.take(4));
          expect(controller.config.showNotesPane, isTrue);
          expect(controller.noteFocusRequest, 1);
          expect(controller.zoteroFieldAtCaret?.citation?.citationId, 'note');
          expect(controller.noteEditText(note), beforeText);
          _clean(controller);
        },
      );
    }
  }

  test('note bibliography selects all exposed paragraphs', () {
    final document = WmlDocument.empty(text: 'Body');
    final note = WordNotes.insert(
      document,
      document.paragraphs.single,
      endnote: false,
      text: 'Intro',
    );
    note.blocks.addAll(_bibliography());
    final controller = _controller(document);
    expect(
      controller.revealZoteroField(controller.zoteroFields.single),
      isTrue,
    );
    expect(
      controller.noteEditingTarget?.selection,
      TextSelection(
        baseOffset: 'Intro\n'.length,
        extentOffset: controller.noteEditText(note).length,
      ),
    );
    _clean(controller);
  });

  test(
    'unsupported headers comments frames and note tables leave selection alone',
    () {
      final document = WmlDocument.empty(text: 'Body');
      document.sections.single.header.add(_cited('header'));
      document.comments.add(WmlComment(id: 1, paragraphs: [_cited('comment')]));
      document.sections.single.blocks.add(WmlFrame(blocks: [_cited('frame')]));
      final note = WordNotes.insert(
        document,
        document.paragraphs.first,
        endnote: false,
        text: 'Note',
      );
      note.blocks.add(
        WmlTable(
          rows: [
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [_cited('note-table')]),
              ],
            ),
          ],
        ),
      );
      final controller = _controller(document);
      final before = _selection(controller);
      expect(controller.zoteroFields, hasLength(4));
      for (final field in controller.zoteroFields) {
        expect(
          controller.canRevealZoteroField(field),
          isFalse,
          reason: field.cachedText,
        );
        expect(
          controller.revealZoteroField(field),
          isFalse,
          reason: field.cachedText,
        );
      }
      expect(_selection(controller), before);
      _clean(controller);
    },
  );

  test(
    'only an exact complete body bibliography selection resolves its field',
    () {
      final controller = _controller(
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                _paragraph('Before'),
                ..._bibliography(),
                _paragraph('After'),
              ],
            ),
          ],
        ),
      );
      final field = controller.zoteroFields.single;
      expect(controller.revealZoteroField(field), isTrue);
      expect(controller.zoteroFieldAtCaret?.kind, ZoteroFieldKind.bibliography);
      controller.caret.selectionAnchor = 1;
      expect(controller.zoteroFieldAtCaret, isNull);
      controller.caret.selectionAnchor = 0;
      controller.caret.logicalIndex--;
      expect(controller.zoteroFieldAtCaret, isNull);
      controller.caret.logicalIndex++;
      controller.caret.selectionAnchorParagraph = 0;
      expect(controller.zoteroFieldAtCaret, isNull);
      controller.caret
        ..paragraphIndex = 1
        ..logicalIndex = 0
        ..selectionAnchorParagraph = 2
        ..selectionAnchor = field.end;
      expect(controller.zoteroFieldAtCaret?.kind, ZoteroFieldKind.bibliography);
      _clean(controller);
    },
  );

  test(
    'only an exact complete Notes bibliography selection resolves its field',
    () {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: false,
        text: 'Intro',
      );
      note.blocks.addAll(_bibliography());
      final controller = _controller(document);
      expect(
        controller.revealZoteroField(controller.zoteroFields.single),
        isTrue,
      );
      final selection = controller.noteEditingTarget!.selection;
      expect(controller.zoteroFieldAtCaret?.kind, ZoteroFieldKind.bibliography);
      for (final altered in [
        selection.copyWith(baseOffset: selection.start + 1),
        selection.copyWith(extentOffset: selection.end - 1),
        selection.copyWith(baseOffset: 0),
      ]) {
        controller.setNoteEditingTarget(note, altered);
        expect(controller.zoteroFieldAtCaret, isNull);
      }
      controller.setNoteEditingTarget(
        note,
        TextSelection(baseOffset: selection.end, extentOffset: selection.start),
      );
      expect(controller.zoteroFieldAtCaret?.kind, ZoteroFieldKind.bibliography);
      _clean(controller);
    },
  );

  test('invalid citation JSON is not a navigation target', () {
    final document = WmlDocument.empty();
    document.paragraphs.single.inlines.add(
      WmlRun(
        text: '(Malformed)',
        fieldInstruction: 'ADDIN ZOTERO_ITEM CSL_CITATION {bad',
      ),
    );
    final controller = _controller(document);
    final field = controller.zoteroFields.single;
    expect(field.isValid, isFalse);
    expect(controller.revealZoteroField(field), isFalse);
    _clean(controller);
  });

  test('navigation refuses to interrupt active Notes composition', () {
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [_cited('body')]),
      ],
    );
    final note = WordNotes.insert(
      document,
      document.paragraphs.single,
      endnote: false,
      text: 'Draft',
    );
    final controller = _controller(document);
    controller.setNoteEditingTarget(
      note,
      const TextSelection.collapsed(offset: 2),
      composing: const TextRange(start: 0, end: 2),
    );
    final before = _selection(controller);
    expect(
      controller.revealZoteroField(controller.zoteroFields.single),
      isFalse,
    );
    expect(_selection(controller), before);
    _clean(controller);
  });

  test('body navigation leaves Notes and object contexts before focusing', () {
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [_cited('body')]),
      ],
    );
    final note = WordNotes.insert(
      document,
      document.paragraphs.single,
      endnote: false,
      text: 'Note',
    );
    final controller = _controller(document);
    controller.setNoteEditingTarget(
      note,
      const TextSelection.collapsed(offset: 2),
    );
    controller.selectedFrame = WmlFrame(blocks: [_paragraph('Frame')]);
    controller.editingFrame = true;
    expect(
      controller.revealZoteroField(controller.zoteroFields.single),
      isTrue,
    );
    expect(controller.noteEditingTarget, isNull);
    expect(controller.selectedFrame, isNull);
    expect(controller.editingFrame, isFalse);
    expect(controller.zoteroFieldAtCaret?.citation?.citationId, 'body');
    _clean(controller);
  });

  test(
    'focus requests retain Notes selection and skip stale deleted notes',
    () {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: false,
        text: 'Note',
      );
      final controller = _controller(document);
      const selected = TextSelection(baseOffset: 4, extentOffset: 1);
      controller.setNoteEditingTarget(note, selected);
      controller.requestEditingFocus();
      expect(controller.noteEditingTarget?.selection, selected);
      expect(controller.noteFocusRequest, 1);
      document.footnotes.clear();
      controller.requestEditingFocus();
      expect(controller.noteFocusRequest, 1);
      _clean(controller);
    },
  );

  // Add Note supports authored notes and selections within one paragraph
  // since cfd4cee5 (see word_zotero_add_note_controller_test.dart, which also
  // covers the cross-paragraph refusal). Opening the transaction must still
  // leave the document and history untouched until Zotero responds.
  test(
    'Add Note opens Notes and single-paragraph body targets without editing before native calls',
    () {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: false,
        text: 'Note',
      );
      final controller = _controller(document);
      // The fixture already contains the footnote's body reference marker.
      final body = document.paragraphs.single;
      final bodyText = body.text;
      final bodyInlines = List<WmlInline>.of(body.inlines);
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 2),
      );
      expect(
        controller.beginZoteroTransaction(
          documentId: 'add-note',
          command: ZoteroCitingCommand.addNote,
        ),
        isA<WordZoteroTransaction>(),
      );
      expect(controller.noteEditText(note), 'Note');
      expect(body.text, bodyText);
      expect(body.inlines, orderedEquals(bodyInlines));
      _clean(controller);
      controller.clearNoteEditingTarget();
      controller.caret
        ..logicalIndex = 2
        ..selectionAnchor = 0;
      final selection = _selection(controller);
      expect(
        controller.beginZoteroTransaction(
          documentId: 'add-note',
          command: ZoteroCitingCommand.addNote,
        ),
        isA<WordZoteroTransaction>(),
      );
      expect(body.text, bodyText);
      expect(body.inlines, orderedEquals(bodyInlines));
      expect(controller.noteEditText(note), 'Note');
      expect(_selection(controller), selection);
      _clean(controller);
    },
  );

  test(
    'body composition rejects every native command before pending edits commit',
    () {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: false,
        text: 'Note',
      );
      final controller = _controller(document);
      controller.setNoteText(note, 'Pending note text');
      controller.caret.logicalIndex = 2;
      controller.caret.collapseSelection();
      final value = TextEditingValue(
        text: document.paragraphs.single.text,
        selection: const TextSelection.collapsed(offset: 2),
        composing: const TextRange(start: 0, end: 2),
      );
      controller.input.setValue(value);
      final before = _selection(controller);
      final revision = controller.contentRevision;
      expect(controller.canUndo, isFalse);
      for (final command in <ZoteroCitingCommand?>[
        null,
        ...ZoteroCitingCommand.values,
      ]) {
        expect(
          () => controller.beginZoteroTransaction(
            documentId: 'body-composition',
            command: command,
          ),
          throwsA(
            isA<UnsupportedError>().having(
              (error) => error.message,
              'message',
              contains('composition'),
            ),
          ),
        );
        expect(controller.input.value, value);
        expect(controller.input.composing, value.composing);
        expect(_selection(controller), before);
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, isFalse);
        expect(note.text, 'Pending note text');
      }
      controller.input.setValue(value.copyWith(composing: TextRange.empty));
      controller.beginZoteroTransaction(documentId: 'composition-finished');
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(note.text, 'Note');
    },
  );

  test(
    'body composition beginning during native work rejects completed changes',
    () {
      final document = WmlDocument.empty(text: 'Body');
      final controller = _controller(document);
      controller.caret.logicalIndex = 2;
      controller.caret.collapseSelection();
      final transaction = controller.beginZoteroTransaction(
        documentId: 'composition-started',
        command: ZoteroCitingCommand.addNote,
      );
      transaction.session.handle('Document.insertText', [
        'composition-started',
        '<p>Research note</p>',
      ]);
      transaction.session.handle('Document.complete', ['composition-started']);
      final value = TextEditingValue(
        text: document.paragraphs.single.text,
        selection: const TextSelection.collapsed(offset: 2),
        composing: const TextRange(start: 0, end: 2),
      );
      controller.input.setValue(value);
      final before = _selection(controller);
      expect(transaction.assertCurrent, throwsStateError);
      expect(transaction.apply, throwsStateError);
      expect(document.paragraphs.single.text, 'Body');
      expect(controller.input.value, value);
      expect(controller.input.composing, value.composing);
      expect(_selection(controller), before);
      _clean(controller);
    },
  );

  test(
    'body focus return does not clear active composition or change selection',
    () {
      final controller = _controller(WmlDocument.empty(text: 'Body'));
      controller.caret.logicalIndex = 2;
      controller.caret.collapseSelection();
      const value = TextEditingValue(
        text: 'Body',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      controller.input.setValue(value);
      final before = _selection(controller);
      var calls = 0;
      controller.onRequestFocus = () {
        calls++;
        controller.input.setValue(value.copyWith(composing: TextRange.empty));
      };
      controller.requestEditingFocus();
      expect(calls, 0);
      expect(controller.input.value, value);
      expect(controller.input.composing, value.composing);
      expect(_selection(controller), before);
      _clean(controller);
    },
  );

  test(
    'Notes focus return does not reveal or interrupt active composition',
    () {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: false,
        text: 'Note',
      );
      final controller = _controller(document);
      controller.syncConfig(controller.config.copyWith(showNotesPane: false));
      controller.setNoteEditingTarget(
        note,
        const TextSelection.collapsed(offset: 2),
        composing: const TextRange(start: 0, end: 2),
      );
      final before = _selection(controller);
      controller.requestEditingFocus();
      expect(controller.noteFocusRequest, 0);
      expect(controller.config.showNotesPane, isFalse);
      expect(_selection(controller), before);
      expect(
        controller.noteEditingTarget?.composing,
        const TextRange(start: 0, end: 2),
      );
      _clean(controller);
    },
  );

  test(
    'reattaching an unchanged body target preserves the complete IME draft',
    () {
      final controller = _controller(WmlDocument.empty(text: 'Body text'));
      controller.caret.logicalIndex = 2;
      controller.caret.collapseSelection();
      controller.attachInput();
      const value = TextEditingValue(
        text: 'Body text',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 4),
      );
      controller.input.setValue(value);
      controller.detachInput();
      final before = _selection(controller);
      controller.attachInput();
      expect(controller.input.isAttached, isTrue);
      expect(controller.input.value, value);
      expect(controller.input.composing, value.composing);
      expect(_selection(controller), before);
      expect(controller.document.paragraphs.single.text, 'Body text');
      _clean(controller);
    },
  );

  test('accepted IME text retains its composition through reattachment', () {
    final controller = _controller(WmlDocument.empty(text: 'Body'));
    controller.caret.logicalIndex = 4;
    controller.caret.collapseSelection();
    controller.attachInput();
    const value = TextEditingValue(
      text: 'Body仮',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 4, end: 5),
    );
    controller.input.updateEditingValue(value);
    expect(controller.document.paragraphs.single.text, value.text);
    expect(controller.caret.logicalIndex, 5);
    final revision = controller.contentRevision;
    final before = _selection(controller);
    controller.detachInput();
    controller.attachInput();
    expect(controller.input.isAttached, isTrue);
    expect(controller.input.value, value);
    expect(controller.input.composing, value.composing);
    expect(_selection(controller), before);
    expect(controller.contentRevision, revision);
    controller.undo();
    expect(controller.document.paragraphs.single.text, 'Body');
    expect(controller.canUndo, isFalse);
  });

  for (final changed in ['paragraph', 'caret', 'text']) {
    test('reattachment does not reuse composition after changing $changed', () {
      final first = _paragraph('Body text');
      final second = _paragraph('Body text');
      final controller = _controller(
        WmlDocument(
          sections: [
            WmlSection(blocks: [first, second]),
          ],
        ),
      );
      controller.caret.logicalIndex = 2;
      controller.caret.collapseSelection();
      controller.attachInput();
      controller.input.setValue(
        const TextEditingValue(
          text: 'Body text',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 4),
        ),
      );
      controller.detachInput();
      switch (changed) {
        case 'paragraph':
          controller.caret.paragraphIndex = 1;
          controller.caret.collapseSelection();
        case 'caret':
          controller.caret.logicalIndex = 3;
          controller.caret.collapseSelection();
        case 'text':
          (first.inlines.single as WmlRun).text = 'Changed text';
      }
      final before = _selection(controller);
      controller.attachInput();
      expect(controller.input.isAttached, isTrue);
      expect(controller.input.composing, TextRange.empty);
      expect(controller.input.value.composing, TextRange.empty);
      expect(
        controller.input.value.text,
        changed == 'text' ? 'Changed text' : 'Body text',
      );
      expect(
        controller.input.value.selection.extentOffset,
        controller.caret.logicalIndex,
      );
      expect(_selection(controller), before);
      _clean(controller);
    });
  }
}
