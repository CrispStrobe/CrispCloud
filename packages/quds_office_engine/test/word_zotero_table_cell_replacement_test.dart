import 'dart:convert';

import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _id = 'research-cell-range';
const _one = '<a href="https://www.zotero.org/?FIRST1">(one)</a>';
const _two = '<a href="https://www.zotero.org/?SECOND2">(two)</a>';

WmlParagraph _p(String text, {bool bold = false, bool italic = false}) =>
    WmlParagraph(
      inlines: [
        WmlRun(
          text: text,
          properties: WmlRunProps(bold: bold, italic: italic),
        ),
      ],
    );

WmlTable _table(List<WmlBlock> blocks) => WmlTable(
  grid: [200],
  rows: [
    WmlTableRow(cells: [WmlTableCell(blocks: blocks, width: 200)]),
  ],
);

WmlContentControlData _control() => WmlContentControlData(
  xml:
      '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr>'
      '<w:id w:val="12"/><w:lock w:val="sdtContentLocked"/>'
      '</w:sdtPr><w:sdtContent/></w:sdt>',
  sourcePartUri: '/word/document.xml',
  relationships: [],
);

final class _Target {
  _Target({String story = 'body', int depth = 1}) {
    table = _table([before, first, middle, last, after]);
    cell = table.rows.single.cells.single
      ..fillColor = 'DDEEFF'
      ..borderBottom = false;
    table.rows.single.cells.add(WmlTableCell(blocks: [neighbor], width: 100));
    table.grid.add(100);
    outer = table;
    for (var level = 1; level < depth; level++) {
      outer = _table([
        _p('Outer prefix $level'),
        outer,
        _p('Outer suffix $level'),
      ]);
    }
    document = WmlDocument.empty(text: 'Body');
    if (story == 'body') {
      root = document.sections.single.blocks;
    } else {
      note = WordNotes.insert(
        document,
        document.paragraphs.single,
        text: 'Authored note lead',
        endnote: story == 'endnote',
      );
      root = note!.blocks;
    }
    root.addAll([outer, _p('Story suffix')]);
  }

  final before = _p('Keep before');
  final first = _p('Left remove', bold: true);
  final middle = _p('Discard middle');
  final last = _p('remove Right', italic: true)
    ..properties.justification = WmlJustification.right
    ..properties.explicitJustification = true;
  final after = _p('Keep after');
  final neighbor = _p('Neighbor');
  late final WmlDocument document;
  late final List<WmlBlock> root;
  late final WmlTable table;
  late final WmlTableCell cell;
  late WmlTable outer;
  WmlNote? note;

  WordZoteroCitingSession session({int? start, int end = 6}) =>
      WordZoteroCitingSession(
        document: document,
        documentId: _id,
        insertionParagraph: first,
        insertionOffset: start ?? first.text.indexOf('remove'),
        insertionEndParagraph: last,
        insertionEndOffset: end,
      );
}

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_id, ...args]);

void _stage(WordZoteroCitingSession session, String html) {
  final temporary = _call(session, 'Document.insertField', ['Http', 0]) as Map;
  _call(session, 'Field.delete', [temporary['id']]);
  _call(session, 'Document.insertText', [html]);
}

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

ZoteroCitation _citation(String id, String text, {int noteIndex = 0}) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: text,
      noteIndex: noteIndex,
      items: [
        ZoteroCitationItem.fromCsl(
          itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
          uris: ['http://zotero.org/users/42/items/ABCD1234'],
          locator: '17',
          prefix: 'see ',
        ),
      ],
    );

void _set(
  WordZoteroCitingSession session,
  Map<String, Object> field,
  String id,
  String text,
) {
  _call(session, 'Field.setCode', [
    field['id'],
    'ITEM CSL_CITATION ${jsonEncode(_citation(id, text, noteIndex: field['noteIndex'] as int).toJson())}',
  ]);
  _call(session, 'Field.setText', [field['id'], text, false]);
}

