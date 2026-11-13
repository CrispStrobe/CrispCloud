// SPDX-License-Identifier: MPL-2.0
// Actual parser/converter execution under both Dart VM and dart2js/Node.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/structured_word_fixture.dart';
import '../test/support/symbol_word_fixture.dart';

void main() => print(
  'Symbol JavaScript/VM acceptance passed: '
  '${jsonEncode(verifySymbolWebAcceptance())}',
);

Map<String, Object> verifySymbolWebAcceptance() {
  var checks = 0;
  void check(bool passed, String reason) {
    if (!passed) throw StateError(reason);
    checks++;
  }

  const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  for (final (name, operations, count, limited) in [
    ('implicit', symbolOperands(), 1, false),
    (
      'prior-false',
      [
        ...wordSprm(0x0855, [0]),
        ...symbolOperands(),
      ],
      1,
      false,
    ),
    (
      'later-false',
      [
        ...symbolOperands(),
        ...wordSprm(0x0855, [0]),
      ],
      0,
      true,
    ),
    ('ordinary', <int>[], 0, false),
    (
      'deleted',
      [
        ...symbolOperands(),
        ...wordSprm(0x0800, [1]),
      ],
      1,
      false,
    ),
    (
      'hidden',
      [
        ...symbolOperands(),
        ...wordSprm(0x083c, [1]),
      ],
      1,
      false,
    ),
  ]) {
    final document = parseLegacyWordDocument(
      symbolWordFixture(operations: operations),
    );
    final converted = convertLegacyWordDocument(document);
    final archive = ZipDecoder().decodeBytes(converted.bytes);
    final xml = XmlDocument.parse(
      utf8.decode(archive.findFile('word/document.xml')!.content),
    );
    final symbols = xml.findAllElements('sym', namespace: w).toList();
    check(symbols.length == count, '$name glyph count');
    check(
      symbols.every(
        (glyph) =>
            glyph.getAttribute('font', namespace: w) == 'Symbol' &&
            glyph.getAttribute('char', namespace: w) == 'F061',
      ),
      '$name exact font/code',
    );
    if (limited) {
      check(
        converted.limitations.contains(
          LegacyWordConversionLimitation.partialFormatting,
        ),
        '$name unresolved later flag must remain qualified',
      );
    }
    if (name == 'deleted') {
      check(
        xml
                .findAllElements('del', namespace: w)
                .single
                .findAllElements('sym', namespace: w)
                .length ==
            1,
        'deletion wrapper retains symbol',
      );
    }
    if (name == 'hidden') {
      check(
        !document.safeHtml.contains('\uf061'),
        'hidden glyph does not leak',
      );
    }
  }
  final repeated = parseLegacyWordDocument(
    symbolWordFixture(text: 'A((B\r', end: 3),
  );
  final symbolRun = repeated.blocks
      .whereType<LegacyWordParagraph>()
      .single
      .runs
      .singleWhere((run) => run.symbol != null);
  check(
    symbolRun.startCp == 1 &&
        symbolRun.endCp == 3 &&
        symbolRun.text == '\ufffc\ufffc',
    'coalesced symbol CPs remain exact',
  );
  for (final font in [3, 0xffff]) {
    var rejected = false;
    try {
      parseLegacyWordDocument(
        symbolWordFixture(operations: symbolOperands(font: font)),
      );
    } on FormatException {
      rejected = true;
    }
    check(rejected, 'invalid source font index $font');
  }
  return {
    'cases': 9,
    'checks': checks,
    'symbolCode': 'F061',
    'ordinaryPunctuationIsDistinct': true,
    'laterFalseIsQualified': true,
  };
}
