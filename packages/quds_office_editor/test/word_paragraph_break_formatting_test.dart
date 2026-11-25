import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

/// Paragraph formatting the suite copies across a paragraph break, in the
/// order a user sets it in the Paragraph dialog.
void _formatParagraph(WordEditorController controller) {
  controller.applyParagraphFormat((WmlParagraphProps props) {
    props.spacingBefore = 12;
    props.spacingAfter = 18;
    props.lineSpacing = 1.5;
    props.lineSpacingRule = WmlLineSpacingRule.auto;
    props.explicitLineSpacing = true;
    props.explicitSpacingBefore = true;
    props.explicitSpacingAfter = true;
    props.indent = const WmlIndent(left: 24, right: 12, firstLine: 6);
    props.explicitIndent = true;
    props.justification = WmlJustification.center;
    props.explicitJustification = true;
    props.keepTogether = true;
    props.keepWithNext = true;
    props.tabs.add(
      const WmlTabStop(position: 36, alignment: WmlTabAlignment.left),
    );
  });
}

void _expectInheritedFormat(
  WmlParagraphProps actual, {
  String? styleId,
  double before = 12,
  double after = 18,
  double line = 1.5,
  WmlIndent indent = const WmlIndent(left: 24, right: 12, firstLine: 6),
  WmlJustification justification = WmlJustification.center,
}) {
  expect(actual.styleId, styleId);
  expect(actual.spacingBefore, before);
  expect(actual.spacingAfter, after);
  expect(actual.lineSpacing, line);
  expect(actual.lineSpacingRule, WmlLineSpacingRule.auto);
  expect(actual.explicitSpacingBefore, isTrue);
  expect(actual.explicitSpacingAfter, isTrue);
  expect(actual.explicitLineSpacing, isTrue);
  expect(actual.indent.left, indent.left);
  expect(actual.indent.right, indent.right);
  expect(actual.indent.firstLine, indent.firstLine);
  expect(actual.indent.hanging, indent.hanging);
  expect(actual.explicitIndent, isTrue);
  expect(actual.justification, justification);
  expect(actual.explicitJustification, isTrue);
  expect(actual.keepTogether, isTrue);
  expect(actual.keepWithNext, isTrue);
  expect(actual.tabs, hasLength(1));
}

WordEditorController _controllerWithCaret(String text, int index) {
  final controller = WordEditorController(
    document: WmlDocument.empty(text: text),
  );
  controller.caret
    ..logicalIndex = index
    ..collapseSelection();
  return controller;
}

