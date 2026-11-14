// SPDX-License-Identifier: MPL-2.0
// Shared VM/JavaScript exact-label and immutable-source acceptance.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/list_literal_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void _check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

String _runText(XmlElement run) => run.descendants
    .whereType<XmlElement>()
    .where(
      (node) =>
          node.name.namespaceUri == _w &&
          (node.name.local == 't' || node.name.local == 'tab'),
    )
    .map((node) => node.name.local == 'tab' ? '\t' : node.innerText)
    .join();

Map<String, Object> verifyListLiteralWebAcceptance() {
  for (final fixture in [...listLiteralCases, ...listLiteralMetamorphicCases]) {
    final source = fixture.build(), before = fixture.build();
    final document = parseLegacyWordDocument(source);
    final level = document.numbering.single.levels.single;
    void check(bool value, String message) =>
        _check(value, '${fixture.name}: $message');
    check(level.text == fixture.text, 'canonical source text');
    check(
      jsonEncode(level.placeholderOffsets) == jsonEncode(fixture.offsets),
      'exact UTF-16 offsets',
    );
    final html = XmlDocument.parse(document.safeHtml);
    final labels = html
        .findAllElements('span')
        .where((node) => node.getAttribute('data-word-list-label') == 'true');
    check(
      labels.length == 1 && labels.single.innerText == fixture.label,
      'exact HTML label',
    );
    final result = convertLegacyWordDocument(document);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    XmlDocument part(String path) =>
        XmlDocument.parse(utf8.decode(archive.findFile(path)!.content));
    final paragraph = part(
      'word/document.xml',
    ).findAllElements('p', namespace: _w).single;
    final runs = paragraph.findElements('r', namespace: _w).toList();
    final suffix = ['', ' ', ''][fixture.suffix];
    final expected = fixture.label + (fixture.suffix == 0 ? '\t' : suffix);
    check(
      runs.length == 2 &&
          _runText(runs.first) == expected &&
          _runText(runs.last) == 'Item',
      'exact synthetic prefix and unchanged body run',
    );
    check(
      paragraph
              .findAllElements('numId', namespace: _w)
              .single
              .getAttribute('val', namespace: _w) ==
          '0',
      'native counter substitution disabled',
    );
    final numbering = part('word/numbering.xml');
    check(
      numbering
              .findAllElements('lvlText', namespace: _w)
              .single
              .getAttribute('val', namespace: _w) ==
          '',
      'ambiguous template is not emitted as active numbering',
    );
    final evidence =
        jsonDecode(
              utf8.decode(
                archive.findFile('word/evidence/manifest.json')!.content,
              ),
            )
            as Map;
    final records = evidence['records'] as List;
    final template =
        records.singleWhere(
              (record) => record['kind'] == 'literalNumberingTemplate',
            )
            as Map;
    check(
      template['text'] == fixture.text &&
          template['binaryTemplate'] == fixture.sourceText &&
          jsonEncode(template['placeholderOffsets']) ==
              jsonEncode(fixture.offsets),
      'lossless source template evidence',
    );
    final marker =
        records.singleWhere(
              (record) => record['kind'] == 'materializedNumberingLabel',
            )
            as Map;
    check(
      marker['label'] == fixture.label &&
          marker['cp'] == 0 &&
          marker['story'] == 'main' &&
          marker['automaticRenumbering'] == false,
      'materialization evidence',
    );
    check(
      result.limitations.contains(LegacyWordConversionLimitation.fieldsLists) &&
          result.preservedCounts['materializedNumberingLabels'] == 1,
      'limitation and counts',
    );
    check(source.length == before.length, 'source length');
    for (var i = 0; i < source.length; i++) {
      check(source[i] == before[i], 'source byte $i');
    }
  }
  return {
    'cases': listLiteralCases.length + listLiteralMetamorphicCases.length,
    'fixtureCases': listLiteralCases.length,
    'metamorphicCases': listLiteralMetamorphicCases.length,
    'exactHtmlLabels': true,
    'exactDocxPrefixes': true,
    'sourceTemplatesRetained': true,
    'automaticRenumberingDisclosed': true,
    'sourceUnchanged': true,
  };
}

void main() => print(jsonEncode(verifyListLiteralWebAcceptance()));
