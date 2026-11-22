import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller({
  String text = 'Before after',
  OfficeSurfaceConfig? config,
  WmlDocument? document,
}) {
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: text),
    config: config,
  );
  addTearDown(controller.dispose);
  return controller;
}

void _at(WordEditorController controller, int offset) {
  controller.caret
    ..paragraphIndex = 0
    ..logicalIndex = offset
    ..collapseSelection();
}

List<String> _paragraphs(WordEditorController controller) => [
  for (final paragraph in controller.document.paragraphs) paragraph.text,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('inserts literal multiline text and retains empty trailing lines', () {
    final controller = _controller();
    _at(controller, 7);

    expect(
      controller.insertPlainText('<b>A & B</b>\r\n\r\nDanke\rمرحبا\n'),
      isTrue,
    );

    expect(_paragraphs(controller), [
      'Before <b>A & B</b>',
      '',
      'Danke',
      'مرحبا',
      'after',
    ]);
    expect(controller.caret.paragraphIndex, 4);
    expect(controller.caret.logicalIndex, 0);
    expect(controller.caret.isCollapsed, isTrue);
    expect(controller.isDirty, isTrue);
    final reopened = WordDeserializer().readBytes(controller.saveBytes());
    expect(reopened.paragraphs.map((paragraph) => paragraph.text), [
      'Before <b>A & B</b>',
      '',
      'Danke',
      'مرحبا',
      'after',
    ]);
  });

  test('replaces the text selection in one undo and redo step', () {
    final controller = _controller(text: 'Left selected right');
    controller.caret
      ..selectionAnchorParagraph = 0
      ..selectionAnchor = 5
      ..paragraphIndex = 0
      ..logicalIndex = 13;

    expect(controller.insertPlainText('one\ntwo'), isTrue);

    for (var cycle = 0; cycle < 3; cycle++) {
      expect(_paragraphs(controller), ['Left one', 'two right']);
      controller.undo();
      expect(_paragraphs(controller), ['Left selected right']);
      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isTrue);
      controller.redo();
    }
  });

  test('multiline history preserves earlier and later independent edits', () {
    final controller = _controller(text: 'Alpha Beta');
    _at(controller, 0);
    controller.insertText('pre ');
    _at(controller, 9);
    expect(controller.insertPlainText('\nfirst\nlast'), isTrue);
    controller.insertText('!');

    for (var cycle = 0; cycle < 3; cycle++) {
      expect(_paragraphs(controller), ['pre Alpha', 'first', 'last! Beta']);
      controller.undo();
      expect(_paragraphs(controller), ['pre Alpha', 'first', 'last Beta']);
      controller.undo();
      expect(_paragraphs(controller), ['pre Alpha Beta']);
      expect(controller.canUndo, isTrue);
      controller.undo();
      expect(_paragraphs(controller), ['Alpha Beta']);
      expect(controller.canUndo, isFalse);
      controller.redo();
      controller.redo();
      controller.redo();
    }
  });

  test('replacing the complete body preserves the final blank paragraph', () {
    final controller = _controller();
    controller.selectAll();

    expect(controller.insertPlainText('Hello\n'), isTrue);

    expect(_paragraphs(controller), ['Hello', '']);
    controller.undo();
    expect(_paragraphs(controller), ['Before after']);
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(_paragraphs(controller), ['Hello', '']);
  });

  for (final startOffset in [0, 1]) {
    for (final reversed in [false, true]) {
      test(
        'refuses partial cross-paragraph replacement from offset $startOffset '
        'with reversed selection $reversed',
        () {
          final controller = _controller(
            document: WmlDocument(
              sections: [
                WmlSection(
                  blocks: [
                    for (final text in ['Prefix', 'abc', 'def', 'Suffix'])
                      WmlParagraph(inlines: [WmlRun(text: text)]),
                  ],
                ),
              ],
            ),
          );
          _at(controller, 0);
          controller.insertText('saved ');
          controller.markClean();
          controller.caret
            ..selectionAnchorParagraph = reversed ? 2 : 1
            ..selectionAnchor = reversed ? 2 : startOffset
            ..paragraphIndex = reversed ? 1 : 2
            ..logicalIndex = reversed ? startOffset : 2;
          final before = _paragraphs(controller);
          final revision = controller.contentRevision;
          final selection = (
            paragraph: controller.caret.paragraphIndex,
            index: controller.caret.logicalIndex,
            anchorParagraph: controller.caret.selectionAnchorParagraph,
            anchor: controller.caret.selectionAnchor,
          );

          expect(controller.insertPlainText('X\nY'), isFalse);

          expect(_paragraphs(controller), before);
          expect(controller.contentRevision, revision);
          expect(controller.isDirty, isFalse);
          expect((
            paragraph: controller.caret.paragraphIndex,
            index: controller.caret.logicalIndex,
            anchorParagraph: controller.caret.selectionAnchorParagraph,
            anchor: controller.caret.selectionAnchor,
          ), selection);
          expect(controller.canUndo, isTrue);
          expect(controller.canRedo, isFalse);
          controller.undo();
          expect(_paragraphs(controller), ['Prefix', 'abc', 'def', 'Suffix']);
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(_paragraphs(controller), before);
        },
      );
    }
  }

  test('replaces a complete multi-paragraph body in one undo step', () {
    final controller = _controller(
      document: WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              for (final text in ['One', 'Two', 'Three'])
                WmlParagraph(inlines: [WmlRun(text: text)]),
            ],
          ),
        ],
      ),
    );
    controller.selectAll();

    expect(controller.insertPlainText('Hello\n\n'), isTrue);

    expect(_paragraphs(controller), ['Hello', '', '']);
    controller.undo();
    expect(_paragraphs(controller), ['One', 'Two', 'Three']);
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(_paragraphs(controller), ['Hello', '', '']);
  });

  test('empty input preserves selection, clean state and redo history', () {
    final controller = _controller(text: 'Body');
    controller.insertText('draft ');
    controller.undo();
    controller.markClean();
    controller.selectAll();
    final revision = controller.contentRevision;
    final selection = controller.caret.normalizedRange;

    expect(controller.insertPlainText(''), isFalse);

    expect(_paragraphs(controller), ['Body']);
    expect(controller.caret.normalizedRange, selection);
    expect(controller.contentRevision, revision);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(controller.canRedo, isTrue);
  });

  test('whitespace is literal content rather than an empty-input shortcut', () {
    final controller = _controller(text: 'Body');
    _at(controller, 0);

    expect(controller.insertPlainText(' \n\t\n'), isTrue);

    expect(_paragraphs(controller), [' ', '\t', 'Body']);
    controller.undo();
    expect(_paragraphs(controller), ['Body']);
    expect(controller.canUndo, isFalse);
  });

  for (final mode in [
    OfficeInteractionMode.viewing,
    OfficeInteractionMode.selecting,
  ]) {
    test(
      '${mode.name} refuses plain-text insertion without history changes',
      () {
        final controller = _controller(
          text: 'Body',
          config: OfficeSurfaceConfig(mode: mode),
        );
        final revision = controller.contentRevision;

        expect(controller.insertPlainText('blocked\ntext'), isFalse);

        expect(_paragraphs(controller), ['Body']);
        expect(controller.contentRevision, revision);
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  test('document protection remains effective for plain-text insertion', () {
    final controller = _controller(text: 'Body');
    controller.setRestrictEditing(true);
    controller.markClean();
    final revision = controller.contentRevision;

    expect(controller.insertPlainText('blocked\ntext'), isFalse);

    expect(_paragraphs(controller), ['Body']);
    expect(controller.contentRevision, revision);
    expect(controller.isDirty, isFalse);
    controller.undo();
    expect(controller.config.allowsMutation, isTrue);
    expect(controller.canUndo, isFalse);
  });

  test('a selected visual is not replaced using a stale text caret', () {
    final paragraph = WmlParagraph(inlines: [WmlRun(text: 'Body')]);
    final visual = WmlVisual(
      visual: OfficeVisual(
        kind: OfficeVisualKind.chartColumn,
        title: 'Selected chart',
        points: OfficeVisual.sampleSeries(),
      ),
    );
    final controller = _controller(
      document: WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph, visual]),
        ],
      ),
    );
    controller.selectVisual(visual);
    final revision = controller.contentRevision;

    expect(controller.insertPlainText('blocked\ntext'), isFalse);

    expect(paragraph.text, 'Body');
    expect(controller.document.sections.single.blocks, [
      same(paragraph),
      same(visual),
    ]);
    expect(controller.selectedVisual, same(visual));
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
  });

  for (final endnote in [false, true]) {
    test('active ${endnote ? 'endnote' : 'footnote'} does not redirect '
        'plain-text insertion into the body', () {
      final note = WmlNote(
        id: 1,
        endnote: endnote,
        addReference: false,
        addReferenceSpace: false,
        paragraphs: [
          WmlParagraph(inlines: [WmlRun(text: 'Note text')]),
        ],
      );
      final document = WmlDocument.empty(text: 'Body text');
      (endnote ? document.endnotes : document.footnotes).add(note);
      final controller = _controller(document: document);
      _at(controller, 4);
      const selection = TextSelection.collapsed(offset: 5);
      controller.setNoteEditingTarget(note, selection);
      final revision = controller.contentRevision;

      expect(controller.insertPlainText('wrong story\ntext'), isFalse);

      expect(_paragraphs(controller), ['Body text']);
      expect(controller.noteEditText(note), 'Note text');
      expect(controller.noteEditingTarget?.note, same(note));
      expect(controller.noteEditingTarget?.selection, selection);
      expect(controller.contentRevision, revision);
      expect(controller.isDirty, isFalse);
      expect(controller.canUndo, isFalse);

      controller.clearNoteEditingTarget();
      expect(controller.insertPlainText('!'), isTrue);
      expect(_paragraphs(controller), ['Body! text']);
      controller.undo();
      expect(_paragraphs(controller), ['Body text']);
      expect(controller.canUndo, isFalse);
    });
  }

  for (final selection in [false, true]) {
    test(
      'unsupported control split fails before ${selection ? 'replacement' : 'insertion'}',
      () {
        final package = OpcPackage.create(OpcPackageKind.word);
        package
            .getPart('/word/document.xml')!
            .writeText(
              '<w:document xmlns:w="${OfficeNamespaces.w}">'
              '<w:body><w:p><w:r><w:t>ab</w:t></w:r>'
              '<w:sdt><w:sdtPr><w:id w:val="42"/></w:sdtPr>'
              '<w:sdtContent><w:r><w:t>XYZ</w:t></w:r></w:sdtContent>'
              '</w:sdt><w:r><w:t>cd</w:t></w:r></w:p>'
              '<w:sectPr/></w:body></w:document>',
            );
        final controller = _controller(
          document: WordDeserializer().read(package),
        );
        _at(controller, 3);
        if (selection) controller.caret.logicalIndex = 4;
        final revision = controller.contentRevision;

        expect(
          () => controller.insertPlainText('First\nSecond'),
          throwsUnsupportedError,
        );

        expect(_paragraphs(controller), ['abXYZcd']);
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
        _at(controller, 7);
        expect(controller.insertPlainText('!'), isTrue);
        expect(_paragraphs(controller), ['abXYZcd!']);
        controller.undo();
        expect(_paragraphs(controller), ['abXYZcd']);
        expect(controller.canUndo, isFalse);
      },
    );
  }

  test('insertion leaves the in-app clipboard unchanged', () async {
    final clipboard = OfficeClipboard.instance;
    final previousUseSystem = clipboard.useSystem;
    clipboard.useSystem = false;
    addTearDown(() {
      clipboard.clear();
      clipboard.useSystem = previousUseSystem;
    });
    await clipboard.write(OfficeClipboardPayload.fromPlain('clipboard text'));
    final previous = clipboard.local;
    final controller = _controller(text: 'Body');
    _at(controller, 0);

    expect(controller.insertPlainText('Inserted\n'), isTrue);

    expect(_paragraphs(controller), ['Inserted', 'Body']);
    expect(clipboard.local, same(previous));
    expect(clipboard.local!.plain, 'clipboard text');
  });

  test('coalesces notifications until the complete insertion is visible', () {
    final previous = OfficeController.coalesceEditNotifications;
    OfficeController.coalesceEditNotifications = true;
    addTearDown(() => OfficeController.coalesceEditNotifications = previous);
    final controller = _controller(text: 'Body');
    _at(controller, 0);
    final revision = controller.contentRevision;
    final observed = <List<String>>[];
    controller.addListener(() => observed.add(_paragraphs(controller)));

    expect(controller.insertPlainText('A\nB\nC'), isTrue);

    expect(observed, [
      ['A', 'B', 'CBody'],
    ]);
    expect(controller.contentRevision, revision + 1);
  });
}
