import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _id = 'writing-position-test';
const _bibliographyCode =
    ' ADDIN ZOTERO_BIBL {"uncited":[],"omitted":[],"custom":[]} CSL_BIBLIOGRAPHY ';

ZoteroCitation _citation(String id, String text) => ZoteroCitation(
  citationId: id,
  plainCitation: text,
  items: [
    ZoteroCitationItem.fromCsl(
      itemData: {'type': 'book', 'title': 'Source $id'},
      uris: ['http://zotero.org/users/42/items/ABCD1234'],
    ),
  ],
);

WmlParagraph _paragraph(String text) =>
    WmlParagraph(inlines: [WmlRun(text: text)]);

WmlDocument _document({String first = '(A)', String? second}) {
  final document = WmlDocument.empty(text: 'Before ');
  final paragraph = document.paragraphs.first;
  WordZotero.insertCitation(paragraph, _citation('a', first));
  if (second != null) {
    paragraph.inlines.add(WmlRun(text: ' between '));
    WordZotero.insertCitation(paragraph, _citation('b', second));
  }
  paragraph.inlines.add(WmlRun(text: ' trailing prose'));
  return document;
}

WordZoteroCitingSession _session(WmlDocument document) =>
    WordZoteroCitingSession(
      document: document,
      documentId: _id,
      insertionParagraph: document.paragraphs.first,
      insertionOffset: 0,
    );

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> args = const [],
]) => session.handle(command, [_id, ...args]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object>>();

void _text(WordZoteroCitingSession session, Object id, String text) =>
    _call(session, 'Field.setText', [id, text, false]);

void _apply(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

void _expectPosition(
  WordZoteroCitingSession session,
  WordZoteroCitingPosition position,
  WmlParagraph paragraph,
  int offset,
) {
  final resolved = session.resolvePosition(position);
  expect(resolved, isNotNull);
  expect(resolved!.paragraph, same(paragraph));
  expect(resolved.offset, offset);
}

void main() {
  test('positions are bounded, source-owned and resolve only after apply', () {
    final document = WmlDocument.empty(text: 'Writing');
    final paragraph = document.paragraphs.first;
    final session = _session(document);
    final position = session.capturePosition(paragraph, 3);
    final foreign = _session(document);
    expect(() => session.resolvePosition(position), throwsStateError);
    expect(() => foreign.resolvePosition(position), throwsArgumentError);
    for (final offset in [-1, paragraph.text.length + 1]) {
      expect(
        () => session.capturePosition(paragraph, offset),
        throwsArgumentError,
      );
    }
    expect(
      () => session.capturePosition(_paragraph('Writing'), 3),
      throwsArgumentError,
    );
    for (var i = 1; i < 8; i++) {
      session.capturePosition(paragraph, i);
    }
    expect(() => session.capturePosition(paragraph, 0), throwsStateError);
    _apply(session);
    _expectPosition(session, position, paragraph, 3);
    expect(() => session.capturePosition(paragraph, 0), throwsStateError);
    expect(paragraph.text, 'Writing');
  });

  test('unanchored note paragraphs cannot be captured', () {
    final document = WmlDocument.empty(text: 'Body');
    final orphan = WmlNote(
      id: 1,
      endnote: false,
      paragraphs: [_paragraph('Note')],
    );
    document.footnotes.add(orphan);
    final session = _session(document);
    expect(
      () => session.capturePosition(orphan.paragraphs.first, 1),
      throwsArgumentError,
    );
  });

  for (final kind in ['frame', 'toc-title', 'toc-item']) {
    test('passive $kind endpoint survives preceding bibliography reflow', () {
      final target = _paragraph('Passive writing target');
      final WmlBlock owner = switch (kind) {
        'frame' => WmlFrame(blocks: [target]),
        'toc-title' => WmlToc(titleParagraph: target),
        _ => WmlToc(itemParagraphs: [target]),
      };
      final bibliography = WordZotero.nativeBibliographyParagraphs(
        instruction: _bibliographyCode,
        text: 'First entry',
      );
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [...bibliography, owner]),
        ],
      );
      final session = _session(document);
      final endpoint = session.capturePosition(target, 8);
      _text(session, _fields(session).single['id']!, 'One\nTwo\nThree');
      _apply(session);
      _expectPosition(session, endpoint, target, 8);
      expect(target.text, 'Passive writing target');
    });
  }

  test('passive endpoint identity changes still reject application', () {
    final target = _paragraph('Frame prose');
    final frame = WmlFrame(blocks: [target]);
    final document = _document();
    document.sections.single.blocks.add(frame);
    final session = _session(document);
    session.capturePosition(target, 3);
    _text(session, _fields(session).single['id']!, 'Expanded');
    _call(session, 'Document.complete');
    frame.blocks[0] = _paragraph('Frame prose');
    expect(session.apply, throwsStateError);
    expect(WordZotero.fields(document).single.cachedText, '(A)');
  });

  test('passive frame capture does not allow native fields in a frame', () {
    final target = _paragraph('Frame ');
    WordZotero.insertCitation(target, _citation('frame', '(A)'));
    final document = WmlDocument.empty(text: 'Body');
    document.sections.single.blocks.add(WmlFrame(blocks: [target]));
    expect(() => _session(document), throwsUnsupportedError);
  });

  for (final replacement in ['(A much longer author citation)', 'X', '']) {
    test('refresh retains prose and field boundaries for "$replacement"', () {
      final document = _document();
      final paragraph = document.paragraphs.first;
      final original = WordZotero.fields(document).single;
      final session = _session(document);
      final before = session.capturePosition(paragraph, original.start - 1);
      final start = session.capturePosition(paragraph, original.start);
      final interior = session.capturePosition(paragraph, original.start + 1);
      final end = session.capturePosition(paragraph, original.end);
      final prose = session.capturePosition(paragraph, original.end + 5);
      _text(session, _fields(session).single['id']!, replacement);
      _apply(session);
      final newEnd = original.start + replacement.length;
      _expectPosition(session, before, paragraph, original.start - 1);
      _expectPosition(session, start, paragraph, original.start);
      _expectPosition(session, interior, paragraph, newEnd);
      _expectPosition(session, end, paragraph, newEnd);
      _expectPosition(session, prose, paragraph, newEnd + 5);
      expect(paragraph.text.substring(newEnd), ' trailing prose');
    });
  }

  for (final reverseCommands in [false, true]) {
    test(
      'multiple refreshes combine offsets, command order=$reverseCommands',
      () {
        final document = _document(first: '(A)', second: '(Second)');
        final paragraph = document.paragraphs.first;
        final original = WordZotero.fields(document);
        final session = _session(document);
        final between = session.capturePosition(paragraph, original[0].end + 4);
        final after = session.capturePosition(paragraph, original[1].end + 6);
        final fields = _fields(session);
        final changes = [
          (fields[0]['id']!, '(A much longer author)'),
          (fields[1]['id']!, 'B'),
        ];
        for (final change in reverseCommands ? changes.reversed : changes) {
          _text(session, change.$1, change.$2);
        }
        _apply(session);
        final current = WordZotero.fields(document);
        _expectPosition(session, between, paragraph, current[0].end + 4);
        _expectPosition(session, after, paragraph, current[1].end + 6);
      },
    );
  }

  for (final mode in ['code', 'plain', 'rich', 'unlink']) {
    test('$mode with identical text preserves positions inside a citation', () {
      final document = _document();
      final paragraph = document.paragraphs.first;
      final original = WordZotero.fields(document).single;
      final session = _session(document);
      final position = session.capturePosition(paragraph, original.start + 1);
      final id = _fields(session).single['id']!;
      switch (mode) {
        case 'code':
          _call(session, 'Field.setCode', [
            id,
            'ITEM CSL_CITATION ${jsonEncode(_citation('replacement-id', '(A)').toJson())}',
          ]);
        case 'plain':
          _text(session, id, '(A)');
        case 'rich':
          _call(session, 'Field.setText', [id, '<i>(A)</i>', true]);
        case 'unlink':
          _call(session, 'Field.removeCode', [id]);
      }
      _apply(session);
      _expectPosition(session, position, paragraph, original.start + 1);
    });
  }

  for (final removeCode in [false, true]) {
    test(
      'delete/unlink maps the text actually retained: unlink=$removeCode',
      () {
        final document = _document();
        final paragraph = document.paragraphs.first;
        final original = WordZotero.fields(document).single;
        final session = _session(document);
        final interior = session.capturePosition(paragraph, original.start + 1);
        final prose = session.capturePosition(paragraph, original.end + 4);
        final id = _fields(session).single['id']!;
        if (removeCode) _text(session, id, 'Long ordinary reference');
        _call(session, removeCode ? 'Field.removeCode' : 'Field.delete', [id]);
        _apply(session);
        final end =
            original.start +
            (removeCode ? 'Long ordinary reference'.length : 0);
        _expectPosition(session, interior, paragraph, end);
        _expectPosition(session, prose, paragraph, end + 4);
        expect(WordZotero.fields(document), isEmpty);
      },
    );
  }

  test('adjacent citation deletion keeps their shared boundary anchored', () {
    final document = WmlDocument.empty(text: 'Prefix ');
    final paragraph = document.paragraphs.first;
    WordZotero.insertCitation(paragraph, _citation('first', '(A)'));
    WordZotero.insertCitation(paragraph, _citation('second', '(B)'));
    paragraph.inlines.add(WmlRun(text: ' suffix'));
    final original = WordZotero.fields(document);
    final session = _session(document);
    final boundary = session.capturePosition(paragraph, original.first.end);
    final after = session.capturePosition(paragraph, original.last.end + 3);
    final fields = _fields(session);
    _call(session, 'Field.delete', [fields.first['id']]);
    _text(session, fields.last['id']!, '(Combined references)');
    _apply(session);
    _expectPosition(session, boundary, paragraph, 'Prefix '.length);
    _expectPosition(
      session,
      after,
      paragraph,
      'Prefix (Combined references)'.length + 3,
    );
  });

  test('both adjacent citation resizes preserve their shared boundary', () {
    final document = WmlDocument.empty(text: 'Prefix ');
    final paragraph = document.paragraphs.first;
    WordZotero.insertCitation(paragraph, _citation('first', '(A)'));
    WordZotero.insertCitation(paragraph, _citation('second', '(B)'));
    paragraph.inlines.add(WmlRun(text: ' suffix'));
    final original = WordZotero.fields(document);
    final session = _session(document);
    final boundary = session.capturePosition(paragraph, original.first.end);
    final after = session.capturePosition(paragraph, original.last.end + 3);
    final fields = _fields(session);
    _text(session, fields.first['id']!, '(Expanded first)');
    _text(session, fields.last['id']!, 'B');
    _apply(session);
    final result = WordZotero.fields(document);
    _expectPosition(session, boundary, paragraph, result.first.end);
    _expectPosition(session, after, paragraph, result.last.end + 3);
  });

  for (final replacement in ['New', 'New one\nNew two\nNew three', null]) {
    test(
      'bibliography reflow retains following paragraph identity: $replacement',
      () {
        final before = _paragraph('Before bibliography');
        final after = _paragraph('Trailing prose');
        final entries = WordZotero.nativeBibliographyParagraphs(
          instruction: _bibliographyCode,
          text: 'Entry one\nEntry two',
        );
        final document = WmlDocument(
          sections: [
            WmlSection(blocks: [before, ...entries, after]),
          ],
        );
        final session = _session(document);
        final prose = session.capturePosition(after, 6);
        final start = session.capturePosition(entries.first, 0);
        final inside = session.capturePosition(entries.last, 3);
        final id = _fields(session).single['id']!;
        if (replacement == null) {
          _call(session, 'Field.delete', [id]);
        } else {
          _text(session, id, replacement);
        }
        _apply(session);
        _expectPosition(session, prose, after, 6);
        _expectPosition(session, start, entries.first, 0);
        final result = replacement == null
            ? entries.first
            : WordZotero.fields(document).single.paragraphs.last;
        _expectPosition(session, inside, result, result.text.length);
        expect(document.paragraphs.last, same(after));
      },
    );
  }

  test(
    'same bibliography text preserves interior across soft/paragraph breaks',
    () {
      final entries = WordZotero.nativeBibliographyParagraphs(
        instruction: _bibliographyCode,
        text: 'Entry one\nEntry two',
      );
      final document = WmlDocument(sections: [WmlSection(blocks: entries)]);
      final session = _session(document);
      final position = session.capturePosition(entries.last, 4);
      _call(session, 'Field.setText', [
        _fields(session).single['id'],
        '<div class="csl-entry">Entry one<br/>Entry two</div>',
        true,
      ]);
      _apply(session);
      final result = WordZotero.fields(document).single;
      expect(result.paragraphs, hasLength(1));
      _expectPosition(
        session,
        position,
        result.paragraph,
        'Entry one\n'.length + 4,
      );
    },
  );

  test('same bibliography text maps a soft break back to entry paragraphs', () {
    final formatted = ZoteroFormattedText.fromHtml(
      '<div class="csl-entry">Entry one<br/>Entry two</div>',
    );
    final entries = WordZotero.nativeBibliographyParagraphs(
      instruction: _bibliographyCode,
      text: formatted.plainText,
      formattedText: formatted,
    );
    expect(entries, hasLength(1));
    final document = WmlDocument(sections: [WmlSection(blocks: entries)]);
    final session = _session(document);
    final position = session.capturePosition(
      entries.single,
      'Entry one\n'.length + 4,
    );
    _call(session, 'Field.setText', [
      _fields(session).single['id'],
      '<div class="csl-entry">Entry one</div>'
          '<div class="csl-entry">Entry two</div>',
      true,
    ]);
    _apply(session);
    final result = WordZotero.fields(document).single;
    expect(result.paragraphs, hasLength(2));
    _expectPosition(session, position, result.paragraphs.last, 4);
  });

  for (final endnote in [false, true]) {
    test(
      'authored ${endnote ? 'endnote' : 'footnote'} prose follows refresh',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.first,
          endnote: endnote,
          text: 'See ',
        );
        final paragraph = note.paragraphs.first;
        WordZotero.insertCitation(paragraph, _citation('note', '(A)'));
        paragraph.inlines.add(WmlRun(text: ' for details'));
        final original = WordZotero.fields(document).single;
        final session = _session(document);
        final position = session.capturePosition(paragraph, original.end + 5);
        _text(
          session,
          _fields(session).single['id']!,
          '(Author and coauthor, 2026)',
        );
        _apply(session);
        final result = WordZotero.fields(document).single;
        _expectPosition(session, position, paragraph, result.end + 5);
        expect(
          (endnote ? document.endnotes : document.footnotes).single,
          same(note),
        );
      },
    );
  }

  for (final noteType in [1, 2]) {
    test(
      'inline citation conversion to note $noteType preserves prose endpoints',
      () {
        final document = _document();
        final paragraph = document.paragraphs.first;
        final original = WordZotero.fields(document).single;
        final session = _session(document);
        final start = session.capturePosition(paragraph, original.start);
        final interior = session.capturePosition(paragraph, original.start + 1);
        final prose = session.capturePosition(paragraph, original.end + 5);
        _call(session, 'Document.convert', [
          [_fields(session).single['id']],
          'Http',
          [noteType],
        ]);
        _apply(session);
        final marker = paragraph.inlines.whereType<WmlRun>().singleWhere(
          (run) => run.noteRefId != null,
        );
        final end = original.start + marker.text.length;
        _expectPosition(session, start, paragraph, original.start);
        _expectPosition(session, interior, paragraph, end);
        _expectPosition(session, prose, paragraph, end + 5);
      },
    );
  }

  for (final sourceEndnote in [false, true]) {
    for (final action in ['inline', 'other-note', 'delete']) {
      test(
        'sole-note $action keeps body prose and gives removed content a boundary ($sourceEndnote)',
        () {
          final document = WmlDocument.empty(text: 'Before ');
          final paragraph = document.paragraphs.first;
          // Reserve a two-digit ID so mapping uses the actual marker span.
          (sourceEndnote ? document.endnotes : document.footnotes).add(
            WmlNote(id: 11, endnote: sourceEndnote),
          );
          final note = WordNotes.insert(
            document,
            paragraph,
            endnote: sourceEndnote,
          );
          final noteParagraph = note.paragraphs.first;
          WordZotero.insertCitation(noteParagraph, _citation('note', '(A)'));
          paragraph.inlines.add(WmlRun(text: ' trailing prose'));
          final marker = paragraph.inlines.whereType<WmlRun>().singleWhere(
            (run) => run.noteRefId != null,
          );
          expect(marker.text.length, 2);
          final session = _session(document);
          final body = session.capturePosition(
            paragraph,
            'Before '.length + marker.text.length + 5,
          );
          final start = session.capturePosition(noteParagraph, 0);
          final interior = session.capturePosition(noteParagraph, 1);
          final id = _fields(session).single['id']!;
          if (action == 'delete') {
            _call(session, 'Field.delete', [id]);
          } else {
            _call(session, 'Document.convert', [
              [id],
              'Http',
              [
                action == 'inline'
                    ? 0
                    : sourceEndnote
                    ? 1
                    : 2,
              ],
            ]);
            _text(session, id, '(Expanded source)');
          }
          _apply(session);
          final trailing = paragraph.text.indexOf(' trailing prose');
          _expectPosition(session, body, paragraph, trailing + 5);
          _expectPosition(session, start, paragraph, 'Before '.length);
          _expectPosition(session, interior, paragraph, trailing);
        },
      );
    }
  }

  test('native capability query accepts the optional default field type', () {
    final session = _session(WmlDocument.empty(text: 'Body'));
    expect(_call(session, 'Document.canInsertField'), isTrue);
    expect(_call(session, 'Document.canInsertField', ['Http']), isTrue);
    expect(
      () => _call(session, 'Document.canInsertField', ['Field']),
      throwsUnsupportedError,
    );
    expect(
      () => _call(session, 'Document.canInsertField', ['Http', 0]),
      throwsFormatException,
    );
  });

  for (final explicitType in [false, true]) {
    test(
      'HTTP capability replay reaches native adapter, explicit=$explicitType',
      () async {
        final document = WmlDocument.empty(text: 'Body');
        final paragraph = document.paragraphs.first;
        final session = _session(document);
        var requests = 0;
        ZoteroHttpResponse response(String command, List<Object?> arguments) =>
            ZoteroHttpResponse(
              statusCode: 200,
              body: jsonEncode({'command': command, 'arguments': arguments}),
            );
        await ZoteroCitingClient(
          transport: (request) async {
            switch (requests++) {
              case 0:
                expect(jsonDecode(request.body!), {
                  'command': 'refresh',
                  'docId': _id,
                });
                return response('Application.getActiveDocument', []);
              case 1:
                final active =
                    jsonDecode(request.body!) as Map<String, Object?>;
                expect(active['documentID'], _id);
                return response('Document.canInsertField', [
                  _id,
                  if (explicitType) 'Http',
                ]);
              case 2:
                expect(jsonDecode(request.body!), isTrue);
                return response('Document.complete', [_id]);
              default:
                fail(
                  'An accepted capability query must not enter error cleanup.',
                );
            }
          },
        ).execute(
          command: ZoteroCitingCommand.refresh,
          documentId: _id,
          handler: session.handle,
        );
        expect(requests, 3);
        expect(session.isComplete, isTrue);
        // Controller hosts capture endpoints after protocol completion, just
        // before the staged edit is published.
        final endpoint = session.capturePosition(paragraph, 2);
        session.apply();
        _expectPosition(session, endpoint, paragraph, 2);
        expect(paragraph.text, 'Body');
      },
    );
  }
}
