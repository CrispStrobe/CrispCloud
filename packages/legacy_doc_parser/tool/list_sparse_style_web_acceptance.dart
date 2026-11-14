// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/list_sparse_style_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void verifyListSparseStyleCase(String name) {
  void check(bool condition, String message) {
    if (!condition) throw StateError('$name: $message');
  }

  final parts = name.split('-');
  final literal = parts[0] == 'literal', property = parts[2], state = parts[3];
  final spec = listSparseStyleProperties[property]!;
  final source = listSparseStyleFixture(name), before = source.toList();
  final document = parseLegacyWordDocument(source);
  final level = document.numbering.single.levels.single;
  check(level.characterStyleIsSparse, 'parsed sparse formatting');
  check(
    level.characterStyleOverrides.any((key) => key.name == property) ==
        (state != 'absent'),
    'exact property override presence',
  );
  final converted = convertLegacyWordDocument(document);
  final archive = ZipDecoder().decodeBytes(converted.bytes);
  XmlDocument part(String name) =>
      XmlDocument.parse(utf8.decode(archive.findFile(name)!.content));
  final paragraph = part(
    'word/document.xml',
  ).findAllElements('p', namespace: _w).single;
  final marker = literal
      ? paragraph
            .findElements('r', namespace: _w)
            .first
            .getElement('rPr', namespace: _w)!
      : part('word/numbering.xml').findAllElements('rPr', namespace: _w).single;
  String? value(XmlElement style) {
    final element = style.getElement(spec.$4, namespace: _w);
    return element == null
        ? null
        : element.getAttribute('val', namespace: _w) ?? '1';
  }

  final expected = !literal && state == 'absent'
      ? null
      : state == 'reset'
      ? spec.$6
      : spec.$5;
  check(
    value(marker) == expected,
    'exact marker XML ${spec.$4}: expected $expected, got ${value(marker)}',
  );
  final body = paragraph
      .findElements('r', namespace: _w)
      .last
      .getElement('rPr', namespace: _w)!;
  check(value(body) == spec.$6, 'body explicit reset unchanged');
  final html = XmlDocument.parse(document.safeHtml.replaceAll('<br>', '<br/>'));
  final labels = html
      .findAllElements('span')
      .where(
        (element) => element.getAttribute('data-word-list-label') == 'true',
      )
      .toList();
  final hidden = property == 'hidden' && state != 'reset';
  check(
    labels.length == (hidden ? 0 : 1),
    'HTML inherited or reset label visibility',
  );
  if (!hidden) {
    check(
      labels.single.innerText == (literal ? '%1 abc' : '7 abc'),
      'exact HTML label source text',
    );
    if (property != 'hidden') {
      check(
        labels.single.toXmlString().contains(spec.$7) == (state != 'reset'),
        'HTML inherited/reset property',
      );
    }
  }
  check(
    (converted.preservedCounts['materializedNumberingLabels'] ?? 0) ==
        (literal ? 1 : 0),
    'materialized count',
  );
  check(source.length == before.length, 'source byte length unchanged');
  for (var i = 0; i < before.length; i++) {
    check(source[i] == before[i], 'source byte $i unchanged');
  }
}
