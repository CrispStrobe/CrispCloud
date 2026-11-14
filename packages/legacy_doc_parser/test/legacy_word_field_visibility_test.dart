// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/nested_field_fixture.dart';
import 'support/story_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

XmlDocument _xml(LegacyWordStructuredConversion conversion) =>
    XmlDocument.parse(
      utf8.decode(
        ZipDecoder()
            .decodeBytes(conversion.bytes)
            .findFile('word/document.xml')!
            .content,
      ),
    );

String? _hidden(XmlElement run) => run
    .getElement('rPr', namespace: _w)
    ?.getElement('vanish', namespace: _w)
    ?.getAttribute('val', namespace: _w);

void main() {
  for (final name in nestedFieldCases) {
    test('field run visibility has exact structural scope: $name', () {
      final model = parseLegacyWordDocument(nestedFieldFixture(name));
      final xml = _xml(convertLegacyWordDocument(model));
      final privateRoot = name == 'private-result';
      final stack = <(bool, bool)>[]; // result phase, hidden field
      var begins = 0;
      for (final run in xml.findAllElements('r', namespace: _w)) {
        final marker = run.getElement('fldChar', namespace: _w);
        final kind = marker?.getAttribute('fldCharType', namespace: _w);
        if (kind == 'begin') {
          final hidden = privateRoot || stack.any((s) => !s.$1 || s.$2);
          expect(
            _hidden(run),
            hidden ? '1' : '0',
            reason: '$name begin $begins',
          );
          stack.add((false, hidden));
          begins++;
        } else if (kind != null) {
          expect(stack, isNotEmpty);
          expect(
            _hidden(run),
            stack.last.$2 ? '1' : '0',
            reason: '$name $kind',
          );
          if (kind == 'separate') {
            stack[stack.length - 1] = (true, stack.last.$2);
          } else {
            stack.removeLast();
          }
        } else if (run.getElement('instrText', namespace: _w) != null) {
          expect(stack, isNotEmpty);
          expect(
            _hidden(run),
            stack.last.$2 ? '1' : '0',
            reason: '$name instruction',
          );
        } else if (run.getElement('t', namespace: _w) != null &&
            stack.any((s) => s.$2)) {
          expect(
            _hidden(run),
            '1',
            reason: '$name instruction-context cached result',
          );
        }
      }
      expect(stack, isEmpty);
      if (name != 'unsupported-result') expect(begins, greaterThan(0));
      for (final run in xml.findAllElements('r', namespace: _w)) {
        final value = run.getElement('t', namespace: _w)?.innerText;
        if (value == 'Visible' || value == 'Cached' || value == '999') {
          expect(
            _hidden(run),
            '0',
            reason: 'Visible root cache must remain visible',
          );
        }
      }
    });
  }

  test('fields nested in a visible cached result remain visible', () {
    final model = parseLegacyWordDocument(
      storyWordFixture(
        main: 'A\x13 QUOTE "outer" \x14before\x13 PAGE \x147\x15after\x15Z\r',
      ),
    );
    final xml = _xml(convertLegacyWordDocument(model));
    expect(model.plainText, 'Abefore7afterZ');
    for (final run in xml.findAllElements('r', namespace: _w)) {
      expect(_hidden(run), '0');
    }
    final markers = xml.findAllElements('fldChar', namespace: _w);
    expect(markers.length, 6);
    expect(
      xml.findAllElements('t', namespace: _w).map((e) => e.innerText).join(),
      'Abefore7afterZ',
    );
  });
}
