import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _id = 'zotero-field-context';
const _bibliographyCode =
    ' ADDIN ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY ';

ZoteroCitation _citation(String id) => ZoteroCitation(
  citationId: id,
  plainCitation: '(Same citation)',
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: <String, Object?>{
        'id': id,
        'type': 'book',
        'title': 'Source $id',
      },
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

WmlParagraph _paragraph(String text, {bool pageBreak = false}) => WmlParagraph(
  inlines: [WmlRun(text: text)],
  properties: WmlParagraphProps(pageBreakBefore: pageBreak),
);

typedef _Fixture = ({
  WmlDocument document,
  WmlParagraph body,
  WmlParagraph tableParagraph,
  WmlNote footnote,
  WmlNote endnote,
  List<WmlParagraph> bibliography,
});

_Fixture _fixture() {
  final writing = _paragraph('Continue writing here.');
  final body = _paragraph('Body before ');
  final tableParagraph = _paragraph('Cell before ');
  WordZotero.insertCitation(body, _citation('body'));
  WordZotero.insertCitation(tableParagraph, _citation('table'));
  final bibliography = WordZotero.nativeBibliographyParagraphs(
    instruction: _bibliographyCode,
    text: 'First reference\nSecond reference\nThird reference',
  );
  final document = WmlDocument(
    sections: [
      WmlSection(
        blocks: [
          writing,
          body,
          WmlTable(
            grid: [240],
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(blocks: [tableParagraph]),
                ],
              ),
            ],
          ),
          ...bibliography,
        ],
      ),
    ],
  );
  final footnote = WordNotes.insert(
    document,
    writing,
    endnote: false,
    text: 'Footnote before ',
  );
  final endnote = WordNotes.insert(
    document,
    writing,
    endnote: true,
    text: 'Endnote before ',
  );
  WordZotero.insertCitation(footnote.paragraphs.single, _citation('footnote'));
  WordZotero.insertCitation(endnote.paragraphs.single, _citation('endnote'));
  return (
    document: document,
    body: body,
    tableParagraph: tableParagraph,
    footnote: footnote,
    endnote: endnote,
    bibliography: bibliography,
  );
}

WordEditorController _controller(WmlDocument document) {
  final controller = WordEditorController(
    document: document,
    layoutEngine: WordLayoutEngine(font: null),
  );
  controller.viewport.extent = const Size(600, 400);
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return controller;
}

WordEditorController _pagedController() {
  final first = _paragraph('First page writing.');
  final second = _paragraph('Second page ', pageBreak: true);
  final third = _paragraph('Third page ', pageBreak: true);
  WordZotero.insertCitation(second, _citation('first'));
  WordZotero.insertCitation(third, _citation('second'));
  return _controller(
    WmlDocument(
      sections: [
        WmlSection(blocks: [first, second, third]),
      ],
    ),
  );
}

WordZoteroTransaction _begin(
  WordEditorController controller, {
  String id = _id,
  bool Function()? isCurrent,
}) => controller.beginZoteroTransaction(
  documentId: id,
  command: ZoteroCitingCommand.refresh,
  isCurrent: isCurrent,
);

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) =>
    transaction.handle(command, [transaction.session.documentId, ...arguments]);

