import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _id = 'adjacent-citations';

ZoteroCitationItem _item(String id) => ZoteroCitationItem.fromCsl(
  itemData: {'type': 'book', 'title': 'Source $id'},
  uris: [
    'http://zotero.org/users/42/items/${id.toUpperCase().padRight(8, '0')}',
  ],
  locator: id == 'a' ? '12' : '34',
  label: id == 'a' ? 'page' : 'chapter',
  prefix: id == 'b' ? 'see ' : null,
  suffix: id == 'c' ? ', emphasis added' : null,
  suppressAuthor: id == 'b',
);

ZoteroCitation _citation(String id, {List<ZoteroCitationItem>? items}) =>
    ZoteroCitation(
      citationId: id,
      plainCitation: '($id)',
      items: items ?? [_item(id)],
    );

void _append(WmlParagraph paragraph, String id, {bool rich = false}) {
  WordZotero.insertNativeCitation(
    paragraph,
    instruction: _citation(id).fieldInstruction,
    text: '($id)',
    formattedText: rich ? ZoteroFormattedText.fromHtml('(<i>$id</i>)') : null,
  );
}

WmlDocument _document({bool rich = false}) {
  final document = WmlDocument.empty(text: 'Lead ');
  final paragraph = document.paragraphs.single;
  for (final id in ['a', 'b', 'c']) {
    _append(paragraph, id, rich: rich);
  }
  paragraph.inlines.add(WmlRun(text: ' tail'));
  return document;
}

WordZoteroCitingSession _session(WmlDocument document) =>
    WordZoteroCitingSession(
      document: document,
      documentId: _id,
      insertionParagraph: document.paragraphs.first,
    );

Object? _call(
  WordZoteroCitingSession session,
  String command, [
  List<Object?> arguments = const [],
]) => session.handle(command, [_id, ...arguments]);

List<Map<String, Object>> _fields(WordZoteroCitingSession session) =>
    (_call(session, 'Document.getFields', ['Http'])! as List<Object?>)
        .cast<Map<String, Object>>();

List<bool> _adjacency(WordZoteroCitingSession session) =>
    _fields(session).map((field) => field['adjacent']! as bool).toList();

void _mergeResponse(
  WordZoteroCitingSession session,
  List<Map<String, Object>> fields,
) {
  // Source-derived Refresh response: Zotero merges earlier adjacent clusters
  // into the final field, preserving that field's identity. Zotero owns item
  // ordering and de-duplication; this adapter accepts the processor's result.
  // integration.js at 98f6486db71115d4198d1f746f487aef45805a2b,
  // Session.updateFromDocument/addCitation and Citation.mergeCitation.
  final merged = ZoteroCitation(
    citationId: 'c',
    items: [_item('c'), _item('a'), _item('b')],
    plainCitation: '(c; a; b)',
    formattedCitation: '(<i>c</i>; a; b)',
  );
  _call(session, 'Field.setCode', [
    fields.last['id'],
    'ITEM CSL_CITATION ${jsonEncode(merged.toJson())}',
  ]);
  _call(session, 'Field.setText', [
    fields.last['id'],
    '(<i>c</i>; a; b)',
    true,
  ]);
  for (final field in fields.take(fields.length - 1)) {
    _call(session, 'Field.delete', [field['id']]);
  }
}

void _complete(WordZoteroCitingSession session) {
  _call(session, 'Document.complete');
  session.apply();
}

WmlDocument _reopen(WmlDocument document) =>
    WordDeserializer().readBytes(WordSerializer().writeBytes(document));

