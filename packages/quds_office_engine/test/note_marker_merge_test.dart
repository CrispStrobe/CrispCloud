import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

WmlDocument _bookmarks() => WordDeserializer().readBytes(
  File('test/fixtures/fidelity/bookmarks.docx').readAsBytesSync(),
);

List<(String, bool, int, int)> _ranges(WmlNote note) {
  final result = <(String, bool, int, int)>[];
  var index = 0;
  for (final paragraph in note.paragraphs) {
    var offset = 0;
    for (final inline in paragraph.inlines) {
      if (inline is WmlRun) offset += inline.text.length;
      if (inline is WmlBookmarkBoundary) {
        result.add((inline.id, inline.isStart, index, offset));
      }
    }
    index++;
  }
  return result;
}

void main() {
  test(
    'incoming note text edits preserve bookmark and automatic-marker positions through Enter and join',
    () async {
      var document = _bookmarks();
      final note = document.footnotes.single;
      WordNotes.editText(note, 'Footnote\nRange');
      expect(_ranges(note), [('40', true, 0, 0), ('40', false, 1, 5)]);
      expect(
        note.paragraphs.first.inlines.whereType<WmlNoteMarker>(),
        hasLength(1),
      );
      expect(note.paragraphs.last.inlines.whereType<WmlNoteMarker>(), isEmpty);
      expect(note.paragraphs.last.properties.bookmarkName, isNull);
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
        expect(_ranges(document.footnotes.single), [
          ('40', true, 0, 0),
          ('40', false, 1, 5),
        ]);
      }
      WordNotes.editText(document.footnotes.single, 'FootnoteRange');
      expect(_ranges(document.footnotes.single), [
        ('40', true, 0, 0),
        ('40', false, 0, 13),
      ]);
    },
  );

  test(
    'unmarked and later-marked imported notes expose their actual leading whitespace',
    () {
      for (final later in <bool>[false, true]) {
        final note = WmlNote(
          id: 1,
          endnote: false,
          addReference: false,
          paragraphs: [
            WmlParagraph(
              inlines: [
                WmlRun(text: '  Lead'),
                if (later)
                  WmlNoteMarker(
                    endnote: false,
                    properties: WmlRunProps()..sourcePropertiesXml = '',
                  ),
                WmlRun(text: ' tail'),
              ],
            ),
          ],
        );
        expect(WordNotes.editableText(note), '  Lead tail');
        WordNotes.editText(note, ' Changed tail');
        expect(note.paragraphs.single.text, ' Changed tail');
        expect(
          note.paragraphs.single.inlines.whereType<WmlNoteMarker>(),
          hasLength(later ? 1 : 0),
        );
      }
    },
  );

  test('note Enter carries the styled tail and late native note mark', () {
    final note = WmlNote(
      id: 1,
      endnote: false,
      addReference: false,
      paragraphs: [
        WmlParagraph(
          inlines: [
            WmlRun(text: 'First '),
            WmlNoteMarker(
              endnote: false,
              properties: WmlRunProps()..sourcePropertiesXml = '',
            ),
            WmlRun(
              text: 'second',
              properties: WmlRunProps(bold: true, color: '123456'),
            ),
          ],
        ),
      ],
    );
    WordNotes.editText(note, 'First \nsecond');
    expect(note.paragraphs.map((p) => p.text), ['First ', 'second']);
    expect(note.paragraphs.first.inlines.whereType<WmlNoteMarker>(), isEmpty);
    expect(note.paragraphs.last.inlines.first, isA<WmlNoteMarker>());
    expect(
      note.paragraphs.last.inlines.whereType<WmlRun>().single.properties.color,
      '123456',
    );
  });

  test(
    'note text edits retain existing line-break structure and Unicode scalars',
    () async {
      var document = _bookmarks();
      final paragraph = document.footnotes.single.paragraphs.single;
      WmlRunEdit.replaceRange(paragraph, 0, paragraph.text.length, 'First\n😀');
      WordNotes.editText(document.footnotes.single, 'First\n😁!');
      expect(document.footnotes.single.paragraphs, hasLength(1));
      expect(paragraph.text, 'First\n😁!');
      document = WordDeserializer().readBytes(
        await OfficeIsolateSave.word(document),
      );
      expect(document.footnotes.single.paragraphs.single.text, 'First\n😁!');
    },
  );

  test(
    'complex note paragraph replacements with native ranges reject before mutation',
    () {
      final note = _bookmarks().footnotes.single;
      final before = _ranges(note);
      expect(
        () => WordNotes.editText(note, 'Different\nParagraphs'),
        throwsUnsupportedError,
      );
      expect(note.paragraphs.single.text, 'FootnoteRange');
      expect(_ranges(note), before);
    },
  );

  test(
    'appended note paragraphs do not duplicate heading or list restart identities',
    () {
      final note = WmlNote(
        id: 1,
        endnote: false,
        paragraphs: [
          WmlParagraph(
            properties: WmlParagraphProps(
              bookmarkName: 'NoteHeading',
              listRestart: 4,
            ),
            inlines: [WmlRun(text: 'One')],
          ),
        ],
      );
      WordNotes.editText(note, 'One\nTwo');
      expect(note.paragraphs.last.properties.bookmarkName, isNull);
      expect(note.paragraphs.last.properties.listRestart, isNull);
    },
  );

  test(
    'generated headings reserve bookmark IDs retained inside opaque body XML',
    () async {
      final package = OpcPackage.create(OpcPackageKind.word);
      package.getPart('/word/document.xml')!.writeText('''
<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>
<w:p><w:r><w:t>Heading</w:t></w:r></w:p>
<w:customXml w:uri="urn:test" w:element="wrapper"><w:p>
<w:bookmarkStart w:id="1" w:name="OpaqueRange"/><w:r><w:t>Opaque</w:t></w:r><w:bookmarkEnd w:id="1"/>
</w:p></w:customXml><w:sectPr/></w:body></w:document>''');
      var document = WordDeserializer().read(package);
      expect(
        document.sections.first.blocks.whereType<WmlOpaqueBlock>(),
        hasLength(1),
      );
      WordToc.applyHeading(document.paragraphs.single, 1);
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
        expect(
          document.paragraphs.single.inlines
              .whereType<WmlBookmarkBoundary>()
              .where((marker) => marker.isStart)
              .single
              .id,
          '2',
        );
        expect(
          document.sections.first.blocks.whereType<WmlOpaqueBlock>().single.xml,
          contains('w:id="1"'),
        );
      }
    },
  );

  for (final context in ['footnotes', 'endnotes', 'textbox', 'opaque']) {
    for (final duplicate in ['id', 'name']) {
      test(
        '$context duplicate bookmark $duplicate rejects before package mutation',
        () async {
          final document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(WmlDocument.empty(text: 'Body')),
          );
          WmlParagraph pair(String id, String name) => WmlParagraph(
            inlines: [
              WmlBookmarkBoundary(id: id, isStart: true, name: name),
              WmlRun(text: name),
              WmlBookmarkBoundary(id: id, isStart: false),
            ],
          );
          final first = pair('71', 'Shared');
          final secondId = duplicate == 'id' ? '+71' : '72';
          final secondName = duplicate == 'name' ? 'Shared' : 'Different';
          final second = pair(secondId, secondName);
          if (context == 'footnotes' || context == 'endnotes') {
            final endnote = context == 'endnotes';
            (endnote ? document.endnotes : document.footnotes).addAll([
              WmlNote(id: 1, endnote: endnote, paragraphs: [first]),
              WmlNote(id: 2, endnote: endnote, paragraphs: [second]),
            ]);
          } else {
            document.sections.first.blocks.add(first);
            if (context == 'textbox') {
              document.sections.first.blocks.add(WmlFrame(blocks: [second]));
            } else {
              document.sections.first.blocks.add(
                WmlOpaqueBlock(
                  xml:
                      '<w:customXml xmlns:w="${OfficeNamespaces.w}"><w:p>'
                      '<w:bookmarkStart w:id="$secondId" w:name="$secondName"/>'
                      '<w:r><w:t>Opaque</w:t></w:r><w:bookmarkEnd w:id="$secondId"/>'
                      '</w:p></w:customXml>',
                  sourcePartUri: '/word/document.xml',
                  relationships: const [],
                ),
              );
            }
          }
          final before = document.package!.save();
          expect(() => WordSerializer().writeBytes(document), throwsStateError);
          expect(document.package!.save(), before);
          await expectLater(OfficeIsolateSave.word(document), throwsStateError);
          expect(document.package!.save(), before);
        },
      );
    }
  }

  test(
    'separate native parts retain independent bookmark identities',
    () async {
      WmlParagraph pair() => WmlParagraph(
        inlines: [
          WmlBookmarkBoundary(id: '71', isStart: true, name: 'Shared'),
          WmlRun(text: 'Shared'),
          WmlBookmarkBoundary(id: '71', isStart: false),
        ],
      );
      var document = WmlDocument.empty(text: 'Body');
      document.sections.first
        ..header.add(pair())
        ..footer.add(pair());
      document.footnotes.add(
        WmlNote(id: 1, endnote: false, paragraphs: [pair()]),
      );
      document.endnotes.add(
        WmlNote(id: 1, endnote: true, paragraphs: [pair()]),
      );
      for (var cycle = 0; cycle < 3; cycle++) {
        document = WordDeserializer().readBytes(
          await OfficeIsolateSave.word(document),
        );
        expect(WordBookmarks.ranges(document).map((range) => range.start.id), [
          '71',
          '71',
          '71',
          '71',
        ]);
      }
    },
  );
}
