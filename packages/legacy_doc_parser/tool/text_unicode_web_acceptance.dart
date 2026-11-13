// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/text_unicode_fixture.dart';

void _check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

Map<String, Object?> verifyTextUnicodeWebAcceptance() {
  for (final name in invalidTextUnicodeCases) {
    final source = textUnicodeFixture(name);
    final before = Uint8List.fromList(source);
    for (final api in <Object? Function(Uint8List)>[
      extractLegacyWordText,
      convertLegacyWordToDocx,
    ]) {
      var rejected = false;
      try {
        api(source);
      } on FormatException catch (error) {
        rejected = error.message.contains('UTF-16');
      }
      _check(rejected, '$name must reject invalid body UTF-16');
    }
    _check(source.length == before.length, '$name source length');
    for (var i = 0; i < source.length; i++) {
      _check(source[i] == before[i], '$name must not modify input');
    }
  }

  const supported = {
    'split-physical-pieces': 'A\u{1f600}Z',
    'valid-field': 'A\u{1f680}Z',
    'unconsumed-auxiliary': 'Main',
  };
  for (final entry in supported.entries) {
    final source = textUnicodeFixture(entry.key);
    _check(extractLegacyWordText(source) == entry.value, '${entry.key} text');
    final archive = ZipDecoder().decodeBytes(convertLegacyWordToDocx(source));
    final document = XmlDocument.parse(
      utf8.decode(archive.findFile('word/document.xml')!.content),
    );
    _check(
      document.findAllElements('w:t').map((e) => e.innerText).join() ==
          entry.value,
      '${entry.key} DOCX text',
    );
  }
  return {
    'invalidMainBodiesRejected': invalidTextUnicodeCases.length,
    'supportedCases': supported.length,
    'sourceUnchanged': true,
  };
}
