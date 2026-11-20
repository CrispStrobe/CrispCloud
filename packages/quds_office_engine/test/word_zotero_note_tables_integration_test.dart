import 'dart:convert';

import 'package:image/image.dart' as image;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _documentId = 'research-target';
const _one = '<a href="https://www.zotero.org/?FIRST1">(old one)</a>';
const _two = '<a href="https://www.zotero.org/?SECOND2">(old two)</a>';

WordZoteroCitingSession _session(
  WmlDocument document,
  WmlParagraph paragraph, {
  int start = 0,
  int? end,
}) => WordZoteroCitingSession(
  document: document,
  documentId: _documentId,
  insertionParagraph: paragraph,
  insertionOffset: start,
  insertionEndOffset: end,
);

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_documentId, ...args]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object>>();

List<Map<String, Object>> _convert(
  WordZoteroCitingSession session,
  List<String> ids, {
  int type = 0,
}) =>
    (_call(session, 'Document.convertPlaceholdersToFields', [
              ids,
              type,
              'Http',
            ])!
            as List<Object?>)
        .cast<Map<String, Object>>();

ZoteroCitation _citation(String id, String text) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

void _set(
  WordZoteroCitingSession session,
  Map<String, Object> field,
  String id,
  String html,
) {
  _call(session, 'Field.setCode', [
    field['id'],
    'ITEM CSL_CITATION ${jsonEncode(_citation(id, html).toJson())}',
  ]);
  _call(session, 'Field.setText', [field['id'], html, true]);
}

void _start(WordZoteroCitingSession session, String html, {int type = 0}) {
  final temp =
      _call(session, 'Document.insertField', ['Http', type])!
          as Map<String, Object>;
  _call(session, 'Field.delete', [temp['id']]);
  _call(session, 'Document.insertText', [html]);
}

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

String _table(String first, String second) =>
    '<table><tbody><tr><td><p>$first</p></td>'
    '<td><p>$second</p></td></tr></tbody></table>';

WmlTable _onlyTable(Iterable<WmlBlock> blocks) =>
    blocks.whereType<WmlTable>().single;

