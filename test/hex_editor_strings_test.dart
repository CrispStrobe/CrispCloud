import 'package:crisp_cloud/l10n/hex_editor_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every hex-specific label covers all nine app languages', () {
    final keys = <String>{};
    for (final row in HexEditorStrings.rows) {
      expect(row.length, HexEditorStrings.languages.length, reason: row.first);
      expect(keys.add(row.first), isTrue, reason: 'Duplicate: ${row.first}');
      for (var i = 0; i < row.length; i++) {
        expect(row[i].trim(), isNotEmpty);
        expect(
          HexEditorStrings.forLanguage(
            HexEditorStrings.languages[i],
            row.first,
          ),
          row[i],
        );
      }
    }
  });

  test(
    'shared commands and package chrome all have supported-language entries',
    () {
      const keys = [
        'Hex editor',
        'Offset',
        'Text',
        'Copy',
        'Cut',
        'Paste',
        'Select all',
        'Enter bytes…',
        'Hex bytes',
        'Byte text (Latin-1)',
        'Apply',
        'Cancel',
        'Retry',
        'Scroll bytes',
        'Loading bytes',
        'Save',
        'Saved',
        'Saving…',
        'Undo',
        'Redo',
        'Discard',
        'Close',
      ];
      for (final language in HexEditorStrings.languages) {
        for (final key in keys) {
          expect(
            HexEditorStrings.forLanguage(language, key),
            isNotEmpty,
            reason: '$language / $key',
          );
        }
      }
      expect(HexEditorStrings.forLanguage('de', 'Save'), 'Speichern');
      expect(HexEditorStrings.forLanguage('xx', 'Hex editor'), 'Hex editor');
    },
  );
}
