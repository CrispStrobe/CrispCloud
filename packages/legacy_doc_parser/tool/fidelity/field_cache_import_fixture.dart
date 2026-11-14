// SPDX-License-Identifier: MPL-2.0
// Minimal ASCII controls for independently measuring native field evaluation.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../../test/support/story_word_fixture.dart';
import '../../test/support/structured_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String _field(String instruction, [String cached = 'Cached']) =>
    '\x13 $instruction \x14$cached\x15';

List<int> _lockedFields(String text) {
  final positions = <int>[], records = <int>[];
  var depth = 0;
  for (var cp = 0; cp < text.length; cp++) {
    final code = text.codeUnitAt(cp);
    if (!const [19, 20, 21].contains(code)) continue;
    positions.add(cp);
    var flags = 0;
    if (code == 19) {
      depth++;
      // MS-DOC 2.9.90 flt: zero is not a valid parsed field type. The native
      // binary importer uses these identities as well as the instruction.
      final type = RegExp(
        r'^\s*(REF|QUOTE|IF)\b',
      ).firstMatch(text.substring(cp + 1))!.group(1);
      flags = {'REF': 3, 'QUOTE': 35, 'IF': 7}[type]!;
    }
    if (code == 21) {
      flags = 0x90 | (depth > 1 ? 0x40 : 0);
      depth--;
    }
    records.addAll([code, flags]);
  }
  return storyPlc([...positions, 0xffffffff], records);
}

List<WordFixtureFkpRun> _fieldCharacterRuns(String text) {
  final result = <WordFixtureFkpRun>[];
  var start = 0;
  for (var cp = 0; cp < text.length; cp++) {
    if (!const [19, 20, 21].contains(text.codeUnitAt(cp))) continue;
    if (start < cp) {
      result.add(WordFixtureFkpRun(16384 + start * 2, 16384 + cp * 2));
    }
    // MS-DOC 2.8.25 Plcfld requires sprmCFSpec=1 at every field character.
    result.add(
      WordFixtureFkpRun(
        16384 + cp * 2,
        16384 + (cp + 1) * 2,
        properties: wordSprm(0x0855, [1]),
      ),
    );
    start = cp + 1;
  }
  if (start < text.length) {
    result.add(WordFixtureFkpRun(16384 + start * 2, 16384 + text.length * 2));
  }
  return result;
}

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Supply a new directory.');
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final definitions = <String, (String, String, bool)>{};
  const instructions = {
    'ref': 'REF Missing',
    'quote': 'QUOTE "Evaluated"',
    'if': 'IF "one" = "one" "Evaluated" "Other"',
  };
  for (final entry in instructions.entries) {
    definitions['${entry.key}-visible'] = (
      'A${_field(entry.value)}Z\r',
      'ACachedZ',
      false,
    );
    definitions['${entry.key}-instruction-child'] = (
      'A${_field('IF ${_field(entry.value, 'Child')} = "unused" "Yes" "No"')}Z\r',
      'ACachedZ',
      false,
    );
    definitions['${entry.key}-result-child'] = (
      'A${_field('QUOTE "Outer"', 'Before${_field(entry.value, 'Child')}After')}Z\r',
      'ABeforeChildAfterZ',
      false,
    );
  }
  definitions['ref-existing-bookmark'] = (
    'TargetA${_field('REF Existing')}Z\r',
    'TargetACachedZ',
    true,
  );
  final manifest = <Map<String, Object>>[];
  final sourceCases = <Map<String, Object>>[],
      convertedCases = <Map<String, Object>>[];
  for (final entry in definitions.entries) {
    final name = entry.key;
    final (text, expected, bookmark) = entry.value;
    final source = storyWordFixture(
      main: text,
      characterRuns: _fieldCharacterRuns(text),
      tablePairs: {
        16: _lockedFields(text),
        if (bookmark) ...{
          21: storyBookmarkNames(['Existing']),
          22: storyPlc([0, 0xffffffff], [...wordU16(0), ...wordU16(0)]),
          23: storyPlc([6, 0xffffffff]),
        },
      },
    );
    final before = source.toList();
    final document = parseLegacyWordDocument(source);
    if (document.plainText != expected ||
        document.fields.any((field) => !field.locked)) {
      throw StateError('$name: source fixture expectation failed');
    }
    final conversion = convertLegacyWordDocument(document);
    final xml = XmlDocument.parse(
      utf8.decode(
        ZipDecoder()
            .decodeBytes(conversion.bytes)
            .findFile('word/document.xml')!
            .content,
      ),
    );
    final begins = xml
        .findAllElements('fldChar', namespace: _w)
        .where(
          (element) =>
              element.getAttribute('fldCharType', namespace: _w) == 'begin',
        );
    if (begins.length != document.fields.length ||
        begins.any(
          (element) => element.getAttribute('fldLock', namespace: _w) != '1',
        )) {
      throw StateError('$name: active locked field preservation failed');
    }
    for (var i = 0; i < source.length; i++) {
      if (source[i] != before[i]) throw StateError('$name: source mutation');
    }
    File('${root.path}/$name.doc').writeAsBytesSync(source);
    File('${root.path}/$name.docx').writeAsBytesSync(conversion.bytes);
    manifest.add({
      'name': name,
      'source': '$name.doc',
      'output': '$name.docx',
      'sourceTextWithMarkers': text,
      'expectedCachedText': expected,
      'activeFields': document.fields.length,
      'sourceFieldsLocked': true,
      'convertedFieldsLocked': true,
      'bookmarkPresent': bookmark,
      'nativeRenderingClaimed': false,
    });
    sourceCases.add({
      'name': name,
      'input': '$name.doc',
      'expectedText': expected,
    });
    convertedCases.add({
      'name': name,
      'input': '$name.docx',
      'expectedText': expected,
    });
  }
  for (final entry in {
    'cases.json': {'cases': manifest},
    'native-source.json': {'cases': sourceCases},
    'native-converted.json': {'cases': convertedCases},
  }.entries) {
    File('${root.path}/${entry.key}').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(entry.value)}\n',
    );
  }
}
