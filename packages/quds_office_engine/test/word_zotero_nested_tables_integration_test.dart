import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _documentId = 'nested-research';

String _table(String content) => '<table><tr><td>$content</td></tr></table>';
String _placeholder(String id) =>
    '<a href="https://www.zotero.org/?$id">($id old)</a>';

WordZoteroCitingSession _session(
  WmlDocument document, {
  int start = 0,
  int? end,
}) => WordZoteroCitingSession(
  document: document,
  documentId: _documentId,
  insertionParagraph: document.paragraphs.first,
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

void _start(WordZoteroCitingSession session, String html) {
  final temp =
      _call(session, 'Document.insertField', ['Http', 0])!
          as Map<String, Object>;
  _call(session, 'Field.delete', [temp['id']]);
  _call(session, 'Document.insertText', [html]);
}

List<Map<String, Object>> _convert(
  WordZoteroCitingSession session,
  List<String> ids,
) =>
    (_call(session, 'Document.convertPlaceholdersToFields', [ids, 0, 'Http'])!
            as List<Object?>)
        .cast<Map<String, Object>>();

void _format(
  WordZoteroCitingSession session,
  Map<String, Object> field,
  String id,
) {
  final citation = ZoteroCitation(
    citationId: id,
    plainCitation: '($id)',
    items: [
      ZoteroCitationItem.fromCsl(
        itemData: {'id': id, 'type': 'book', 'title': 'Source $id'},
        uris: ['http://zotero.org/users/42/items/ABCD1234'],
      ),
    ],
  );
  _call(session, 'Field.setCode', [
    field['id'],
    'ITEM CSL_CITATION ${jsonEncode(citation.toJson())}',
  ]);
  _call(session, 'Field.setText', [field['id'], '<i>($id)</i>', true]);
}

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

String _payload() =>
    '<p>Intro ${_placeholder('FIRST1')}</p>'
    '${_table('<p>Outer</p>${_table('<ol start="4"><li>Deep ${_placeholder('DEEP2')}</li><li>Next</li></ol>')}')}'
    '<p>Tail ${_placeholder('LAST3')}</p>';

void main() {
  test(
    'nested citations remain detached and ordered through refresh and unlink',
    () {
      final document = WmlDocument.empty(text: 'BeforeTARGETAfter');
      final original = document.paragraphs.single;
      final session = _session(document, start: 6, end: 12);
      _start(session, _payload());
      final converted = _convert(session, ['LAST3', 'DEEP2', 'FIRST1']);
      for (var index = 0; index < converted.length; index++) {
        _format(session, converted[index], ['LAST3', 'DEEP2', 'FIRST1'][index]);
      }
      expect(_fields(session).map((field) => field['text']), [
        '(FIRST1)',
        '(DEEP2)',
        '(LAST3)',
      ]);
      expect(document.sections.single.blocks, [same(original)]);
      expect(original.text, 'BeforeTARGETAfter');
      expect(WordZotero.fields(document), isEmpty);
      _finish(session);

      var current = document;
      for (var round = 0; round < 3; round++) {
        final fields = WordZotero.fields(current);
        expect(fields.map((field) => field.cachedText), [
          '(FIRST1)',
          '(DEEP2)',
          '(LAST3)',
        ]);
        final tables = WordTree.descendants(
          current.sections.expand((section) => section.blocks),
        ).whereType<WmlTable>().toList();
        expect(tables, hasLength(2));
        expect(
          tables.first.rows.single.cells.single.blocks[1],
          same(tables.last),
        );
        expect(
          tables.first.rows.single.cells.single.blocks.last,
          isA<WmlParagraph>(),
        );
        expect(
          WordTree.paragraphs([tables.last]).map((p) => p.properties.listLabel),
          ['4. ', '5. '],
        );
        expect(
          fields[1].paragraph,
          same(WordTree.paragraphs([tables.last]).first),
        );
        final refresh = _session(current);
        for (final (index, field) in _fields(refresh).indexed) {
          _format(refresh, field, ['FIRST1', 'DEEP2', 'LAST3'][index]);
        }
        _finish(refresh);
        current = WordDeserializer().readBytes(
          WordSerializer().writeBytes(current),
        );
      }

      final beforeUnlink = current.paragraphs.map((p) => p.text).toList();
      final unlink = _session(current);
      for (final field in _fields(unlink)) {
        _call(unlink, 'Field.removeCode', [field['id']]);
      }
      _finish(unlink);
      expect(WordZotero.fields(current), isEmpty);
      expect(current.paragraphs.map((p) => p.text), beforeUnlink);
      expect(
        WordTree.descendants(
          current.sections.single.blocks,
        ).whereType<WmlTable>(),
        hasLength(2),
      );
    },
  );

  test('incomplete nested insertion cannot publish document changes', () {
    final document = WmlDocument.empty(text: 'Keep');
    final original = document.paragraphs.single;
    final session = _session(document);
    _start(session, _payload());
    final fields = _convert(session, ['FIRST1', 'DEEP2', 'LAST3']);
    for (final (index, field) in fields.indexed) {
      _format(session, field, ['FIRST1', 'DEEP2', 'LAST3'][index]);
    }
    expect(session.apply, throwsStateError);
    expect(original.text, 'Keep');
    expect(document.sections.single.blocks, [same(original)]);
    expect(WordZotero.fields(document), isEmpty);
  });

  test(
    'inner malformed table is rejected before any native content changes',
    () {
      final document = WmlDocument.empty(text: 'Keep');
      final original = document.paragraphs.single;
      final session = _session(document);
      expect(
        () => _start(
          session,
          _table(
            '<p>Good outer</p>'
            '<table><tr><td rowspan="2">Bad inner</td></tr></table>',
          ),
        ),
        throwsUnsupportedError,
      );
      expect(original.text, 'Keep');
      expect(document.sections.single.blocks, [same(original)]);
      expect(WordZotero.fields(document), isEmpty);
    },
  );

  test('unconverted deep placeholder blocks completion atomically', () {
    final document = WmlDocument.empty(text: 'Keep');
    final original = document.paragraphs.single;
    final session = _session(document);
    _start(session, _payload());
    expect(() => _convert(session, ['FIRST1', 'LAST3']), throwsFormatException);
    expect(() => _call(session, 'Document.complete'), throwsFormatException);
    expect(original.text, 'Keep');
    expect(document.sections.single.blocks, [same(original)]);
    expect(WordZotero.fields(document), isEmpty);
  });

  test(
    'all eight accepted table levels paint the actual deepest paragraph',
    () {
      var html = '<p>Deepest visible</p>';
      for (var level = 0; level < 8; level++) {
        html = _table(html);
      }
      final document = WmlDocument.empty(text: 'Target');
      final session = _session(document, end: 6);
      _start(session, html);
      _convert(session, []);
      _finish(session);
      final tables = WordTree.descendants(
        document.sections.single.blocks,
      ).whereType<WmlTable>().toList();
      expect(tables, hasLength(8));
      final paragraphs = document.paragraphs.toList();
      final deep = paragraphs.singleWhere((p) => p.text == 'Deepest visible');
      final laid = WordLayoutEngine(font: null).layout(document);
      expect(laid.pages, hasLength(1));
      final paintedTables = laid.pages.single.frames
          .map((frame) => frame.table)
          .whereType<WmlTable>()
          .toSet();
      expect(paintedTables, unorderedEquals(tables));
      final glyphs =
          laid.pages.single.lines
              .where((line) => line.paragraphIndex == paragraphs.indexOf(deep))
              .expand((line) => line.glyphs)
              .where((glyph) => !glyph.glyph.isSpace)
              .toList()
            ..sort(
              (a, b) => a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex),
            );
      expect(
        String.fromCharCodes(glyphs.map((glyph) => glyph.glyph.codePoint)),
        'Deepestvisible',
      );
    },
  );

  test(
    'a tall nested row retains each paragraph once across physical pages',
    () {
      final document = WmlDocument(
        sections: [
          WmlSection(
            pageSize: const WmlPageSize(width: 400, height: 200),
            margins: const WmlPageMargins(
              left: 20,
              right: 20,
              top: 20,
              bottom: 20,
            ),
            blocks: [
              WmlParagraph(inlines: [WmlRun(text: 'Target')]),
            ],
          ),
        ],
      );
      final html = _table(
        _table(
          [for (var index = 0; index < 60; index++) '<p>Line$index</p>'].join(),
        ),
      );
      final session = _session(document, end: 6);
      _start(session, html);
      _convert(session, []);
      _finish(session);
      for (var round = 0; round < 2; round++) {
        final current = round == 0
            ? document
            : WordDeserializer().readBytes(
                WordSerializer().writeBytes(document),
              );
        final paragraphs = current.paragraphs.toList();
        final laid = WordLayoutEngine(font: null).layout(current);
        expect(laid.pages.length, greaterThan(1));
        for (final (index, paragraph) in paragraphs.indexed) {
          if (paragraph.text.isEmpty) continue;
          final glyphs =
              laid.pages
                  .expand((page) => page.lines)
                  .where((line) => line.paragraphIndex == index)
                  .expand((line) => line.glyphs)
                  .where((glyph) => !glyph.glyph.isSpace)
                  .toList()
                ..sort(
                  (a, b) =>
                      a.glyph.logicalIndex.compareTo(b.glyph.logicalIndex),
                );
          expect(
            glyphs.map((glyph) => glyph.glyph.logicalIndex),
            List.generate(paragraph.text.length, (index) => index),
            reason: 'Every character paints once for ${paragraph.text}',
          );
          expect(
            String.fromCharCodes(glyphs.map((glyph) => glyph.glyph.codePoint)),
            paragraph.text,
          );
        }
      }
    },
  );
}
