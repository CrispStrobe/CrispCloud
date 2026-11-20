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

WmlParagraph _nativeFieldParagraph({bool empty = false}) => WmlParagraph(
  inlines: [
    WmlRun(text: 'Before '),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.instruction, text: ' DATE '),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
    WmlRun(text: empty ? '' : '2026'),
    WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
    WmlRun(text: ' after'),
  ],
);

WmlDocument _documentWith(List<WmlParagraph> paragraphs) =>
    WmlDocument(sections: [WmlSection(blocks: paragraphs)]);

OpcPackage _listStoriesPackage({required bool definitions}) {
  final package = OpcPackage.create(OpcPackageKind.word);
  void put(String name, String kind, String xml) {
    final uri = '/word/$name.xml';
    final existing = package.getPart(uri);
    if (existing != null) {
      existing.writeText(xml);
      return;
    }
    package.createPart(
      uri,
      'application/vnd.openxmlformats-officedocument.wordprocessingml.$kind+xml',
      utf8.encode(xml),
    );
  }

  String paragraph(String text, {int id = 7, String extra = ''}) =>
      '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/>'
      '<w:numId w:val="$id"/></w:numPr></w:pPr>'
      '<w:r><w:t>$text</w:t></w:r>$extra</w:p>';
  put(
    'document',
    'document.main',
    '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>'
        '${paragraph('Body one', extra: '<w:r><w:footnoteReference w:id="1"/></w:r>'
            '<w:r><w:footnoteReference w:id="2"/></w:r>'
            '<w:r><w:endnoteReference w:id="1"/></w:r>')}'
        '${paragraph('Body two')}</w:body></w:document>',
  );
  put(
    'footnotes',
    'footnotes',
    '<w:footnotes xmlns:w="${OfficeNamespaces.w}">'
        '<w:footnote w:id="1">${paragraph('First note one')}'
        '${paragraph('First note two')}</w:footnote>'
        '<w:footnote w:id="2">${paragraph('Nine', id: 8)}'
        '${paragraph('Shared start')}${paragraph('Unnumbered', id: 0)}'
        '</w:footnote></w:footnotes>',
  );
  put(
    'endnotes',
    'endnotes',
    '<w:endnotes xmlns:w="${OfficeNamespaces.w}">'
        '<w:endnote w:id="1">${paragraph('Endnote one')}'
        '${paragraph('Endnote two')}${paragraph('Endnote three')}'
        '</w:endnote></w:endnotes>',
  );
  if (definitions) {
    put(
      'numbering',
      'numbering',
      '<w:numbering xmlns:w="${OfficeNamespaces.w}">'
          '<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0">'
          '<w:start w:val="3"/><w:numFmt w:val="decimal"/>'
          '<w:lvlText w:val="%1."/><w:pPr>'
          '<w:ind w:left="720" w:hanging="360"/></w:pPr>'
          '</w:lvl></w:abstractNum>'
          '<w:num w:numId="7"><w:abstractNumId w:val="1"/></w:num>'
          '<w:num w:numId="8"><w:abstractNumId w:val="1"/>'
          '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="9"/>'
          '</w:lvlOverride></w:num></w:numbering>',
    );
    package
        .relationshipsFor('/word/document.xml')
        .add(type: RelationshipTypes.numbering, target: 'numbering.xml');
  }
  return package;
}

