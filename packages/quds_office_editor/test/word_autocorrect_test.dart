import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_editor/src/embed/word_autocorrect.dart';

void main() {
  group('Word autocorrect', () {
    test('German and English double quotes are context aware', () {
      final deOpen = wordAutocorrectInsertion(
        text: '"',
        offset: 0,
        inserted: '"',
        language: 'de-DE',
      );
      expect(deOpen.text, '„');

      final deClose = wordAutocorrectInsertion(
        text: 'Wort"',
        offset: 4,
        inserted: '"',
        language: 'de-DE',
      );
      expect(deClose.text, 'Wort“');

      final enOpen = wordAutocorrectInsertion(
        text: '"',
        offset: 0,
        inserted: '"',
        language: 'en-US',
      );
      expect(enOpen.text, '“');
      final enClose = wordAutocorrectInsertion(
        text: 'word"',
        offset: 4,
        inserted: '"',
        language: 'en-US',
      );
      expect(enClose.text, 'word”');
    });

    test('apostrophes and single quotes are context aware', () {
      expect(
        wordAutocorrectInsertion(
          text: "don'",
          offset: 3,
          inserted: "'",
          language: 'en-US',
        ).text,
        'don’',
      );
      expect(
        wordAutocorrectInsertion(
          text: "'word",
          offset: 0,
          inserted: "'",
          language: 'en-US',
        ).text,
        '‘word',
      );
      expect(
        wordAutocorrectInsertion(
          text: "‚word'",
          offset: 5,
          inserted: "'",
          language: 'de-DE',
        ).text,
        '‚word‘',
      );
    });

    test('spaced dash becomes an en dash and longer runs an em dash', () {
      expect(
        wordAutocorrectInsertion(
          text: 'asdf - ',
          offset: 6,
          inserted: ' ',
          language: 'de-DE',
        ).text,
        'asdf – ',
      );
      expect(
        wordAutocorrectInsertion(
          text: 'asdf -- ',
          offset: 7,
          inserted: ' ',
          language: 'de-DE',
        ).text,
        'asdf – ',
      );
      expect(
        wordAutocorrectInsertion(
          text: 'asdf --- ',
          offset: 8,
          inserted: ' ',
          language: 'de-DE',
        ).text,
        'asdf — ',
      );
      expect(
        wordAutocorrectInsertion(
          text: 'asdf - x ',
          offset: 7,
          inserted: ' ',
          language: 'de-DE',
        ).text,
        'asdf - x ',
      );
    });

    test('controller applies corrections through the IME path', () {
      final word = WordEditorController();
      word.document.proofingLanguage = 'de-DE';
      const typed = 'Hallo "Welt" - ';
      for (final char in typed.split('')) {
        word.applyImeText('${word.document.paragraphs.first.text}$char');
      }
      expect(word.document.paragraphs.first.text, 'Hallo „Welt“ – ');
    });

    test('committed corrections are synchronized with the input bridge', () {
      final word = WordEditorController();
      addTearDown(word.dispose);
      word.document.proofingLanguage = 'de-DE';
      for (final char in 'Hallo "Welt" -- '.split('')) {
        final next = '${word.input.value.text}$char';
        word.input.updateEditingValue(
          TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(offset: next.length),
          ),
        );
        expect(word.input.value.text, word.document.paragraphs.first.text);
        expect(
          word.input.value.selection.extentOffset,
          word.caret.logicalIndex,
        );
      }
      expect(word.document.paragraphs.first.text, 'Hallo „Welt“ – ');
    });

    test('IME bridge keeps autocorrection on the following keystroke', () {
      final word = WordEditorController();
      addTearDown(word.dispose);
      word.document.proofingLanguage = 'de-DE';
      word.input.updateEditingValue(
        const TextEditingValue(
          text: '"',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      final correctedParagraph = word.document.paragraphs.first.text;
      final correctedInput = word.input.value;

      // The next platform value extends the bridge's editing state, which
      // must already contain the correction sent back to the IME.
      final nextText = '${word.input.value.text}a';
      word.input.updateEditingValue(
        TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: nextText.length),
        ),
      );

      expect(
        [
          correctedParagraph,
          correctedInput.text,
          word.document.paragraphs.first.text,
          word.input.value.text,
        ],
        ['„', '„', '„a', '„a'],
      );
      expect(
        correctedInput.selection,
        const TextSelection.collapsed(offset: 1),
      );
      expect(
        word.input.value.selection,
        const TextSelection.collapsed(offset: 2),
      );
      expect(word.caret.logicalIndex, 2);
    });
  });
}
