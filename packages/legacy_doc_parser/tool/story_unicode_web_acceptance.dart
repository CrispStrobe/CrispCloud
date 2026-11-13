// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/story_unicode_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void _check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

void _unchanged(Uint8List source, Uint8List before, String name) {
  _check(source.length == before.length, '$name source length');
  for (var i = 0; i < source.length; i++) {
    _check(source[i] == before[i], '$name source mutation');
  }
}

Map<String, Object?> verifyStoryUnicodeWebAcceptance() {
  for (final name in invalidStoryUnicodeCases) {
    final source = storyUnicodeFixture(name);
    final before = Uint8List.fromList(source);
    var rejected = false;
    try {
      parseLegacyWordDocument(source);
    } on FormatException catch (error) {
      rejected = error.message.contains('story boundary');
    }
    _check(rejected, '$name must reject a scalar crossing a story boundary');
    _unchanged(source, before, name);
  }

  const name = 'supplementary-stories';
  final source = storyUnicodeFixture(name);
  final before = Uint8List.fromList(source);
  final document = parseLegacyWordDocument(source);
  _check(document.plainText == 'A\u{1f600}', '$name main text');
  _check(document.stories.single.plainText == 'B\u{1f680}', '$name note text');
  for (final paragraph in [
    ...document.blocks.whereType<LegacyWordParagraph>(),
    ...document.stories.single.blocks.whereType<LegacyWordParagraph>(),
  ]) {
    for (final run in paragraph.runs) {
      _check(
        run.startCp >= paragraph.startCp && run.endCp <= paragraph.endCp,
        '$name run exceeds its containing paragraph',
      );
    }
  }
  final result = convertLegacyWordDocument(document);
  final archive = ZipDecoder().decodeBytes(result.bytes);
  String textOf(String path) {
    final xml = XmlDocument.parse(utf8.decode(archive.findFile(path)!.content));
    return xml
        .findAllElements('t', namespace: _w)
        .map((e) => e.innerText)
        .join();
  }

  _check(textOf('word/document.xml') == 'A\u{1f600}', '$name DOCX main text');
  _check(textOf('word/footnotes.xml') == 'B\u{1f680}', '$name DOCX note text');
  _unchanged(source, before, name);
  return {
    'cases': invalidStoryUnicodeCases.length + 1,
    'invalidStoryBoundariesRejected': invalidStoryUnicodeCases.length,
    'supplementaryStoryTextPreserved': true,
    'sourceUnchanged': true,
  };
}