void main() {
  test(
    'DOCX note list labels use native starts with independent story counters',
    () {
      var document = WordDeserializer().read(
        _listStoriesPackage(definitions: true),
      );
      for (var round = 0; round <= 2; round++) {
        expect(document.paragraphs.map((p) => p.properties.listLabel), [
          '3. ',
          '4. ',
        ]);
        expect(
          document.footnotes[0].allParagraphs.map(
            (p) => p.properties.listLabel,
          ),
          ['3. ', '4. '],
        );
        expect(
          document.footnotes[1].allParagraphs.map(
            (p) => p.properties.listLabel,
          ),
          ['9. ', '3. ', null],
        );
        expect(
          document.endnotes.single.allParagraphs.map(
            (p) => p.properties.listLabel,
          ),
          ['3. ', '4. ', '5. '],
        );
        expect(
          document.footnotes.first.paragraphs.first.properties.indent.left,
          36,
        );
        expect(
          document.endnotes.single.paragraphs.first.properties.indent.hanging,
          18,
        );
        if (round < 2) document = _reopen(document);
      }
    },
  );

  test('missing numbering definitions use the same note and body fallback', () {
    final document = WordDeserializer().read(
      _listStoriesPackage(definitions: false),
    );
    expect(document.paragraphs.map((p) => p.properties.listLabel), [
      '• ',
      '• ',
    ]);
    expect(
      document.footnotes[0].allParagraphs.map((p) => p.properties.listLabel),
      ['• ', '• '],
    );
    expect(
      document.footnotes[1].allParagraphs.map((p) => p.properties.listLabel),
      ['• ', '• ', null],
    );
    expect(
      document.endnotes.single.allParagraphs.map((p) => p.properties.listLabel),
      ['• ', '• ', '• '],
    );
  });

  for (final endnote in [false, true]) {
    final label = endnote ? 'endnote' : 'footnote';
    final type = endnote ? 2 : 1;

    for (final requested in [0, type]) {
      test(
        '$label research content inherits its story for request $requested',
        () {
          final document = WmlDocument.empty(text: 'Body');
          final note = WordNotes.insert(
            document,
            document.paragraphs.single,
            endnote: endnote,
            text: 'Before target after',
          );
          final paragraph = note.paragraphs.single;
          WordZotero.insertCitation(
            paragraph,
            _citation('before', '(B)'),
            index: 0,
          );
          WordZotero.insertCitation(
            paragraph,
            _citation('after', '(A)'),
            index: paragraph.text.length,
          );
          final start = paragraph.text.indexOf('target');
          final original = paragraph.text;
          final session = _session(
            document,
            paragraph,
            start: start,
            end: start + 6,
          );
          expect(session.canInsertNoteText, isTrue);
          final originalFields = _fields(session);
          _start(
            session,
            '<p>First <b>$_one</b></p><p>Second $_two</p>',
            type: requested,
          );
          final inserted = _convert(session, [
            'SECOND2',
            'FIRST1',
          ], type: requested);
          expect(inserted.map((field) => field['noteIndex']), [1, 1]);
          _set(session, inserted[0], 'two', '(Two)');
          _set(session, inserted[1], 'one', '<i>(One)</i>');
          _set(session, originalFields.first, 'before', '(Before expanded)');
          _set(session, originalFields.last, 'after', '(After expanded)');
          expect(_fields(session).map((field) => field['id']), [
            originalFields.first['id'],
            inserted[1]['id'],
            inserted[0]['id'],
            originalFields.last['id'],
          ]);
          expect(
            paragraph.text,
            original,
            reason: 'The entire result stays staged.',
          );
          _finish(session);
          expect(note.paragraphs.map((p) => p.text), [
            '(Before expanded)Before First (One)',
            'Second (Two) after(After expanded)',
          ]);
          expect(session.caretAfter!.paragraph, same(note.paragraphs.last));
          expect(session.caretAfter!.offset, 'Second (Two)'.length);
          expect(document.footnotes.length + document.endnotes.length, 1);
          expect(
            note.allParagraphs
                .expand((p) => p.inlines.whereType<WmlRun>())
                .any((run) => run.noteRefId != null),
            isFalse,
          );
          final reopened = _reopen(document);
          final restored =
              (endnote ? reopened.endnotes : reopened.footnotes).single;
          expect(
            WordNotes.editableText(restored),
            WordNotes.editableText(note),
          );
          expect(
            WordZotero.fields(
              reopened,
            ).map((field) => field.citation!.citationId),
            ['before', 'one', 'two', 'after'],
          );
          final next = _session(reopened, restored.paragraphs.first);
          expect(_fields(next).map((field) => field['noteIndex']), [
            1,
            1,
            1,
            1,
          ]);
        },
      );
    }

    test(
      '$label headings lists and images retain the leading reference marker',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Trailing prose',
        );
        final paragraph = note.paragraphs.single;
        paragraph.inlines.insert(
          0,
          WmlNoteMarker(endnote: endnote, properties: WmlRunProps(bold: true)),
        );
        final png = image.encodePng(
          image.Image(width: 2, height: 2, numChannels: 4),
        );
        final session = _session(document, paragraph);
        _start(
          session,
          '<h2>Research</h2><ol start="3"><li><p>First $_one</p>'
          '<p><img src="data:image/png;base64,${base64Encode(png)}" '
          'width="24" alt="Note image"/></p><ul><li>Nested $_two</li></ul>'
          '</li></ol>',
          type: type,
        );
        final inserted = _convert(session, ['SECOND2', 'FIRST1'], type: type);
        _set(session, inserted[0], 'two', '(Two)');
        _set(session, inserted[1], 'one', '(One)');
        _finish(session);
        for (final result in [document, _reopen(document)]) {
          final current = (endnote ? result.endnotes : result.footnotes).single;
          expect(current.paragraphs.first.text, 'Research');
          expect(current.paragraphs.first.properties.headingLevel, 2);
          final markers = current.allParagraphs
              .expand((p) => p.inlines.whereType<WmlNoteMarker>())
              .toList();
          expect(markers, hasLength(1));
          expect(current.paragraphs.first.inlines.first, same(markers.single));
          expect(markers.single.endnote, endnote);
          expect(markers.single.properties.bold, isTrue);
          expect(current.paragraphs.last.text, 'Trailing prose');
          expect(current.paragraphs[1].properties.numId, isNotNull);
          expect(current.paragraphs[1].properties.listLabel, '3. ');
          expect(current.paragraphs[2].properties.numberingSuppressed, isTrue);
          final pictures = current.allParagraphs
              .expand((p) => p.inlines.whereType<WmlRun>())
              .where((run) => run.inlineVisual != null)
              .toList();
          expect(pictures, hasLength(1));
          expect(
            WordZotero.fields(
              result,
            ).map((field) => field.citation!.citationId),
            ['one', 'two'],
          );
          expect(result.footnotes.length + result.endnotes.length, 1);
        }
        expect(session.caretAfter!.paragraph.text, 'Nested (Two)');
        expect(session.caretAfter!.offset, 'Nested (Two)'.length);
      },
    );

    test(
      '$label visible start keeps reference separator on the inserted heading',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: ' Trailing prose',
        );
        final paragraph = note.paragraphs.single;
        paragraph.inlines.insert(
          0,
          WmlNoteMarker(endnote: endnote, properties: WmlRunProps(bold: true)),
        );
        expect(WordNotes.editableText(note), 'Trailing prose');
        final session = _session(document, paragraph, start: 1);
        _start(session, '<h2>Research</h2><p>Details</p>', type: type);
        _finish(session);
        for (final result in [document, _reopen(document)]) {
          final current = (endnote ? result.endnotes : result.footnotes).single;
          expect(current.paragraphs.map((p) => p.text), [
            ' Research',
            'Details',
            'Trailing prose',
          ]);
          expect(
            WordNotes.editableText(current),
            'Research\nDetails\nTrailing prose',
          );
          expect(current.paragraphs.first.inlines.first, isA<WmlNoteMarker>());
          expect(current.paragraphs.first.properties.headingLevel, 2);
        }
      },
    );

    test(
      '$label rejects incompatible placeholder placement before changes',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
          text: 'Keep',
        );
        final session = _session(document, note.paragraphs.single);
        _start(session, '<p>$_one</p>', type: type);
        expect(
          () => _convert(session, ['FIRST1'], type: endnote ? 1 : 2),
          throwsUnsupportedError,
        );
        expect(
          () => _call(session, 'Document.complete'),
          throwsFormatException,
        );
        expect(note.text, 'Keep');
        expect(WordZotero.fields(document), isEmpty);
        expect(document.footnotes.length + document.endnotes.length, 1);
      },
    );

    test(
      '$label keeps destination note when an original sole citation is deleted',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
        );
        final paragraph = note.paragraphs.single;
        WordZotero.insertCitation(paragraph, _citation('old', '(Old)'));
        final session = _session(
          document,
          paragraph,
          start: paragraph.text.length,
        );
        final original = _fields(session).single;
        _start(session, '<p> New authored content</p>', type: type);
        _call(session, 'Field.delete', [original['id']]);
        _finish(session);
        expect(
          (endnote ? document.endnotes : document.footnotes).single,
          same(note),
        );
        expect(note.text, 'New authored content');
        expect(WordZotero.fields(document), isEmpty);
        expect(session.caretAfter!.offset, note.paragraphs.single.text.length);
      },
    );

    test(
      '$label refuses conversion of the destination after research text is staged',
      () {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: endnote,
        );
        final paragraph = note.paragraphs.single;
        WordZotero.insertCitation(paragraph, _citation('old', '(Old)'));
        final session = _session(
          document,
          paragraph,
          start: paragraph.text.length,
        );
        final field = _fields(session).single;
        _start(session, '<p> New content</p>', type: type);
        expect(
          () => _call(session, 'Document.convert', [
            [field['id']],
            'Http',
            [0],
          ]),
          throwsUnsupportedError,
        );
        expect(note.text, '(Old)');
      },
    );
  }

  test(
    'body selection replaces only ordinary selected text and adjusts earlier fields',
    () {
      final document = WmlDocument.empty(text: 'Before target after');
      final paragraph = document.paragraphs.single;
      WordZotero.insertCitation(
        paragraph,
        _citation('before', '(B)'),
        index: 0,
      );
      WordZotero.insertCitation(
        paragraph,
        _citation('after', '(A)'),
        index: paragraph.text.length,
      );
      final start = paragraph.text.indexOf('target');
      final session = _session(
        document,
        paragraph,
        start: start,
        end: start + 6,
      );
      final originals = _fields(session);
      _start(session, '<p>First $_one</p><p>Second</p>');
      final inserted = _convert(session, ['FIRST1']).single;
      _set(session, inserted, 'one', '(One)');
      _set(session, originals.first, 'before', '(Expanded before)');
      _set(session, originals.last, 'after', '(Expanded after)');
      _finish(session);
      expect(document.paragraphs.map((p) => p.text), [
        '(Expanded before)Before First (One)',
        'Second after(Expanded after)',
      ]);
      expect(session.caretAfter!.offset, 'Second'.length);
      expect(
        WordZotero.fields(
          _reopen(document),
        ).map((field) => field.citation!.citationId),
        ['before', 'one', 'after'],
      );
    },
  );

  test(
    'selection containing a field or note reference is refused as a whole',
    () {
      final document = WmlDocument.empty(text: 'Before after');
      final paragraph = document.paragraphs.single;
      WordZotero.insertCitation(paragraph, _citation('old', '(Old)'), index: 7);
      final citationTarget = _session(
        document,
        paragraph,
        start: 0,
        end: paragraph.text.length,
      );
      expect(citationTarget.canInsertNoteText, isFalse);
      expect(
        () => _call(citationTarget, 'Document.insertText', ['<p>New</p>']),
        throwsUnsupportedError,
      );
      final noteDocument = WmlDocument.empty(text: 'Body');
      final body = noteDocument.paragraphs.single;
      WordNotes.insert(noteDocument, body, endnote: false, text: 'Keep note');
      final noteTarget = _session(
        noteDocument,
        body,
        start: 0,
        end: body.text.length,
      );
      expect(noteTarget.canInsertNoteText, isFalse);
      expect(noteDocument.footnotes.single.text, 'Keep note');
      expect(WordZotero.fields(document).single.citation!.citationId, 'old');
    },
  );

  test(
    'selection crossing a structural marker or commented text is refused',
    () {
      final document = WmlDocument.empty(text: 'Before');
      final paragraph = document.paragraphs.single;
      paragraph.inlines.addAll([
        WmlBookmarkBoundary(id: '1', isStart: true, name: 'keep'),
        WmlRun(text: ' after'),
        WmlBookmarkBoundary(id: '1', isStart: false),
      ]);
      expect(
        _session(document, paragraph, start: 1, end: 10).canInsertNoteText,
        isFalse,
      );
      final commented = WmlDocument.empty(text: 'Commented');
      commented.paragraphs.single.inlines
          .whereType<WmlRun>()
          .single
          .commentIds
          .add(1);
      expect(
        _session(
          commented,
          commented.paragraphs.single,
          end: 3,
        ).canInsertNoteText,
        isFalse,
      );
    },
  );

  test(
    'selection bounds and surrogate boundaries are validated without edits',
    () {
      final document = WmlDocument.empty(text: 'A😀B');
      final paragraph = document.paragraphs.single;
      for (final range in [(3, 2), (-1, 2), (0, 5)]) {
        expect(
          () => _session(document, paragraph, start: range.$1, end: range.$2),
          throwsArgumentError,
        );
      }
      expect(
        _session(document, paragraph, start: 2).canInsertNoteText,
        isFalse,
      );
      expect(
        _session(document, paragraph, start: 1, end: 2).canInsertNoteText,
        isFalse,
      );
      expect(
        _session(document, paragraph, start: 1, end: 3).canInsertNoteText,
        isTrue,
      );
      expect(paragraph.text, 'A😀B');
    },
  );

  test(
    'selection touching bookmark endpoints preserves the complete range',
    () {
      final paragraph = WmlParagraph(
        inlines: [
          WmlRun(text: 'Before '),
          WmlBookmarkBoundary(id: '1', isStart: true, name: 'keep'),
          WmlRun(text: 'Target'),
          WmlBookmarkBoundary(id: '1', isStart: false),
          WmlRun(text: ' after'),
        ],
      );
      final document = _documentWith([paragraph]);
      final before = List<WmlInline>.of(paragraph.inlines);
      for (final range in [(7, 13), (3, 7), (13, 16)]) {
        final session = _session(
          document,
          paragraph,
          start: range.$1,
          end: range.$2,
        );
        expect(session.canInsertNoteText, isFalse);
        expect(
          () => _call(session, 'Document.insertText', ['<p>Replacement</p>']),
          throwsUnsupportedError,
        );
        expect(paragraph.inlines, orderedEquals(before));
        expect(paragraph.text, 'Before Target after');
      }
    },
  );

  test('empty atomic runs at selection endpoints are protected', () {
    for (final atStart in [false, true]) {
      final atomic = WmlRun(text: '', fieldInstruction: ' DATE ');
      final text = WmlRun(text: 'Target');
      final paragraph = WmlParagraph(
        inlines: atStart ? [atomic, text] : [text, atomic],
      );
      final document = _documentWith([paragraph]);
      final session = _session(document, paragraph, end: 6);
      expect(session.canInsertNoteText, isFalse);
      expect(
        () => _call(session, 'Document.insertText', ['<p>Replacement</p>']),
        throwsUnsupportedError,
      );
      expect(paragraph.inlines, contains(same(atomic)));
      expect(paragraph.text, 'Target');
    }
    final paragraph = WmlParagraph(
      inlines: [
        WmlRun(),
        WmlRun(text: 'Target'),
      ],
    );
    final session = _session(_documentWith([paragraph]), paragraph, end: 6);
    expect(session.canInsertNoteText, isTrue);
    _start(session, '<p>Replacement</p>');
    _finish(session);
    expect(paragraph.text, 'Replacement');
  });

  test('malformed text-box fields do not block an independent body target', () {
    final target = WmlParagraph(inlines: [WmlRun(text: 'Target')]);
    final marker = WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin);
    final frame = WmlFrame(
      blocks: [
        WmlParagraph(
          inlines: [
            marker,
            WmlRun(text: 'Frame'),
          ],
        ),
      ],
    );
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [frame, target]),
      ],
    );
    final session = _session(document, target, start: 3);
    expect(session.canInsertNoteText, isTrue);
    _start(session, '<p>Added</p>');
    _finish(session);
    expect(target.text, 'TarAddedget');
    expect((frame.blocks.single as WmlParagraph).inlines.first, same(marker));
  });

  test('a frame field endpoint cannot close an unmatched body field', () {
    final first = WmlParagraph(
      inlines: [
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
        WmlFieldBoundary(
          kind: WmlFieldBoundaryKind.instruction,
          text: ' DATE ',
        ),
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
        WmlRun(text: 'Body field'),
      ],
    );
    final frame = WmlFrame(
      blocks: [
        WmlParagraph(
          inlines: [
            WmlRun(text: 'Frame'),
            WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          ],
        ),
      ],
    );
    final target = WmlParagraph(inlines: [WmlRun(text: 'Target')]);
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [first, frame, target]),
      ],
    );
    final session = _session(document, target, start: 3);
    expect(session.canInsertNoteText, isFalse);
    expect(
      () => _call(session, 'Document.insertText', ['<p>Added</p>']),
      throwsUnsupportedError,
    );
    expect(target.text, 'Target');
  });

  test(
    'native complex field results and exact endpoints refuse research content',
    () {
      for (final range in [(8, 8), (8, 10), (7, 11), (7, 7), (11, 11)]) {
        final paragraph = _nativeFieldParagraph();
        final document = _documentWith([paragraph]);
        final before = List<WmlInline>.of(paragraph.inlines);
        final session = _session(
          document,
          paragraph,
          start: range.$1,
          end: range.$2,
        );
        expect(session.canInsertNoteText, isFalse, reason: '$range');
        expect(
          () => _call(session, 'Document.insertText', [
            '<p>First</p><p>Second</p>',
          ]),
          throwsUnsupportedError,
        );
        expect(paragraph.text, 'Before 2026 after');
        expect(paragraph.inlines, orderedEquals(before));
      }
    },
  );

  test(
    'empty native complex fields have no safe research insertion endpoint',
    () {
      final paragraph = _nativeFieldParagraph(empty: true);
      final document = _documentWith([paragraph]);
      expect(
        _session(document, paragraph, start: 7).canInsertNoteText,
        isFalse,
      );
      expect(
        _session(document, paragraph, start: 6, end: 8).canInsertNoteText,
        isFalse,
      );
    },
  );

  test(
    'ordinary text strictly before and after a native field remains editable',
    () {
      for (final offset in [3, 15]) {
        final paragraph = _nativeFieldParagraph();
        final document = _documentWith([paragraph]);
        final boundaries = paragraph.inlines
            .whereType<WmlFieldBoundary>()
            .toList();
        final session = _session(document, paragraph, start: offset);
        expect(session.canInsertNoteText, isTrue);
        _start(session, '<p>First</p><p>Second</p>');
        _finish(session);
        final owner = document.paragraphs.singleWhere(
          (p) => p.inlines.whereType<WmlFieldBoundary>().isNotEmpty,
        );
        expect(
          owner.inlines.whereType<WmlFieldBoundary>(),
          orderedEquals(boundaries),
        );
        expect(owner.text, contains('2026'));
        expect(document.paragraphs, hasLength(2));
      }
    },
  );

  test(
    'cross-paragraph native field cached text is protected without local markers',
    () {
      final first = WmlParagraph(
        inlines: [
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' REF source ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlRun(text: 'first'),
        ],
      );
      final middle = WmlParagraph(inlines: [WmlRun(text: 'middle')]);
      final last = WmlParagraph(
        inlines: [
          WmlRun(text: 'last'),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
        ],
      );
      final document = _documentWith([first, middle, last]);
      expect(_session(document, middle, start: 2).canInsertNoteText, isFalse);
      expect(
        _session(document, middle, start: 1, end: 4).canInsertNoteText,
        isFalse,
      );
      expect(document.paragraphs.map((p) => p.text), [
        'first',
        'middle',
        'last',
      ]);
    },
  );

  test(
    'malformed native field packets refuse research edits in their story',
    () {
      final begin = WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin);
      final code = WmlFieldBoundary(
        kind: WmlFieldBoundaryKind.instruction,
        text: ' DATE ',
      );
      final separate = WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate);
      final end = WmlFieldBoundary(kind: WmlFieldBoundaryKind.end);
      for (final markers in <List<WmlFieldBoundary>>[
        [begin, code, separate],
        [code],
        [separate],
        [end],
        [begin, code, separate, separate, end],
        [begin, separate, code, end],
      ]) {
        final first = WmlParagraph(
          inlines: [
            ...markers,
            WmlRun(text: 'retained'),
          ],
        );
        final target = WmlParagraph(inlines: [WmlRun(text: 'ordinary target')]);
        final document = _documentWith([first, target]);
        final session = _session(document, target, start: 3);
        expect(session.canInsertNoteText, isFalse);
        expect(
          () => _call(session, 'Document.insertText', ['<p>New</p>']),
          throwsUnsupportedError,
        );
        expect(target.text, 'ordinary target');
      }
    },
  );

  test(
    'nested native field results are protected while outside text remains safe',
    () {
      final paragraph = WmlParagraph(
        inlines: [
          WmlRun(text: 'Outside '),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' IF ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
          WmlFieldBoundary(
            kind: WmlFieldBoundaryKind.instruction,
            text: ' DATE ',
          ),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.separate),
          WmlRun(text: '2026'),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          WmlFieldBoundary(kind: WmlFieldBoundaryKind.end),
          WmlRun(text: ' trailing'),
        ],
      );
      final document = _documentWith([paragraph]);
      expect(
        _session(document, paragraph, start: 9).canInsertNoteText,
        isFalse,
      );
      expect(_session(document, paragraph, start: 3).canInsertNoteText, isTrue);
    },
  );

  test(
    'native field protection is scoped to the chosen body or authored-note story',
    () {
      final body = _nativeFieldParagraph();
      final document = _documentWith([body]);
      final note = WordNotes.insert(
        document,
        body,
        endnote: false,
        text: 'Authored',
      );
      expect(
        _session(document, note.paragraphs.single, start: 3).canInsertNoteText,
        isTrue,
      );
      note.paragraphs.single.inlines.insert(
        0,
        WmlFieldBoundary(kind: WmlFieldBoundaryKind.begin),
      );
      expect(_session(document, body, start: 3).canInsertNoteText, isTrue);
      expect(
        _session(document, note.paragraphs.single, start: 3).canInsertNoteText,
        isFalse,
      );
    },
  );

  test(
    'research text cannot extend a paragraph-owned field at its end boundary',
    () {
      final document = WmlDocument.empty(text: 'Result');
      final paragraph = document.paragraphs.single;
      paragraph.properties.fieldInstruction = _citation(
        'old',
        'Result',
      ).fieldInstruction;
      final session = _session(
        document,
        paragraph,
        start: paragraph.text.length,
      );
      expect(session.canInsertNoteText, isFalse);
      expect(
        () => _call(session, 'Document.insertText', ['<p>New</p>']),
        throwsUnsupportedError,
      );
      expect(paragraph.text, 'Result');
    },
  );

  test(
    'changed selection content or deleted note refuses completed research content',
    () {
      for (final remove in [false, true]) {
        final document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.single,
          endnote: false,
          text: 'Replace',
        );
        final paragraph = note.paragraphs.single;
        final session = _session(
          document,
          paragraph,
          end: paragraph.text.length,
        );
        _start(session, '<p>Research</p>');
        _call(session, 'Document.complete');
        if (remove) {
          WordNotes.delete(document, note.id, endnote: false);
        } else {
          paragraph.inlines.add(WmlRun(text: ' changed'));
        }
        expect(session.apply, throwsStateError);
        if (!remove) expect(note.text, 'Replace changed');
        expect(WordZotero.fields(document), isEmpty);
      }
    },
  );
}
