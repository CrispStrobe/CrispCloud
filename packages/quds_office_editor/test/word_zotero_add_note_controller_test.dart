import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _id = 'controller-add-note';
const _firstPlaceholder =
    '<a href="https://www.zotero.org/?ABC123">(old first)</a>';
const _secondPlaceholder =
    '<a href="https://www.zotero.org/?DEF456">(old second)</a>';
const _annotation =
    '<div data-schema-version="8" data-citation-items="%5B%5D">'
    '<h1>Research</h1><p><span class="highlight" '
    'data-annotation="%7B%22pageLabel%22%3A%224%22%7D">'
    'A <i>quoted</i> passage</span> $_firstPlaceholder Comment</p>'
    '<p><b>Conclusion</b> $_secondPlaceholder</p></div>';
const _selectedAnnotations =
    '<div data-schema-version="8" data-citation-items="%5B%5D">'
    '<p><span class="highlight" '
    'data-annotation="%7B%22pageLabel%22%3A%224%22%7D">'
    'A <i>quoted</i> passage</span> $_firstPlaceholder Comment</p>'
    '<p><span class="underline" '
    'data-annotation="%7B%22pageLabel%22%3A%224%22%7D">'
    '<u>Another passage</u></span> $_secondPlaceholder</p></div>';
const _structuredList =
    '<ol start="3"><li><p>Parent $_firstPlaceholder</p>'
    '<p><i>More detail</i></p><ul><li><p>Nested $_secondPlaceholder</p>'
    '<p>Nested detail</p></li></ul><p>After nested</p></li>'
    '<li><p>Next</p></li></ol>';

const _tableResearchHtml =
    '<table><tbody><tr>'
    '<td data-colwidth="120" style="background-color: #ffeedd">'
    '<ol start="3"><li>First $_firstPlaceholder</li></ol></td>'
    '<td data-colwidth="240"><p>Second $_secondPlaceholder</p></td>'
    '</tr></tbody></table>';

// Unequal physical row shapes share three logical columns. Both citations
// live in merged cells, with the second merge starting after an ordinary cell.
const _mergedTableResearchHtml =
    '<table><tbody><tr>'
    '<td colspan="2" data-colwidth="120,160" '
    'style="background-color: #ffeedd">'
    '<ol start="3"><li>First $_firstPlaceholder</li></ol></td>'
    '<td data-colwidth="240"><p>Top right</p></td></tr><tr>'
    '<td data-colwidth="120"><p>Bottom left</p></td>'
    '<td colspan="2" data-colwidth="160,240">'
    '<p>Second $_secondPlaceholder</p></td>'
    '</tr></tbody></table>';

void _expectResearchTable(WmlTable table, {required bool merged}) {
  expect(table.grid, merged ? [90.0, 120.0, 180.0] : [90.0, 180.0]);
  expect(
    table.rows.map((row) => row.cells.map((cell) => cell.gridSpan).toList()),
    merged
        ? [
            [2, 1],
            [1, 2],
          ]
        : [
            [1, 1],
          ],
  );
  expect(
    table.rows.map((row) => row.cells.map((cell) => cell.width).toList()),
    merged
        ? [
            [210.0, 180.0],
            [90.0, 300.0],
          ]
        : [
            [90.0, 180.0],
          ],
  );
  expect(table.rows.first.cells.first.fillColor, 'FFEEDD');
  expect(WordTable.supportsGridAddressing(table), isTrue);
  if (merged) {
    expect(
      WordTable.cellAtGrid(table, 0, 1)!.cell,
      same(table.rows.first.cells.first),
    );
    expect(
      WordTable.cellAtGrid(table, 1, 2)!.cell,
      same(table.rows.last.cells.last),
    );
  }
}

String _preferences([int noteType = 0]) => jsonEncode({
  'dataVersion': 4,
  'sessionID': 'add-note-session',
  'zoteroVersion': '10.0',
  'style': {
    'styleID': noteType == 0
        ? 'http://www.zotero.org/styles/apa'
        : 'http://www.zotero.org/styles/chicago-note-bibliography',
    'locale': 'de-DE',
  },
  'prefs': {'fieldType': 'Http', 'noteType': noteType},
});

ZoteroCitation _citation(
  String id,
  String text, {
  int noteIndex = 0,
}) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  noteIndex: noteIndex,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {
        'id': 'source-$id',
        'type': 'book',
        'title': 'Research source $id',
        'author': [
          {'family': 'Author', 'given': id},
        ],
      },
      uris: [
        'http://zotero.org/users/42/items/${id == 'first' ? 'ABCD1234' : 'EFGH5678'}',
      ],
      locator: '4',
      label: 'page',
    ),
  ],
);

String _code(String id, String text, {int noteIndex = 0}) =>
    'ITEM CSL_CITATION ${jsonEncode(_citation(id, text, noteIndex: noteIndex).toJson())}';

WmlDocument _document() => WmlDocument(
  sections: [
    WmlSection(
      blocks: [
        WmlParagraph(
          properties: WmlParagraphProps(styleId: 'Normal', spacingAfter: 6),
          inlines: [
            WmlRun(text: 'Before', properties: WmlRunProps(bold: true)),
            WmlRun(
              text: 'After',
              properties: WmlRunProps(italic: true),
              hyperlink: const WmlHyperlink(
                url: 'https://example.org/authored',
              ),
            ),
          ],
        ),
        WmlParagraph(inlines: [WmlRun(text: 'Unrelated')]),
      ],
    ),
  ],
);

WordEditorController _controller({WmlDocument? document}) {
  final controller = WordEditorController(document: document ?? _document());
  controller.proofing.enabled = false;
  controller.caret
    ..logicalIndex = 6
    ..collapseSelection();
  addTearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });
  return controller;
}

WordZoteroTransaction _begin(
  WordEditorController controller, {
  ZoteroCitingCommand command = ZoteroCitingCommand.addNote,
}) => controller.beginZoteroTransaction(documentId: _id, command: command);

Object? _call(
  WordZoteroTransaction transaction,
  String command, [
  List<Object?> arguments = const [],
]) {
  transaction.assertCurrent();
  return transaction.session.handle(command, [_id, ...arguments]);
}

void _insertText(
  WordZoteroTransaction transaction,
  String html, {
  int noteType = 0,
}) {
  _call(transaction, 'Document.setDocumentData', [_preferences(noteType)]);
  final temporary =
      _call(transaction, 'Document.insertField', ['Http', noteType])!
          as Map<String, Object>;
  _call(transaction, 'Field.delete', [temporary['id']]);
  _call(transaction, 'Document.insertText', [html]);
}

void _stageCitedNote(
  WordZoteroTransaction transaction, {
  String html = _annotation,
  int noteType = 0,
}) {
  _insertText(transaction, html, noteType: noteType);
  final fields =
      (_call(transaction, 'Document.convertPlaceholdersToFields', [
                ['DEF456', 'ABC123'],
                noteType,
                'Http',
              ])!
              as List<Object?>)
          .cast<Map<String, Object>>();
  for (var index = 0; index < fields.length; index++) {
    final field = fields[index];
    final id = index == 0 ? 'second' : 'first';
    final text = index == 0 ? '(Second, 2025)' : '(First, 2024)';
    _call(transaction, 'Field.setCode', [
      field['id'],
      _code(id, text, noteIndex: field['noteIndex']! as int),
    ]);
    _call(transaction, 'Field.setText', [field['id'], '<i>$text</i>', true]);
  }
}

