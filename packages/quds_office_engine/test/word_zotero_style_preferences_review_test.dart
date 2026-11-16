import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _style = 'http://www.zotero.org/styles/apa';

String _json({Object? style, Object? noteType = 0}) => jsonEncode({
  'style': style ?? {'styleID': _style, 'locale': 'de-DE'},
  'prefs': {'fieldType': 'Field', 'noteType': noteType},
});

void main() {
  test(
    'truly unset style remains distinguishable from damaged preferences',
    () {
      expect(WordZoteroDocumentData.stylePreferences(''), isNull);
      expect(
        WordZoteroDocumentData.stylePreferences(
          '{"prefs":{"fieldType":"Field"}}',
        ),
        isNull,
      );
      expect(
        WordZoteroDocumentData.stylePreferences(_json(style: {'styleID': ''})),
        isNull,
      );
    },
  );

  for (final (name, data) in <(String, String)>[
    ('non-object style', _json(style: [_style])),
    ('non-string style identity', _json(style: {'styleID': 17})),
    ('non-string locale', _json(style: {'styleID': _style, 'locale': true})),
    ('non-integer placement', _json(noteType: '1')),
    ('negative placement', _json(noteType: -1)),
    ('unsupported placement', _json(noteType: 3)),
    (
      'duplicate XML styles',
      '<data><style id="$_style"/><style id="another-style"/>'
          '<prefs><pref name="fieldType" value="Field"/></prefs></data>',
    ),
    (
      'invalid XML placement',
      '<data><style id="$_style"/><prefs>'
          '<pref name="fieldType" value="Field"/>'
          '<pref name="noteType" value="footnotes"/></prefs></data>',
    ),
  ]) {
    test('damaged $name cannot be treated as an unset document style', () {
      final document = WmlDocument.empty(text: 'Original document')
        ..zoteroDocumentData = data;
      expect(
        () => WordZoteroDocumentData.stylePreferences(
          WordZoteroDocumentData.read(document),
        ),
        throwsFormatException,
      );
      expect(document.zoteroDocumentData, data);
      expect(document.paragraphs.single.text, 'Original document');
      expect(WordZotero.fields(document), isEmpty);
    });
  }
}