List<Map<String, Object>> _fields(WordZoteroTransaction transaction) =>
    (_call(transaction, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object>>();

String _fieldId(WordZoteroTransaction transaction, String citationId) =>
    _fields(transaction).singleWhere(
          (field) =>
              (field['code']! as String).contains('"citationID":"$citationId"'),
        )['id']!
        as String;

String _state(WmlDocument document) => jsonEncode(<String, Object?>{
  'body': document.paragraphs.map((paragraph) => paragraph.text).toList(),
  'notes': [
    for (final note in [...document.footnotes, ...document.endnotes])
      <Object?>[note.id, note.endnote, note.text],
  ],
  'fields': [
    for (final field in WordZotero.fields(document))
      <Object?>[field.instruction, field.cachedText, field.start, field.end],
  ],
  'data': WordZoteroDocumentData.read(document),
});

List<int> _selection(WordEditorController controller) => [
  controller.caret.paragraphIndex,
  controller.caret.logicalIndex,
  controller.caret.selectionAnchorParagraph,
  controller.caret.selectionAnchor,
];

void _expectClean(WordEditorController controller) {
  expect(controller.canUndo, isFalse);
  expect(controller.canRedo, isFalse);
  expect(controller.isDirty, isFalse);
  expect(controller.contentRevision, 0);
}

const _viewportCanvasKey = ValueKey('zotero-context-viewport');

Future<RenderWordCanvas> _mountViewport(
  WidgetTester tester,
  WordEditorController controller,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 600,
          height: 400,
          child: WordCanvas(
            key: _viewportCanvasKey,
            document: controller.document,
            laidOut: controller.documentLaidOut,
            caret: controller.caret,
            viewport: controller.viewport,
            config: const OfficeSurfaceConfig(showRulers: false),
            zoteroFieldRanges:
                controller.zoteroFieldContext?.sourceRanges ?? const [],
          ),
        ),
      ),
    ),
  );
  expect(tester.takeException(), isNull);
  return tester.renderObject<RenderWordCanvas>(find.byKey(_viewportCanvasKey));
}

Rect _screenBounds(
  RenderWordCanvas canvas,
  LaidOutLine line,
  int start,
  int end,
) {
  final boxes = CaretEngine.rangeRectsOnLine(
    line,
    line.y,
    line.height,
    start,
    end,
  );
  expect(boxes, isNotEmpty);
  var bounds = boxes.first;
  for (final box in boxes.skip(1)) {
    bounds = bounds.expandToInclude(box);
  }
  return Rect.fromPoints(
    canvas.windowForPagePoint(line.pageIndex, bounds.topLeft),
    canvas.windowForPagePoint(line.pageIndex, bounds.bottomRight),
  );
}

void _expectVisible(Rect bounds) {
  expect(bounds.left, greaterThanOrEqualTo(-.01));
  expect(bounds.right, lessThanOrEqualTo(600 - 14 + .01));
  expect(bounds.top, greaterThanOrEqualTo(-.01));
  expect(bounds.bottom, lessThanOrEqualTo(400 + .01));
}