void _makeComplex(WmlParagraph paragraph) {
  final run = paragraph.inlines.whereType<WmlRun>().singleWhere(
    (run) => run.fieldInstruction != null,
  );
  final index = paragraph.inlines.indexOf(run);
  paragraph.inlines.replaceRange(index, index + 1, [
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
    WmlFieldBoundary(
      kind: WmlFieldBoundaryKind.instruction,
      text: run.fieldInstruction!,
    ),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
    WmlRun(text: run.text, properties: run.properties.copy()),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
  ]);
  paragraph.properties
    ..fieldBegin = true
    ..fieldSeparate = true
    ..fieldEnd = true;
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

WmlTableCell _savedCell(WmlDocument document) => [
  for (final block in WordTree.descendants([
    ...document.sections.expand((section) => section.blocks),
    ...document.footnotes.expand((note) => note.blocks),
    ...document.endnotes.expand((note) => note.blocks),
  ]))
    if (block is WmlTable)
      for (final row in block.rows)
        for (final cell in row.cells)
          if (cell.fillColor == 'DDEEFF') cell,
].single;

void main() {
  test(
    'moving an originally cross-cell endpoint cannot make the session eligible',
    () {
      final first = _p('First');
      final last = _p('Last');
      final firstCell = WmlTableCell(blocks: [first]);
      final lastCell = WmlTableCell(blocks: [last]);
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [
              WmlTable(
                rows: [
                  WmlTableRow(cells: [firstCell, lastCell]),
                ],
              ),
            ],
          ),
        ],
      );
      final session = WordZoteroCitingSession(
        document: document,
        documentId: _id,
        insertionParagraph: first,
        insertionEndParagraph: last,
        insertionEndOffset: 2,
      );
      lastCell.blocks.clear();
      firstCell.blocks.add(last);
      expect(document.paragraphs, [same(first), same(last)]);
      expect(session.canInsertNoteText, isFalse);
      expect(
        () => _call(session, 'Document.insertText', ['<p>New</p>']),
        throwsUnsupportedError,
      );
      expect(first.text, 'First');
      expect(last.text, 'Last');
    },
  );

  for (final html in [
    '<h2>Heading</h2>',
    '<ol start="4"><li>First</li><li>Second</li></ol>',
  ]) {
    test('rich replacement respects a covariant paragraph owner: $html', () {
      final target = _Target();
      final blocks = List<WmlParagraph>.of(
        target.cell.blocks.cast<WmlParagraph>(),
      );
      target.cell.blocks = blocks;
      final session = target.session();
      _stage(session, html);
      _finish(session);
      expect(target.cell.blocks, same(blocks));
      expect(blocks.first, same(target.before));
      expect(blocks.last, same(target.after));
      expect(blocks[1].text, 'Left ');
      expect(blocks[blocks.length - 2].text, ' Right');
      expect(blocks[2].text, html.startsWith('<h2>') ? 'Heading' : 'First');
      expect(
        _savedCell(_reopen(target.document)).blocks,
        hasLength(blocks.length),
      );
    });
  }

  for (final story in ['body', 'footnote', 'endnote']) {
    for (final complex in [false, true]) {
      test(
        '$story cell retains rich research content and citations, complex=$complex',
        () {
          final target = _Target(story: story, depth: 3);
          WordZotero.insertCitation(
            target.first,
            _citation('before', '(B)'),
            index: 0,
          );
          WordZotero.insertCitation(
            target.last,
            _citation('after', '(A)'),
            index: target.last.text.length,
          );
          if (complex) {
            _makeComplex(target.first);
            _makeComplex(target.last);
          }
          final originalCellBlocks = target.cell.blocks;
          final session = target.session();
          expect(session.canInsertNoteText, isTrue);
          final originals =
              (_call(session, 'Document.getFields', ['Http']) as List)
                  .cast<Map<String, Object>>();
          final png = image.encodePng(
            image.Image(width: 2, height: 2, numChannels: 4),
          );
          _stage(
            session,
            '<h2>Research</h2><ol start="3"><li>Alpha $_one '
            '<img src="data:image/png;base64,${base64Encode(png)}" width="24" '
            'alt="Research image"/></li><li>Beta $_two</li></ol>',
          );
          expect(target.cell.blocks, [
            same(target.before),
            same(target.first),
            same(target.middle),
            same(target.last),
            same(target.after),
          ]);
          final inserted =
              (_call(session, 'Document.convertPlaceholdersToFields', [
                        ['SECOND2', 'FIRST1'],
                        0,
                        'Http',
                      ])
                      as List)
                  .cast<Map<String, Object>>();
          expect(
            inserted.map((field) => field['noteIndex']),
            story == 'body' ? [0, 0] : [1, 1],
          );
          _set(session, inserted[0], 'two', '(Two)');
          _set(session, inserted[1], 'one', '(One)');
          _set(session, originals.first, 'before', '(Expanded before)');
          _set(session, originals.last, 'after', '(Expanded after)');
          _finish(session);
          expect(target.cell.blocks, same(originalCellBlocks));
          expect(target.cell.blocks.first, same(target.before));
          expect(target.cell.blocks.last, same(target.after));
          expect(target.neighbor.text, 'Neighbor');
          expect(target.cell.blocks.contains(target.middle), isFalse);
          expect(session.caretAfter!.paragraph.text, 'Beta (Two)');
          expect(session.caretAfter!.offset, 'Beta (Two)'.length);
          for (final model in [target.document, _reopen(target.document)]) {
            final cell = _savedCell(model);
            final paragraphs = cell.blocks.cast<WmlParagraph>();
            expect(paragraphs.map((p) => p.text), [
              'Keep before',
              '(Expanded before)Left ',
              'Research',
              'Alpha (One) \uFFFC',
              'Beta (Two)',
              ' Right(Expanded after)',
              'Keep after',
            ]);
            expect(cell.width, 200);
            expect(cell.borderBottom, isFalse);
            expect(paragraphs.elementAt(2).properties.headingLevel, 2);
            expect(paragraphs.elementAt(3).properties.listLabel, '3. ');
            expect(paragraphs.elementAt(4).properties.listLabel, '4. ');
            expect(
              paragraphs.elementAt(5).properties.justification,
              WmlJustification.right,
            );
            expect(
              paragraphs
                  .elementAt(5)
                  .inlines
                  .whereType<WmlRun>()
                  .any(
                    (run) =>
                        run.text.contains('Right') &&
                        run.properties.italic == true,
                  ),
              isTrue,
            );
            final pictures = paragraphs
                .expand((p) => p.inlines.whereType<WmlRun>())
                .where((run) => run.inlineVisual != null);
            expect(pictures, hasLength(1));
            final fields = WordZotero.fields(model);
            expect(fields.map((field) => field.citation!.citationId), [
              'before',
              'one',
              'two',
              'after',
            ]);
            expect(
              fields.map((field) => field.citation!.items.single.locator),
              everyElement('17'),
            );
            expect(
              model.footnotes.length + model.endnotes.length,
              story == 'body' ? 0 : 1,
            );
          }
        },
      );
    }
  }

  for (final offsets in [(0, 0), (0, 12), (11, 0), (5, 6)]) {
    test(
      'same-cell half-open endpoints $offsets survive save and another edit',
      () {
        final target = _Target();
        final session = target.session(start: offsets.$1, end: offsets.$2);
        expect(session.canInsertNoteText, isTrue);
        _stage(session, '<p>Alpha</p><p>Beta</p>');
        _finish(session);
        final expected = [
          'Keep before',
          '${'Left remove'.substring(0, offsets.$1)}Alpha',
          'Beta${'remove Right'.substring(offsets.$2)}',
          'Keep after',
        ];
        final saved = _reopen(target.document);
        final cell = _savedCell(saved);
        expect(cell.blocks.cast<WmlParagraph>().map((p) => p.text), expected);
        final first = cell.blocks[1] as WmlParagraph;
        final last = cell.blocks[2] as WmlParagraph;
        final again = WordZoteroCitingSession(
          document: saved,
          documentId: _id,
          insertionParagraph: first,
          insertionOffset: offsets.$1,
          insertionEndParagraph: last,
          insertionEndOffset: 4,
        );
        _stage(again, '<p>Again</p>');
        _finish(again);
        expect(cell.blocks.cast<WmlParagraph>().map((p) => p.text), [
          'Keep before',
          '${'Left remove'.substring(0, offsets.$1)}Again'
              '${'remove Right'.substring(offsets.$2)}',
          'Keep after',
        ]);
      },
    );
  }

  for (final story in ['body', 'footnote', 'endnote']) {
    test('$story merged-origin cell keeps span and continuation structure', () {
      final target = _Target(story: story);
      target.cell
        ..gridSpan = 2
        ..vMerge = WmlVMerge.restart
        ..width = 200;
      target.table.grid
        ..clear()
        ..addAll([100, 100, 100]);
      final continuation = WmlTableCell(
        blocks: [_p('')],
        gridSpan: 2,
        vMerge: WmlVMerge.cont,
        width: 200,
      );
      target.table.rows.add(
        WmlTableRow(
          cells: [
            continuation,
            WmlTableCell(blocks: [_p('Other row')], width: 100),
          ],
        ),
      );
      final session = target.session();
      _stage(session, '<p>New</p>');
      _finish(session);
      expect(target.cell.gridSpan, 2);
      expect(target.cell.vMerge, WmlVMerge.restart);
      expect(target.table.rows.last.cells.first, same(continuation));
      expect(continuation.blocks.single, isA<WmlParagraph>());
      final cell = _savedCell(_reopen(target.document));
      expect(cell.gridSpan, 2);
      expect(cell.vMerge, WmlVMerge.restart);
      expect(cell.blocks.cast<WmlParagraph>().map((p) => p.text), [
        'Keep before',
        'Left New Right',
        'Keep after',
      ]);
    });
  }

  for (final structure in [
    'cross cell',
    'cross row',
    'body to cell',
    'cell to body',
    'selected nested table',
    'control ancestor',
    'frame ancestor',
    'outer control',
    'outer frame',
    'continuation',
    'outer continuation',
  ]) {
    test('$structure cannot become a same-cell replacement', () {
      final target = _Target(depth: 2);
      switch (structure) {
        case 'cross cell':
          target.cell.blocks.remove(target.last);
          target.table.rows.single.cells.last.blocks.add(target.last);
        case 'cross row':
          target.cell.blocks.remove(target.last);
          target.table.rows.add(
            WmlTableRow(
              cells: [
                WmlTableCell(blocks: [target.last]),
              ],
            ),
          );
        case 'body to cell':
          target.cell.blocks.remove(target.first);
          target.root.insert(0, target.first);
        case 'cell to body':
          target.cell.blocks.remove(target.last);
          target.root.add(target.last);
        case 'selected nested table':
          target.cell.blocks.insert(2, _table([_p('Nested')]));
        case 'control ancestor':
          final blocks = target.cell.blocks;
          target.cell.blocks = [
            WmlContentControlBlock(control: _control(), blocks: blocks),
          ];
        case 'frame ancestor':
          target.cell.blocks = [WmlFrame(blocks: target.cell.blocks)];
        case 'outer control':
          target.root[target.root.indexOf(
            target.outer,
          )] = WmlContentControlBlock(
            control: _control(),
            blocks: [target.outer],
          );
        case 'outer frame':
          target.root[target.root.indexOf(target.outer)] = WmlFrame(
            blocks: [target.outer],
          );
        case 'continuation':
          target.cell.vMerge = WmlVMerge.cont;
        case 'outer continuation':
          target.outer.rows.single.cells.single.vMerge = WmlVMerge.cont;
      }
      final session = target.session();
      expect(session.canInsertNoteText, isFalse);
      expect(
        () => _call(session, 'Document.insertText', ['<p>New</p>']),
        throwsUnsupportedError,
      );
      expect(target.first.text, 'Left remove');
      expect(target.last.text, 'remove Right');
      expect(target.neighbor.text, 'Neighbor');
    });
  }

  for (final alias in [
    'table',
    'row',
    'cell',
    'blocks',
    'control',
    'frame',
    'header',
    'note',
  ]) {
    test('refuses $alias alias without mutating the original cell', () {
      final target = _Target();
      switch (alias) {
        case 'table':
          target.root.add(target.table);
        case 'row':
          target.table.rows.add(target.table.rows.single);
        case 'cell':
          target.table.rows.single.cells.add(target.cell);
        case 'blocks':
          target.table.rows.single.cells.add(
            WmlTableCell(blocks: target.cell.blocks),
          );
        case 'control':
          target.root.add(
            WmlContentControlBlock(control: _control(), blocks: [target.first]),
          );
        case 'frame':
          target.root.add(WmlFrame(blocks: [target.last]));
        case 'header':
          target.document.sections.single.header.add(target.first);
        case 'note':
          target.document.footnotes.add(
            WmlNote(id: 40, endnote: false, paragraphs: [target.last]),
          );
      }
      final session = target.session();
      expect(session.canInsertNoteText, isFalse);
      expect(
        () => _call(session, 'Document.insertText', ['<p>New</p>']),
        throwsUnsupportedError,
      );
      expect(target.first.text, 'Left remove');
      expect(target.last.text, 'remove Right');
    });
  }

  for (final when in ['before staging', 'after completion']) {
    for (final change in [
      'blocks',
      'cell',
      'cells',
      'row',
      'rows',
      'table',
      'root list',
      'section',
      'outer cell',
      'outer list',
      'control',
      'continuation',
    ]) {
      test(
        'rejects changed $change ownership $when with unchanged flat text',
        () {
          final target = _Target(depth: 2);
          final session = target.session();
          if (when == 'after completion') {
            _stage(session, '<p>New</p>');
            _call(session, 'Document.complete');
          }
          final originalParagraphs = target.document.paragraphs.toList();
          switch (change) {
            case 'blocks':
              target.cell.blocks = List<WmlBlock>.of(target.cell.blocks);
            case 'cell':
              target.table.rows.single.cells[0] = WmlTableCell(
                blocks: target.cell.blocks,
              );
            case 'cells':
              target.table.rows.single.cells = List<WmlTableCell>.of(
                target.table.rows.single.cells,
              );
            case 'row':
              target.table.rows[0] = WmlTableRow(
                cells: target.table.rows.single.cells,
              );
            case 'rows':
              target.table.rows = List<WmlTableRow>.of(target.table.rows);
            case 'table':
              final blocks = target.outer.rows.single.cells.single.blocks;
              blocks[blocks.indexOf(target.table)] = WmlTable(
                rows: target.table.rows,
              );
            case 'root list':
              target.document.sections.single.blocks = List<WmlBlock>.of(
                target.root,
              );
            case 'section':
              target.document.sections[0] = WmlSection(blocks: target.root);
            case 'outer cell':
              target.outer.rows.single.cells[0] = WmlTableCell(
                blocks: target.outer.rows.single.cells.single.blocks,
              );
            case 'outer list':
              final cell = target.outer.rows.single.cells.single;
              cell.blocks = List<WmlBlock>.of(cell.blocks);
            case 'control':
              target.root[target.root.indexOf(
                target.outer,
              )] = WmlContentControlBlock(
                control: _control(),
                blocks: [target.outer],
              );
            case 'continuation':
              target.cell.vMerge = WmlVMerge.cont;
          }
          expect(target.document.paragraphs, orderedEquals(originalParagraphs));
          expect(
            when == 'after completion'
                ? session.apply
                : () => _stage(session, '<p>New</p>'),
            throwsA(anyOf(isA<StateError>(), isA<UnsupportedError>())),
          );
          expect(target.first.text, 'Left remove');
          expect(target.middle.text, 'Discard middle');
          expect(target.last.text, 'remove Right');
          expect(
            target.document.paragraphs.any((p) => p.text.contains('New')),
            isFalse,
          );
        },
      );
    }
  }

  for (final story in ['body', 'footnote', 'endnote']) {
    test('$story incoming table stays refused inside an existing cell', () {
      final target = _Target(story: story);
      final session = target.session();
      final original = List<WmlBlock>.of(target.cell.blocks);
      expect(session.canInsertNoteText, isTrue);
      expect(
        () => _stage(session, '<table><tr><td>New</td></tr></table>'),
        throwsUnsupportedError,
      );
      expect(target.cell.blocks, original);
      expect(target.first.text, 'Left remove');
      expect(target.last.text, 'remove Right');
      expect(session.hasInsertedNoteText, isFalse);
      expect(target.document.zoteroDocumentData, isNull);
    });
  }
}
