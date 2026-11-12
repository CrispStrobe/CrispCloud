import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _metadata =
    '<w:sdtPr><w:id w:val="42"/>'
    '<w:alias w:val="Customer title"/><w:tag w:val="customer-title"/>'
    '<w:dataBinding w:storeItemID="{AABBCCDD}" w:xpath="/customer/title"/>'
    '</w:sdtPr><w:sdtEndPr><w:rPr><w:i/></w:rPr></w:sdtEndPr>';

String _paragraphXml(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

String _controlXml(String content) =>
    '<w:sdt>$_metadata'
    '<w:sdtContent>$content</w:sdtContent></w:sdt>';

WordEditorController _controller(String body) {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}" xmlns:r="${OfficeNamespaces.r}">'
        '<w:body>$body<w:sectPr/></w:body></w:document>',
      );
  final controller = WordEditorController(
    document: WordDeserializer().read(package),
  );
  addTearDown(controller.dispose);
  return controller;
}

WordEditorController _inline([String content = 'XYZ']) => _controller(
  '<w:p><w:r><w:t>ab</w:t></w:r>'
  '${_controlXml(content.isEmpty ? '' : '<w:r><w:t>$content</w:t></w:r>')}'
  '<w:r><w:t>cd</w:t></w:r></w:p>',
);

WordEditorController _auxiliaryController(String story) {
  final package = OpcPackage.create(OpcPackageKind.word);
  final comment = story == 'comment';
  final header = story == 'header';
  final uri = comment ? '/word/comments.xml' : '/word/${story}1.xml';
  final root = comment
      ? 'comments'
      : header
      ? 'hdr'
      : 'ftr';
  final body =
      '${_controlXml(_paragraphXml('Controlled'))}'
      '${_paragraphXml('Following')}';
  package.createPart(
    uri,
    comment
        ? OfficeContentTypes.wordComments
        : header
        ? OfficeContentTypes.wordHeader
        : OfficeContentTypes.wordFooter,
    utf8.encode(
      '<w:$root xmlns:w="${OfficeNamespaces.w}">'
      '${comment ? '<w:comment w:id="7" w:author="Source author">$body</w:comment>' : body}'
      '</w:$root>',
    ),
  );
  final relationship = package
      .relationshipsFor('/word/document.xml')
      .add(
        type: comment
            ? RelationshipTypes.comments
            : header
            ? RelationshipTypes.header
            : RelationshipTypes.footer,
        target: uri.substring('/word/'.length),
      );
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}" xmlns:r="${OfficeNamespaces.r}">'
        '<w:body>${_paragraphXml('Body remains')}<w:sectPr>'
        '${comment ? '' : '<w:${story}Reference w:type="default" r:id="${relationship.id}"/>'}'
        '</w:sectPr></w:body></w:document>',
      );
  final controller = WordEditorController(
    document: WordDeserializer().read(package),
  );
  addTearDown(controller.dispose);
  return controller;
}

void _at(WordEditorController controller, WmlParagraph paragraph, int offset) {
  controller.caret
    ..paragraphIndex = controller.document.paragraphs.toList().indexOf(
      paragraph,
    )
    ..logicalIndex = offset
    ..collapseSelection();
}

List<XmlElement> _all(XmlElement root, String localName) => [
  for (final child in root.childElements) ...[
    if (child.namespaceUri == OfficeNamespaces.w &&
        child.localName == localName)
      child,
    ..._all(child, localName),
  ],
];

XmlElement _native(WordEditorController controller) {
  final package = OpcPackage.openBytes(controller.saveBytes());
  return XmlDocument.parse(
    package.getPart('/word/document.xml')!.readText(),
  ).root!;
}