void main() {
  test(
    'native client carries adjacency and applies the complete merge response',
    () async {
      final document = _document(rich: true);
      final session = _session(document);
      var requestIndex = 0;
      var fields = <Map<String, Object?>>[];
      final merged = ZoteroCitation(
        citationId: 'c',
        items: [_item('c'), _item('a'), _item('b')],
        plainCitation: '(c; a; b)',
      );
      ZoteroHttpResponse command(String name, List<Object?> arguments) =>
          ZoteroHttpResponse(
            statusCode: 200,
            body: jsonEncode({'command': name, 'arguments': arguments}),
          );
      await ZoteroCitingClient(
        transport: (request) async {
          switch (requestIndex++) {
            case 0:
              expect(jsonDecode(request.body!), {
                'command': 'refresh',
                'docId': _id,
              });
              return command('Application.getActiveDocument', []);
            case 1:
              final response =
                  jsonDecode(request.body!) as Map<String, Object?>;
              expect(response['supportsCitationMerging'], isTrue);
              return command('Document.getFields', [_id, 'Http']);
            case 2:
              fields = (jsonDecode(request.body!) as List<Object?>)
                  .cast<Map<String, Object?>>();
              expect(fields.map((field) => field['adjacent']), [
                true,
                true,
                false,
              ]);
              return command('Field.setCode', [
                _id,
                fields.last['id'],
                'ITEM CSL_CITATION ${jsonEncode(merged.toJson())}',
              ]);
            case 3:
              return command('Field.setText', [
                _id,
                fields.last['id'],
                '(<i>c</i>; a; b)',
                true,
              ]);
            case 4:
              return command('Field.delete', [_id, fields[1]['id']]);
            case 5:
              return command('Field.delete', [_id, fields[0]['id']]);
            case 6:
              return command('Document.complete', [_id]);
            default:
              fail('No response should be posted after Document.complete');
          }
        },
      ).execute(
        command: ZoteroCitingCommand.refresh,
        documentId: _id,
        handler: session.handle,
        guard: session.assertUnchanged,
      );
      expect(requestIndex, 7);
      expect(session.isComplete, isTrue);
      expect(document.paragraphs.single.text, 'Lead (a)(b)(c) tail');
      session.apply();
      expect(document.paragraphs.single.text, 'Lead (c; a; b) tail');
      expect(WordZotero.fields(document).single.citation!.citationId, 'c');
    },
  );

  for (final rich in [false, true]) {
    test(
      'refresh adjacency follows next ${rich ? 'rich' : 'simple'} packet',
      () {
        final document = _document(rich: rich);
        for (final current in [document, _reopen(document)]) {
          final session = _session(current);
          final app =
              session.handle('Application.getActiveDocument', [])!
                  as Map<String, Object>;
          expect(app['supportsCitationMerging'], isTrue);
          expect(_adjacency(session), [true, true, false]);
          expect(session.hasChanges, isFalse);
        }
      },
    );

    test(
      'native merge response keeps metadata and survives DOCX, rich=$rich',
      () {
        final document = _document(rich: rich);
        final session = _session(document);
        final fields = _fields(session);
        _mergeResponse(session, fields);
        expect(document.paragraphs.single.text, 'Lead (a)(b)(c) tail');
        expect(WordZotero.fields(document), hasLength(3));
        _complete(session);
        for (final current in [document, _reopen(document)]) {
          expect(current.paragraphs.single.text, 'Lead (c; a; b) tail');
          final field = WordZotero.fields(current).single;
          expect(field.citation!.citationId, 'c');
          expect(field.citation!.items.map((item) => item.itemData!['title']), [
            'Source c',
            'Source a',
            'Source b',
          ]);
          expect(field.citation!.items[0].suffix, ', emphasis added');
          expect(field.citation!.items[1].locator, '12');
          expect(field.citation!.items[1].label, 'page');
          expect(field.citation!.items[2].prefix, 'see ');
          expect(field.citation!.items[2].suppressAuthor, isTrue);
          expect(
            field.paragraph.inlines.whereType<WmlRun>().any(
              (run) => run.text == 'c' && run.properties.italic,
            ),
            isTrue,
          );
          expect(_adjacency(_session(current)), [false]);
        }
      },
    );
  }

  for (final separator in [' ', '\n', '\u200b']) {
    test(
      'visible or zero-width text separates citation clusters: $separator',
      () {
        final document = WmlDocument.empty();
        final paragraph = document.paragraphs.single;
        _append(paragraph, 'a');
        paragraph.inlines.add(WmlRun(text: separator));
        _append(paragraph, 'b');
        expect(_adjacency(_session(document)), [false, false]);
      },
    );
  }

  test('empty ordinary formatting runs do not separate packets', () {
    final document = WmlDocument.empty();
    final paragraph = document.paragraphs.single;
    _append(paragraph, 'a');
    paragraph.inlines.add(WmlRun(properties: WmlRunProps(bold: true)));
    _append(paragraph, 'b');
    expect(_adjacency(_session(document)), [true, false]);
  });

  for (final marker in [
    'bookmark',
    'empty-comment',
    'empty-link',
    'native-field',
  ]) {
    test('$marker between packets prevents adjacency', () {
      final document = WmlDocument.empty();
      final paragraph = document.paragraphs.single;
      _append(paragraph, 'a');
      _append(paragraph, 'b');
      final boundary = paragraph.inlines.indexOf(
        WordZotero.fields(document)[1].run!,
      );
      paragraph.inlines.insertAll(boundary, switch (marker) {
        'bookmark' => [
          WmlBookmarkBoundary(id: '1', isStart: true, name: 'Between'),
          WmlBookmarkBoundary(id: '1', isStart: false),
        ],
        'empty-comment' => [
          WmlRun(commentIds: [1]),
        ],
        'empty-link' => [
          WmlRun(hyperlink: const WmlHyperlink(url: 'https://example.org')),
        ],
        _ => [
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' DATE ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
        ],
      });
      expect(_adjacency(_session(document)), [false, false]);
    });
  }

  test(
    'commented citations and content-controlled paragraphs stay separate',
    () {
      final commented = _document();
      WordZotero.fields(commented).first.run!.commentIds.add(1);
      expect(_adjacency(_session(commented)), [false, true, false]);

      final controlled = _document();
      final paragraph = controlled.paragraphs.single;
      final control = WmlContentControlData(
        xml: '<w:sdt xmlns:w="${OfficeNamespaces.w}"><w:sdtPr/></w:sdt>',
        sourcePartUri: '/word/document.xml',
        relationships: const [],
      );
      paragraph.inlines.insert(
        0,
        WmlContentControlBoundary(control: control, start: true),
      );
      paragraph.inlines.add(
        WmlContentControlBoundary(control: control, start: false),
      );
      expect(_adjacency(_session(controlled)), [false, false, false]);
    },
  );

  test('paragraph and table-cell boundaries never imply adjacency', () {
    final paragraphs = List.generate(4, (_) => WmlParagraph());
    for (var index = 0; index < paragraphs.length; index++) {
      _append(paragraphs[index], ['a', 'b', 'c', 'd'][index]);
    }
    final document = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            paragraphs[0],
            paragraphs[1],
            WmlTable(
              grid: [120, 120],
              rows: [
                WmlTableRow(
                  cells: [
                    WmlTableCell(blocks: [paragraphs[2]]),
                    WmlTableCell(blocks: [paragraphs[3]]),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
    expect(_adjacency(_session(document)), [false, false, false, false]);
  });

  for (final endnote in [false, true]) {
    test(
      'adjacent citations merge within one authored ${endnote ? 'endnote' : 'footnote'}',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Authored ',
        );
        for (final id in ['a', 'b', 'c']) {
          _append(note.paragraphs.single, id, rich: true);
        }
        final other = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Other ',
        );
        _append(other.paragraphs.single, 'd');
        final session = _session(document);
        final fields = _fields(session);
        expect(fields.map((field) => field['adjacent']), [
          true,
          true,
          false,
          false,
        ]);
        expect(fields.map((field) => field['noteIndex']), [1, 1, 1, 2]);
        _mergeResponse(session, fields.take(3).toList());
        _complete(session);
        for (final current in [document, _reopen(document)]) {
          final notes = endnote ? current.endnotes : current.footnotes;
          expect(notes, hasLength(2));
          expect(WordNotes.editableText(notes.first), 'Authored (c; a; b)');
          expect(WordNotes.editableText(notes.last), 'Other (d)');
          final fresh = _fields(_session(current));
          expect(fresh.map((field) => field['noteIndex']), [1, 2]);
          expect(fresh.map((field) => field['adjacent']), [false, false]);
        }
      },
    );
  }

  test(
    'deleted or unlinked staging cannot make separated originals adjacent',
    () {
      for (final command in ['Field.delete', 'Field.removeCode']) {
        final document = _document();
        final session = _session(document);
        final fields = _fields(session);
        _call(session, command, [fields[1]['id']]);
        expect(_adjacency(session), [false, false]);
        expect(document.paragraphs.single.text, 'Lead (a)(b)(c) tail');
      }
    },
  );

  test('bibliography and staged insertion always break a merge chain', () {
    final document = WmlDocument.empty();
    final paragraph = document.paragraphs.single;
    _append(paragraph, 'a');
    paragraph.inlines.add(
      WmlRun(
        text: 'References',
        fieldInstruction: ' ADDIN ZOTERO_BIBL {} CSL_BIBLIOGRAPHY ',
      ),
    );
    _append(paragraph, 'b');
    expect(_adjacency(_session(document)), [false, false, false]);

    final staged = _document();
    final session = WordZoteroCitingSession(
      document: staged,
      documentId: _id,
      insertionParagraph: staged.paragraphs.single,
      insertionOffset: WordZotero.fields(staged).first.end,
    );
    _call(session, 'Document.insertField', ['Http', 0]);
    expect(_adjacency(session), [false, false, true, false]);
  });

  test('reported adjacency is rechecked if a zero-width boundary appears', () {
    final document = _document();
    final session = _session(document);
    final fields = _fields(session);
    _mergeResponse(session, fields);
    _call(session, 'Document.complete');
    final paragraph = document.paragraphs.single;
    final second = WordZotero.fields(document)[1].run!;
    final index = paragraph.inlines.indexOf(second);
    paragraph.inlines.insert(
      index,
      WmlBookmarkBoundary(id: '9', isStart: true, name: 'Late'),
    );
    expect(session.apply, throwsStateError);
    expect(paragraph.text, 'Lead (a)(b)(c) tail');
    expect(WordZotero.fields(document), hasLength(3));
  });

  test('moving citations into separate notes disables adjacency', () {
    final session = _session(_document());
    final fields = _fields(session);
    _call(session, 'Document.convert', [
      fields.map((field) => field['id']).toList(),
      'Http',
      [1, 1, 1],
    ]);
    expect(_adjacency(session), [false, false, false]);
  });

  test(
    'long citation runs enumerate each pair once and terminate the chain',
    () {
      final document = WmlDocument.empty();
      final paragraph = document.paragraphs.single;
      paragraph.inlines
        ..clear()
        ..addAll([
          for (var index = 0; index < 1500; index++)
            WmlRun(
              text: '(a)',
              fieldInstruction: ZoteroCitation(
                citationId: 'cluster-$index',
                items: [_item('a')],
                plainCitation: '(a)',
              ).fieldInstruction,
            ),
        ]);
      final session = _session(document);
      final fields = _fields(session);
      expect(fields, hasLength(1500));
      expect(
        fields.take(1499).every((field) => field['adjacent'] == true),
        isTrue,
      );
      expect(fields.last['adjacent'], isFalse);
      expect(fields.map((field) => field['id']).toSet(), hasLength(1500));
      session.assertUnchanged();
    },
  );

  test('abandoning a staged merge never mutates the document', () {
    final document = _document(rich: true);
    final before = WordZotero.fields(
      document,
    ).map((field) => field.instruction).toList();
    final session = _session(document);
    _mergeResponse(session, _fields(session));
    expect(session.isComplete, isFalse);
    expect(session.apply, throwsStateError);
    expect(document.paragraphs.single.text, 'Lead (a)(b)(c) tail');
    expect(
      WordZotero.fields(document).map((field) => field.instruction),
      before,
    );
  });
}
