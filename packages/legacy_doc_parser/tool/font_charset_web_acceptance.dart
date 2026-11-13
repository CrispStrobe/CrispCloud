// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/font_charset_fixture.dart';

void main() => print(
  'Font charset JavaScript/VM acceptance passed: '
  '${jsonEncode(verifyFontCharsetWebAcceptance())}',
);

Map<String, Object> verifyFontCharsetWebAcceptance() {
  const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  var checks = 0;
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
    checks++;
  }

  final cases = <(String, List<(String, int)>, String?)>[
    ('symbol', [('Wingdings', 2)], '02'),
    ('default', [('Wingdings', 1)], '01'),
    ('alias', [('Wingdings', 1), ('Wingdings', 2)], '02'),
    ('repeated', [('Wingdings', 2), ('Wingdings', 2)], '02'),
    ('conflict', [('Wingdings', 0), ('Wingdings', 2)], null),
    ('locale-default', [('Wingdings', 1), ('Wingdings', 0)], null),
    ('unknown', [('Wingdings', 9)], null),
    ('empty-name', [('', 1)], null),
  ];
  for (final (name, fonts, expected) in cases) {
    final document = parseLegacyWordDocument(fontCharsetWordFixture(fonts));
    check(document.fontTable.length == fonts.length, '$name source indices');
    check(
      document.fontTable.asMap().entries.every(
        (entry) =>
            entry.value.sourceIndex == entry.key &&
            entry.value.name == fonts[entry.key].$1 &&
            entry.value.charset == fonts[entry.key].$2,
      ),
      '$name exact source operands',
    );
    check(document.plainText == '\uf0fc', '$name PUA unchanged');
    final archive = ZipDecoder().decodeBytes(
      convertLegacyWordDocument(document).bytes,
    );
    final part = archive.findFile('word/fontTable.xml');
    final actual = part == null
        ? null
        : XmlDocument.parse(utf8.decode(part.content))
              .findAllElements('charset', namespace: w)
              .single
              .getAttribute('val', namespace: w);
    check(actual == expected, '$name bounded charset serialization');
    final evidence = jsonDecode(
      utf8.decode(archive.findFile('word/evidence/manifest.json')!.content),
    );
    final record = (evidence['records'] as List).singleWhere(
      (record) => record['kind'] == 'sourceFontCharsets',
    );
    check(
      (record['definitions'] as List).length == fonts.length,
      '$name raw operands retained',
    );
  }
  return {'cases': cases.length, 'checks': checks, 'puaRemapped': false};
}
