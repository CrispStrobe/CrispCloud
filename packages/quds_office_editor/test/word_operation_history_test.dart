import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller([String text = 'Alpha Beta']) {
  final controller = WordEditorController(
    document: WmlDocument.empty(text: text),
  );
  addTearDown(controller.dispose);
  return controller;
}

Iterable<XmlElement> _descendants(XmlElement root, String name) sync* {
  for (final child in root.childElements) {
    if (child.localName == name) yield child;
    yield* _descendants(child, name);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final endnote in [false, true]) {
    test(
      '${endnote ? 'endnote' : 'footnote'} edit replays after insertion',
      () {
        final controller = _controller();
        controller.caret.logicalIndex = 5;
        controller.caret.collapseSelection();
        controller.insertFootnote(text: 'Original note', endnote: endnote);
        final notes = endnote
            ? controller.document.endnotes
            : controller.document.footnotes;
        final note = notes.single;
        controller.setNoteText(note, 'Edited note');
        controller.commitNoteEdit(note);

        for (var cycle = 0; cycle < 3; cycle++) {
          expect(notes.single.text, 'Edited note');
          expect(controller.document.paragraphs.single.text, 'Alpha1 Beta');
          controller.undo();
          expect(notes.single.text, 'Original note');
          controller.undo();
          expect(notes, isEmpty);
          expect(controller.document.paragraphs.single.text, 'Alpha Beta');
          controller.redo();
          expect(notes.single, same(note));
          controller.redo();
        }
        final reopened = WordDeserializer().readBytes(controller.saveBytes());
        expect(
          (endnote ? reopened.endnotes : reopened.footnotes).single.text,
          'Edited note',
        );
        expect(reopened.paragraphs.single.text, 'Alpha1 Beta');
      },
    );
  }

  test('split, type and format replay against the same paragraph', () {
    final controller = _controller();
    controller.caret.logicalIndex = 5;
    controller.caret.collapseSelection();
    controller.insertParagraphBreak();
    final inserted = controller.document.paragraphs.last;
    controller.insertText('X');
    controller.applyParagraphFormat((props) => props.spacingBefore = 24);

    for (var cycle = 0; cycle < 3; cycle++) {
      expect(controller.document.paragraphs.map((p) => p.text), [
        'Alpha',
        'X Beta',
      ]);
      expect(inserted.properties.spacingBefore, 24);
      controller.undo();
      controller.undo();
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'Alpha Beta');
      controller.redo();
      expect(controller.document.paragraphs.last, same(inserted));
      controller.redo();
      controller.redo();
    }
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(reopened.paragraphs.map((p) => p.text), ['Alpha', 'X Beta']);
    expect(reopened.paragraphs.last.properties.spacingBefore, 24);
  });

  test(
    'header paragraph history stays in its story after closing the pane',
    () {
      final controller = _controller('Body');
      controller.beginHeaderFooterEdit(0, footer: false);
      controller.insertText('Header text');
      controller.caret.logicalIndex = 6;
      controller.caret.collapseSelection();
      controller.insertParagraphBreak();
      controller.endHeaderFooterEdit();

      controller.undo();
      expect(controller.document.sections.single.header.map((p) => p.text), [
        'Header text',
      ]);
      expect(controller.document.paragraphs.single.text, 'Body');
      controller.redo();
      expect(controller.document.sections.single.header.map((p) => p.text), [
        'Header',
        ' text',
      ]);
      expect(controller.document.paragraphs.single.text, 'Body');
    },
  );

  test(
    'page break remains one history step and survives replay and export',
    () {
      final controller = _controller();
      controller.caret.logicalIndex = 5;
      controller.caret.collapseSelection();
      controller.insertPageBreak();
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(controller.document.paragraphs.map((p) => p.text), [
          'Alpha',
          ' Beta',
        ]);
        expect(
          controller.document.paragraphs.last.properties.pageBreakBefore,
          isTrue,
        );
        expect(controller.pageCount, 2);
        controller.undo();
        expect(controller.document.paragraphs.single.text, 'Alpha Beta');
        expect(controller.canUndo, isFalse);
        controller.redo();
      }
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      expect(reopened.paragraphs.last.properties.pageBreakBefore, isTrue);
    },
  );

  test(
    'Enter does not copy a one-time page or column break to the next paragraph',
    () {
      final controller = _controller();
      controller.document.paragraphs.single.properties
        ..pageBreakBefore = true
        ..columnBreakBefore = true;
      controller.caret.logicalIndex = 5;
      controller.caret.collapseSelection();
      controller.insertParagraphBreak();
      expect(
        controller.document.paragraphs.first.properties.pageBreakBefore,
        isTrue,
      );
      expect(
        controller.document.paragraphs.last.properties.pageBreakBefore,
        isFalse,
      );
      expect(
        controller.document.paragraphs.last.properties.columnBreakBefore,
        isFalse,
      );
    },
  );

  test('comment edit, reply and resolve preserve history targets', () {
    final controller = _controller('Annotated body');
    controller.insertComment(text: 'Original comment', author: 'Ada');
    controller.endCommentEdit();
    final comment = controller.document.comments.single;
    controller.updateComment(comment.id, text: 'Edited comment');
    controller.replyToComment(comment.id, text: 'Reply', author: 'Grace');
    expect(controller.document.comments.first, same(comment));
    controller.setCommentResolved(comment.id, true);

    for (var cycle = 0; cycle < 3; cycle++) {
      expect(controller.document.comments.map((c) => c.text), [
        'Edited comment',
        'Reply',
      ]);
      expect(controller.document.comments.first.resolved, isTrue);
      for (var step = 0; step < 4; step++) {
        controller.undo();
      }
      expect(controller.document.comments, isEmpty);
      for (var step = 0; step < 4; step++) {
        controller.redo();
      }
    }
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(reopened.comments.map((c) => c.text), ['Edited comment', 'Reply']);
    expect(reopened.comments.first.resolved, isTrue);
  });

  test(
    'deleting a comment from its pane restores body anchors and edit history',
    () {
      final controller = _controller('Annotated body');
      controller.insertComment(text: 'Original comment');
      final comment = controller.document.comments.single;
      controller.updateComment(comment.id, text: 'Edited comment');
      controller.beginCommentEdit(comment.id);
      controller.deleteComment(comment.id);
      expect(controller.document.comments, isEmpty);
      expect(
        controller.document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .expand((r) => r.commentIds),
        isEmpty,
      );
      controller.undo();
      expect(controller.document.comments.single, same(comment));
      expect(controller.document.paragraphs.single.text, 'Annotated body');
      expect(
        controller.document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .expand((r) => r.commentIds),
        contains(comment.id),
      );
      controller.undo();
      expect(controller.document.comments.single.text, 'Original comment');
      controller.redo();
      expect(controller.document.comments.single.text, 'Edited comment');
    },
  );

  test('formatting and style commands apply to every selected paragraph', () {
    final controller = _controller('First');
    controller.document.sections.single.blocks.add(
      WmlParagraph(inlines: [WmlRun(text: 'Second')]),
    );
    controller.relayout();
    controller.selectAll();
    controller.applyStyle('Quote');
    expect(controller.document.paragraphs.map((p) => p.properties.styleId), [
      'Quote',
      'Quote',
    ]);
    controller.undo();
    expect(controller.document.paragraphs.map((p) => p.properties.styleId), [
      null,
      null,
    ]);
    controller.selectAll();
    controller.markClean();
    controller.setDropCap(3);
    controller.setParagraphShading('FFFF00');
    controller.setParagraphBorder('003366');
    expect(controller.isDirty, isTrue);
    expect(
      controller.document.paragraphs.map((p) => p.properties.dropCapLines),
      [3, 3],
    );
    expect(
      controller.document.paragraphs.map((p) => p.properties.shadingFill),
      ['FFFF00', 'FFFF00'],
    );
    expect(
      controller.document.paragraphs.map((p) => p.properties.borderColor),
      ['003366', '003366'],
    );
    for (var step = 0; step < 3; step++) {
      controller.undo();
    }
    expect(
      controller.document.paragraphs.map((p) => p.properties.dropCapLines),
      [0, 0],
    );
    expect(
      controller.document.paragraphs.map((p) => p.properties.shadingFill),
      [null, null],
    );
    expect(
      controller.document.paragraphs.map((p) => p.properties.borderColor),
      [null, null],
    );
    for (var step = 0; step < 3; step++) {
      controller.redo();
    }
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(reopened.paragraphs.map((p) => p.properties.dropCapLines), [3, 3]);
    expect(reopened.paragraphs.map((p) => p.properties.shadingFill), [
      'FFFF00',
      'FFFF00',
    ]);
    expect(reopened.paragraphs.map((p) => p.properties.borderColor), [
      '003366',
      '003366',
    ]);
  });

  test('section flags and revision tracking are dirty, reversible edits', () {
    final controller = _controller();
    final section = controller.document.sections.single;
    controller.setDifferentFirstPage(true);
    controller.setDifferentOddEven(true);
    controller.setLinkToPrevious(false);
    controller.setLineNumbers(true);
    controller.setTrackRevisions(true);
    expect(controller.isDirty, isTrue);
    for (var cycle = 0; cycle < 2; cycle++) {
      expect(section.differentFirstPage, isTrue);
      expect(section.differentOddEven, isTrue);
      expect(section.linkToPrevious, isFalse);
      expect(section.lineNumbers, isTrue);
      expect(controller.document.trackRevisions, isTrue);
      for (var step = 0; step < 5; step++) {
        controller.undo();
      }
      expect(section.differentFirstPage, isFalse);
      expect(section.differentOddEven, isFalse);
      expect(section.linkToPrevious, isTrue);
      expect(section.lineNumbers, isFalse);
      expect(controller.document.trackRevisions, isFalse);
      for (var step = 0; step < 5; step++) {
        controller.redo();
      }
    }
    controller.setMode(OfficeInteractionMode.viewing);
    controller.setTrackRevisions(false);
    expect(controller.document.trackRevisions, isTrue);
  });

  test('moving and restyling an existing ruler tab creates a history step', () {
    final controller = _controller();
    final paragraph = controller.document.paragraphs.single;
    paragraph.properties.tabs.add(const WmlTabStop(position: 36));
    controller.beginRulerEdit();
    controller.previewRulerEdit(
      const WordRulerEdit(
        tabs: [
          WmlTabStop(
            position: 72,
            alignment: WmlTabAlignment.right,
            leader: WmlTabLeader.dot,
          ),
        ],
      ),
    );
    controller.commitRulerEdit();
    expect(controller.isDirty, isTrue);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(paragraph.properties.tabs.single.position, 36);
    expect(paragraph.properties.tabs.single.alignment, WmlTabAlignment.left);
    expect(paragraph.properties.tabs.single.leader, WmlTabLeader.none);
    controller.redo();
    expect(paragraph.properties.tabs.single.position, 72);
    expect(paragraph.properties.tabs.single.alignment, WmlTabAlignment.right);
    expect(paragraph.properties.tabs.single.leader, WmlTabLeader.dot);
  });

  test('inserting a table updates visible layout before another edit', () {
    final controller = _controller();
    controller.insertTable(rows: 2, columns: 3);
    final table = controller.document.sections.single.blocks
        .whereType<WmlTable>()
        .single;
    expect(
      controller.documentLaidOut.pages
          .expand((p) => p.frames)
          .where((b) => identical(b.table, table)),
      hasLength(6),
    );
    controller.undo();
    expect(
      controller.documentLaidOut.pages
          .expand((p) => p.frames)
          .where((b) => b.table != null),
      isEmpty,
    );
    controller.redo();
    expect(
      controller.documentLaidOut.pages
          .expand((p) => p.frames)
          .where((b) => identical(b.table, table)),
      hasLength(6),
    );
  });

  test('inserting a field updates visible layout immediately', () {
    final controller = _controller('Body');
    controller.document.properties.title = 'Reference title';
    controller.insertField(WmlFieldKind.title);
    expect(controller.document.paragraphs.map((p) => p.text), [
      'Body',
      'Reference title',
    ]);
    expect(
      controller.documentLaidOut.pages
          .expand((p) => p.lines)
          .any((line) => line.paragraphIndex == 1),
      isTrue,
    );
  });

  test('selected hyperlink is dirty, undoable and preserves selected text', () {
    final controller = _controller('Before selected after');
    controller.caret
      ..selectionAnchor = 7
      ..logicalIndex = 15;
    controller.insertHyperlink(
      text: 'ignored display',
      target: 'https://example.com/link',
    );
    expect(controller.isDirty, isTrue);
    expect(controller.document.paragraphs.single.text, 'Before selected after');
    for (var cycle = 0; cycle < 3; cycle++) {
      final runs = controller.document.paragraphs.single.inlines
          .whereType<WmlRun>();
      expect(
        runs.where((r) => r.hyperlink != null).map((r) => r.text).join(),
        'selected',
      );
      controller.undo();
      expect(
        controller.document.paragraphs.single.inlines.whereType<WmlRun>().every(
          (r) => r.hyperlink == null,
        ),
        isTrue,
      );
      expect(
        controller.document.paragraphs.single.text,
        'Before selected after',
      );
      controller.redo();
    }
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(
      reopened.paragraphs.single.inlines
          .whereType<WmlRun>()
          .where((r) => r.hyperlink != null)
          .single
          .hyperlink!
          .url,
      'https://example.com/link',
    );
  });

  test('collapsed hyperlink insertion replays as a single rich edit', () {
    final controller = _controller('Before after');
    controller.caret.logicalIndex = 7;
    controller.caret.collapseSelection();
    controller.insertHyperlink(
      text: 'link ',
      target: 'https://example.com/link',
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(controller.document.paragraphs.single.text, 'Before link after');
      final run = controller.document.paragraphs.single.inlines
          .whereType<WmlRun>()
          .where((r) => r.hyperlink != null)
          .single;
      expect(run.text, 'link ');
      expect(run.properties.underline, WmlUnderline.single);
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'Before after');
      expect(controller.canUndo, isFalse);
      controller.redo();
    }
  });

  test(
    'hyperlink across paragraphs preserves text and paragraph boundaries',
    () {
      final controller = _controller('First span');
      controller.document.sections.single.blocks.add(
        WmlParagraph(inlines: [WmlRun(text: 'Second span')]),
      );
      controller.relayout();
      controller.caret
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 6
        ..paragraphIndex = 1
        ..logicalIndex = 6;
      controller.insertHyperlink(text: 'unused label', target: '#bookmark');
      expect(controller.document.paragraphs.map((p) => p.text), [
        'First span',
        'Second span',
      ]);
      expect(
        controller.document.paragraphs.map(
          (p) => p.inlines
              .whereType<WmlRun>()
              .where((r) => r.hyperlink != null)
              .map((r) => r.text)
              .join(),
        ),
        ['span', 'Second'],
      );
      controller.undo();
      expect(
        controller.document.paragraphs
            .expand((p) => p.inlines)
            .whereType<WmlRun>()
            .every((r) => r.hyperlink == null),
        isTrue,
      );
      controller.redo();
      expect(controller.document.paragraphs.map((p) => p.text), [
        'First span',
        'Second span',
      ]);
    },
  );

  test('delete history stays with its target after caret navigation', () {
    final controller = _controller('First');
    controller.document.sections.single.blocks.add(
      WmlParagraph(inlines: [WmlRun(text: 'Second')]),
    );
    controller.relayout();
    controller.caret.logicalIndex = 5;
    controller.caret.collapseSelection();
    controller.deleteSelectionOr(backward: true);
    expect(controller.document.paragraphs.first.text, 'Firs');
    controller.jumpToParagraph(1);
    controller.undo();
    expect(controller.document.paragraphs.map((p) => p.text), [
      'First',
      'Second',
    ]);
    controller.redo();
    expect(controller.document.paragraphs.map((p) => p.text), [
      'Firs',
      'Second',
    ]);
  });

  test(
    'deleting part of a multi-digit note mark is atomic and undo restores its reference',
    () {
      final controller = _controller('Body');
      controller.document.footnotes.add(WmlNote(id: 11, endnote: false));
      controller.caret.logicalIndex = 2;
      controller.caret.collapseSelection();
      controller.insertFootnote(text: 'Referenced note');
      expect(controller.document.paragraphs.single.text, 'Bo12dy');
      controller.caret
        ..selectionAnchor = 2
        ..logicalIndex = 3;
      controller.deleteSelectionOr(backward: false);
      expect(controller.document.paragraphs.single.text, 'Body');
      expect(controller.caret.logicalIndex, 2);
      controller.undo();
      final reference = controller.document.paragraphs.single.inlines
          .whereType<WmlRun>()
          .where((r) => r.noteRefId != null)
          .single;
      expect(reference.noteRefId, 12);
      expect(reference.text, '12');
      controller.redo();
      expect(controller.document.paragraphs.single.text, 'Body');
    },
  );

  test('Enter replaces the selected text in one history step', () {
    final controller = _controller('Alpha selected Beta');
    controller.caret
      ..selectionAnchor = 5
      ..logicalIndex = 14;
    controller.insertParagraphBreak();
    expect(controller.document.paragraphs.map((p) => p.text), [
      'Alpha',
      ' Beta',
    ]);
    controller.undo();
    expect(controller.document.paragraphs.single.text, 'Alpha selected Beta');
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(controller.document.paragraphs.map((p) => p.text), [
      'Alpha',
      ' Beta',
    ]);
  });

  test(
    'citation insertion preserves surrounding text and replays its native field',
    () {
      final controller = _controller();
      controller.caret.logicalIndex = 5;
      controller.caret.collapseSelection();
      controller.insertCitation(
        WmlCitation(
          tag: 'ada2025',
          author: 'Ada',
          title: 'Notes',
          year: '2025',
        ),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(
          controller.document.paragraphs.single.text,
          'Alpha (Ada 2025) Beta',
        );
        expect(controller.document.citations.single.tag, 'ada2025');
        final field = controller.document.paragraphs.single.inlines
            .whereType<WmlRun>()
            .where((r) => r.fieldInstruction != null)
            .single;
        expect(
          WordFields.kindOf(field.fieldInstruction),
          WmlFieldKind.citation,
        );
        controller.undo();
        expect(controller.document.paragraphs.single.text, 'Alpha Beta');
        expect(controller.document.citations, isEmpty);
        controller.redo();
      }
      final reopened = WordDeserializer().readBytes(controller.saveBytes());
      expect(reopened.paragraphs.single.text, 'Alpha (Ada 2025) Beta');
      expect(
        reopened.paragraphs.single.inlines
            .whereType<WmlRun>()
            .where((r) => r.fieldInstruction != null)
            .single
            .fieldInstruction,
        contains('CITATION ada2025'),
      );
    },
  );

  test('index marking is a dirty reversible operation', () {
    final controller = _controller();
    controller.markIndexTerm('Alpha');
    expect(controller.isDirty, isTrue);
    expect(controller.document.indexMarks.single.term, 'Alpha');
    controller.undo();
    expect(controller.document.indexMarks, isEmpty);
    controller.redo();
    expect(controller.document.indexMarks.single.term, 'Alpha');
    expect(controller.document.indexMarks.single.paragraphIndex, 0);
  });

  test('tracked typing and deletion records participate in undo and redo', () {
    final controller = _controller('Body');
    controller.document.trackRevisions = true;
    controller.caret.logicalIndex = 4;
    controller.caret.collapseSelection();
    controller.insertText(' added');
    expect(controller.document.revisions.single.kind, WmlRevisionKind.insert);
    final inserted = controller.document.revisions.single;
    controller.undo();
    expect(controller.document.paragraphs.single.text, 'Body');
    expect(controller.document.revisions, isEmpty);
    controller.redo();
    expect(controller.document.paragraphs.single.text, 'Body added');
    expect(controller.document.revisions.single, same(inserted));

    controller.caret.logicalIndex = 2;
    controller.caret.collapseSelection();
    controller.deleteSelectionOr(backward: true);
    expect(controller.document.revisions, hasLength(2));
    expect(controller.document.revisions.last.text, 'o');
    controller.undo();
    expect(controller.document.revisions, [inserted]);
    controller.redo();
    expect(controller.document.revisions.last.kind, WmlRevisionKind.delete);
    expect(controller.document.paragraphs.single.text, 'Body added');
  });

  for (final accept in [true, false]) {
    test(
      '${accept ? 'accept' : 'reject'} all revisions handles offsets and history',
      () {
        final controller = _controller('abcXYZdef123ghi');
        final kind = accept ? WmlRevisionKind.delete : WmlRevisionKind.insert;
        controller.document.revisions.addAll([
          WmlRevision(
            id: 1,
            kind: kind,
            paragraphIndex: 0,
            start: 3,
            end: 6,
            text: 'XYZ',
          ),
          WmlRevision(
            id: 2,
            kind: kind,
            paragraphIndex: 0,
            start: 9,
            end: 12,
            text: '123',
          ),
        ]);
        if (accept) {
          controller.acceptAllRevisions();
        } else {
          controller.rejectAllRevisions();
        }
        expect(controller.isDirty, isTrue);
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(controller.document.paragraphs.single.text, 'abcdefghi');
          expect(controller.document.revisions, isEmpty);
          controller.undo();
          expect(controller.document.paragraphs.single.text, 'abcXYZdef123ghi');
          expect(controller.document.revisions.map((r) => r.accepted), [
            null,
            null,
          ]);
          controller.redo();
        }
      },
    );
  }

  test('column break replays and exports as one history step', () {
    final controller = _controller();
    controller.document.sections.single.columnCount = 2;
    controller.caret.logicalIndex = 5;
    controller.caret.collapseSelection();
    controller.insertColumnBreak();
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(
        controller.document.paragraphs.last.properties.columnBreakBefore,
        isTrue,
      );
      controller.undo();
      expect(controller.document.paragraphs.single.text, 'Alpha Beta');
      expect(controller.canUndo, isFalse);
      controller.redo();
    }
    final bytes = controller.saveBytes();
    final xml = XmlDocument.parse(
      OpcPackage.openBytes(bytes).getPart('/word/document.xml')!.readText(),
    ).root!;
    expect(
      _descendants(xml, 'br').where((e) => e.getAttribute('type') == 'column'),
      hasLength(1),
    );
    final reopened = WordDeserializer().readBytes(bytes);
    expect(
      reopened.paragraphs.last.inlines.whereType<WmlBreak>().any(
        (br) => br.type == WmlBreakType.column,
      ),
      isTrue,
    );
  });
}