List<XmlElement> _elements(XmlElement root, String localName) => <XmlElement>[
  for (final child in root.childElements) ...<XmlElement>[
    if (child.localName == localName) child,
    ..._elements(child, localName),
  ],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('paragraph formatting survives Enter', () {
    test('at the end: the new paragraph inherits every direct property', () {
      final controller = _controllerWithCaret('Alpha Beta', 10);
      addTearDown(controller.dispose);
      _formatParagraph(controller);
      final before = controller.document.paragraphs.single.properties.copy();

      controller.insertParagraphBreak();

      final paragraphs = controller.document.paragraphs.toList();
      expect(paragraphs.map((WmlParagraph p) => p.text), <String>[
        'Alpha Beta',
        '',
      ]);
      expect(
        identical(paragraphs[0].properties, paragraphs[1].properties),
        isFalse,
      );
      _expectInheritedFormat(paragraphs[1].properties);
      expect(paragraphs[0].properties.spacingBefore, before.spacingBefore);
      expect(paragraphs[1].properties.importedParagraphMark, isNotNull);
      expect(controller.caret.paragraphIndex, 1);
      expect(controller.caret.logicalIndex, 0);
    });

    test('in the middle: both halves keep the paragraph formatting', () {
      final controller = _controllerWithCaret('Alpha Beta', 5);
      addTearDown(controller.dispose);
      _formatParagraph(controller);

      controller.insertParagraphBreak();

      final paragraphs = controller.document.paragraphs.toList();
      expect(paragraphs.map((WmlParagraph p) => p.text), <String>[
        'Alpha',
        ' Beta',
      ]);
      _expectInheritedFormat(paragraphs[0].properties);
      _expectInheritedFormat(paragraphs[1].properties);
    });

    test('on an empty formatted paragraph: still inherits the format', () {
      final controller = _controllerWithCaret('', 0);
      addTearDown(controller.dispose);
      _formatParagraph(controller);

      controller.insertParagraphBreak();
      controller.insertParagraphBreak();

      for (final paragraph in controller.document.paragraphs) {
        _expectInheritedFormat(paragraph.properties);
      }
    });

    test('inside a table cell keeps the cell paragraph format', () {
      final cellParagraph = WmlParagraph(
        properties: WmlParagraphProps(
          spacingBefore: 6,
          spacingAfter: 14,
          lineSpacing: 1.5,
          explicitIndent: true,
          indent: const WmlIndent(left: 12),
        ),
        inlines: <WmlInline>[WmlRun(text: 'Cell')],
      );
      final document = WmlDocument.empty();
      document.sections.first.blocks.add(
        WmlTable(
          grid: <double>[200],
          rows: <WmlTableRow>[
            WmlTableRow(
              cells: <WmlTableCell>[
                WmlTableCell(blocks: <WmlBlock>[cellParagraph]),
              ],
            ),
          ],
        ),
      );
      final controller = WordEditorController(document: document);
      addTearDown(controller.dispose);
      controller.relayout();
      controller.jumpToParagraph(1);
      controller.caret
        ..logicalIndex = 4
        ..collapseSelection();

      controller.insertParagraphBreak();

      final cell = document.sections.first.blocks
          .whereType<WmlTable>()
          .first
          .rows
          .first
          .cells
          .first;
      final paragraphs = cell.blocks.whereType<WmlParagraph>().toList();
      expect(paragraphs.map((WmlParagraph p) => p.text), <String>['Cell', '']);
      for (final paragraph in paragraphs) {
        expect(paragraph.properties.spacingBefore, 6);
        expect(paragraph.properties.spacingAfter, 14);
        expect(paragraph.properties.lineSpacing, 1.5);
        expect(paragraph.properties.indent.left, 12);
      }
    });
  });

  group('paragraph formatting survives an imported DOCX', () {
    test(
      'split, undo, redo and sparse save keep the source paragraph format',
      () async {
        final controller = WordEditorController.fromBytes(
          File(
            '../quds_office_engine/test/fixtures/fidelity/word.docx',
          ).readAsBytesSync(),
        );
        addTearDown(controller.dispose);
        controller.jumpToParagraph(1);
        final before = controller.document.paragraphs
            .elementAt(1)
            .properties
            .copy();
        controller.caret
          ..logicalIndex = controller.document.paragraphs
              .elementAt(1)
              .text
              .length
          ..collapseSelection();

        controller.insertParagraphBreak();

        final inserted = controller.document.paragraphs.elementAt(2);
        expect(inserted.text, '');
        expect(inserted.properties.styleId, before.styleId);
        expect(inserted.properties.spacingAfter, before.spacingAfter);
        expect(inserted.properties.explicitSpacingAfter, isTrue);
        expect(inserted.properties.justification, before.justification);

        controller.undo();
        expect(controller.document.paragraphs, hasLength(5));
        controller.redo();
        expect(controller.document.paragraphs, hasLength(6));

        final bytes = await controller.saveBytesAsync();
        final package = OpcPackage.openBytes(bytes);
        final root = XmlDocument.parse(
          package.getPart('/word/document.xml')!.readText(),
        ).root!;
        final bodyParagraphs = _elements(root, 'p').take(3).toList();
        final insertedPPr = bodyParagraphs[2].firstChild(
          'pPr',
          namespaceUri: OfficeNamespaces.w,
        )!;
        expect(
          insertedPPr
              .firstChild('pStyle', namespaceUri: OfficeNamespaces.w)
              ?.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          before.styleId,
        );
        expect(
          insertedPPr
              .firstChild('spacing', namespaceUri: OfficeNamespaces.w)
              ?.getAttribute('after', namespaceUri: OfficeNamespaces.w),
          '${(before.spacingAfter * 20).round()}',
        );
        expect(
          insertedPPr
              .firstChild('jc', namespaceUri: OfficeNamespaces.w)
              ?.getAttribute('val', namespaceUri: OfficeNamespaces.w),
          isNotNull,
        );

        final reopened = WordDeserializer().readBytes(bytes);
        final reloaded = reopened.paragraphs.elementAt(2).properties;
        expect(reloaded.styleId, before.styleId);
        expect(reloaded.spacingBefore, before.spacingBefore);
        expect(reloaded.spacingAfter, before.spacingAfter);
        expect(reloaded.justification, before.justification);
      },
    );
  });

  group('typing continues the caret formatting after Enter', () {
    test('bold, size, color and font carry into the new paragraph', () async {
      final controller = _controllerWithCaret('Bold large', 10);
      addTearDown(controller.dispose);
      _formatParagraph(controller);
      controller.selectAll();
      controller.applyRunFormat((WmlRunProps props) {
        props.bold = true;
        props.italic = true;
        props.fontSizeHalfPoints = 40;
        props.color = 'FF0000';
        props.asciiFont = 'Georgia';
      });
      controller.caret
        ..collapseSelection()
        ..logicalIndex = 10;

      controller.insertParagraphBreak();
      controller.insertText('X');

      final paragraph = controller.document.paragraphs.last;
      expect(paragraph.text, 'X');
      final run = paragraph.inlines.single as WmlRun;
      expect(run.properties.bold, isTrue);
      expect(run.properties.italic, isTrue);
      expect(run.properties.fontSizeHalfPoints, 40);
      expect(run.properties.color, 'FF0000');
      expect(run.properties.asciiFont, 'Georgia');
      expect(
        paragraph.properties.importedParagraphMark?.fontSizeHalfPoints,
        40,
      );

      // A save/reopen keeps the typed run, the paragraph spacing and the
      // paragraph mark that produced the run.
      final bytes = await controller.saveBytesAsync();
      final reopened = WordDeserializer().readBytes(bytes);
      final reloadedParagraph = reopened.paragraphs.last;
      expect(reloadedParagraph.text, 'X');
      final reloadedRun = reloadedParagraph.inlines.single as WmlRun;
      expect(reloadedRun.properties.bold, isTrue);
      expect(reloadedRun.properties.fontSizeHalfPoints, 40);
      expect(reloadedParagraph.properties.spacingAfter, 18);
      expect(
        reloadedParagraph.properties.importedParagraphMark?.fontSizeHalfPoints,
        40,
      );
    });

    test(
      'typing in an empty formatted paragraph follows the paragraph mark',
      () {
        final controller = _controllerWithCaret('', 0);
        addTearDown(controller.dispose);
        controller.applyParagraphFormat((WmlParagraphProps props) {
          props.importedParagraphMark = WmlRunProps()
            ..bold = true
            ..fontSizeHalfPoints = 32;
          props.spacingBefore = 10;
          props.spacingAfter = 10;
        });

        controller.insertText('New');

        final paragraph = controller.document.paragraphs.single;
        final run = paragraph.inlines.single as WmlRun;
        expect(run.properties.bold, isTrue);
        expect(run.properties.fontSizeHalfPoints, 32);
        expect(paragraph.properties.spacingBefore, 10);
        expect(paragraph.properties.spacingAfter, 10);
      },
    );
  });

  group('list numbering stays coherent', () {
    test('Enter in a numbered list continues 1. 2. 3.', () {
      final controller = _controllerWithCaret('Item one', 8);
      addTearDown(controller.dispose);
      controller.toggleList(numbered: true);
      controller.caret
        ..logicalIndex = 8
        ..collapseSelection();

      controller.insertParagraphBreak();
      controller.insertText('Item two');
      controller.insertParagraphBreak();
      controller.insertText('Item three');

      expect(
        controller.document.paragraphs.map(
          (WmlParagraph p) => p.properties.listLabel,
        ),
        <String>['1. ', '2. ', '3. '],
      );
    });

    test('Enter in a bullet list repeats the bullet without a number', () {
      final controller = _controllerWithCaret('One', 3);
      addTearDown(controller.dispose);
      controller.toggleList(numbered: false);
      controller.caret
        ..logicalIndex = 3
        ..collapseSelection();

      controller.insertParagraphBreak();
      controller.insertText('Two');

      expect(
        controller.document.paragraphs.map((WmlParagraph p) => p.text),
        <String>['One', 'Two'],
      );
      expect(
        controller.document.paragraphs
            .map((WmlParagraph p) => p.properties.listLabel)
            .toSet(),
        <String>{'• '},
      );
    });

    test('splitting an earlier item renumbers the following items', () {
      final controller = _controllerWithCaret('One', 3);
      addTearDown(controller.dispose);
      controller.toggleList(numbered: true);
      controller.caret
        ..logicalIndex = 3
        ..collapseSelection();
      controller.insertParagraphBreak();
      controller.insertText('Two');
      controller.insertParagraphBreak();
      controller.insertText('Three');
      // Put the caret back at the end of the first item and split it.
      controller.jumpToParagraph(0);
      controller.caret
        ..logicalIndex = 3
        ..collapseSelection();
      controller.insertParagraphBreak();
      controller.insertText('One and a half');

      expect(
        controller.document.paragraphs.map(
          (WmlParagraph p) => p.properties.listLabel,
        ),
        <String>['1. ', '2. ', '3. ', '4. '],
      );
    });

    test('undo and redo renumber the list again', () {
      final controller = _controllerWithCaret('One', 3);
      addTearDown(controller.dispose);
      controller.toggleList(numbered: true);
      controller.caret
        ..logicalIndex = 3
        ..collapseSelection();
      controller.insertParagraphBreak();
      controller.insertText('Two');
      expect(
        controller.document.paragraphs.map(
          (WmlParagraph p) => p.properties.listLabel,
        ),
        <String>['1. ', '2. '],
      );

      controller.undo();
      controller.undo();
      expect(controller.document.paragraphs, hasLength(1));
      expect(controller.document.paragraphs.single.properties.listLabel, '1. ');
      controller.redo();
      controller.redo();
      expect(
        controller.document.paragraphs.map(
          (WmlParagraph p) => p.properties.listLabel,
        ),
        <String>['1. ', '2. '],
      );
    });

    test(
      'save and reopen keeps sequential labels and the paragraph format',
      () async {
        final controller = _controllerWithCaret('One', 3);
        addTearDown(controller.dispose);
        _formatParagraph(controller);
        controller.toggleList(numbered: true);
        controller.caret
          ..logicalIndex = 3
          ..collapseSelection();
        controller.insertParagraphBreak();
        controller.insertText('Two');

        final bytes = await controller.saveBytesAsync();
        final reopened = WordDeserializer().readBytes(bytes);
        expect(
          reopened.paragraphs.map((WmlParagraph p) => p.properties.listLabel),
          <String>['1. ', '2. '],
        );
        for (final paragraph in reopened.paragraphs) {
          expect(paragraph.properties.spacingBefore, 12);
          expect(paragraph.properties.spacingAfter, 18);
        }
      },
    );
  });

  group('usual paragraph editing operations', () {
    test('Backspace join keeps the destination format and renumbers', () {
      final controller = _controllerWithCaret('One', 3);
      addTearDown(controller.dispose);
      _formatParagraph(controller);
      controller.toggleList(numbered: true);
      controller.caret
        ..logicalIndex = 3
        ..collapseSelection();
      controller.insertParagraphBreak();
      controller.insertText('Two');
      controller.insertParagraphBreak();
      controller.insertText('Three');
      expect(
        controller.document.paragraphs.map(
          (WmlParagraph p) => p.properties.listLabel,
        ),
        <String>['1. ', '2. ', '3. '],
      );

      // Delete the empty gap before "Two": join keeps the first item's format.
      controller.jumpToParagraph(1);
      controller.caret
        ..logicalIndex = 0
        ..collapseSelection();
      controller.deleteSelectionOr(backward: true);
      expect(controller.document.paragraphs.first.text, 'OneTwo');
      _expectInheritedFormat(controller.document.paragraphs.first.properties);
      expect(
        controller.document.paragraphs.map(
          (WmlParagraph p) => p.properties.listLabel,
        ),
        <String>['1. ', '2. '],
      );
    });

    test('Delete join keeps the destination paragraph format', () {
      final controller = _controllerWithCaret('One', 3);
      addTearDown(controller.dispose);
      _formatParagraph(controller);
      controller.caret
        ..logicalIndex = 3
        ..collapseSelection();
      controller.insertParagraphBreak();
      controller.insertText('Two');

      controller.jumpToParagraph(0);
      controller.caret
        ..logicalIndex = 3
        ..collapseSelection();
      controller.deleteSelectionOr(backward: false);

      expect(controller.document.paragraphs, hasLength(1));
      expect(controller.document.paragraphs.single.text, 'OneTwo');
      _expectInheritedFormat(controller.document.paragraphs.single.properties);
    });

    test('Enter after a multi-paragraph selection keeps the first format', () {
      final controller = _controllerWithCaret('One', 3);
      addTearDown(controller.dispose);
      _formatParagraph(controller);
      controller.caret
        ..logicalIndex = 3
        ..collapseSelection();
      controller.insertParagraphBreak();
      controller.insertText('Two');
      // Select from the middle of "One" to the middle of "Two".
      controller.caret
        ..paragraphIndex = 0
        ..logicalIndex = 1
        ..selectionAnchorParagraph = 1
        ..selectionAnchor = 2;

      controller.insertParagraphBreak();

      final paragraphs = controller.document.paragraphs.toList();
      expect(paragraphs.map((WmlParagraph p) => p.text), <String>['O', 'o']);
      for (final paragraph in paragraphs) {
        _expectInheritedFormat(paragraph.properties);
      }
    });
  });

  group('live editor surface', () {
    testWidgets('the Enter key keeps paragraph and character formatting', (
      WidgetTester tester,
    ) async {
      final controller = _controllerWithCaret('Alpha Beta', 10);
      addTearDown(controller.dispose);
      _formatParagraph(controller);
      controller.selectAll();
      controller.applyRunFormat((WmlRunProps props) {
        props.bold = true;
        props.fontSizeHalfPoints = 36;
      });
      controller.caret
        ..collapseSelection()
        ..logicalIndex = 10;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: QudsWordEditor(
                controller: controller,
                focusNode: focus,
                enableLiveProofing: false,
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      controller.refreshView();
      await tester.pump();
      expect(controller.input.isAttached, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      final paragraphs = controller.document.paragraphs.toList();
      expect(paragraphs.map((WmlParagraph p) => p.text), <String>[
        'Alpha Beta',
        '',
      ]);
      _expectInheritedFormat(paragraphs[1].properties);
      expect(
        paragraphs[1].properties.importedParagraphMark?.fontSizeHalfPoints,
        36,
      );

      controller.insertText('Bold');
      final run = controller.document.paragraphs.last.inlines.single as WmlRun;
      expect(run.text, 'Bold');
      expect(run.properties.bold, isTrue);
      expect(run.properties.fontSizeHalfPoints, 36);
    });
  });
}
