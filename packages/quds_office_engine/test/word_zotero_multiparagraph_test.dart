import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _id = 'research-paragraph-range';
const _one = '<a href="https://www.zotero.org/?FIRST1">(one)</a>';
const _two = '<a href="https://www.zotero.org/?SECOND2">(two)</a>';

WmlParagraph _paragraph(
  String text, {
  bool bold = false,
  bool italic = false,
}) => WmlParagraph(
  inlines: [
    WmlRun(
      text: text,
      properties: WmlRunProps(bold: bold, italic: italic),
    ),
  ],
);

WmlDocument _document(List<WmlBlock> blocks) =>
    WmlDocument(sections: [WmlSection(blocks: blocks)]);

WordZoteroCitingSession _session(
  WmlDocument document,
  WmlParagraph first,
  WmlParagraph last, {
  int start = 0,
  int end = 0,
}) => WordZoteroCitingSession(
  document: document,
  documentId: _id,
  insertionParagraph: first,
  insertionOffset: start,
  insertionEndParagraph: last,
  insertionEndOffset: end,
);

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

void _finish(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

WmlContentControlData _control() => WmlContentControlData(
  xml:
      '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr><w:id w:val="12"/>'
      '</w:sdtPr><w:sdtContent/></w:sdt>',
  sourcePartUri: '/word/document.xml',
  relationships: [],
);

void main() {
  for (final complex in [false, true]) {
    for (final side in ['prefix', 'suffix', 'zero suffix']) {
      test(
        'untouched $side citation packet (complex=$complex) stays active',
        () {
          final first = _paragraph('Before Remove');
          final last = _paragraph(
            side == 'zero suffix' ? ' After' : 'Remove After',
          );
          final document = _document([first, last]);
          final target = side == 'prefix' ? first : last;
          WordZotero.insertCitation(
            target,
            _citation('keep', '(Old)'),
            index: side == 'prefix'
                ? 7
                : side == 'zero suffix'
                ? 0
                : 6,
          );
          if (complex) {
            final run = target.inlines.whereType<WmlRun>().singleWhere(
              (run) => run.fieldInstruction != null,
            );
            final index = target.inlines.indexOf(run);
            target.inlines.replaceRange(index, index + 1, [
              WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
              WmlFieldBoundary(
                kind: WmlFieldBoundaryKind.instruction,
                text: run.fieldInstruction!,
              ),
              WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
              WmlRun(text: run.text, properties: run.properties.copy()),
              WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
            ]);
            target.properties
              ..fieldBegin = true
              ..fieldSeparate = true
              ..fieldEnd = true;
          }
          final field = WordZotero.fields(document).single;
          final session = _session(
            document,
            first,
            last,
            start: side == 'prefix' ? field.end : 7,
            end: side == 'zero suffix' ? 0 : 6,
          );
          expect(session.canInsertNoteText, isTrue);
          final original =
              (_call(session, 'Document.getFields', ['Http']) as List)
                  .cast<Map<String, Object>>()
                  .single;
          _stage(session, '<p>New</p>');
          _set(session, original, 'keep', '(Updated source)');
          _finish(session);
          expect(
            document.paragraphs.single.text,
            side == 'prefix'
                ? 'Before (Updated source)New After'
                : 'Before New(Updated source) After',
          );
          expect(
            WordZotero.fields(_reopen(document)).single.citation!.citationId,
            'keep',
          );
        },
      );
    }
  }

  test('an empty citation in a fully consumed paragraph remains protected', () {
    final first = _paragraph('First');
    final middle = _paragraph('');
    final last = _paragraph('Last');
    final document = _document([first, middle, last]);
    WordZotero.insertCitation(middle, _citation('keep', ''));
    expect(
      _session(document, first, last, start: 2, end: 2).canInsertNoteText,
      isFalse,
    );
    expect(WordZotero.fields(document).single.citation!.citationId, 'keep');
  });

  for (final metadata in [
    'bookmark',
    'source bookmark',
    'begin',
    'separate',
    'end',
  ]) {
    test('preserves paragraph-owned $metadata by refusing its replacement', () {
      final first = _paragraph('First');
      final middle = _paragraph('Middle');
      final last = _paragraph('Last');
      switch (metadata) {
        case 'bookmark':
          middle.properties.bookmarkName = 'Keep';
        case 'source bookmark':
          middle.properties.sourceBookmarkName = 'Keep';
        case 'begin':
          middle.properties.fieldBegin = true;
        case 'separate':
          middle.properties.fieldSeparate = true;
        case 'end':
          middle.properties.fieldEnd = true;
      }
      final document = _document([first, middle, last]);
      expect(
        _session(document, first, last, start: 1, end: 2).canInsertNoteText,
        isFalse,
      );
      expect(document.sections.single.blocks, [first, middle, last]);
    });
  }

  for (final otherOwner in ['section', 'header', 'comment', 'note']) {
    test('refuses a paragraph also owned by another $otherOwner', () {
      final first = _paragraph('First');
      final shared = _paragraph('Last suffix');
      final document = _document([first, shared]);
      switch (otherOwner) {
        case 'section':
          document.sections.add(WmlSection(blocks: [shared]));
        case 'header':
          document.sections.single.header.add(shared);
        case 'comment':
          document.comments.add(WmlComment(id: 1, paragraphs: [shared]));
        case 'note':
          document.footnotes.add(
            WmlNote(id: 1, endnote: false, paragraphs: [shared]),
          );
      }
      expect(
        _session(document, first, shared, start: 2, end: 4).canInsertNoteText,
        isFalse,
      );
      expect(shared.text, 'Last suffix');
    });
  }

  for (final endnote in [false, true]) {
    for (final marker in [false, true]) {
      for (final html in [
        '<p>New</p>',
        '<h2>New</h2>',
        '<table><tr><td>New</td></tr></table>',
      ]) {
        test(
          '${endnote ? 'endnote' : 'footnote'} raw zero $marker $html retains both spaces',
          () {
            final document = WmlDocument.empty(text: 'Body');
            final note = WordNotes.insert(
              document,
              document.paragraphs.single,
              endnote: endnote,
              text: ' Remove',
            );
            final first = note.paragraphs.single;
            if (marker) {
              first.inlines.insert(
                0,
                WmlNoteMarker(endnote: endnote, properties: WmlRunProps()),
              );
            }
            final last = _paragraph('Remove suffix');
            note.blocks.add(last);
            final session = _session(document, first, last, end: 6);
            expect(session.canInsertNoteText, isTrue);
            _stage(session, html);
            _finish(session);
            expect(note.allParagraphs.first.text, startsWith(' '));
            expect(note.allParagraphs.last.text, endsWith(' suffix'));
            if (html.startsWith('<p>')) {
              expect(note.allParagraphs.single.text, ' New suffix');
              expect(session.caretAfter!.offset, 4);
            } else {
              expect(note.allParagraphs.last.text, ' suffix');
            }
            final reopened = _reopen(document);
            final saved = endnote
                ? reopened.endnotes.single
                : reopened.footnotes.single;
            expect(saved.allParagraphs.first.text, startsWith(' '));
            expect(saved.allParagraphs.last.text, endsWith(' suffix'));
          },
        );
      }
    }
  }

  for (final endpoints in [(0, 0), (0, 5), (5, 0), (2, 3)]) {
    test('replaces half-open paragraphs at endpoints $endpoints', () {
      final first = _paragraph('First', bold: true);
      final last = _paragraph('Final', italic: true);
      final document = _document([first, _paragraph(''), last]);
      final session = _session(
        document,
        first,
        last,
        start: endpoints.$1,
        end: endpoints.$2,
      );
      expect(session.canInsertNoteText, isTrue);
      _stage(session, '<p>New</p>');
      expect(document.paragraphs.map((p) => p.text), ['First', '', 'Final']);
      _finish(session);
      final expected =
          '${'First'.substring(0, endpoints.$1)}New${'Final'.substring(endpoints.$2)}';
      expect(document.paragraphs.single.text, expected);
      expect(session.caretAfter!.offset, endpoints.$1 + 3);
      if (endpoints.$1 > 0) {
        expect(first.inlines.whereType<WmlRun>().first.properties.bold, isTrue);
      }
      if (endpoints.$2 < 5) {
        expect(
          first.inlines.whereType<WmlRun>().last.properties.italic,
          isTrue,
        );
      }
      expect(_reopen(document).paragraphs.single.text, expected);
    });
  }

  test('separate plain suffix keeps its end paragraph formatting', () {
    final first = _paragraph('Left remove', bold: true)
      ..properties.justification = WmlJustification.center
      ..properties.explicitJustification = true;
    final last = _paragraph('remove Right', italic: true)
      ..properties.justification = WmlJustification.right
      ..properties.explicitJustification = true;
    final document = _document([first, _paragraph('discard'), last]);
    final session = _session(document, first, last, start: 5, end: 6);
    _stage(session, '<p>Alpha</p><p>Beta</p>');
    _finish(session);
    for (final model in [document, _reopen(document)]) {
      final paragraphs = model.paragraphs.toList();
      expect(paragraphs.map((p) => p.text), ['Left Alpha', 'Beta Right']);
      expect(
        paragraphs.first.properties.justification,
        WmlJustification.center,
      );
      expect(paragraphs.last.properties.justification, WmlJustification.right);
      expect(
        paragraphs.last.inlines.whereType<WmlRun>().last.properties.italic,
        isTrue,
      );
    }
    expect(session.caretAfter!.offset, 4);
  });

  for (final story in ['body', 'footnote', 'endnote']) {
    for (final payload in {
      'paragraphs': '<p>Alpha $_one</p><p>Beta $_two</p>',
      'list': '<ol start="3"><li>Alpha $_one</li><li>Beta $_two</li></ol>',
      'table':
          '<table><tbody><tr><td rowspan="2"><p>Alpha $_one</p></td>'
          '<td><p>Beta $_two</p></td></tr><tr><td>Cell</td></tr>'
          '</tbody></table>',
    }.entries) {
      test(
        '$story ${payload.key} preserves citation order and rich suffix',
        () {
          final first = _paragraph('Left replace', bold: true);
          final last = _paragraph('remove Right', italic: true)
            ..properties.justification = WmlJustification.right
            ..properties.explicitJustification = true;
          final blocks = <WmlBlock>[first, _paragraph('middle'), last];
          final document = _document(
            story == 'body' ? blocks : [_paragraph('Body')],
          );
          WmlNote? note;
          if (story != 'body') {
            note = WordNotes.insert(
              document,
              document.paragraphs.single,
              endnote: story == 'endnote',
              text: 'Original',
            );
            note.blocks
              ..clear()
              ..addAll(blocks);
            first.inlines.insert(
              0,
              WmlNoteMarker(
                endnote: story == 'endnote',
                properties: WmlRunProps(vertAlign: WmlVertAlign.superscript),
              ),
            );
            first.inlines.insert(1, WmlRun(text: ' '));
          }
          WordZotero.insertCitation(
            first,
            _citation('before', '(B)'),
            index: story == 'body' ? 0 : 1,
          );
          WordZotero.insertCitation(
            last,
            _citation('after', '(A)'),
            index: last.text.length,
          );
          final session = _session(
            document,
            first,
            last,
            start: first.text.indexOf('replace'),
            end: 6,
          );
          final original =
              (_call(session, 'Document.getFields', ['Http']) as List)
                  .cast<Map<String, Object>>();
          _stage(session, payload.value);
          final inserted =
              (_call(session, 'Document.convertPlaceholdersToFields', [
                        ['SECOND2', 'FIRST1'],
                        0,
                        'Http',
                      ])
                      as List)
                  .cast<Map<String, Object>>();
          expect(
            inserted.map((f) => f['noteIndex']),
            story == 'body' ? [0, 0] : [1, 1],
          );
          _set(session, inserted[0], 'two', '(Two)');
          _set(session, inserted[1], 'one', '(One)');
          _set(session, original.first, 'before', '(Expanded before)');
          _set(session, original.last, 'after', '(Expanded after)');
          _finish(session);
          expect(
            session.caretAfter!.paragraph.text,
            payload.key == 'table'
                ? ' Right(Expanded after)'
                : contains('(Two)'),
          );
          for (
            var round = 0, model = document;
            round < 3;
            round++, model = _reopen(model)
          ) {
            final fields = WordZotero.fields(model);
            expect(fields.map((f) => f.citation!.citationId), [
              'before',
              'one',
              'two',
              'after',
            ]);
            expect(
              fields.map((f) => f.citation!.items.single.locator),
              everyElement('17'),
            );
            final paragraphs = story == 'body'
                ? model.paragraphs.toList()
                : (story == 'footnote'
                          ? model.footnotes.single
                          : model.endnotes.single)
                      .allParagraphs
                      .toList();
            expect(paragraphs.first.text, contains('(Expanded before)Left '));
            expect(paragraphs.last.text, endsWith(' Right(Expanded after)'));
            expect(
              paragraphs.any(
                (p) => p.text.contains('replace') || p.text.contains('remove'),
              ),
              isFalse,
            );
            expect(
              paragraphs.last.inlines.whereType<WmlRun>().any(
                (run) =>
                    run.text.contains('Right') && run.properties.italic == true,
              ),
              isTrue,
            );
            if (story != 'body') {
              expect(
                paragraphs.first.inlines.whereType<WmlNoteMarker>(),
                hasLength(1),
              );
              expect(paragraphs.first.text, startsWith(' '));
            }
          }
          if (note != null) expect(document.paragraphs.single.text, 'Body1');
        },
      );
    }
  }

  for (final marker in [
    'bookmark',
    'comment',
    'native field',
    'control',
    'paragraph field',
    'empty atomic',
  ]) {
    test('refuses selected $marker without changing any paragraph', () {
      final first = _paragraph('First');
      final middle = _paragraph('Middle');
      final last = _paragraph('Last');
      switch (marker) {
        case 'bookmark':
          middle.inlines.insert(
            0,
            WmlBookmarkBoundary(id: '8', isStart: true, name: 'Keep'),
          );
          middle.inlines.add(WmlBookmarkBoundary(id: '8', isStart: false));
        case 'comment':
          middle.inlines.whereType<WmlRun>().single.commentIds.add(4);
        case 'native field':
          middle.inlines.insertAll(0, [
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
            WmlFieldBoundary(
              kind: WmlFieldBoundaryKind.instruction,
              text: ' DATE ',
            ),
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          ]);
          middle.inlines.add(WmlFieldBoundary(kind: WmlFieldBoundaryKind.end));
        case 'control':
          final control = _control();
          middle.inlines.insert(
            0,
            WmlContentControlBoundary(control: control, start: true),
          );
          middle.inlines.add(
            WmlContentControlBoundary(control: control, start: false),
          );
        case 'paragraph field':
          middle.properties.fieldInstruction = ' PAGE ';
        case 'empty atomic':
          middle.inlines.add(WmlRun(text: '', fieldInstruction: ' DATE '));
      }
      final document = _document([first, middle, last]);
      final session = _session(document, first, last, start: 2, end: 2);
      expect(session.canInsertNoteText, isFalse);
      expect(
        () => _call(session, 'Document.insertText', ['<p>New</p>']),
        throwsUnsupportedError,
      );
      expect(document.sections.single.blocks, [first, middle, last]);
      expect(document.paragraphs.map((p) => p.text), [
        'First',
        'Middle',
        'Last',
      ]);
    });
  }

  test(
    'refuses a citation or note reference in a consumed middle paragraph',
    () {
      for (final note in [false, true]) {
        final first = _paragraph('First');
        final middle = _paragraph('Middle');
        final last = _paragraph('Last');
        final document = _document([first, middle, last]);
        if (note) {
          WordNotes.insert(document, middle, text: 'Keep note', endnote: false);
        } else {
          WordZotero.insertCitation(middle, _citation('keep', '(Keep)'));
        }
        final session = _session(document, first, last, start: 2, end: 2);
        expect(session.canInsertNoteText, isFalse);
        expect(document.paragraphs, hasLength(3));
      }
    },
  );

  for (final structure in [
    'table',
    'content control',
    'section',
    'table cell boundary',
  ]) {
    test('refuses crossing $structure ownership', () {
      final first = _paragraph('First');
      final last = _paragraph('Last');
      final document = _document([first, last]);
      switch (structure) {
        case 'table':
          document.sections.single.blocks.insert(
            1,
            WmlTable(
              rows: [
                WmlTableRow(
                  cells: [
                    WmlTableCell(blocks: [_paragraph('cell')]),
                  ],
                ),
              ],
            ),
          );
        case 'content control':
          document.sections.single.blocks
            ..clear()
            ..add(
              WmlContentControlBlock(
                control: _control(),
                blocks: [first, last],
              ),
            );
        case 'section':
          document.sections.single.blocks.removeLast();
          document.sections.add(WmlSection(blocks: [last]));
        case 'table cell boundary':
          document.sections.single.blocks
            ..clear()
            ..add(
              WmlTable(
                rows: [
                  WmlTableRow(
                    cells: [
                      WmlTableCell(blocks: [first]),
                      WmlTableCell(blocks: [last]),
                    ],
                  ),
                ],
              ),
            );
      }
      expect(
        _session(document, first, last, start: 1, end: 2).canInsertNoteText,
        isFalse,
      );
      expect(first.text, 'First');
      expect(last.text, 'Last');
    });
  }

  test(
    'refuses an enclosing native field with both boundaries outside the range',
    () {
      final before = _paragraph('Before')
        ..inlines.insertAll(0, [
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' REF source ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
        ]);
      final first = _paragraph('First');
      final last = _paragraph('Last');
      final after = _paragraph('After')
        ..inlines.add(WmlFieldBoundary(kind: WmlFieldBoundaryKind.end));
      final document = _document([before, first, last, after]);
      expect(
        _session(document, first, last, start: 1, end: 2).canInsertNoteText,
        isFalse,
      );
    },
  );

  test('reversed, foreign and surrogate-splitting endpoints are refused', () {
    final first = _paragraph('A😀B');
    final last = _paragraph('C😀D');
    final document = _document([first, last]);
    for (final session in [
      _session(document, last, first, start: 1, end: 1),
      _session(document, first, _paragraph('Foreign'), end: 1),
      _session(document, first, last, start: 2, end: 3),
      _session(document, first, last, start: 1, end: 2),
    ]) {
      expect(session.canInsertNoteText, isFalse);
    }
    expect(() => _session(document, first, last, end: 9), throwsArgumentError);
  });

  for (final change in ['text', 'order', 'container', 'bookmark']) {
    test('rechecks $change before applying a completed replacement', () {
      final first = _paragraph('First');
      final middle = _paragraph('Middle');
      final last = _paragraph('Last');
      final document = _document([first, middle, last]);
      final session = _session(document, first, last, start: 2, end: 2);
      _stage(session, '<p>New</p>');
      _call(session, 'Document.complete');
      switch (change) {
        case 'text':
          middle.inlines.add(WmlRun(text: ' changed'));
        case 'order':
          document.sections.single.blocks.setAll(0, [first, last, middle]);
        case 'container':
          document.sections.single.blocks
            ..clear()
            ..add(
              WmlContentControlBlock(
                control: _control(),
                blocks: [first, middle, last],
              ),
            );
        case 'bookmark':
          middle.inlines.insert(
            0,
            WmlBookmarkBoundary(id: '9', isStart: true, name: 'Later'),
          );
          middle.inlines.add(WmlBookmarkBoundary(id: '9', isStart: false));
      }
      expect(
        session.apply,
        throwsA(anyOf(isA<StateError>(), isA<UnsupportedError>())),
      );
      expect(first.text, 'First');
      expect(last.text, 'Last');
      expect(document.paragraphs.any((p) => p.text.contains('New')), isFalse);
    });
  }
}