void _complete(WordZoteroTransaction transaction) {
  _call(transaction, 'Document.complete');
  transaction.session.prepareReview();
}

List<Object?> _paragraph(WmlParagraph paragraph) => [
  paragraph.text,
  paragraph.properties.styleId,
  paragraph.properties.headingLevel,
  paragraph.properties.spacingAfter,
  for (final run in paragraph.inlines.whereType<WmlRun>())
    [
      run.text,
      run.properties.bold,
      run.properties.italic,
      run.properties.underline.name,
      run.hyperlink?.url,
      run.fieldInstruction,
      run.fieldLocked,
      run.noteRefId,
      run.noteRefEndnote,
    ],
];

String _state(WmlDocument document) => jsonEncode({
  'body': [for (final p in document.paragraphs) _paragraph(p)],
  'footnotes': [
    for (final note in document.footnotes)
      [
        note.id,
        note.endnote,
        for (final p in note.allParagraphs) _paragraph(p),
      ],
  ],
  'endnotes': [
    for (final note in document.endnotes)
      [
        note.id,
        note.endnote,
        for (final p in note.allParagraphs) _paragraph(p),
      ],
  ],
  'preferences': WordZoteroDocumentData.read(document),
});

String? _numberingXml(WmlDocument document) {
  final package = document.package;
  if (package == null) return null;
  final relationships = package.relationshipsFor('/word/document.xml');
  final relationship = relationships.firstByType(RelationshipTypes.numbering);
  return relationship == null
      ? null
      : package.getPart(relationships.resolve(relationship))?.readText();
}

List<Object?> _listProperties(WmlParagraph paragraph) => [
  paragraph.properties.numId,
  paragraph.properties.ilvl,
  paragraph.properties.listLabel,
  paragraph.properties.listRestart,
  paragraph.properties.numberingSuppressed,
  paragraph.properties.indent.left,
  paragraph.properties.indent.hanging,
];

List<String> _citationsInReadingOrder(WmlDocument document) {
  final session = WordZoteroCitingSession(
    document: document,
    documentId: 'list-reading-order',
  );
  final fields =
      session.handle('Document.getFields', ['list-reading-order', 'Http'])!
          as List<Object?>;
  return fields
      .cast<Map<String, Object>>()
      .map((f) => f['text']! as String)
      .toList();
}

typedef _Step = Map<String, Object?> Function(_Desktop desktop);

class _Desktop {
  _Desktop(this.steps);
  final List<_Step> steps;
  final requests = <ZoteroHttpRequest>[];
  final fields = <Map<String, Object?>>[];
  String documentId = '';
  String fieldId = '';
  String command = '';

  Map<String, Object?> message(String name, List<Object?> args) => {
    'command': name,
    'arguments': args,
  };

  Future<ZoteroHttpResponse> send(ZoteroHttpRequest request) async {
    final index = requests.length;
    requests.add(request);
    final Object? decoded = jsonDecode(request.body!);
    if (index == 0) {
      final initial = decoded! as Map<String, Object?>;
      documentId = initial['docId']! as String;
      command = initial['command']! as String;
    } else if (decoded case {'id': final String id}) {
      fieldId = id;
    } else if (decoded is List<Object?>) {
      fields
        ..clear()
        ..addAll(decoded.cast<Map<String, Object?>>());
    }
    expect(index, lessThan(steps.length));
    return ZoteroHttpResponse(
      statusCode: 200,
      headers: const {},
      body: jsonEncode(steps[index](this)),
    );
  }
}

List<_Step> _script({bool cancel = false, String html = _annotation}) => [
  (d) => d.message('Application.getActiveDocument', []),
  (d) => d.message('Document.getDocumentData', [d.documentId]),
  (d) => d.message('Document.setDocumentData', [d.documentId, _preferences()]),
  (d) => d.message('Document.insertField', [d.documentId, 'Http', 0]),
  (d) => d.message('Field.delete', [d.documentId, d.fieldId]),
  if (!cancel) ...[
    (d) => d.message('Document.insertText', [d.documentId, html]),
    (d) => d.message('Document.convertPlaceholdersToFields', [
      d.documentId,
      ['DEF456', 'ABC123'],
      0,
      'Http',
    ]),
    (d) => d.message('Field.setCode', [
      d.documentId,
      d.fields[0]['id'],
      _code(
        'second',
        '(Second, 2025)',
        noteIndex: d.fields[0]['noteIndex']! as int,
      ),
    ]),
    (d) => d.message('Field.setText', [
      d.documentId,
      d.fields[0]['id'],
      '<i>(Second, 2025)</i>',
      true,
    ]),
    (d) => d.message('Field.setCode', [
      d.documentId,
      d.fields[1]['id'],
      _code(
        'first',
        '(First, 2024)',
        noteIndex: d.fields[1]['noteIndex']! as int,
      ),
    ]),
    (d) => d.message('Field.setText', [
      d.documentId,
      d.fields[1]['id'],
      '<i>(First, 2024)</i>',
      true,
    ]),
  ],
  (d) => d.message('Document.complete', [d.documentId]),
];

