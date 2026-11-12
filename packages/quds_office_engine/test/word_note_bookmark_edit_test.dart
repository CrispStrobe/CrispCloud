import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _crossParagraph = '''
<w:p><w:r><w:t>lead</w:t></w:r></w:p>
<w:p><w:bookmarkStart w:id="7" w:name="NoteSpan"/><w:r><w:rPr><w:b/></w:rPr><w:t>First</w:t></w:r></w:p>
<w:p><w:r><w:t>Second</w:t></w:r><w:bookmarkEnd w:id="7"/></w:p>
<w:p><w:r><w:t>Trailing</w:t></w:r></w:p>''';

WmlDocument _document({
  bool endnote = false,
  String content = _crossParagraph,
}) {
  final kind = endnote ? 'endnote' : 'footnote';
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>'
        '<w:r><w:t>Body</w:t></w:r><w:r><w:${kind}Reference w:id="1"/></w:r>'
        '</w:p><w:sectPr/></w:body></w:document>',
      );
  final uri = '/word/${kind}s.xml';
  final bytes = utf8.encode(
    '<w:${kind}s xmlns:w="${OfficeNamespaces.w}">'
    '<w:$kind w:id="1">$content</w:$kind></w:${kind}s>',
  );
  final part = package.getPart(uri);
  if (part == null) {
    package.createPart(
      uri,
      endnote
          ? OfficeContentTypes.wordEndnotes
          : OfficeContentTypes.wordFootnotes,
      bytes,
    );
  } else {
    part.writeBytes(bytes);
  }
  final relationships = package.relationshipsFor('/word/document.xml');
  final type = endnote
      ? RelationshipTypes.endnotes
      : RelationshipTypes.footnotes;
  if (relationships.firstByType(type) == null) {
    relationships.add(type: type, target: '${kind}s.xml');
  }
  return WordDeserializer().read(package);
}

WmlNote _note(WmlDocument doc, bool endnote) =>
    (endnote ? doc.endnotes : doc.footnotes).single;

Map<String, String> _packageBytes(WmlDocument doc) => {
  for (final part in doc.package!.parts)
    part.uri: base64Encode(part.readBytes()),
};

void _rejectWithoutMutation(WmlDocument doc, bool endnote, String text) {
  final note = _note(doc, endnote);
  final blocks = List<WmlBlock>.from(note.blocks);
  final paragraphs = note.allParagraphs.toList();
  final inlines = {
    for (final p in paragraphs) p: List<WmlInline>.from(p.inlines),
  };
  final texts = {for (final p in paragraphs) p: p.text};
  final ranges = {
    for (final range in WordBookmarks.ranges(doc)) range.name: range.text,
  };
  final package = _packageBytes(doc);
  expect(
    () => WordNotes.editText(note, text),
    throwsA(
      isA<UnsupportedError>().having(
        (error) => error.message,
        'explanation',
        contains('orphan bookmark'),
      ),
    ),
  );
  expect(note.blocks, orderedEquals(blocks));
  expect(note.allParagraphs, orderedEquals(paragraphs));
  for (final paragraph in paragraphs) {
    expect(paragraph.inlines, orderedEquals(inlines[paragraph]!));
    expect(paragraph.text, texts[paragraph]);
  }
  expect({
    for (final range in WordBookmarks.ranges(doc)) range.name: range.text,
  }, ranges);
  expect(_packageBytes(doc), package);
}

