import 'package:crisp_cloud/l10n/image_editor_strings.dart';
import 'package:crisp_cloud/l10n/media_editor_strings.dart';
import 'package:crisp_cloud/widgets/media_editor_controls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every media message covers all nine application languages', () {
    expect(MediaEditorStrings.languages.toSet(), ImageEditorStrings.supportedLanguageCodes);
    final keys = <String>{};
    for (final row in MediaEditorStrings.rows) {
      expect(row, hasLength(MediaEditorStrings.languages.length), reason: row.first);
      expect(keys.add(row.first), isTrue, reason: 'Duplicate message: ${row.first}');
      for (final text in row) { expect(text.trim(), isNotEmpty, reason: row.first); }
    }
    for (final language in MediaEditorStrings.languages) {
      for (final row in MediaEditorStrings.rows) {
        expect(MediaEditorStrings.forLanguage(language, row.first), isNotEmpty);
      }
      for (final command in ['File', 'Edit', 'Undo', 'Redo', 'Original', 'Cancel', 'Retry', 'Discard', 'Close editor', 'Continue editing', 'Could not apply changes', 'Unsaved changes will be lost.']) {
        expect(MediaEditorStrings.forLanguage(language, command), isNotEmpty);
      }
    }
  });

  test('precision trim fields parse unambiguous media timestamps', () {
    expect(parseMediaTime('1:02.125'), const Duration(seconds: 62, milliseconds: 125));
    expect(parseMediaTime('1:02:03.5'), const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500));
    expect(parseMediaTime('0.001'), const Duration(milliseconds: 1));
    expect(formatMediaTime(const Duration(minutes: 62, milliseconds: 125)), '62:00.125');
    for (final invalid in ['', '-1', 'NaN', 'Infinity', '1:60', '0:0:0:1', '0.5:20', '9999999999999999999999']) {
      expect(parseMediaTime(invalid), isNull, reason: invalid);
    }
  });
}