Future<void> _openTextInsertion(
  WidgetTester tester,
  WordEditorController controller,
  _Desktop desktop, {
  required ZoteroCitingCommand command,
}) async {
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
            child: const Text('Insert Zotero research content'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Insert Zotero research content'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  for (final command in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    final name = command.name;
    for (final (tableLabel, tableHtml, merged) in [
      ('table', _tableResearchHtml, false),
      ('horizontally merged table', _mergedTableResearchHtml, true),
    ]) {
      for (final reverse in [false, true]) {
        test(
          '$name $tableLabel replacement restores ${reverse ? 'backward' : 'forward'} selection and native owners on undo',
          () {
            final controller = _controller();
            controller.caret
              ..logicalIndex = reverse ? 1 : 6
              ..selectionAnchor = reverse ? 6 : 1
              ..selectionAnchorParagraph = 0;
            final document = controller.document;
            final before = _state(document);
            final beforeNumbering = _numberingXml(document);
            final transaction = _begin(controller, command: command);
            _stageCitedNote(transaction, html: tableHtml);
            _complete(transaction);
            expect(_state(document), before);
            expect(controller.canUndo, isFalse);
            transaction.apply();

            final blocks = document.sections.single.blocks;
            final table = blocks.whereType<WmlTable>().single;
            expect(blocks.first, isA<WmlParagraph>());
            expect((blocks.first as WmlParagraph).text, 'B');
            _expectResearchTable(table, merged: merged);
            final cellParagraph =
                table.rows.first.cells.first.blocks.single as WmlParagraph;
            final lastCellParagraph =
                table.rows.last.cells.last.blocks.single as WmlParagraph;
            expect(cellParagraph.text, 'First (First, 2024)');
            expect(cellParagraph.properties.listLabel, '3. ');
            final suffix = blocks[blocks.indexOf(table) + 1] as WmlParagraph;
            expect(suffix.text, 'After');
            expect(
              document.paragraphs.elementAt(controller.caret.paragraphIndex),
              same(suffix),
            );
            expect(controller.caret.logicalIndex, 0);
            expect(controller.zoteroFields.map((f) => f.citation!.citationId), [
              'first',
              'second',
            ]);
            expect(
              controller.zoteroFields.first.paragraph,
              same(cellParagraph),
            );
            expect(
              controller.zoteroFields.last.paragraph,
              same(lastCellParagraph),
            );
            expect(controller.zoteroFields.every((f) => f.canEdit), isTrue);
            final after = _state(document);

            controller.undo();
            expect(_state(document), before);
            expect(_numberingXml(document), beforeNumbering);
            expect(
              document.sections.single.blocks.whereType<WmlTable>(),
              isEmpty,
            );
            expect(controller.caret.selectionAnchor, reverse ? 6 : 1);
            expect(controller.caret.logicalIndex, reverse ? 1 : 6);
            expect(controller.canUndo, isFalse);
            controller.redo();
            expect(_state(document), after);
            expect(document.sections.single.blocks, contains(same(table)));
            _expectResearchTable(table, merged: merged);
            expect(
              controller.zoteroFields.first.paragraph,
              same(cellParagraph),
            );
            expect(
              controller.zoteroFields.last.paragraph,
              same(lastCellParagraph),
            );
            final reopened = WordDeserializer().readBytes(
              WordSerializer().writeBytes(document),
            );
            _expectResearchTable(
              reopened.sections.single.blocks.whereType<WmlTable>().single,
              merged: merged,
            );
            expect(_citationsInReadingOrder(reopened), [
              '(First, 2024)',
              '(Second, 2025)',
            ]);
          },
        );
      }

      for (final endnote in [false, true]) {
        final label = endnote ? 'endnote' : 'footnote';
        test(
          '$name $tableLabel in an authored $label returns to the Notes pane',
          () {
            final document = _document();
            final note = WordNotes.insert(
              document,
              document.paragraphs.last,
              text: 'Left chosen Right',
              endnote: endnote,
            );
            final controller = _controller(document: document);
            const selection = TextSelection(baseOffset: 11, extentOffset: 5);
            controller.setNoteEditingTarget(note, selection);
            final before = _state(document);
            final transaction = _begin(controller, command: command);
            _stageCitedNote(
              transaction,
              html: tableHtml,
              noteType: endnote ? 2 : 1,
            );
            _complete(transaction);
            transaction.apply();
            final table = note.blocks.whereType<WmlTable>().single;
            expect(note.blocks, hasLength(3));
            expect(controller.noteEditText(note), 'Left \n Right');
            expect(controller.noteEditingTarget?.note, same(note));
            expect(
              controller.noteEditingTarget?.selection,
              const TextSelection.collapsed(offset: 6),
            );
            expect(document.footnotes.length + document.endnotes.length, 1);
            expect(
              controller.zoteroFields.every(
                (f) => note.allParagraphs.contains(f.paragraph),
              ),
              isTrue,
            );
            final reopened = WordDeserializer().readBytes(
              WordSerializer().writeBytes(document),
            );
            final restored =
                (endnote ? reopened.endnotes : reopened.footnotes).single;
            _expectResearchTable(
              restored.blocks.whereType<WmlTable>().single,
              merged: merged,
            );
            expect(
              WordZotero.fields(reopened).map((f) => f.citation!.citationId),
              ['first', 'second'],
            );
            controller.undo();
            expect(_state(document), before);
            expect(controller.noteEditingTarget?.selection, selection);
            expect(note.blocks.whereType<WmlTable>(), isEmpty);
            expect(controller.canUndo, isFalse);
            controller.redo();
            expect(note.blocks, contains(same(table)));
            _expectResearchTable(table, merged: merged);
            expect(
              controller.noteEditingTarget?.selection,
              const TextSelection.collapsed(offset: 6),
            );
          },
        );
      }

      test(
        '$name abandoned $tableLabel staging leaves document and numbering unchanged',
        () {
          final controller = _controller();
          final before = _state(controller.document);
          final numbering = _numberingXml(controller.document);
          final transaction = _begin(controller, command: command);
          _stageCitedNote(transaction, html: tableHtml);
          expect(transaction.apply, throwsStateError);
          expect(_state(controller.document), before);
          expect(_numberingXml(controller.document), numbering);
          expect(
            controller.document.sections.single.blocks.whereType<WmlTable>(),
            isEmpty,
          );
          expect(controller.canUndo, isFalse);
          expect(controller.isDirty, isFalse);
        },
      );

      test('$name stale $tableLabel result preserves the selected text', () {
        final controller = _controller();
        controller.caret
          ..selectionAnchor = 1
          ..selectionAnchorParagraph = 0;
        final before = _state(controller.document);
        final transaction = _begin(controller, command: command);
        _stageCitedNote(transaction, html: tableHtml);
        _complete(transaction);
        controller.caret.logicalIndex = 5;
        expect(transaction.apply, throwsStateError);
        expect(_state(controller.document), before);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      });

      testWidgets(
        '$name native dialog completes a cited $tableLabel as one undo step',
        (tester) async {
          final controller = _controller();
          final before = _state(controller.document);
          final desktop = _Desktop(_script(html: tableHtml));
          await _openTextInsertion(
            tester,
            controller,
            desktop,
            command: command,
          );
          expect(desktop.command, name);
          expect(
            controller.document.sections.single.blocks.whereType<WmlTable>(),
            hasLength(1),
          );
          expect(controller.zoteroFields.map((f) => f.citation!.citationId), [
            'first',
            'second',
          ]);
          final table = controller.document.sections.single.blocks
              .whereType<WmlTable>()
              .single;
          _expectResearchTable(table, merged: merged);
          final after = _state(controller.document);
          expect(desktop.requests, hasLength(12));
          expect(controller.caret.logicalIndex, 0);
          expect(tester.takeException(), isNull);
          controller.undo();
          expect(_state(controller.document), before);
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(_state(controller.document), after);
          expect(
            controller.document.sections.single.blocks,
            contains(same(table)),
          );
          _expectResearchTable(table, merged: merged);
        },
      );
    }

    test('$name rejects row-spanning table content before any edit', () {
      final controller = _controller();
      final before = _state(controller.document);
      final transaction = _begin(controller, command: command);
      expect(
        () => _insertText(
          transaction,
          '<table><tr><td rowspan="2"><p>Unsupported</p></td></tr></table>',
        ),
        throwsUnsupportedError,
      );
      expect(_state(controller.document), before);
      expect(controller.canUndo, isFalse);
    });

    test(
      '$name cancellation after merged-table staging drains without applying',
      () async {
        final controller = _controller();
        controller.caret
          ..selectionAnchor = 1
          ..selectionAnchorParagraph = 0;
        final before = _state(controller.document);
        final numbering = _numberingXml(controller.document);
        final transaction = _begin(controller, command: command);
        final cancellation = ZoteroCitingCancellation();
        final desktop = _Desktop([
          ..._script(html: _mergedTableResearchHtml).take(6),
          (d) => d.message('Document.complete', [d.documentId]),
        ]);
        var stagedTable = false;
        await expectLater(
          ZoteroCitingClient(transport: desktop.send).execute(
            command: command,
            documentId: _id,
            cancellation: cancellation,
            guard: transaction.assertCurrent,
            handler: (name, arguments) {
              final result = transaction.session.handle(name, arguments);
              if (name == 'Document.insertText') {
                stagedTable = transaction.session.hasInsertedNoteText;
                cancellation.cancel();
              }
              return result;
            },
          ),
          throwsA(
            isA<ZoteroCitingException>()
                .having((e) => e.kind, 'kind', ZoteroCitingErrorKind.cancelled)
                .having(
                  (e) => e.desktopMayNeedRestart,
                  'cleanup incomplete',
                  isFalse,
                ),
          ),
        );
        expect(stagedTable, isTrue);
        expect(desktop.requests, hasLength(7));
        expect(jsonDecode(desktop.requests.last.body!), contains('error'));
        expect(transaction.apply, throwsStateError);
        expect(_state(controller.document), before);
        expect(_numberingXml(controller.document), numbering);
        expect(controller.zoteroFields, isEmpty);
        expect(controller.caret.selectionAnchor, 1);
        expect(controller.caret.logicalIndex, 6);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );
  }

  test('annotated note is staged, preserves prose and positions the caret', () {
    final controller = _controller();
    final before = _state(controller.document);
    final transaction = _begin(controller);
    _stageCitedNote(transaction);
    _complete(transaction);
    expect(_state(controller.document), before);
    expect(controller.canUndo, isFalse);
    transaction.apply();
    final paragraphs = controller.document.paragraphs.toList();
    expect(paragraphs.map((p) => p.text), [
      'Before',
      'Research',
      'A quoted passage (First, 2024) Comment',
      'Conclusion (Second, 2025)',
      'After',
      'Unrelated',
    ]);
    expect(
      paragraphs.first.inlines.whereType<WmlRun>().single.properties.bold,
      isTrue,
    );
    final authoredTail = paragraphs[4].inlines.whereType<WmlRun>().single;
    expect(authoredTail.properties.italic, isTrue);
    expect(authoredTail.hyperlink!.url, 'https://example.org/authored');
    expect(paragraphs.first.properties.styleId, 'Normal');
    expect(paragraphs[1].properties.headingLevel, 1);
    expect(paragraphs[4].properties.styleId, 'Normal');
    expect(controller.zoteroFields.map((f) => f.citation!.citationId), [
      'first',
      'second',
    ]);
    expect(controller.zoteroFields.every((f) => f.canEdit), isTrue);
    expect(controller.caret.paragraphIndex, 3);
    expect(controller.caret.logicalIndex, paragraphs[3].text.length);
    expect(controller.caret.isCollapsed, isTrue);
    expect(controller.noteEditingTarget, isNull);
  });

  test('one undo and redo restore paragraph and existing note identities', () {
    final document = _document();
    final original = document.paragraphs.first;
    final unrelated = document.paragraphs.last;
    final existingNote = WordNotes.insert(
      document,
      unrelated,
      text: 'Authored note',
      endnote: false,
    );
    final controller = _controller(document: document);
    final before = _state(document);
    final transaction = _begin(controller);
    _stageCitedNote(transaction);
    _complete(transaction);
    transaction.apply();
    final after = _state(document);
    final inserted = document.paragraphs.skip(1).take(3).toList();
    expect(document.paragraphs.first, same(original));
    controller.undo();
    expect(_state(document), before);
    expect(document.paragraphs.first, same(original));
    expect(document.paragraphs.last, same(unrelated));
    expect(document.footnotes.single, same(existingNote));
    expect(controller.caret.paragraphIndex, 0);
    expect(controller.caret.logicalIndex, 6);
    expect(controller.canUndo, isFalse);
    controller.redo();
    expect(_state(document), after);
    expect(document.paragraphs.first, same(original));
    expect(document.paragraphs.last, same(unrelated));
    expect(document.footnotes.single, same(existingNote));
    for (var index = 0; index < inserted.length; index++) {
      expect(document.paragraphs.elementAt(index + 1), same(inserted[index]));
    }
    expect(controller.caret.paragraphIndex, 3);
    expect(controller.caret.logicalIndex, inserted.last.text.length);
  });

  test(
    'controller result reopens from DOCX with live fields and preferences',
    () {
      final controller = _controller();
      final transaction = _begin(controller);
      _stageCitedNote(transaction);
      _complete(transaction);
      transaction.apply();
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(controller.document),
      );
      expect(
        reopened.paragraphs.map((p) => p.text),
        controller.document.paragraphs.map((p) => p.text),
      );
      expect(reopened.paragraphs.elementAt(1).properties.headingLevel, 1);
      expect(WordZoteroDocumentData.read(reopened), contains('de-DE'));
      expect(
        WordZoteroDocumentData.read(reopened),
        contains('"fieldType":"Field"'),
      );
      final fields = WordZotero.fields(reopened);
      expect(fields.map((f) => f.citation!.citationId), ['first', 'second']);
      expect(fields.every((f) => f.canEdit), isTrue);
      expect(fields.first.citation!.items.single.locator, '4');
      expect(fields.first.citation!.items.single.uris, [
        'http://zotero.org/users/42/items/ABCD1234',
      ]);
      expect(
        reopened.paragraphs
            .elementAt(2)
            .inlines
            .whereType<WmlRun>()
            .any((run) => run.text.contains('quoted') && run.properties.italic),
        isTrue,
      );
      expect(
        reopened.paragraphs
            .elementAt(4)
            .inlines
            .whereType<WmlRun>()
            .single
            .hyperlink!
            .url,
        'https://example.org/authored',
      );
    },
  );

  for (final noteType in [1, 2]) {
    test('note style $noteType keeps active citations and undo identities', () {
      final controller = _controller();
      final document = controller.document;
      final before = _state(document);
      final transaction = _begin(controller);
      _stageCitedNote(
        transaction,
        noteType: noteType,
        html:
            '<p>Quote $_firstPlaceholder and $_secondPlaceholder</p><p>End.</p>',
      );
      _complete(transaction);
      transaction.apply();
      final notes = List<WmlNote>.of(
        noteType == 1 ? document.footnotes : document.endnotes,
      );
      expect(notes, hasLength(2));
      expect(notes.map((note) => WordNotes.editableText(note)).toSet(), {
        '(First, 2024)',
        '(Second, 2025)',
      });
      expect(
        controller.zoteroFields.map((f) => f.citation!.citationId).toSet(),
        {'first', 'second'},
      );
      expect(controller.caret.paragraphIndex, 1);
      expect(controller.caret.logicalIndex, 4);
      expect(controller.noteEditingTarget, isNull);
      final after = _state(document);
      controller.undo();
      expect(_state(document), before);
      expect(document.footnotes, isEmpty);
      expect(document.endnotes, isEmpty);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(_state(document), after);
      final restoredNotes = noteType == 1
          ? document.footnotes
          : document.endnotes;
      for (var index = 0; index < notes.length; index++) {
        expect(restoredNotes[index], same(notes[index]));
      }
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(
        noteType == 1 ? reopened.footnotes : reopened.endnotes,
        hasLength(2),
      );
      expect(WordZotero.fields(reopened).every((f) => f.canEdit), isTrue);
    });
  }

  for (final noteType in [0, 1, 2]) {
    test(
      'Add Annotation keeps quoted text, live citations and one undo for style $noteType',
      () {
        final controller = _controller();
        final document = controller.document;
        final original = document.paragraphs.first;
        final unrelated = document.paragraphs.last;
        final before = _state(document);
        final transaction = _begin(
          controller,
          command: ZoteroCitingCommand.addAnnotation,
        );
        _stageCitedNote(
          transaction,
          html: _selectedAnnotations,
          noteType: noteType,
        );
        _complete(transaction);
        expect(_state(document), before);
        expect(controller.canUndo, isFalse);
        transaction.apply();
        final after = _state(document);
        final afterCaret = (
          controller.caret.paragraphIndex,
          controller.caret.logicalIndex,
        );
        expect(_citationsInReadingOrder(document), [
          '(First, 2024)',
          '(Second, 2025)',
        ]);
        expect(document.footnotes, hasLength(noteType == 1 ? 2 : 0));
        expect(document.endnotes, hasLength(noteType == 2 ? 2 : 0));
        expect(controller.zoteroFields.every((field) => field.canEdit), isTrue);
        expect(document.paragraphs.first, same(original));
        expect(document.paragraphs.last, same(unrelated));
        expect(
          document.paragraphs.first.text,
          startsWith('BeforeA quoted passage'),
        );
        expect(document.paragraphs.first.text, endsWith(' Comment'));
        expect(document.paragraphs.elementAt(1).text, endsWith('After'));
        final runs = document.paragraphs.expand(
          (paragraph) => paragraph.inlines.whereType<WmlRun>(),
        );
        expect(
          runs.any(
            (run) => run.text.contains('quoted') && run.properties.italic,
          ),
          isTrue,
        );
        expect(
          runs.any(
            (run) =>
                run.text.contains('Another passage') &&
                run.properties.underline == WmlUnderline.single,
          ),
          isTrue,
        );
        expect(controller.noteEditingTarget, isNull);
        controller.undo();
        expect(_state(document), before);
        expect(document.paragraphs.first, same(original));
        expect(document.paragraphs.last, same(unrelated));
        expect(controller.caret.paragraphIndex, 0);
        expect(controller.caret.logicalIndex, 6);
        expect(controller.canUndo, isFalse);
        controller.redo();
        expect(_state(document), after);
        expect((
          controller.caret.paragraphIndex,
          controller.caret.logicalIndex,
        ), afterCaret);
        final reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        expect(
          reopened.paragraphs.map((paragraph) => paragraph.text),
          document.paragraphs.map((paragraph) => paragraph.text),
        );
        expect(_citationsInReadingOrder(reopened), [
          '(First, 2024)',
          '(Second, 2025)',
        ]);
        final fields = WordZotero.fields(reopened);
        expect(fields.every((field) => field.canEdit), isTrue);
        expect(fields.map((field) => field.citation!.items.single.locator), [
          '4',
          '4',
        ]);
        expect(reopened.footnotes, hasLength(noteType == 1 ? 2 : 0));
        expect(reopened.endnotes, hasLength(noteType == 2 ? 2 : 0));
        expect(WordZoteroDocumentData.read(reopened), contains('de-DE'));
      },
    );
  }

  test('a rich uncited note inserts once and leaves its tail editable', () {
    final controller = _controller();
    final transaction = _begin(controller);
    _insertText(
      transaction,
      '<p><b>Research</b><br>detail</p><p><i>Next</i></p>',
    );
    _complete(transaction);
    transaction.apply();
    expect(controller.document.paragraphs.map((p) => p.text), [
      'BeforeResearch\ndetail',
      'NextAfter',
      'Unrelated',
    ]);
    expect(controller.zoteroFields, isEmpty);
    expect(controller.caret.paragraphIndex, 1);
    expect(controller.caret.logicalIndex, 4);
    controller.undo();
    expect(controller.document.paragraphs.map((p) => p.text), [
      'BeforeAfter',
      'Unrelated',
    ]);
    expect(controller.canUndo, isFalse);
  });

  for (final noteType in [0, 1, 2]) {
    test(
      'cited research lists retain numbering and one-step undo for style $noteType',
      () {
        final controller = _controller();
        final document = controller.document;
        final original = document.paragraphs.first;
        final before = _state(document);
        final transaction = _begin(controller);
        _stageCitedNote(
          transaction,
          noteType: noteType,
          html:
              '<ul><li>Quote $_firstPlaceholder</li></ul>'
              '<ol start="4"><li>Conclusion $_secondPlaceholder</li>'
              '<li><b>Continue</b></li></ol>',
        );
        _complete(transaction);
        expect(_numberingXml(document), isNull);
        expect(_state(document), before);
        transaction.apply();
        final paragraphs = document.paragraphs.toList();
        expect(paragraphs.map((p) => p.text).first, 'Before');
        expect(paragraphs[4].text, 'After');
        expect(paragraphs[5].text, 'Unrelated');
        expect(paragraphs.first.properties.numId, isNull);
        expect(paragraphs[4].properties.numId, isNull);
        expect(paragraphs[1].properties.listLabel?.trim(), '•');
        expect(paragraphs[2].properties.listLabel?.trim(), '4.');
        expect(paragraphs[3].properties.listLabel?.trim(), '5.');
        expect(_citationsInReadingOrder(document), [
          '(First, 2024)',
          '(Second, 2025)',
        ]);
        expect(controller.caret.paragraphIndex, 3);
        expect(controller.caret.logicalIndex, 'Continue'.length);
        final after = _state(document);
        final lists = paragraphs.skip(1).take(3).map(_listProperties).toList();
        final numbering = _numberingXml(document);
        expect(numbering, isNotNull);
        controller.undo();
        expect(_state(document), before);
        expect(document.paragraphs.first, same(original));
        expect(_numberingXml(document), isNull);
        expect(controller.caret.logicalIndex, 6);
        expect(controller.canUndo, isFalse);
        controller.redo();
        expect(_state(document), after);
        expect(document.paragraphs.skip(1).take(3).map(_listProperties), lists);
        expect(_numberingXml(document), numbering);
        final reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(document),
        );
        final reopenedLists = reopened.paragraphs.skip(1).take(3).toList();
        expect(reopenedLists.map((p) => p.properties.listLabel?.trim()), [
          '•',
          '4.',
          '5.',
        ]);
        expect(_citationsInReadingOrder(reopened), [
          '(First, 2024)',
          '(Second, 2025)',
        ]);
        expect(WordZotero.fields(reopened).every((f) => f.canEdit), isTrue);
        expect(reopened.footnotes, hasLength(noteType == 1 ? 2 : 0));
        expect(reopened.endnotes, hasLength(noteType == 2 ? 2 : 0));
      },
    );
  }

  test(
    'research-list history preserves imported numbering and unrelated package data after save',
    () {
      final document = _document();
      final authored = document.paragraphs.last;
      WordLists.applyLevel(authored, numbered: true, document: document);
      final controller = _controller(document: document);
      final beforeNumbering = _numberingXml(document);
      final authoredList = _listProperties(authored);
      final transaction = _begin(controller);
      _insertText(transaction, '<ol start="3"><li>New</li><li>Next</li></ol>');
      _complete(transaction);
      transaction.apply();
      final insertedId = document.paragraphs.elementAt(1).properties.numId;
      expect(insertedId, isNot(authored.properties.numId));
      final afterNumbering = _numberingXml(document);
      WordSerializer().writeBytes(document);
      final package = document.package!;
      final payload = Uint8List.fromList([7, 11, 13]);
      package.createPart(
        '/word/media/preserved.bin',
        'application/octet-stream',
        payload,
      );
      final related = package
          .relationshipsFor('/word/document.xml')
          .add(type: RelationshipTypes.image, target: 'media/preserved.bin');
      controller.undo();
      expect(_numberingXml(document), beforeNumbering);
      expect(_listProperties(authored), authoredList);
      expect(
        package.getPart('/word/media/preserved.bin')!.readBytes(),
        payload,
      );
      expect(
        package.relationshipsFor('/word/document.xml').byId(related.id),
        same(related),
      );
      controller.redo();
      expect(_numberingXml(document), afterNumbering);
      expect(_listProperties(authored), authoredList);
      expect(
        package.getPart('/word/media/preserved.bin')!.readBytes(),
        payload,
      );
      expect(
        package.relationshipsFor('/word/document.xml').byId(related.id),
        same(related),
      );
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(
        reopened.paragraphs.elementAt(1).properties.listLabel?.trim(),
        '3.',
      );
      expect(
        reopened.paragraphs.elementAt(2).properties.listLabel?.trim(),
        '4.',
      );
      expect(reopened.paragraphs.last.properties.listLabel?.trim(), '1.');
    },
  );

  for (final command in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    for (final noteType in [0, 1, 2]) {
      test(
        '${command.name} nested list paragraphs and citations have one undo step for style $noteType',
        () {
          final controller = _controller();
          final document = controller.document;
          final original = document.paragraphs.first;
          final unrelated = document.paragraphs.last;
          final before = _state(document);
          final transaction = _begin(controller, command: command);
          _stageCitedNote(
            transaction,
            html: _structuredList,
            noteType: noteType,
          );
          _complete(transaction);
          expect(_state(document), before);
          expect(_numberingXml(document), isNull);
          expect(controller.canUndo, isFalse);
          transaction.apply();

          final paragraphs = document.paragraphs.toList();
          expect(paragraphs, hasLength(9));
          expect(paragraphs.first.text, 'Before');
          expect(paragraphs[7].text, 'After');
          expect(paragraphs.last, same(unrelated));
          final inserted = paragraphs.skip(1).take(6).toList();
          expect(inserted.map((p) => p.properties.listLabel?.trim()), [
            '3.',
            null,
            '◦',
            null,
            null,
            '4.',
          ]);
          expect(inserted.map((p) => p.properties.ilvl), [0, 0, 1, 1, 0, 0]);
          expect(inserted.map((p) => p.properties.indent.left), [
            18,
            18,
            36,
            36,
            18,
            18,
          ]);
          for (final index in [1, 3, 4]) {
            expect(inserted[index].properties.numberingSuppressed, isTrue);
            expect(inserted[index].properties.numId, isNull);
          }
          expect(inserted[1].text, 'More detail');
          expect(
            inserted[1].inlines.whereType<WmlRun>().single.properties.italic,
            isTrue,
          );
          expect(inserted[3].text, 'Nested detail');
          expect(inserted[4].text, 'After nested');
          expect(_citationsInReadingOrder(document), [
            '(First, 2024)',
            '(Second, 2025)',
          ]);
          expect(controller.caret.paragraphIndex, 6);
          expect(controller.caret.logicalIndex, 'Next'.length);
          final after = _state(document);
          final listState = inserted.map(_listProperties).toList();
          final numbering = _numberingXml(document);

          // Saving can materialize package parts; undo must still restore the
          // pre-insertion document and remove only this operation's numbering.
          WordSerializer().writeBytes(document);
          controller.undo();
          expect(_state(document), before);
          expect(document.paragraphs.first, same(original));
          expect(document.paragraphs.last, same(unrelated));
          expect(_numberingXml(document), isNull);
          expect(controller.caret.paragraphIndex, 0);
          expect(controller.caret.logicalIndex, 6);
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(_state(document), after);
          expect(
            document.paragraphs.skip(1).take(6).map(_listProperties),
            listState,
          );
          expect(_numberingXml(document), numbering);

          var reopened = document;
          for (var cycle = 0; cycle < 2; cycle++) {
            reopened = WordDeserializer().readBytes(
              WordSerializer().writeBytes(reopened),
            );
            final lists = reopened.paragraphs.skip(1).take(6).toList();
            expect(lists.map((p) => p.properties.listLabel?.trim()), [
              '3.',
              null,
              '◦',
              null,
              null,
              '4.',
            ]);
            expect(lists.map((p) => p.properties.indent.left), [
              18,
              18,
              36,
              36,
              18,
              18,
            ]);
            expect(_citationsInReadingOrder(reopened), [
              '(First, 2024)',
              '(Second, 2025)',
            ]);
            expect(
              WordZotero.fields(reopened).every((field) => field.canEdit),
              isTrue,
            );
            expect(reopened.footnotes, hasLength(noteType == 1 ? 2 : 0));
            expect(reopened.endnotes, hasLength(noteType == 2 ? 2 : 0));
          }
        },
      );
    }

    test(
      '${command.name} stale nested-list result leaves numbering untouched',
      () {
        final controller = _controller();
        final before = _state(controller.document);
        final transaction = _begin(controller, command: command);
        _stageCitedNote(transaction, html: _structuredList);
        _complete(transaction);
        controller.caret
          ..logicalIndex = 1
          ..collapseSelection();
        expect(transaction.apply, throwsStateError);
        expect(_state(controller.document), before);
        expect(_numberingXml(controller.document), isNull);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );

    test(
      '${command.name} excessive list depth refuses the entire insertion',
      () {
        final controller = _controller();
        final before = _state(controller.document);
        final transaction = _begin(controller, command: command);
        final html = '${'<ol><li>Item' * 10}Deep${'</li></ol>' * 10}';
        expect(() => _insertText(transaction, html), throwsUnsupportedError);
        expect(_state(controller.document), before);
        expect(_numberingXml(controller.document), isNull);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );
  }

  test(
    'redo allocates a numbering relationship without overwriting a reused ID',
    () {
      final controller = _controller();
      final document = controller.document;
      final transaction = _begin(controller);
      _insertText(transaction, '<ol><li>Research</li></ol>');
      _complete(transaction);
      transaction.apply();
      final package = document.package!;
      final relationships = package.relationshipsFor('/word/document.xml');
      final formerId = relationships
          .firstByType(RelationshipTypes.numbering)!
          .id;
      controller.undo();
      expect(relationships.byId(formerId), isNull);
      final unrelated = relationships.add(
        id: formerId,
        type: RelationshipTypes.hyperlink,
        target: 'https://example.org/preserved',
        targetMode: RelationshipTargetMode.external,
      );
      controller.redo();
      expect(relationships.byId(formerId), same(unrelated));
      expect(
        relationships.firstByType(RelationshipTypes.numbering)!.id,
        isNot(formerId),
      );
      expect(
        document.paragraphs.elementAt(1).properties.listLabel?.trim(),
        '1.',
      );
      final reopened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(
        reopened.paragraphs.elementAt(1).properties.listLabel?.trim(),
        '1.',
      );
    },
  );

  for (final scenario in [
    'viewing',
    'selecting',
    'track changes',
    'document protection',
    'unresolved revision',
    'locked citation',
    'inline content control',
    'header',
    'footer',
    'comment',
    'selected text box',
    'editing text box',
    'body composition',
    'note composition',
  ]) {
    test('Add Annotation refuses $scenario before staging content', () {
      final document = _document();
      final paragraph = document.paragraphs.first;
      final otherStory = WmlParagraph(inlines: [WmlRun(text: 'Other story')]);
      final frame = WmlFrame(blocks: [otherStory]);
      WmlNote? note;
      switch (scenario) {
        case 'track changes':
          document.trackRevisions = true;
        case 'document protection':
          document.restrictEditing = true;
        case 'unresolved revision':
          document.revisions.add(
            WmlRevision(
              id: 1,
              kind: WmlRevisionKind.insert,
              paragraphIndex: 0,
              targetParagraph: paragraph,
              start: 0,
              end: 6,
              text: 'Before',
            ),
          );
        case 'locked citation':
          WordZotero.insertCitation(
            document.paragraphs.last,
            _citation('locked', '(Locked)'),
          );
          WordZotero.fields(document).single.run!.fieldLocked = true;
        case 'inline content control':
          final control = WmlContentControlData(
            xml:
                '<w:sdt xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
                '<w:sdtPr/><w:sdtContent/></w:sdt>',
            sourcePartUri: '/word/document.xml',
            relationships: const [],
          );
          paragraph.inlines
            ..insert(
              0,
              WmlContentControlBoundary(control: control, start: true),
            )
            ..add(WmlContentControlBoundary(control: control, start: false));
        case 'header':
          document.sections.single.header.add(otherStory);
        case 'footer':
          document.sections.single.footer.add(otherStory);
        case 'comment':
          document.comments.add(WmlComment(id: 7, paragraphs: [otherStory]));
        case 'selected text box' || 'editing text box':
          document.sections.single.blocks.add(frame);
        case 'note composition':
          note = WordNotes.insert(
            document,
            document.paragraphs.last,
            text: 'Authored note',
            endnote: false,
          );
      }
      final controller = _controller(document: document);
      switch (scenario) {
        case 'viewing':
          controller.setMode(OfficeInteractionMode.viewing);
        case 'selecting':
          controller.setMode(OfficeInteractionMode.selecting);
        case 'header' || 'footer':
          controller.beginHeaderFooterEdit(0, footer: scenario == 'footer');
          expect(controller.isEditingHeaderFooter, isTrue);
        case 'comment':
          controller.beginCommentEdit(7);
          expect(controller.isEditingComment, isTrue);
        case 'selected text box' || 'editing text box':
          controller.selectFrame(
            frame,
            editing: scenario == 'editing text box',
          );
        case 'body composition':
          controller.input.setValue(
            TextEditingValue(
              text: paragraph.text,
              selection: const TextSelection.collapsed(offset: 6),
              composing: const TextRange(start: 0, end: 6),
            ),
          );
        case 'note composition':
          controller.setNoteEditingTarget(
            note!,
            const TextSelection.collapsed(offset: 2),
            composing: const TextRange(start: 0, end: 2),
          );
      }
      final before = _state(document);
      final revision = controller.contentRevision;
      final input = controller.input.value;
      final noteTarget = controller.noteEditingTarget;
      expect(
        () => _begin(controller, command: ZoteroCitingCommand.addAnnotation),
        switch (scenario) {
          'viewing' ||
          'selecting' ||
          'document protection' ||
          'note composition' => throwsStateError,
          _ => throwsUnsupportedError,
        },
      );
      expect(_state(document), before);
      expect(otherStory.text, 'Other story');
      expect(controller.contentRevision, revision);
      expect(controller.input.value, input);
      expect(controller.noteEditingTarget, same(noteTarget));
      expect(controller.canUndo, isFalse);
      expect(controller.isDirty, isFalse);
    });
  }

  for (final command in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    for (final endnote in [false, true]) {
      for (final noteType in [0, endnote ? 2 : 1]) {
        test(
          '${command.name} inserts into an authored ${endnote ? 'endnote' : 'footnote'} with style $noteType',
          () {
            final document = _document();
            final note = WordNotes.insert(
              document,
              document.paragraphs.last,
              text: 'Existing',
              endnote: endnote,
            );
            final controller = _controller(document: document);
            const selection = TextSelection.collapsed(offset: 2);
            controller.setNoteEditingTarget(note, selection);
            final before = _state(document);
            final body = document.paragraphs.map(_paragraph).toList();
            final transaction = _begin(controller, command: command);
            _stageCitedNote(transaction, noteType: noteType);
            _complete(transaction);
            expect(_state(document), before);
            expect(controller.canUndo, isFalse);
            transaction.apply();
            const expected =
                'Ex\nResearch\nA quoted passage (First, 2024) Comment\n'
                'Conclusion (Second, 2025)\nisting';
            expect(controller.noteEditText(note), expected);
            expect(document.paragraphs.map(_paragraph), body);
            expect(document.footnotes, hasLength(endnote ? 0 : 1));
            expect(document.endnotes, hasLength(endnote ? 1 : 0));
            expect(controller.zoteroFields.map((f) => f.citation!.citationId), [
              'first',
              'second',
            ]);
            expect(
              controller.zoteroFields.every(
                (f) => note.allParagraphs.contains(f.paragraph),
              ),
              isTrue,
            );
            expect(controller.noteEditingTarget?.note, same(note));
            expect(
              controller.noteEditingTarget?.selection,
              TextSelection.collapsed(offset: expected.indexOf('\nisting')),
            );
            expect(controller.caret.logicalIndex, 6);
            final after = _state(document);
            final reopened = WordDeserializer().readBytes(
              WordSerializer().writeBytes(document),
            );
            final reopenedNote =
                (endnote ? reopened.endnotes : reopened.footnotes).single;
            expect(WordNotes.editableText(reopenedNote), expected);
            expect(WordZotero.fields(reopened), hasLength(2));
            controller.undo();
            expect(_state(document), before);
            expect(controller.noteEditingTarget?.note, same(note));
            expect(controller.noteEditingTarget?.selection, selection);
            expect(controller.canUndo, isFalse);
            controller.redo();
            expect(_state(document), after);
            expect(controller.noteEditingTarget?.note, same(note));
          },
        );
      }

      test(
        '${command.name} replaces an authored ${endnote ? 'endnote' : 'footnote'} selection and restores its direction on undo',
        () {
          final document = _document();
          final note = WordNotes.insert(
            document,
            document.paragraphs.last,
            text: 'Left chosen Right',
            endnote: endnote,
          );
          final controller = _controller(document: document);
          const selection = TextSelection(baseOffset: 11, extentOffset: 5);
          controller.setNoteEditingTarget(note, selection);
          final before = _state(document);
          final transaction = _begin(controller, command: command);
          _insertText(transaction, '<p><b>Replacement</b></p>');
          _complete(transaction);
          expect(controller.noteEditText(note), 'Left chosen Right');
          transaction.apply();
          expect(controller.noteEditText(note), 'Left Replacement Right');
          expect(controller.noteEditingTarget?.note, same(note));
          expect(
            controller.noteEditingTarget?.selection,
            const TextSelection.collapsed(offset: 16),
          );
          controller.undo();
          expect(_state(document), before);
          expect(controller.noteEditingTarget?.selection, selection);
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(controller.noteEditText(note), 'Left Replacement Right');
        },
      );

      test(
        'a moved ${endnote ? 'endnote' : 'footnote'} selection refuses a staged ${command.name}',
        () {
          final document = _document();
          final note = WordNotes.insert(
            document,
            document.paragraphs.last,
            text: 'Authored',
            endnote: endnote,
          );
          final controller = _controller(document: document);
          controller.setNoteEditingTarget(
            note,
            const TextSelection(baseOffset: 1, extentOffset: 4),
          );
          final before = _state(document);
          final transaction = _begin(controller, command: command);
          _stageCitedNote(transaction);
          _complete(transaction);
          controller.setNoteEditingTarget(
            note,
            const TextSelection(baseOffset: 1, extentOffset: 5),
          );
          expect(transaction.apply, throwsStateError);
          expect(_state(document), before);
          expect(controller.canUndo, isFalse);
          expect(controller.isDirty, isFalse);
        },
      );
    }

    for (final reverse in [false, true]) {
      test(
        '${command.name} replaces a ${reverse ? 'backward' : 'forward'} body selection atomically',
        () {
          final controller = _controller();
          controller.caret
            ..logicalIndex = reverse ? 1 : 6
            ..selectionAnchor = reverse ? 6 : 1
            ..selectionAnchorParagraph = 0;
          final before = _state(controller.document);
          final transaction = _begin(controller, command: command);
          _stageCitedNote(transaction);
          _complete(transaction);
          expect(_state(controller.document), before);
          transaction.apply();
          expect(controller.document.paragraphs.map((p) => p.text), [
            'B',
            'Research',
            'A quoted passage (First, 2024) Comment',
            'Conclusion (Second, 2025)',
            'After',
            'Unrelated',
          ]);
          expect(controller.caret.isCollapsed, isTrue);
          expect(controller.caret.paragraphIndex, 3);
          expect(controller.zoteroFields, hasLength(2));
          final after = _state(controller.document);
          controller.undo();
          expect(_state(controller.document), before);
          expect(controller.caret.selectionAnchor, reverse ? 6 : 1);
          expect(controller.caret.logicalIndex, reverse ? 1 : 6);
          expect(controller.canUndo, isFalse);
          controller.redo();
          expect(_state(controller.document), after);
          expect(controller.caret.isCollapsed, isTrue);
        },
      );
    }

    for (final inNote in [false, true]) {
      test(
        '${command.name} refuses a selection across an intervening ${inNote ? 'note' : 'body'} table',
        () {
          final controller = _controller();
          final table = WmlTable(
            rows: [
              WmlTableRow(
                cells: [
                  WmlTableCell(
                    blocks: [
                      WmlParagraph(inlines: [WmlRun(text: 'Preserve table')]),
                    ],
                  ),
                ],
              ),
            ],
          );
          if (inNote) {
            final note = WordNotes.insert(
              controller.document,
              controller.document.paragraphs.last,
              text: 'First',
              endnote: false,
            );
            note.blocks.addAll([
              table,
              WmlParagraph(inlines: [WmlRun(text: 'Second')]),
            ]);
            controller.setNoteEditingTarget(
              note,
              const TextSelection(baseOffset: 2, extentOffset: 9),
            );
          } else {
            controller.document.sections.single.blocks.insert(1, table);
            controller.caret
              ..paragraphIndex = 2
              ..logicalIndex = 2
              ..selectionAnchor = 1
              ..selectionAnchorParagraph = 0;
          }
          final before = _state(controller.document);
          expect(
            () => _begin(controller, command: command),
            throwsUnsupportedError,
          );
          expect(_state(controller.document), before);
          expect(controller.canUndo, isFalse);
        },
      );
    }

    test(
      'a caret inside an existing citation refuses ${command.name} before staging',
      () {
        final document = WmlDocument.empty(text: 'Before ');
        WordZotero.insertCitation(
          document.paragraphs.single,
          _citation('existing', '(Existing)'),
        );
        final controller = _controller(document: document);
        controller.caret
          ..logicalIndex = 8
          ..collapseSelection();
        final before = _state(document);
        expect(
          () => _begin(controller, command: command),
          throwsUnsupportedError,
        );
        expect(_state(document), before);
        expect(controller.zoteroFields.single.citation!.citationId, 'existing');
        expect(controller.canUndo, isFalse);
      },
    );

    test(
      'a changed caret refuses a fully staged ${command.name} atomically',
      () {
        final controller = _controller();
        final before = _state(controller.document);
        final transaction = _begin(controller, command: command);
        _stageCitedNote(transaction);
        _complete(transaction);
        controller.caret
          ..logicalIndex = 1
          ..collapseSelection();
        expect(transaction.apply, throwsStateError);
        expect(_state(controller.document), before);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );

    test(
      '${command.name} unknown citation placeholder cannot mutate live text or preferences',
      () {
        final controller = _controller();
        final before = _state(controller.document);
        final transaction = _begin(controller, command: command);
        _insertText(transaction, '<p>Quote $_firstPlaceholder</p>');
        expect(
          () => _call(transaction, 'Document.convertPlaceholdersToFields', [
            ['UNKNOWN'],
            0,
            'Http',
          ]),
          throwsFormatException,
        );
        expect(_state(controller.document), before);
        expect(controller.isDirty, isFalse);
        expect(controller.canUndo, isFalse);
      },
    );

    test(
      'an unsupported ${command.name} image keeps the whole document unchanged',
      () {
        final controller = _controller();
        final before = _state(controller.document);
        final transaction = _begin(controller, command: command);
        expect(
          () => _insertText(
            transaction,
            '<p>Before<img src="https://example.org/image.png"/>after</p>',
          ),
          throwsUnsupportedError,
        );
        expect(_state(controller.document), before);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );
  }

  for (final command in [
    ZoteroCitingCommand.addNote,
    ZoteroCitingCommand.addAnnotation,
  ]) {
    testWidgets(
      'the shared ${command.name} command replaces text in the active note',
      (tester) async {
        final controller = _controller();
        final document = controller.document;
        final note = WordNotes.insert(
          document,
          document.paragraphs.last,
          text: 'Left chosen Right',
          endnote: true,
        );
        const selection = TextSelection(baseOffset: 5, extentOffset: 11);
        controller.setNoteEditingTarget(note, selection);
        final before = _state(document);
        final body = document.paragraphs.map(_paragraph).toList();
        final desktop = _Desktop(_script());
        await _openTextInsertion(tester, controller, desktop, command: command);
        expect(desktop.command, command.name);
        expect(desktop.requests, hasLength(12));
        expect(document.paragraphs.map(_paragraph), body);
        expect(controller.noteEditingTarget?.note, same(note));
        expect(controller.noteEditText(note), isNot(contains('chosen')));
        expect(controller.noteEditText(note), contains('(First, 2024)'));
        expect(controller.zoteroFields, hasLength(2));
        expect(document.endnotes, hasLength(1));
        controller.undo();
        expect(_state(document), before);
        expect(controller.noteEditingTarget?.selection, selection);
        expect(controller.canUndo, isFalse);
      },
    );

    testWidgets(
      'the shared ${command.name} command inserts live citation paragraphs',
      (tester) async {
        final controller = _controller();
        final desktop = _Desktop(_script());
        final before = _state(controller.document);
        await _openTextInsertion(tester, controller, desktop, command: command);
        expect(desktop.command, command.name);
        expect(desktop.requests, hasLength(12));
        expect(
          find.byKey(const ValueKey<String>('zotero-direct-command')),
          findsNothing,
        );
        expect(
          controller.zoteroFields.map((field) => field.citation!.citationId),
          ['first', 'second'],
        );
        expect(controller.document.paragraphs.elementAt(1).text, 'Research');
        expect(controller.caret.paragraphIndex, 3);
        controller.undo();
        expect(_state(controller.document), before);
        expect(controller.canUndo, isFalse);
      },
    );

    testWidgets(
      'cancelled ${command.name} selection discards temporary fields and style changes',
      (tester) async {
        final controller = _controller();
        controller.caret
          ..selectionAnchor = 1
          ..selectionAnchorParagraph = 0;
        final desktop = _Desktop(_script(cancel: true));
        final before = _state(controller.document);
        await _openTextInsertion(tester, controller, desktop, command: command);
        expect(desktop.command, command.name);
        expect(desktop.requests, hasLength(6));
        expect(
          find.byKey(const ValueKey<String>('zotero-direct-command')),
          findsNothing,
        );
        expect(_state(controller.document), before);
        expect(controller.zoteroFields, isEmpty);
        expect(controller.caret.selectionAnchor, 1);
        expect(controller.caret.logicalIndex, 6);
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isFalse);
      },
    );
  }
}