void main() {
  test('table replacement preserves rich prose and active field ownership', () {
    final original = WmlParagraph(
      inlines: [
        WmlRun(text: 'Before ', properties: WmlRunProps(bold: true)),
        WmlRun(text: 'TARGET'),
        WmlRun(
          text: ' after',
          properties: WmlRunProps(italic: true),
          hyperlink: const WmlHyperlink(url: 'https://example.org/authored'),
        ),
      ],
    );
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [original]),
      ],
    );
    final session = _session(document, original, start: 7, end: 13);
    _start(session, _table('First $_one', 'Second $_two'));
    final inserted = _convert(session, ['SECOND2', 'FIRST1']);
    _set(session, inserted[0], 'two', '(Two)');
    _set(session, inserted[1], 'one', '<i>(One)</i>');
    expect(original.text, 'Before TARGET after');
    expect(document.sections.single.blocks, [same(original)]);
    _finish(session);

    final blocks = document.sections.single.blocks;
    expect(blocks, hasLength(3));
    expect(blocks.first, same(original));
    final table = _onlyTable(blocks);
    expect(
      table.rows.single.cells.map(
        (c) => (c.blocks.single as WmlParagraph).text,
      ),
      ['First (One)', 'Second (Two)'],
    );
    final suffix = blocks.last as WmlParagraph;
    expect(original.text, 'Before ');
    expect(original.inlines.whereType<WmlRun>().single.properties.bold, isTrue);
    expect(suffix.text, ' after');
    final run = suffix.inlines.whereType<WmlRun>().single;
    expect(run.properties.italic, isTrue);
    expect(run.hyperlink!.url, 'https://example.org/authored');
    expect(session.caretAfter!.paragraph, same(suffix));
    expect(session.caretAfter!.offset, 0);
    final fields = WordZotero.fields(document);
    expect(fields.map((f) => f.citation!.citationId), ['one', 'two']);
    expect(fields[0].paragraph, same(table.rows.single.cells[0].blocks.single));
    expect(fields[1].paragraph, same(table.rows.single.cells[1].blocks.single));
  });

  test('table-only body insertion has no detached cell or missing caret', () {
    final document = WmlDocument.empty();
    final session = _session(document, document.paragraphs.single);
    _start(session, _table('Left', 'Right'));
    _finish(session);
    final blocks = document.sections.single.blocks;
    expect(blocks, hasLength(2));
    expect(blocks.first, isA<WmlTable>());
    final suffix = blocks.last as WmlParagraph;
    expect(suffix.text, isEmpty);
    expect(session.caretAfter, (paragraph: suffix, offset: 0));
    final reopened = _reopen(document);
    expect(reopened.sections.single.blocks.first, isA<WmlTable>());
    expect(reopened.sections.single.blocks.last, isA<WmlParagraph>());
  });

  test('fields before and after a table insertion retain document order', () {
    final document = WmlDocument.empty(text: 'Left TARGET Right');
    final paragraph = document.paragraphs.single;
    WordZotero.insertCitation(paragraph, _citation('before', '(B)'), index: 0);
    WordZotero.insertCitation(
      paragraph,
      _citation('after', '(A)'),
      index: paragraph.text.length,
    );
    final start = paragraph.text.indexOf('TARGET');
    final session = _session(document, paragraph, start: start, end: start + 6);
    final original = _fields(session);
    _start(session, _table(_one, _two));
    final inserted = _convert(session, ['SECOND2', 'FIRST1']);
    _set(session, original.first, 'before', '(Before expanded)');
    _set(session, original.last, 'after', '(After expanded)');
    _set(session, inserted[0], 'two', '(Two)');
    _set(session, inserted[1], 'one', '(One)');
    expect(_fields(session).map((f) => f['id']), [
      original.first['id'],
      inserted[1]['id'],
      inserted[0]['id'],
      original.last['id'],
    ]);
    _finish(session);
    expect(document.paragraphs.first.text, '(Before expanded)Left ');
    expect(document.paragraphs.last.text, ' Right(After expanded)');
    expect(session.caretAfter!.paragraph, same(document.paragraphs.last));
    expect(session.caretAfter!.offset, 0);
    for (final result in [document, _reopen(document)]) {
      expect(WordZotero.fields(result).map((f) => f.citation!.citationId), [
        'before',
        'one',
        'two',
        'after',
      ]);
      final fresh = _session(result, result.paragraphs.first);
      expect(_fields(fresh).map((f) => f['noteIndex']), [0, 0, 0, 0]);
    }
  });

  test('ordinary paragraphs around a table remain outside its cells', () {
    final document = WmlDocument.empty(text: 'BeforeAfter');
    final session = _session(document, document.paragraphs.single, start: 6);
    _start(session, '<p>Intro</p>${_table('Cell one', 'Cell two')}<p>End</p>');
    _finish(session);
    final blocks = document.sections.single.blocks;
    expect(blocks.map((b) => b is WmlParagraph ? b.text : 'TABLE'), [
      'Before',
      'Intro',
      'TABLE',
      'End',
      'After',
    ]);
    expect(session.caretAfter!.paragraph, same(blocks[3]));
    expect(session.caretAfter!.offset, 3);
  });

  for (final endnote in [false, true]) {
    final label = endnote ? 'endnote' : 'footnote';
    final type = endnote ? 2 : 1;
    for (final separator in [false, true]) {
      test(
        '$label leading table preserves its marker and separator $separator',
        () {
          final document = WmlDocument.empty(text: 'Body');
          final note = WordNotes.insert(
            document,
            document.paragraphs.single,
            endnote: endnote,
            text: separator ? ' Trailing prose' : 'Trailing prose',
          );
          final original = note.paragraphs.single;
          original.inlines.insert(
            0,
            WmlNoteMarker(
              endnote: endnote,
              properties: WmlRunProps(bold: true),
            ),
          );
          final session = _session(
            document,
            original,
            start: separator ? 1 : 0,
          );
          _start(session, _table(_one, _two), type: type);
          final fields = _convert(session, ['SECOND2', 'FIRST1'], type: type);
          expect(fields.map((f) => f['noteIndex']), [1, 1]);
          _set(session, fields[0], 'two', '(Two)');
          _set(session, fields[1], 'one', '(One)');
          _finish(session);
          expect(note.blocks, hasLength(3));
          expect(note.blocks.first, same(original));
          expect(original.inlines.first, isA<WmlNoteMarker>());
          expect(original.text, separator ? ' ' : '');
          final table = _onlyTable(note.blocks);
          expect(
            WordTree.paragraphs([
              table,
            ]).expand((p) => p.inlines.whereType<WmlNoteMarker>()),
            isEmpty,
          );
          final suffix = note.blocks.last as WmlParagraph;
          expect(suffix.text, 'Trailing prose');
          expect(session.caretAfter, (paragraph: suffix, offset: 0));
          expect(WordNotes.editableParagraphs(note), contains(same(suffix)));
          expect(document.footnotes.length + document.endnotes.length, 1);
          for (final result in [document, _reopen(document)]) {
            final current =
                (endnote ? result.endnotes : result.footnotes).single;
            expect(current.blocks.first, isA<WmlParagraph>());
            expect(current.blocks[1], isA<WmlTable>());
            expect(
              current.paragraphs.first.inlines.first,
              isA<WmlNoteMarker>(),
            );
            expect(
              WordZotero.fields(result).map((f) => f.citation!.citationId),
              ['one', 'two'],
            );
            expect(
              _fields(
                _session(result, current.paragraphs.first),
              ).map((f) => f['noteIndex']),
              [1, 1],
            );
          }
        },
      );
    }

    test('$label offset zero keeps the automatic separator before a table', () {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: endnote,
        text: ' Tail',
      );
      final paragraph = note.paragraphs.single;
      paragraph.inlines.insert(
        0,
        WmlNoteMarker(endnote: endnote, properties: WmlRunProps()),
      );
      final session = _session(document, paragraph);
      _start(session, _table('Left', 'Right'), type: type);
      _finish(session);
      expect(note.paragraphs.first.text, ' ');
      expect(note.paragraphs.first.inlines.first, isA<WmlNoteMarker>());
      expect(note.paragraphs.last.text, 'Tail');
      expect(session.caretAfter, (paragraph: note.paragraphs.last, offset: 0));
    });

    test('$label empty authored story receives a main-flow table caret', () {
      final document = WmlDocument.empty(text: 'Body');
      final note = WordNotes.insert(
        document,
        document.paragraphs.single,
        endnote: endnote,
      );
      final session = _session(document, note.paragraphs.single);
      _start(session, _table('Cell', ''), type: type);
      _finish(session);
      expect(note.blocks.map((b) => b.runtimeType), [
        WmlParagraph,
        WmlTable,
        WmlParagraph,
      ]);
      final suffix = note.blocks.last as WmlParagraph;
      expect(session.caretAfter, (paragraph: suffix, offset: 0));
      expect(WordNotes.editableParagraphs(note).last, same(suffix));
      final restored =
          (endnote ? _reopen(document).endnotes : _reopen(document).footnotes)
              .single;
      expect(
        restored.paragraphs.first.inlines.any((i) => i is WmlNoteMarker),
        isTrue,
      );
    });

    test(
      '$label incompatible table citation conversion leaves all content staged',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Keep',
        );
        final original = note.paragraphs.single;
        final session = _session(document, original);
        _start(session, _table(_one, ''), type: type);
        expect(
          () => _convert(session, ['FIRST1'], type: endnote ? 1 : 2),
          throwsUnsupportedError,
        );
        expect(
          () => _call(session, 'Document.complete'),
          throwsFormatException,
        );
        expect(note.blocks, [same(original)]);
        expect(note.text, 'Keep');
        expect(WordZotero.fields(document), isEmpty);
      },
    );
  }

  for (final type in [1, 2]) {
    test(
      'table cell citations create separate native notes for style $type',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final session = _session(
          document,
          document.paragraphs.single,
          start: 4,
        );
        _start(session, _table('First $_one', 'Second $_two'), type: type);
        final fields = _convert(session, ['SECOND2', 'FIRST1'], type: type);
        expect(fields.map((f) => f['noteIndex']), [2, 1]);
        _set(session, fields[0], 'two', '(Two)');
        _set(session, fields[1], 'one', '(One)');
        _finish(session);
        final table = _onlyTable(document.sections.single.blocks);
        final references = WordTree.paragraphs([table])
            .expand((p) => p.inlines.whereType<WmlRun>())
            .where((r) => r.noteRefId != null)
            .toList();
        expect(references, hasLength(2));
        expect(
          references.every((r) => r.noteRefEndnote == (type == 2)),
          isTrue,
        );
        for (final result in [document, _reopen(document)]) {
          expect(
            (type == 2 ? result.endnotes : result.footnotes),
            hasLength(2),
          );
          expect(
            _fields(
              _session(result, result.paragraphs.first),
            ).map((f) => f['noteIndex']),
            [1, 2],
          );
        }
      },
    );
  }

  test(
    'table geometry pictures lists and citations survive DOCX and refresh',
    () {
      final png = image.encodePng(
        image.Image(width: 2, height: 2, numChannels: 4),
      );
      final document = WmlDocument.empty(text: 'BeforeAfter');
      final session = _session(document, document.paragraphs.single, start: 6);
      final html =
          '<table><tbody><tr>'
          '<td data-colwidth="120" style="background-color: #abcdef">'
          '<ol start="3"><li>First $_one</li><li>Next</li></ol></td>'
          '<td data-colwidth="240"><p><img src="data:image/png;base64,'
          '${base64Encode(png)}" width="24" alt="Cell image"/></p>'
          '<ol start="7"><li>Second $_two</li></ol></td>'
          '</tr></tbody></table>';
      _start(session, html);
      final fields = _convert(session, ['SECOND2', 'FIRST1']);
      _set(session, fields[0], 'two', '(Two)');
      _set(session, fields[1], 'one', '(One)');
      _finish(session);
      var result = _reopen(document);
      for (var round = 0; round < 2; round++) {
        final table = _onlyTable(result.sections.single.blocks);
        expect(table.grid, [90.0, 180.0]);
        expect(table.rows.single.cells.first.fillColor, 'ABCDEF');
        final paragraphs = WordTree.paragraphs([table]).toList();
        expect(
          paragraphs
              .where((p) => p.properties.listLabel != null)
              .map((p) => p.properties.listLabel),
          ['3. ', '4. ', '7. '],
        );
        final visuals = paragraphs
            .expand((p) => p.inlines.whereType<WmlRun>())
            .where((r) => r.inlineVisual != null)
            .toList();
        expect(visuals, hasLength(1));
        final refresh = _session(result, result.paragraphs.first);
        final current = _fields(refresh);
        expect(current, hasLength(2));
        _set(refresh, current[0], 'one', '(One refreshed)');
        _set(refresh, current[1], 'two', '(Two refreshed)');
        _finish(refresh);
        expect(WordZotero.fields(result).map((f) => f.cachedText), [
          '(One refreshed)',
          '(Two refreshed)',
        ]);
        expect(_onlyTable(result.sections.single.blocks), same(table));
        expect(table.grid, [90.0, 180.0]);
        result = _reopen(result);
      }
    },
  );

  test('table payload cannot create a nested destination table', () {
    final target = WmlParagraph(inlines: [WmlRun(text: 'Keep')]);
    final cell = WmlTableCell(blocks: [target]);
    final outer = WmlTable(
      rows: [
        WmlTableRow(cells: [cell]),
      ],
      grid: [120],
    );
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [outer]),
      ],
    );
    final session = _session(document, target);
    expect(() => _start(session, _table('A', 'B')), throwsUnsupportedError);
    expect(cell.blocks, [same(target)]);
    expect(target.text, 'Keep');
    expect(document.sections.single.blocks, [same(outer)]);
  });

  test(
    'moving a staged table target into a cell refuses apply before mutation',
    () {
      final document = WmlDocument.empty(text: 'Keep');
      final paragraph = document.paragraphs.single;
      final session = _session(document, paragraph);
      _start(session, _table('A', 'B'));
      _call(session, 'Document.complete');
      final outer = WmlTable(
        rows: [
          WmlTableRow(
            cells: [
              WmlTableCell(blocks: [paragraph]),
            ],
          ),
        ],
        grid: [120],
      );
      document.sections.single.blocks
        ..clear()
        ..add(outer);
      expect(session.apply, throwsA(anything));
      expect(outer.rows.single.cells.single.blocks, [same(paragraph)]);
      expect(paragraph.text, 'Keep');
    },
  );

  for (final ids in [
    <String>[],
    ['FIRST1'],
    ['FIRST1', 'FIRST1'],
    ['FIRST1', 'UNKNOWN'],
  ]) {
    test(
      'incomplete or invalid table placeholders reject atomically: $ids',
      () {
        final document = WmlDocument.empty(text: 'Keep');
        final paragraph = document.paragraphs.single;
        final session = _session(document, paragraph, end: 4);
        _start(session, _table(_one, _two));
        expect(() => _convert(session, ids), throwsFormatException);
        expect(
          () => _call(session, 'Document.complete'),
          throwsFormatException,
        );
        expect(document.sections.single.blocks, [same(paragraph)]);
        expect(paragraph.text, 'Keep');
        expect(WordZotero.fields(document), isEmpty);
        expect(document.footnotes, isEmpty);
        expect(document.endnotes, isEmpty);
      },
    );
  }
}
