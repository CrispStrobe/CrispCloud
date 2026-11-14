// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/field_marker_formatting_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

Map<String, Object> verifyFieldMarkerFormattingCase(
  int mask,
  int resultMask,
  bool compressed,
  bool instructionHidden,
) {
  final source = fieldMarkerFormattingFixture(
    markerMask: mask,
    resultMask: resultMask,
    compressed: compressed,
    instructionHidden: instructionHidden,
  );
  final before = source.toList();
  void check(bool condition, String message) {
    if (!condition) {
      throw StateError(
        'marker=$mask result=$resultMask compressed=$compressed instruction=$instructionHidden: $message',
      );
    }
  }

  final document = parseLegacyWordDocument(source);
  final field = document.fields.single;
  check(field.beginHidden == (mask & 1 != 0), 'begin model');
  check(field.separatorHidden == (mask & 2 != 0), 'separator model');
  check(field.endHidden == (mask & 4 != 0), 'end model');
  final expectedRanges = instructionHidden
      ? [(0, field.instruction.length)]
      : <(int, int)>[];
  check(
    field.instructionHiddenRanges.length == expectedRanges.length &&
        List.generate(
          expectedRanges.length,
          (i) => field.instructionHiddenRanges[i] == expectedRanges[i],
        ).every((v) => v),
    'instruction model',
  );
  final visibleResult = switch (resultMask) {
    0 => 'LeftRight',
    1 => 'Right',
    _ => '',
  };
  check(document.plainText == 'A${visibleResult}Z', 'visible cached source');
  final conversion = convertLegacyWordDocument(document);
  final xml = XmlDocument.parse(
    utf8.decode(
      ZipDecoder()
          .decodeBytes(conversion.bytes)
          .findFile('word/document.xml')!
          .content,
    ),
  );
  final markers = <(String?, String?)>[];
  final instructions = StringBuffer();
  for (final run in xml.findAllElements('r', namespace: _w)) {
    final hidden = run
        .getElement('rPr', namespace: _w)
        ?.getElement('vanish', namespace: _w)
        ?.getAttribute('val', namespace: _w);
    final marker = run.getElement('fldChar', namespace: _w);
    if (marker != null) {
      markers.add((marker.getAttribute('fldCharType', namespace: _w), hidden));
    }
    final instruction = run.getElement('instrText', namespace: _w);
    if (instruction != null) {
      instructions.write(instruction.innerText);
      check(hidden == (instructionHidden ? '1' : '0'), 'instruction XML');
    }
  }
  final expectedMarkers = [
    ('begin', mask & 1 == 0 ? '0' : '1'),
    ('separate', mask & 2 == 0 ? '0' : '1'),
    ('end', mask & 4 == 0 ? '0' : '1'),
  ];
  check(
    markers.length == 3 &&
        List.generate(
          3,
          (i) => markers[i] == expectedMarkers[i],
        ).every((v) => v),
    'marker XML',
  );
  check(instructions.toString() == field.instruction, 'exact instruction text');
  check(conversion.preservedCounts['fields'] == 1, 'field count');
  for (var i = 0; i < source.length; i++) {
    check(source[i] == before[i], 'source mutation');
  }
  return {
    'mask': mask,
    'resultMask': resultMask,
    'compressed': compressed,
    'instructionHidden': instructionHidden,
  };
}

Map<String, Object> verifyFieldMarkerFormattingWebAcceptance() {
  var cases = 0;
  for (final compressed in [true, false]) {
    for (var mask = 0; mask < 8; mask++) {
      for (final resultMask in [0, 1, 3]) {
        for (final instructionHidden in [true, false]) {
          verifyFieldMarkerFormattingCase(
            mask,
            resultMask,
            compressed,
            instructionHidden,
          );
          cases++;
        }
      }
    }
  }
  return {
    'cases': cases,
    'sourceUnchanged': true,
    'markerStatesIndependent': true,
    'instructionStatesIndependent': true,
  };
}

void main() => print(jsonEncode(verifyFieldMarkerFormattingWebAcceptance()));
