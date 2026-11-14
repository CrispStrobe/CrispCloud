// SPDX-License-Identifier: MPL-2.0
// The same independently authored list bytes run on the VM and compiled JS.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/list_metadata_fixture.dart';

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

Map<String, Object> verifyListMetadataWebAcceptance() {
  const expected = <String, (List<String>, int, String, String, int?)>{
    'bullet-ignored-restart': (['\u2022'], 0, 'bullet', '\u2022', null),
    'none-ignored-restart': ([], 0, 'none', '', null),
    'none-literal': (['Appendix'], 0, 'none', 'Appendix', null),
    'none-empty-placeholder': (['Appendix .'], 0, 'none', 'Appendix %1.', null),
    'none-ancestor-placeholder': (
      ['3.', '3 Appendix '],
      1,
      'none',
      '%1 Appendix %2',
      null,
    ),
    'literal-percent-text': (
      ['% %0 %x 50%'],
      0,
      'decimal',
      '% %0 %x 50%',
      null,
    ),
    'percent-before-placeholder': (['%7 %'], 0, 'decimal', '%%1 %', null),
    'numbered-valid-restart': (['7.'], 0, 'decimal', '%1.', 0),
    'numbered-inactive-restart': (['7.'], 0, 'decimal', '%1.', null),
    'uncommon-format-literal': (['Appendix'], 0, 'hebrew1', 'Appendix', null),
    'uncommon-format-ancestor': (
      ['3.', '3 Appendix'],
      1,
      'hebrew1',
      '%1 Appendix',
      null,
    ),
    'uncommon-format-legal': (['7.'], 0, 'hebrew1', '%1.', null),
    'literal-label-tab': (['A\tB'], 0, 'decimal', 'A\tB', null),
    'tab-before-placeholder': (['A\t7'], 0, 'decimal', 'A\t%1', null),
    'none-label-tab': (['A\tB'], 0, 'none', 'A\tB', null),
    'literal-percent-one': (['%1'], 0, 'decimal', '%1', null),
    'literal-percent-nine': (['%9'], 0, 'decimal', '%9', null),
    'mixed-literal-percent': (
      ['7 literal %1'],
      0,
      'decimal',
      '%1 literal %1',
      null,
    ),
    'override-literal-percent': (['%1'], 0, 'decimal', '%1', null),
    'none-literal-percent': (['%1'], 0, 'none', '%1', null),
  };
  _check(
    expected.keys.join(',') == listMetadataCases.join(','),
    'List metadata acceptance inventory changed',
  );
  for (final name in listMetadataCases) {
    final source = listMetadataFixture(name);
    final before = Uint8List.fromList(source);
    final document = parseLegacyWordDocument(source);
    final (labels, levelIndex, format, text, restart) = expected[name]!;
    final html = XmlDocument.parse(document.safeHtml);
    final actualLabels = html
        .findAllElements('span')
        .where((node) => node.getAttribute('data-word-list-label') == 'true')
        .map((node) => node.innerText)
        .toList();
    _check(actualLabels.length == labels.length, '$name HTML label count');
    for (var i = 0; i < labels.length; i++) {
      _check(actualLabels[i] == labels[i], '$name HTML label $i');
    }
    final definition = document.numbering.singleWhere(
      (definition) => definition.id == 1,
    );
    final level = definition.levels.singleWhere(
      (level) => level.level == levelIndex,
    );
    _check(level.format == format, '$name model number format');
    _check(level.text == text, '$name model label template');
    _check(level.restartAfterLevel == restart, '$name model restart');
    _check(
      !document.warnings.contains(LegacyWordWarning.numberingNotReconstructed),
      '$name unexpected incomplete numbering warning',
    );

    final result = convertLegacyWordDocument(document);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final numbering = XmlDocument.parse(
      utf8.decode(archive.findFile('word/numbering.xml')!.content),
    );
    final native = numbering
        .findAllElements('lvl', namespace: _w)
        .singleWhere(
          (level) => level.getAttribute('ilvl', namespace: _w) == '$levelIndex',
        );
    String? value(String element) => native
        .getElement(element, namespace: _w)
        ?.getAttribute('val', namespace: _w);
    _check(value('numFmt') == format, '$name native number format');
    final materialized = materializedListMetadataCases.contains(name);
    _check(
      value('lvlText') == (materialized ? '' : text),
      '$name native label template',
    );
    if (materialized) {
      final main = XmlDocument.parse(
        utf8.decode(archive.findFile('word/document.xml')!.content),
      );
      _check(
        main.findAllElements('t', namespace: _w).first.innerText ==
            labels.single,
        '$name exact materialized label',
      );
      _check(
        main
                .findAllElements('numId', namespace: _w)
                .single
                .getAttribute('val', namespace: _w) ==
            '0',
        '$name native numbering disabled',
      );
      _check(
        result.limitations.contains(LegacyWordConversionLimitation.fieldsLists),
        '$name materialization disclosed',
      );
    }
    _check(value('lvlRestart') == restart?.toString(), '$name native restart');
    _unchanged(source, before, name);
  }

  for (final name in invalidListMetadataCases) {
    final source = listMetadataFixture(name);
    final before = Uint8List.fromList(source);
    var rejected = false;
    try {
      parseLegacyWordDocument(source);
    } on FormatException {
      rejected = true;
    }
    _check(rejected, '$name must not become a changed list label');
    _unchanged(source, before, name);
  }
  return {
    'cases': listMetadataCases.length + invalidListMetadataCases.length,
    'supportedCases': listMetadataCases.length,
    'materializedLiteralLabels': materializedListMetadataCases.length,
    'invalidNumberedRestartsRejected': invalidListMetadataCases.length,
    'literalLabelsPreserved': true,
    'sourceUnchanged': true,
  };
}

void main() => print(jsonEncode(verifyListMetadataWebAcceptance()));