List<double> _lineGeometry(LaidOutLine line) => [
  line.x,
  line.width,
  for (final glyph in line.glyphs) ...[glyph.x, glyph.advance],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'highlight preserves content, backwards writing selection and focus',
    () {
      final fixture = _fixture();
      final controller = _controller(fixture.document);
      controller.caret
        ..logicalIndex = 2
        ..selectionAnchor = 8
        ..selectionAnchorParagraph = 0;
      var focusRequests = 0;
      controller.onRequestFocus = () => focusRequests++;
      final before = _state(fixture.document);
      final selection = _selection(controller);
      final caret = controller.caret;
      final transaction = _begin(controller);
      expect(controller.zoteroFieldContext, isNull);
      _call(transaction, 'Field.select', [_fieldId(transaction, 'body')]);
      expect(
        controller.zoteroFieldContext!.sourceField!.paragraph,
        same(fixture.body),
      );
      expect(_selection(controller), selection);
      expect(controller.caret, same(caret));
      expect(controller.noteEditingTarget, isNull);
      expect(controller.noteFocusRequest, 0);
      expect(focusRequests, 0);
      expect(controller.input.isAttached, isFalse);
      expect(_state(fixture.document), before);
      _expectClean(controller);
      transaction.clearFieldContext();
      expect(controller.zoteroFieldContext, isNull);
      expect(_selection(controller), selection);
      expect(_state(fixture.document), before);
      _expectClean(controller);
    },
  );

  for (final story in ['body', 'table', 'footnote', 'endnote']) {
    test(
      '$story context resolves exact paragraph identity among equal texts',
      () {
        final fixture = _fixture();
        final controller = _controller(fixture.document);
        final transaction = _begin(controller);
        final expected = switch (story) {
          'body' => fixture.body,
          'table' => fixture.tableParagraph,
          'footnote' => fixture.footnote.paragraphs.single,
          _ => fixture.endnote.paragraphs.single,
        };
        final expectedNote = switch (story) {
          'footnote' => fixture.footnote,
          'endnote' => fixture.endnote,
          _ => null,
        };
        _call(transaction, 'Field.select', [_fieldId(transaction, story)]);
        final context = controller.zoteroFieldContext!;
        expect(context.sourceField!.paragraph, same(expected));
        expect(context.sourceRanges.single.paragraph, same(expected));
        expect(context.sourceField!.citation!.citationId, story);
        expect(context.sourceNote, same(expectedNote));
        expect(context.sourceText, '(Same citation)');
        expect(controller.noteEditingTarget, isNull);
        _expectClean(controller);
      },
    );
  }

  test('multipart bibliography retains every original source range', () {
    final fixture = _fixture();
    final controller = _controller(fixture.document);
    final transaction = _begin(controller);
    final field = _fields(
      transaction,
    ).singleWhere((field) => (field['code']! as String).startsWith('BIBL '));
    final before = _state(fixture.document);
    _call(transaction, 'Field.select', [field['id']]);
    _call(transaction, 'Field.setText', [
      field['id'],
      'Pending bibliography',
      false,
    ]);
    final context = controller.zoteroFieldContext!;
    expect(context.kind, ZoteroFieldKind.bibliography);
    expect(context.sourceRanges, [
      for (final paragraph in fixture.bibliography)
        (paragraph: paragraph, start: 0, end: paragraph.text.length),
    ]);
    expect(
      context.sourceText,
      'First reference\nSecond reference\nThird reference',
    );
    expect(_state(fixture.document), before);
    _expectClean(controller);
  });

  test('selecting another story preserves the active Notes selection', () {
    final fixture = _fixture();
    final controller = _controller(fixture.document);
    controller.caret
      ..logicalIndex = 3
      ..collapseSelection();
    controller.setNoteEditingTarget(
      fixture.footnote,
      const TextSelection(baseOffset: 6, extentOffset: 2, isDirectional: true),
    );
    final noteTarget = controller.noteEditingTarget;
    final selection = _selection(controller);
    final focusRequest = controller.noteFocusRequest;
    final before = _state(fixture.document);
    final transaction = _begin(controller);
    _call(transaction, 'Field.select', [_fieldId(transaction, 'endnote')]);
    expect(controller.zoteroFieldContext!.sourceNote, same(fixture.endnote));
    expect(controller.noteEditingTarget, noteTarget);
    expect(_selection(controller), selection);
    expect(controller.noteFocusRequest, focusRequest);
    transaction.clearFieldContext();
    expect(controller.noteEditingTarget, noteTarget);
    expect(_state(fixture.document), before);
    _expectClean(controller);
  });

  for (final command in [
    'Field.delete',
    'Field.removeCode',
    'Document.insertField',
    'Document.complete',
  ]) {
    test(
      '$command clears presentation and notifies already-built consumers',
      () {
        final fixture = _fixture();
        final controller = _controller(fixture.document);
        final transaction = _begin(controller);
        final field = _fieldId(transaction, 'body');
        final presented = <String?>[];
        controller.addListener(
          () => presented.add(controller.zoteroFieldContext?.fieldId),
        );
        _call(transaction, 'Field.select', [field]);
        expect(presented.last, field);
        final notifications = presented.length;
        _call(transaction, command, switch (command) {
          'Document.complete' => const <Object?>[],
          'Document.insertField' => <Object?>['Http', 0],
          _ => <Object?>[field],
        });
        expect(controller.zoteroFieldContext, isNull);
        expect(transaction.presentedFieldContext, isNull);
        expect(presented.length, greaterThan(notifications));
        expect(presented.last, isNull);
        _expectClean(controller);
      },
    );
  }

  test('a failed callback clears context without committing staged data', () {
    final fixture = _fixture();
    final controller = _controller(fixture.document);
    final before = _state(fixture.document);
    final transaction = _begin(controller);
    final field = _fieldId(transaction, 'body');
    _call(transaction, 'Field.select', [field]);
    _call(transaction, 'Field.setText', [field, 'Staged text', false]);
    expect(
      () => _call(transaction, 'Field.select', ['missing']),
      throwsFormatException,
    );
    expect(controller.zoteroFieldContext, isNull);
    expect(transaction.presentedFieldContext, isNull);
    expect(_state(fixture.document), before);
    _expectClean(controller);
  });

  test('temporary inserted field exposes no staged source text or ranges', () {
    final controller = _controller(WmlDocument.empty(text: 'Writing'));
    final transaction = _begin(controller);
    final field =
        _call(transaction, 'Document.insertField', ['Http', 0])!
            as Map<String, Object>;
    _call(transaction, 'Field.select', [field['id']]);
    final context = controller.zoteroFieldContext!;
    expect(context.source, WordZoteroFieldSelectionSource.stagedInsertion);
    expect(context.sourceRanges, isEmpty);
    expect(context.sourceField, isNull);
    expect(context.sourceText, isNull);
    expect(controller.zoteroFields, isEmpty);
    _expectClean(controller);
  });

  test(
    'clear restores the original viewport when the user did not move it',
    () {
      final controller = _pagedController();
      const original = Offset(13, 29);
      controller.viewport.origin = original;
      final transaction = _begin(controller);
      _call(transaction, 'Field.select', [_fieldId(transaction, 'first')]);
      expect(controller.viewport.origin.dy, greaterThan(original.dy));
      expect(controller.viewport.origin.dx, original.dx);
      transaction.clearFieldContext();
      expect(controller.viewport.origin, original);
      _expectClean(controller);
    },
  );

  for (final side in ['left', 'right']) {
    testWidgets('high zoom reveals a citation beyond the $side edge', (
      tester,
    ) async {
      final source = _paragraph('');
      if (side == 'right') {
        source.properties.justification = WmlJustification.right;
      }
      WordZotero.insertCitation(source, _citation('zoomed'));
      final controller = _controller(
        WmlDocument(
          sections: [
            WmlSection(blocks: [source]),
          ],
        ),
      );
      final original = Offset(side == 'left' ? 700 : 0, 29);
      controller.viewport
        ..setScale(2)
        ..origin = original;
      var canvas = await _mountViewport(tester, controller);
      final line = controller.documentLaidOut.pages.single.lines.single;
      final field = WordZotero.fields(controller.document).single;
      final before = _screenBounds(canvas, line, field.start, field.end);
      expect(
        side == 'left' ? before.right < 0 : before.left > 600 - 14,
        isTrue,
        reason: 'the whole citation begins beyond the visible canvas',
      );
      expect(controller.viewport.origin, original);
      final selection = _selection(controller);
      final transaction = _begin(controller);
      _call(transaction, 'Field.select', [_fieldId(transaction, 'zoomed')]);
      expect(controller.viewport.origin.dx, isNot(original.dx));
      final revealed = controller.viewport.origin;
      canvas = await _mountViewport(tester, controller);
      canvas.markNeedsLayout();
      await tester.pump();
      expect(controller.viewport.origin, revealed);
      _expectVisible(_screenBounds(canvas, line, field.start, field.end));
      expect(_selection(controller), selection);
      transaction.clearFieldContext();
      expect(controller.viewport.origin, original);
      _expectClean(controller);
    });
  }

  testWidgets('high zoom preserves a horizontal view containing the field', (
    tester,
  ) async {
    final source = _paragraph('');
    WordZotero.insertCitation(source, _citation('visible'));
    final controller = _controller(
      WmlDocument(
        sections: [
          WmlSection(blocks: [source]),
        ],
      ),
    );
    const original = Offset(200, 29);
    controller.viewport
      ..setScale(2)
      ..origin = original;
    final canvas = await _mountViewport(tester, controller);
    final line = controller.documentLaidOut.pages.single.lines.single;
    final field = WordZotero.fields(controller.document).single;
    final before = _screenBounds(canvas, line, field.start, field.end);
    expect(before.left, greaterThan(0));
    expect(before.right, lessThan(600 - 14));
    final transaction = _begin(controller);
    _call(transaction, 'Field.select', [_fieldId(transaction, 'visible')]);
    expect(controller.viewport.origin.dx, original.dx);
    _expectVisible(_screenBounds(canvas, line, field.start, field.end));
    transaction.clearFieldContext();
    expect(controller.viewport.origin, original);
  });

  testWidgets(
    'last page footnote clamps to the canvas bottom and restores after layout',
    (tester) async {
      final first = _paragraph('Keep writing here.');
      final last = _paragraph('Last page anchor.', pageBreak: true);
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [first, last]),
        ],
      );
      final note = WordNotes.insert(
        document,
        last,
        endnote: false,
        text: 'Original source ',
      );
      final source = note.paragraphs.single;
      WordZotero.insertCitation(source, _citation('last-note'));
      final controller = _controller(document);
      const original = Offset(13, 29);
      controller.viewport.origin = original;
      var canvas = await _mountViewport(tester, controller);
      final layout = controller.documentLaidOut;
      final page = layout.pages.last;
      final line = page.notes.singleWhere(
        (line) => identical(line.sourceParagraph, source),
      );
      final field = WordZotero.fields(document).single;
      final scale = controller.viewport.scale * 96 / 72;
      final maxY =
          layout.pages.fold<double>(
            24,
            (height, page) => height + page.height * scale + 24,
          ) -
          400;
      final unconstrained =
          layout.pageStackTop(page.index, scale) + line.y * scale - 48;
      expect(unconstrained, greaterThan(maxY));
      final transaction = _begin(controller);
      final originalGeometry = _lineGeometry(line);
      final incremental = layout.supportsIncrementalReuse;
      _call(transaction, 'Field.select', [_fieldId(transaction, 'last-note')]);
      expect(controller.viewport.origin.dy, closeTo(maxY, .001));
      expect(_lineGeometry(line), originalGeometry);
      expect(layout.supportsIncrementalReuse, incremental);
      final revealed = controller.viewport.origin;
      canvas = await _mountViewport(tester, controller);
      canvas.markNeedsLayout();
      await tester.pump();
      expect(controller.viewport.origin, revealed);
      final displayStart = line.proofingOffsets!.indexOf(field.start);
      final displayEnd = line.proofingOffsets!.indexOf(field.end);
      expect(displayStart, greaterThan(field.start));
      _expectVisible(_screenBounds(canvas, line, displayStart, displayEnd));
      expect(controller.noteEditingTarget, isNull);
      transaction.clearFieldContext();
      expect(controller.viewport.origin, original);
      _expectClean(controller);
    },
  );

  testWidgets('overlay note reveal measures source text beyond its label', (
    tester,
  ) async {
    final anchor = _paragraph('Writing beside a note anchor.');
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [anchor]),
      ],
    );
    final note = WordNotes.insert(document, anchor, endnote: false, text: '');
    final source = note.paragraphs.single;
    WordZotero.insertCitation(source, _citation('overlay-note'));
    final controller = _controller(document);
    final layout = controller.documentLaidOut;
    final page = layout.pages.single;
    final shaped = page.notes.singleWhere(
      (line) => identical(line.sourceParagraph, source),
    );
    const label = '17 ';
    final text = '$label${source.text}';
    final overlay = LaidOutLine(
      glyphs: [],
      x: shaped.boxX,
      y: shaped.y,
      width: shaped.boxWidth,
      height: shaped.height,
      pageIndex: page.index,
      paragraphIndex: -1,
      justification: WmlJustification.right,
      overlayText: text,
      overlaySize: 11,
      sourceParagraph: source,
      sourceText: text,
      proofingOffsets: [
        for (var i = 0; i < label.length; i++) null,
        for (var i = 0; i <= source.text.length; i++) i,
      ],
      boxX: shaped.boxX,
      boxWidth: shaped.boxWidth,
    );
    page.notes[page.notes.indexOf(shaped)] = overlay;
    const original = Offset(0, 29);
    controller.viewport
      ..setScale(2)
      ..origin = original;
    var canvas = await _mountViewport(tester, controller);
    final field = WordZotero.fields(document).single;
    final painter = PaintRunText.plain(
      text: text,
      fontSize: overlay.overlaySize,
      color: controller.config.theme.documentText,
      themeFamily: controller.config.theme.fontFamily,
    )..layout();
    addTearDown(painter.dispose);
    final ink = painter
        .getBoxesForSelection(
          TextSelection(
            baseOffset: label.length + field.start,
            extentOffset: label.length + field.end,
          ),
        )
        .single
        .toRect()
        .shift(Offset(overlay.x + overlay.width - painter.width, overlay.y));
    Rect onScreen() => Rect.fromPoints(
      canvas.windowForPagePoint(page.index, ink.topLeft),
      canvas.windowForPagePoint(page.index, ink.bottomRight),
    );
    expect(onScreen().left, greaterThan(600 - 14));
    final transaction = _begin(controller);
    _call(transaction, 'Field.select', [_fieldId(transaction, 'overlay-note')]);
    final revealed = controller.viewport.origin;
    canvas = await _mountViewport(tester, controller);
    canvas.markNeedsLayout();
    await tester.pump();
    expect(controller.viewport.origin, revealed);
    _expectVisible(onScreen());
    expect(controller.noteEditingTarget, isNull);
    transaction.clearFieldContext();
    expect(controller.viewport.origin, original);
    _expectClean(controller);
  });

  for (final action in ['scroll', 'zoom']) {
    test('clear respects user $action after revealing context', () {
      final controller = _pagedController();
      controller.viewport.origin = const Offset(13, 29);
      final transaction = _begin(controller);
      _call(transaction, 'Field.select', [_fieldId(transaction, 'first')]);
      if (action == 'scroll') {
        controller.viewport.origin += const Offset(12, 137);
      } else {
        controller.viewport.setScale(1.5);
      }
      final userOrigin = controller.viewport.origin;
      final userScale = controller.viewport.scale;
      transaction.clearFieldContext();
      expect(controller.viewport.origin, userOrigin);
      expect(controller.viewport.scale, userScale);
      _expectClean(controller);
    });
  }

  test('later selection restores the newer user scroll and zoom', () {
    final controller = _pagedController();
    controller.viewport.origin = const Offset(13, 29);
    final transaction = _begin(controller);
    _call(transaction, 'Field.select', [_fieldId(transaction, 'first')]);
    controller.viewport
      ..origin = const Offset(41, 315)
      ..setScale(1.5);
    // Zoom now keeps the content point in view instead of leaving the old
    // scaled offset, so the user's state is the post-zoom origin.
    final Offset userOrigin = controller.viewport.origin;
    _call(transaction, 'Field.select', [_fieldId(transaction, 'second')]);
    expect(controller.viewport.origin, isNot(userOrigin));
    transaction.clearFieldContext();
    expect(controller.viewport.origin, userOrigin);
    expect(controller.viewport.scale, 1.5);
  });

  test('older operation cannot adopt or clear a newer operation context', () {
    final controller = _pagedController();
    const original = Offset(13, 29);
    controller.viewport.origin = original;
    final first = _begin(controller);
    _call(first, 'Field.select', [_fieldId(first, 'first')]);
    final second = _begin(controller, id: 'newer-operation');
    final selected = _fieldId(second, 'second');
    _call(second, 'Field.select', [selected]);
    final newOrigin = controller.viewport.origin;
    expect(first.presentedFieldContext, isNull);
    expect(second.presentedFieldContext!.fieldId, selected);
    first.clearFieldContext();
    expect(controller.viewport.origin, newOrigin);
    expect(
      controller.zoteroFieldContext!.sourceField!.citation!.citationId,
      'second',
    );
    second.clearFieldContext();
    expect(controller.viewport.origin, original);
    expect(controller.zoteroFieldContext, isNull);
  });

  for (final change in ['caret', 'source', 'document', 'host']) {
    test(
      'changed $change is not presented and stale cleanup leaves its view',
      () {
        final controller = _pagedController();
        var hostCurrent = true;
        controller.viewport.origin = const Offset(13, 29);
        final transaction = _begin(controller, isCurrent: () => hostCurrent);
        final field = _fieldId(transaction, 'first');
        _call(transaction, 'Field.select', [field]);
        final revealed = controller.viewport.origin;
        switch (change) {
          case 'caret':
            controller.caret.logicalIndex = 2;
          case 'source':
            controller.document.paragraphs.first.inlines.add(
              WmlRun(text: 'changed'),
            );
          case 'document':
            controller.document = WmlDocument.empty(text: 'Another document');
          case 'host':
            hostCurrent = false;
        }
        controller.refreshView();
        expect(controller.zoteroFieldContext, isNull);
        expect(transaction.presentedFieldContext, isNull);
        expect(
          () => _call(transaction, 'Field.select', [field]),
          throwsStateError,
        );
        expect(controller.viewport.origin, revealed);
        transaction.clearFieldContext();
        expect(controller.viewport.origin, revealed);
      },
    );
  }

  test(
    'changed Notes selection invalidates context without moving its caret',
    () {
      final fixture = _fixture();
      final controller = _controller(fixture.document);
      controller.setNoteEditingTarget(
        fixture.footnote,
        const TextSelection.collapsed(offset: 2),
      );
      final transaction = _begin(controller);
      _call(transaction, 'Field.select', [_fieldId(transaction, 'body')]);
      const changed = TextSelection.collapsed(offset: 4);
      controller.setNoteEditingTarget(fixture.footnote, changed);
      expect(controller.zoteroFieldContext, isNull);
      transaction.clearFieldContext();
      expect(controller.noteEditingTarget!.selection, changed);
    },
  );

  test('disposal cleanup does not notify a dead controller', () {
    final controller = _pagedController();
    final transaction = _begin(controller);
    _call(transaction, 'Field.select', [_fieldId(transaction, 'first')]);
    controller.dispose();
    expect(controller.zoteroFieldContext, isNull);
    expect(transaction.clearFieldContext, returnsNormally);
    expect(() => _call(transaction, 'Document.complete'), throwsStateError);
  });

  test(
    'silent lifecycle cleanup clears ownership without synchronous repaint',
    () {
      final controller = _pagedController();
      final transaction = _begin(controller);
      _call(transaction, 'Field.select', [_fieldId(transaction, 'first')]);
      var notifications = 0;
      controller.addListener(() => notifications++);
      transaction.clearFieldContext(notify: false);
      expect(controller.zoteroFieldContext, isNull);
      expect(transaction.presentedFieldContext, isNull);
      expect(notifications, 0);
      controller.refreshView();
      expect(notifications, 1);
    },
  );

  test('highlighted updates commit together as one undoable operation', () {
    final fixture = _fixture();
    final controller = _controller(fixture.document);
    controller.caret
      ..logicalIndex = 2
      ..selectionAnchor = 8
      ..selectionAnchorParagraph = 0;
    final before = _state(fixture.document);
    final selection = _selection(controller);
    final transaction = _begin(controller);
    final body = _fieldId(transaction, 'body');
    final note = _fieldId(transaction, 'endnote');
    _call(transaction, 'Field.select', [body]);
    _call(transaction, 'Field.setText', [body, '(Changed body)', false]);
    _call(transaction, 'Field.select', [note]);
    _call(transaction, 'Field.setText', [note, '(Changed note)', false]);
    expect(controller.zoteroFieldContext!.sourceText, '(Same citation)');
    expect(_state(fixture.document), before);
    _expectClean(controller);
    _call(transaction, 'Document.complete');
    expect(controller.zoteroFieldContext, isNull);
    transaction.session.prepareReview();
    transaction.apply();
    final after = _state(fixture.document);
    expect(fixture.body.text, contains('(Changed body)'));
    expect(fixture.endnote.text, contains('(Changed note)'));
    expect(_selection(controller), selection);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(_state(fixture.document), before);
    expect(_selection(controller), selection);
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(_state(fixture.document), after);
    expect(controller.zoteroFieldContext, isNull);
  });
}
