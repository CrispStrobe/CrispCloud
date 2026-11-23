import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/structured_word_fixture.dart';

// A .doc stores built-in style names in the UI language ("Standard",
// "Überschrift 1"); OOXML identifies built-in styles by their canonical names,
// as Word's own export does. User-defined styles keep their names.
void main() {
  test('built-in styles get canonical names; user styles keep theirs', () {
    final bytes = StructuredWordFixture(
      pieces: const [
        WordFixturePiece('Titel\rText\rEigen\r', compressed: false),
      ],
      paragraphRuns: const [
        WordFixtureFkpRun(8192, 8204, styleIndex: 1),
        WordFixtureFkpRun(8204, 8214, styleIndex: 0),
        WordFixtureFkpRun(8214, 8226, styleIndex: 2),
      ],
      styles: const {
        0: WordFixtureStyle(name: 'Standard', builtinId: 0),
        1: WordFixtureStyle(name: 'Überschrift 1', builtinId: 1),
        2: WordFixtureStyle(name: 'Meine Vorlage'),
      },
    ).build();
    final document = parseLegacyWordDocument(bytes);
    final names = [
      for (final block in document.blocks.whereType<LegacyWordParagraph>())
        block.style.styleName,
    ];
    expect(names, ['heading 1', 'Normal', 'Meine Vorlage']);
    final archive = ZipDecoder().decodeBytes(convertLegacyWord(bytes).bytes);
    final styles = utf8.decode(
      archive.findFile('word/styles.xml')!.content as List<int>,
    );
    expect(styles, contains('<w:name w:val="heading 1"/>'));
    expect(styles, contains('<w:name w:val="Normal"/>'));
    expect(styles, contains('<w:name w:val="Meine Vorlage"/>'));
    expect(styles, isNot(contains('Standard')));
  });
}