void _expectMetadata(XmlElement root) {
  final control = _all(root, 'sdt').single;
  final properties = control.firstChild('sdtPr')!;
  expect(properties.firstChild('id')!.getAttribute('val'), '42');
  expect(properties.firstChild('alias')!.getAttribute('val'), 'Customer title');
  expect(properties.firstChild('tag')!.getAttribute('val'), 'customer-title');
  expect(
    properties.firstChild('dataBinding')!.getAttribute('storeItemID'),
    '{AABBCCDD}',
  );
  expect(
    properties.firstChild('dataBinding')!.getAttribute('xpath'),
    '/customer/title',
  );
  expect(
    control.firstChild('sdtEndPr')!.firstChild('rPr')!.firstChild('i'),
    isNotNull,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'block control split, edit and formatting stay in their original owner',
    () {
      final controller = _controller(
        _paragraphXml('Before') +
            _controlXml(_paragraphXml('Alpha Beta')) +
            _paragraphXml('After'),
      );
      final section = controller.document.sections.single;
      final control = section.blocks.whereType<WmlContentControlBlock>().single;
      final original = control.blocks.single as WmlParagraph;
      _at(controller, original, 5);
      controller.insertText('!');
      controller.insertParagraphBreak();
      final tail = control.blocks.last as WmlParagraph;
      controller.caret
        ..selectionAnchor = 0
        ..logicalIndex = tail.text.length;
      controller.applyRunFormat((props) => props.bold = true);
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(section.blocks, hasLength(3));
        expect(section.blocks[1], same(control));
        expect(control.blocks, [same(original), same(tail)]);
        expect(original.text, 'Alpha!');
        expect(tail.text, ' Beta');
        expect(tail.inlines.whereType<WmlRun>().single.properties.bold, isTrue);
        final native = _native(controller);
        _expectMetadata(native);
        expect(
          _all(
            native,
            'sdtContent',
          ).single.childrenNamed('p').map((p) => p.text),
          ['Alpha!', ' Beta'],
        );
        expect(
          native.firstChild('body')!.childrenNamed('p').map((p) => p.text),
          ['Before', 'After'],
        );
        final reopened = WordDeserializer().readBytes(controller.saveBytes());
        expect(reopened.paragraphs.map((p) => p.text), [
          'Before',
          'Alpha!',
          ' Beta',
          'After',
        ]);
        controller.undo();
        controller.undo();
        controller.undo();
        expect(control.blocks.single, same(original));
        expect(original.text, 'Alpha Beta');
        controller.redo();
        controller.redo();
        controller.redo();
      }
    },
  );

  test(
    'block insertion from a nested table stays inside the enclosing control',
    () {
      final controller = _controller(_controlXml(_paragraphXml('Anchor')));
      final section = controller.document.sections.single;
      final control = section.blocks.single as WmlContentControlBlock;
      final anchor = control.blocks.single as WmlParagraph;
      _at(controller, anchor, anchor.text.length);
      controller.insertTable(rows: 1, columns: 1);
      final table = control.blocks.last as WmlTable;
      final cell = table.rows.single.cells.single.blocks.single as WmlParagraph;
      _at(controller, cell, 0);
      controller.insertText('Cell');
      controller.insertPicture(
        OfficeVisual(
          kind: OfficeVisualKind.chartColumn,
          title: 'Inside control',
          points: OfficeVisual.sampleSeries(),
        ),
      );
      final picture = control.blocks.last as WmlVisual;
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(section.blocks.single, same(control));
        expect(control.blocks, [same(anchor), same(table), same(picture)]);
        expect(cell.text, 'Cell');
        final native = _native(controller);
        _expectMetadata(native);
        final content = _all(native, 'sdtContent').single;
        expect(content.firstChild('tbl'), isNotNull);
        expect(_all(content, 'drawing'), hasLength(1));
        controller.undo();
        controller.undo();
        controller.undo();
        expect(control.blocks.single, same(anchor));
        controller.redo();
        controller.redo();
        controller.redo();
      }
      controller.selectVisual(picture);
      controller.deleteSelectedVisual();
      expect(control.blocks, [same(anchor), same(table)]);
      controller.undo();
      expect(control.blocks.last, same(picture));
      controller.deleteTable(table: table);
      expect(control.blocks, [same(anchor), same(picture)]);
      controller.undo();
      expect(control.blocks, [same(anchor), same(table), same(picture)]);
    },
  );

  test('a paragraph inside a frame and table uses its exact child list', () {
    final controller = _controller(_controlXml(_paragraphXml('Placeholder')));
    final control =
        controller.document.sections.single.blocks.single
            as WmlContentControlBlock;
    final paragraph = WmlParagraph(inlines: [WmlRun(text: 'abcd')]);
    final frame = WmlFrame(blocks: [paragraph]);
    final cell = WmlTableCell(blocks: [frame]);
    final table = WmlTable(
      rows: [
        WmlTableRow(cells: [cell]),
      ],
    );
    control.blocks
      ..clear()
      ..add(table);
    controller.relayout();
    _at(controller, paragraph, 2);
    controller.insertParagraphBreak();
    final tail = frame.blocks.last as WmlParagraph;
    for (var cycle = 0; cycle < 3; cycle++) {
      expect(control.blocks.single, same(table));
      expect(cell.blocks.single, same(frame));
      expect(frame.blocks, [same(paragraph), same(tail)]);
      expect(paragraph.text, 'ab');
      expect(tail.text, 'cd');
      controller.undo();
      expect(frame.blocks.single, same(paragraph));
      expect(paragraph.text, 'abcd');
      controller.redo();
    }
    _at(controller, tail, 0);
    controller.deleteSelectionOr(backward: true);
    expect(frame.blocks.single, same(paragraph));
    expect(paragraph.text, 'abcd');
    controller.undo();
    expect(frame.blocks, [same(paragraph), same(tail)]);
  });

  test(
    'inline control text and formatting edits retain native wrapper metadata',
    () {
      final controller = _inline();
      final paragraph = controller.document.paragraphs.single;
      _at(controller, paragraph, 3);
      controller.insertText('!');
      controller.caret
        ..selectionAnchor = 2
        ..logicalIndex = 6;
      controller.applyRunFormat((props) => props.bold = true);
      for (var cycle = 0; cycle < 3; cycle++) {
        final native = _native(controller);
        _expectMetadata(native);
        final content = _all(native, 'sdtContent').single;
        expect(content.text, 'X!YZ');
        expect(_all(content, 'b'), isNotEmpty);
        expect(paragraph.text, 'abX!YZcd');
        controller.undo();
        controller.undo();
        expect(paragraph.text, 'abXYZcd');
        expect(
          paragraph.inlines.whereType<WmlContentControlBoundary>(),
          hasLength(2),
        );
        controller.redo();
        controller.redo();
      }
    },
  );

  for (final offset in [2, 5]) {
    test(
      'splitting at inline control boundary $offset preserves one complete wrapper',
      () {
        final controller = _inline();
        final original = controller.document.paragraphs.single;
        _at(controller, original, offset);
        controller.insertParagraphBreak();
        for (var cycle = 0; cycle < 3; cycle++) {
          final paragraphs = controller.document.paragraphs.toList();
          expect(
            paragraphs.map((p) => p.text),
            offset == 2 ? ['ab', 'XYZcd'] : ['abXYZ', 'cd'],
          );
          expect(
            paragraphs
                .expand((p) => p.inlines)
                .whereType<WmlContentControlBoundary>(),
            hasLength(2),
          );
          final native = _native(controller);
          _expectMetadata(native);
          expect(_all(native, 'sdtContent').single.text, 'XYZ');
          controller.undo();
          expect(controller.document.paragraphs.single, same(original));
          expect(original.text, 'abXYZcd');
          controller.redo();
        }
      },
    );
  }

  test('an empty inline control moves to exactly one side of a split', () {
    final controller = _inline('');
    final original = controller.document.paragraphs.single;
    _at(controller, original, 2);
    controller.insertParagraphBreak();
    final paragraphs = controller.document.paragraphs.toList();
    expect(paragraphs.map((p) => p.text), ['ab', 'cd']);
    expect(
      paragraphs.first.inlines.whereType<WmlContentControlBoundary>(),
      isEmpty,
    );
    expect(
      paragraphs.last.inlines.whereType<WmlContentControlBoundary>(),
      hasLength(2),
    );
    _expectMetadata(_native(controller));
    controller.undo();
    expect(
      original.inlines.whereType<WmlContentControlBoundary>(),
      hasLength(2),
    );
    controller.redo();
    _expectMetadata(_native(controller));
  });

  test('pasting into an empty inline control retains its wrapper', () async {
    OfficeClipboard.instance.useSystem = false;
    addTearDown(() {
      OfficeClipboard.instance.clear();
      OfficeClipboard.instance.useSystem = true;
    });
    final controller = _controller('<w:p>${_controlXml('')}</w:p>');
    final paragraph = controller.document.paragraphs.single;
    _at(controller, paragraph, 0);
    await OfficeClipboard.instance.write(
      OfficeClipboardPayload(
        kind: OfficeClipboardKind.richText,
        plain: 'Filled',
        wordBlocks: [
          WmlParagraph(inlines: [WmlRun(text: 'Filled')]),
        ],
      ),
    );
    await controller.pasteFromClipboard();
    expect(controller.document.paragraphs.single, same(paragraph));
    expect(paragraph.text, 'Filled');
    final native = _native(controller);
    _expectMetadata(native);
    expect(_all(native, 'sdtContent').single.text, 'Filled');
    controller.undo();
    expect(paragraph.text, '');
    expect(
      paragraph.inlines.whereType<WmlContentControlBoundary>(),
      hasLength(2),
    );
  });

  for (final selection in [false, true]) {
    test(
      'unsupported inline split rejects before ${selection ? 'selection replacement' : 'typing history'} changes',
      () {
        final controller = _inline();
        final paragraph = controller.document.paragraphs.single;
        _at(controller, paragraph, 3);
        if (selection) controller.caret.logicalIndex = 4;
        expect(controller.insertParagraphBreak, throwsUnsupportedError);
        expect(paragraph.text, 'abXYZcd');
        expect(controller.document.paragraphs, hasLength(1));
        expect(controller.commands.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
        _at(controller, paragraph, paragraph.text.length);
        controller.insertText('!');
        expect(paragraph.text, 'abXYZcd!');
        controller.undo();
        expect(paragraph.text, 'abXYZcd');
        expect(controller.commands.canUndo, isFalse);
        _expectMetadata(_native(controller));
      },
    );
  }

  for (final rich in [false, true]) {
    test(
      '${rich ? 'rich' : 'plain'} multiline paste preflights every split',
      () async {
        OfficeClipboard.instance.useSystem = false;
        addTearDown(() {
          OfficeClipboard.instance.clear();
          OfficeClipboard.instance.useSystem = true;
        });
        final controller = _inline();
        final paragraph = controller.document.paragraphs.single;
        _at(controller, paragraph, 3);
        await OfficeClipboard.instance.write(
          rich
              ? OfficeClipboardPayload(
                  kind: OfficeClipboardKind.richText,
                  plain: 'First\nSecond',
                  paragraphs: [
                    [OfficeClipboardSpan(text: 'First', props: WmlRunProps())],
                    [OfficeClipboardSpan(text: 'Second', props: WmlRunProps())],
                  ],
                )
              : OfficeClipboardPayload.fromPlain('First\nSecond'),
        );
        await expectLater(
          controller.pasteFromClipboard(),
          throwsUnsupportedError,
        );
        expect(paragraph.text, 'abXYZcd');
        expect(controller.commands.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
        _at(controller, paragraph, paragraph.text.length);
        controller.insertText('!');
        controller.undo();
        expect(paragraph.text, 'abXYZcd');
        expect(controller.commands.canUndo, isFalse);
      },
    );
  }

  test(
    'multi-paragraph inline-control deletion and joining fail before mutation',
    () {
      final controller = _inline();
      final first = controller.document.paragraphs.single;
      final last = WmlParagraph(inlines: [WmlRun(text: 'After')]);
      controller.document.sections.single.blocks.add(last);
      _at(controller, last, 0);
      expect(
        () => controller.deleteSelectionOr(backward: true),
        throwsUnsupportedError,
      );
      controller.caret
        ..selectionAnchorParagraph = 0
        ..selectionAnchor = 6
        ..paragraphIndex = 1
        ..logicalIndex = 2;
      expect(
        () => controller.deleteSelectionOr(backward: false),
        throwsUnsupportedError,
      );
      expect(controller.document.paragraphs, [same(first), same(last)]);
      expect(first.text, 'abXYZcd');
      expect(last.text, 'After');
      expect(controller.commands.canUndo, isFalse);
    },
  );

  test('notes-pane replacement validates all controlled paragraphs first', () {
    final controller = _inline();
    final controlled = controller.document.paragraphs.single;
    final body = WmlParagraph(inlines: [WmlRun(text: 'Body remains')]);
    controller.document.sections.single.blocks
      ..clear()
      ..add(body);
    final first = WmlParagraph(inlines: [WmlRun(text: 'First remains')]);
    final note = WmlNote(
      id: 1,
      endnote: false,
      addReference: false,
      paragraphs: [first, controlled],
    );
    controller.document.footnotes.add(note);
    expect(
      () => controller.setNoteText(note, 'First changed\nXcd'),
      throwsUnsupportedError,
    );
    expect(first.text, 'First remains');
    expect(controlled.text, 'abXYZcd');
    expect(controller.commands.canUndo, isFalse);
    expect(controller.isDirty, isFalse);
    expect(
      () => controller.setNoteText(note, 'First remains\nabXYZcd\nExtra'),
      throwsUnsupportedError,
    );
    expect(note.paragraphs, [same(first), same(controlled)]);
    expect(body.text, 'Body remains');
  });

  test('unsupported IME replacement leaves typing and history usable', () {
    final controller = _inline();
    final paragraph = controller.document.paragraphs.single;
    expect(() => controller.applyImeText('Xcd'), throwsUnsupportedError);
    expect(paragraph.text, 'abXYZcd');
    expect(controller.commands.canUndo, isFalse);
    expect(controller.isDirty, isFalse);
    _at(controller, paragraph, paragraph.text.length);
    controller.insertText('!');
    expect(paragraph.text, 'abXYZcd!');
    controller.undo();
    expect(paragraph.text, 'abXYZcd');
    _expectMetadata(_native(controller));
  });

  for (final inline in [false, true]) {
    test(
      'copying a native ${inline ? 'inline' : 'block'} control refuses duplicate IDs before mutation',
      () async {
        OfficeClipboard.instance.useSystem = false;
        addTearDown(() {
          OfficeClipboard.instance.clear();
          OfficeClipboard.instance.useSystem = true;
        });
        final controller = inline
            ? _inline()
            : _controller(_controlXml(_paragraphXml('Anchor')));
        final paragraph = controller.document.paragraphs.single;
        final before = paragraph.text;
        await OfficeClipboard.instance.write(
          OfficeClipboardPayload(
            kind: OfficeClipboardKind.richText,
            plain: before,
            wordBlocks: [
              WmlClone.block(controller.document.sections.single.blocks.single),
            ],
          ),
        );
        _at(controller, paragraph, 0);
        controller.caret.logicalIndex = 1;
        await expectLater(
          controller.pasteFromClipboard(),
          throwsUnsupportedError,
        );
        expect(paragraph.text, before);
        expect(controller.document.paragraphs.single, same(paragraph));
        expect(controller.commands.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
        _expectMetadata(_native(controller));
        _at(controller, paragraph, paragraph.text.length);
        controller.insertText('!');
        controller.undo();
        expect(paragraph.text, before);
        expect(controller.commands.canUndo, isFalse);
      },
    );
  }

  test(
    'notes-pane edits retain nested control topology and revision identities',
    () {
      final controller = _controller(_controlXml(_paragraphXml('abXYZcd')));
      final control =
          controller.document.sections.single.blocks.single
              as WmlContentControlBlock;
      final original = control.blocks.single as WmlParagraph;
      final bodyParagraph = WmlParagraph(
        inlines: [WmlRun(text: 'Body remains')],
      );
      controller.document.sections.single.blocks
        ..clear()
        ..add(bodyParagraph);
      final tableCell = WmlParagraph(inlines: [WmlRun(text: 'Excluded table')]);
      final table = WmlTable(
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [tableCell]),
            ],
          ),
        ],
      );
      final note = WmlNote(
        id: 1,
        endnote: false,
        addReference: false,
        blocks: [control, table],
      );
      controller.document.footnotes.add(note);
      final revision = WordRevisions.record(
        controller.document,
        kind: WmlRevisionKind.insert,
        paragraphIndex: -1,
        paragraph: original,
        start: 2,
        end: 5,
        text: 'XYZ',
        author: 'Original reviewer',
      );
      controller.document.trackRevisions = false;
      expect(controller.noteEditText(note), 'abXYZcd');
      controller.setNoteText(note, '--abXYZcd\nAdded line');
      controller.commitNoteEdit(note);
      final added = control.blocks.last as WmlParagraph;
      for (var cycle = 0; cycle < 3; cycle++) {
        expect(note.blocks, [same(control), same(table)]);
        expect(control.blocks, [same(original), same(added)]);
        expect(controller.noteEditText(note), '--abXYZcd\nAdded line');
        expect(revision.targetParagraph, same(original));
        expect((revision.start, revision.end), (4, 7));
        expect(tableCell.text, 'Excluded table');
        expect(bodyParagraph.text, 'Body remains');
        final bytes = controller.saveBytes();
        final package = OpcPackage.openBytes(bytes);
        final xml = XmlDocument.parse(
          package.getPart('/word/footnotes.xml')!.readText(),
        ).root!;
        _expectMetadata(xml);
        expect(
          _all(xml, 'sdtContent').single.childrenNamed('p').map((p) => p.text),
          ['--abXYZcd', 'Added line'],
        );
        final reopened = WordDeserializer().readBytes(bytes);
        expect(
          WordNotes.editableText(reopened.footnotes.single),
          '--abXYZcd\nAdded line',
        );
        controller.undo();
        expect(control.blocks.single, same(original));
        expect(original.text, 'abXYZcd');
        expect((revision.start, revision.end), (2, 5));
        controller.redo();
      }
      controller.setNoteText(note, '--abXYZcd');
      controller.commitNoteEdit(note);
      expect(control.blocks.single, same(original));
      controller.undo();
      expect(control.blocks, [same(original), same(added)]);
    },
  );

  for (final story in ['header', 'footer', 'comment']) {
    test(
      '$story native paragraph control keeps rich history and guards structural edits',
      () async {
        OfficeClipboard.instance.useSystem = false;
        addTearDown(() {
          OfficeClipboard.instance.clear();
          OfficeClipboard.instance.useSystem = true;
        });
        final controller = _auxiliaryController(story);
        final section = controller.document.sections.single;
        final parent = story == 'comment'
            ? controller.document.comments.single.paragraphs
            : story == 'header'
            ? section.header
            : section.footer;
        final paragraph = parent.first;
        final following = parent.last;
        final wrapper = paragraph.contentControlWrappers.single;
        expect(paragraph.text, 'Controlled');
        expect(following.text, 'Following');
        expect(wrapper.id, '42');
        if (story == 'comment') {
          controller.beginCommentEdit(7);
        } else {
          controller.beginHeaderFooterEdit(0, footer: story == 'footer');
        }
        controller.caret
          ..paragraphIndex = 0
          ..logicalIndex = 3
          ..collapseSelection();
        controller.insertText('++');
        controller.caret
          ..selectionAnchorParagraph = 0
          ..selectionAnchor = 0
          ..logicalIndex = paragraph.text.length;
        controller.applyRunFormat((props) => props.bold = true);
        for (var cycle = 0; cycle < 3; cycle++) {
          expect(parent, [same(paragraph), same(following)]);
          expect(paragraph.contentControlWrappers, [same(wrapper)]);
          expect(paragraph.text, 'Con++trolled');
          expect(
            paragraph.inlines.whereType<WmlRun>().every(
              (run) => run.properties.bold,
            ),
            isTrue,
          );
          expect(controller.document.paragraphs.single.text, 'Body remains');
          final bytes = controller.saveBytes();
          final package = OpcPackage.openBytes(bytes);
          final uri = story == 'comment'
              ? '/word/comments.xml'
              : '/word/${story}1.xml';
          final xml = XmlDocument.parse(package.getPart(uri)!.readText()).root!;
          _expectMetadata(xml);
          final content = _all(xml, 'sdtContent').single;
          expect(content.childrenNamed('p').single.text, 'Con++trolled');
          expect(content.childrenNamed('r'), isEmpty);
          final reopened = WordDeserializer().readBytes(bytes);
          final restored = story == 'comment'
              ? reopened.comments.single.paragraphs.first
              : story == 'header'
              ? reopened.sections.single.header.first
              : reopened.sections.single.footer.first;
          expect(restored.text, 'Con++trolled');
          expect(restored.contentControlWrappers.single.id, '42');
          controller.undo();
          controller.undo();
          expect(controller.commands.canUndo, isFalse);
          expect(paragraph.text, 'Controlled');
          expect(paragraph.contentControlWrappers, [same(wrapper)]);
          controller.redo();
          controller.redo();
        }

        controller.undo();
        controller.markClean();
        expect(controller.commands.canUndo, isTrue);
        expect(controller.commands.canRedo, isTrue);
        final inlines = List<WmlInline>.of(paragraph.inlines);
        final followingInlines = List<WmlInline>.of(following.inlines);
        (int, int, int, int) selection() => (
          controller.caret.paragraphIndex,
          controller.caret.logicalIndex,
          controller.caret.selectionAnchorParagraph,
          controller.caret.selectionAnchor,
        );
        void assertUnchanged((int, int, int, int) before) {
          expect(parent, [same(paragraph), same(following)]);
          expect(paragraph.text, 'Con++trolled');
          expect(following.text, 'Following');
          expect(paragraph.contentControlWrappers, [same(wrapper)]);
          expect(paragraph.inlines, orderedEquals(inlines));
          expect(following.inlines, orderedEquals(followingInlines));
          expect(selection(), before);
          expect(controller.commands.canUndo, isTrue);
          expect(controller.commands.canRedo, isTrue);
          expect(controller.isDirty, isFalse);
          expect(controller.document.paragraphs.single.text, 'Body remains');
        }

        for (final offset in [0, 3, paragraph.text.length]) {
          controller.caret
            ..paragraphIndex = 0
            ..logicalIndex = offset
            ..collapseSelection();
          final before = selection();
          expect(controller.insertParagraphBreak, throwsUnsupportedError);
          assertUnchanged(before);
        }
        controller.caret
          ..paragraphIndex = 1
          ..logicalIndex = 0
          ..collapseSelection();
        var before = selection();
        expect(
          () => controller.deleteSelectionOr(backward: true),
          throwsUnsupportedError,
        );
        assertUnchanged(before);
        controller.caret
          ..selectionAnchorParagraph = 0
          ..selectionAnchor = 1
          ..paragraphIndex = 1
          ..logicalIndex = 2;
        before = selection();
        expect(
          () => controller.deleteSelectionOr(backward: false),
          throwsUnsupportedError,
        );
        assertUnchanged(before);

        final incoming = WmlClone.paragraph(paragraph);
        incoming.contentControlWrappers
          ..clear()
          ..add(
            WmlContentControlData(
              xml: wrapper.xml.replaceFirst('w:val="42"', 'w:val="43"'),
              sourcePartUri: wrapper.sourcePartUri,
              relationships: wrapper.relationships,
              id: '43',
            ),
          );
        await OfficeClipboard.instance.write(
          OfficeClipboardPayload(
            kind: OfficeClipboardKind.richText,
            plain: incoming.text,
            wordBlocks: [incoming],
          ),
        );
        controller.caret
          ..paragraphIndex = 1
          ..logicalIndex = 3
          ..collapseSelection();
        before = selection();
        await expectLater(
          controller.pasteFromClipboard(),
          throwsUnsupportedError,
        );
        assertUnchanged(before);
        controller.redo();
        expect(
          paragraph.inlines.whereType<WmlRun>().every(
            (run) => run.properties.bold,
          ),
          isTrue,
        );
        controller.undo();
        controller.undo();
        expect(paragraph.text, 'Controlled');
        expect(controller.commands.canUndo, isFalse);
      },
    );
  }
}
