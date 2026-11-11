import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';
import '../tool/fidelity/note_fixture.dart';

void main() {
  test('editable note text omits the space after the note number', () {
    final WmlNote note = WmlNote(
      id: 1,
      endnote: false,
      paragraphs: <WmlParagraph>[
        WmlParagraph(inlines: <WmlInline>[WmlRun(text: ' First')]),
        WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Second')]),
      ],
    );
    expect(WordNotes.editableText(note), 'First\nSecond');
    WordNotes.editText(note, 'First line\nSecond');
    expect(note.paragraphs.first.text, ' First line');
    expect(note.paragraphs.last.text, 'Second');
  });

  test('editing a rich note keeps formatting, tables, pictures and links', () {
    final WmlDocument doc = richNoteFixture();
    final WmlNote note = doc.footnotes.single;
    final int tables = note.blocks.whereType<WmlTable>().length;
    final int visuals = note.visuals.length;
    expect(WordNotes.editableText(note), 'Rich note\nNote link');

    WordNotes.editText(note, 'Rich note, edited\nNote link');

    final WmlParagraph first = note.paragraphs.first;
    expect(first.text, 'Rich note, edited');
    final List<WmlRun> runs = first.inlines.whereType<WmlRun>().toList();
    expect(runs, isNotEmpty);
    for (final WmlRun run in runs.where((WmlRun r) => r.text.isNotEmpty)) {
      expect(run.properties.bold, isTrue, reason: run.text);
      expect(run.properties.color, '008844', reason: run.text);
      expect(run.properties.fontSizeHalfPoints, 24, reason: run.text);
    }
    expect(note.blocks.whereType<WmlTable>(), hasLength(tables));
    expect(note.visuals, hasLength(visuals));

    final LaidOutDocument layout = WordLayoutEngine(font: null).layout(doc);
    final List<LaidOutGlyph> glyphs = layout.pages
        .expand((LaidOutPage p) => p.notes)
        .expand((LaidOutLine l) => l.glyphs)
        .toList();
    expect(
      glyphs.any(
        (LaidOutGlyph g) => g.hyperlink?.url == 'https://example.com/note',
      ),
      isTrue,
    );
  });

  test('added and removed lines become styled paragraphs', () {
    final WmlNote note = WmlNote(
      id: 3,
      endnote: false,
      paragraphs: <WmlParagraph>[
        WmlParagraph(
          properties: WmlParagraphProps()..styleId = 'FootnoteText',
          inlines: <WmlInline>[
            WmlRun(text: 'One', properties: WmlRunProps(italic: true)),
          ],
        ),
      ],
    );
    WordNotes.editText(note, 'One\nTwo\nThree');
    expect(note.paragraphs.map((WmlParagraph p) => p.text), <String>[
      'One',
      'Two',
      'Three',
    ]);
    for (final WmlParagraph paragraph in note.paragraphs) {
      expect(paragraph.properties.styleId, 'FootnoteText');
      expect(
        paragraph.inlines.whereType<WmlRun>().first.properties.italic,
        isTrue,
      );
    }
    WordNotes.editText(note, 'One');
    expect(note.paragraphs, hasLength(1));
    expect(note.paragraphs.single.text, 'One');
  });

  test('edited note text survives save and reopen', () async {
    final WmlDocument doc = richNoteFixture();
    WordNotes.editText(doc.footnotes.single, 'Changed note\nNote link');
    final WmlDocument reopened = WordDeserializer().readBytes(
      await OfficeIsolateSave.word(doc),
    );
    final WmlNote note = reopened.footnotes.single;
    expect(WordNotes.editableText(note), 'Changed note\nNote link');
    expect(note.blocks.whereType<WmlTable>(), hasLength(1));
    final WmlRun run = note.paragraphs.first.inlines
        .whereType<WmlRun>()
        .firstWhere((WmlRun r) => r.text.contains('Changed'));
    expect(run.properties.bold, isTrue);
  });
}