void main() {
  for (final endnote in [false, true]) {
    final kind = endnote ? 'endnote' : 'footnote';
    test(
      '$kind rejects orphaned end before earlier paragraph text can change',
      () {
        final doc = _document(endnote: endnote);
        _rejectWithoutMutation(doc, endnote, 'changed lead\nchanged First');
        expect(WordBookmarks.byName(doc, 'NoteSpan')!.text, 'First\nSecond');
      },
    );

    test(
      '$kind rejects orphaned start when the retained endpoint is in a table',
      () {
        final doc = _document(
          endnote: endnote,
          content: '''
<w:p><w:r><w:t>lead</w:t></w:r></w:p>
<w:p><w:bookmarkStart w:id="7" w:name="NoteSpan"/><w:r><w:t>First</w:t></w:r></w:p>
<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="1200"/></w:tblGrid><w:tr><w:tc><w:tcPr/>
<w:p><w:r><w:t>Table end</w:t></w:r><w:bookmarkEnd w:id="7"/></w:p>
</w:tc></w:tr></w:tbl>''',
        );
        _rejectWithoutMutation(doc, endnote, 'changed lead');
        expect(_note(doc, endnote).blocks.last, isA<WmlTable>());
      },
    );

    test(
      '$kind permits complete cross-paragraph range removal through three exports',
      () {
        var doc = _document(endnote: endnote);
        final before = _packageBytes(doc);
        final first = _note(doc, endnote).paragraphs.first;
        WordNotes.editText(_note(doc, endnote), 'changed lead');
        expect(_note(doc, endnote).paragraphs.single, same(first));
        expect(WordBookmarks.ranges(doc), isEmpty);
        expect(
          _packageBytes(doc),
          before,
          reason: 'Model edits do not eagerly mutate package parts',
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          final package = WordSerializer().write(doc);
          final xml = package.getPart('/word/${kind}s.xml')!.readText();
          expect(xml, isNot(contains('bookmarkStart')));
          expect(xml, isNot(contains('bookmarkEnd')));
          doc = WordDeserializer().readBytes(package.save());
          expect(_note(doc, endnote).text, 'changed lead');
          expect(WordBookmarks.ranges(doc), isEmpty);
        }
      },
    );
  }

  test(
    'a complete bookmark in a single removed paragraph remains a legal edit',
    () {
      var doc = _document(
        content: '''
<w:p><w:r><w:t>lead</w:t></w:r></w:p>
<w:p><w:bookmarkStart w:id="7" w:name="NoteSpan"/><w:r><w:t>selected</w:t></w:r><w:bookmarkEnd w:id="7"/></w:p>''',
      );
      WordNotes.editText(doc.footnotes.single, 'lead');
      doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
      expect(doc.footnotes.single.paragraphs, hasLength(1));
      expect(WordBookmarks.ranges(doc), isEmpty);
    },
  );

  for (final native in [false, true]) {
    test(
      'appended paragraphs inherit formatting but clear ${native ? 'native' : 'generated'} bookmark identity',
      () {
        var doc = _document(
          content: native
              ? '<w:p><w:bookmarkStart w:id="7" w:name="Original"/><w:r><w:rPr><w:b/></w:rPr><w:t>lead</w:t></w:r><w:bookmarkEnd w:id="7"/></w:p>'
              : '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>lead</w:t></w:r></w:p>',
        );
        final note = doc.footnotes.single;
        final template = note.paragraphs.single;
        if (!native) template.properties.bookmarkName = 'Original';
        template.properties.spacingAfter = 17;
        WordNotes.editText(note, 'lead\nnew paragraph\nlast paragraph');
        expect(note.paragraphs.first, same(template));
        for (final paragraph in note.paragraphs.skip(1)) {
          expect(paragraph.properties.bookmarkName, isNull);
          expect(paragraph.properties.sourceBookmarkName, isNull);
          expect(paragraph.properties.spacingAfter, 17);
          expect(
            paragraph.inlines.whereType<WmlRun>().single.properties.bold,
            isTrue,
          );
        }
        for (var cycle = 0; cycle < 3; cycle++) {
          doc = WordDeserializer().readBytes(WordSerializer().writeBytes(doc));
          final range = WordBookmarks.byName(doc, 'Original')!;
          expect(range.text, 'lead');
          expect(WordBookmarks.ranges(doc), hasLength(1));
          expect(
            doc.footnotes.single.paragraphs
                .skip(1)
                .every(
                  (p) =>
                      p.properties.bookmarkName == null &&
                      p.properties.sourceBookmarkName == null,
                ),
            isTrue,
          );
        }
      },
    );
  }
}
