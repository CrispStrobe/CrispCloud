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

    final archive = ZipDecoder().decodeBytes(
      convertLegacyWordDocument(document).bytes,
    );
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
    _check(value('lvlText') == text, '$name native label template');
    _check(value('lvlRestart') == restart?.toString(), '$name native restart');
    _unchanged(source, before, name);
  }

  for (final name in [
    ...unsupportedListMetadataCases,
    ...invalidListMetadataCases,
  ]) {
    final source = listMetadataFixture(name);
    final before = Uint8List.fromList(source);
    var rejected = false;
    try {
      parseLegacyWordDocument(source);
    } on FormatException catch (error) {
      rejected =
          invalidListMetadataCases.contains(name) ||
          error.message.contains('literal percent-number sequence');
    }
    _check(rejected, '$name must not become a changed list label');
    _unchanged(source, before, name);
  }
  return {
    'cases':
        listMetadataCases.length +
        unsupportedListMetadataCases.length +
        invalidListMetadataCases.length,
    'supportedCases': listMetadataCases.length,
    'unsupportedLiteralLabelsRejected': unsupportedListMetadataCases.length,
    'invalidNumberedRestartsRejected': invalidListMetadataCases.length,
    'literalLabelsPreserved': true,
    'sourceUnchanged': true,
  };
}

void main() => print(jsonEncode(verifyListMetadataWebAcceptance()));
