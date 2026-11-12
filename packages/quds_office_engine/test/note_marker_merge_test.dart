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
      if (inline is WmlBookmarkMarker) {
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
        note.paragraphs.first.inlines.whereType<WmlNoteBodyMarker>(),
        hasLength(1),
      );
      expect(
        note.paragraphs.last.inlines.whereType<WmlNoteBodyMarker>(),
        isEmpty,
      );
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
          preserveBodyMarkers: true,
          paragraphs: [
            WmlParagraph(
              inlines: [
                WmlRun(text: '  Lead'),
                if (later) WmlNoteBodyMarker(endnote: false),
                WmlRun(text: ' tail'),
              ],
            ),
          ],
        );
        expect(WordNotes.editableText(note), '  Lead tail');
        WordNotes.editText(note, ' Changed tail');
        expect(note.paragraphs.single.text, ' Changed tail');
        expect(
          note.paragraphs.single.inlines.whereType<WmlNoteBodyMarker>(),
          hasLength(later ? 1 : 0),
        );
      }
    },
  );

  test('note Enter carries the styled tail and late native note mark', () {
    final note = WmlNote(
      id: 1,
      endnote: false,
      preserveBodyMarkers: true,
      paragraphs: [
        WmlParagraph(
          inlines: [
            WmlRun(text: 'First '),
            WmlNoteBodyMarker(endnote: false, propertiesXml: ''),
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
    expect(
      note.paragraphs.first.inlines.whereType<WmlNoteBodyMarker>(),
      isEmpty,
    );
    expect(note.paragraphs.last.inlines.first, isA<WmlNoteBodyMarker>());
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
              .whereType<WmlBookmarkStart>()
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
}
