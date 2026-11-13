// SPDX-License-Identifier: MPL-2.0
// The same binary field cases run on the VM, in compiled JS and through the
// independent Open XML SDK gate. No field instructions are evaluated.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/nested_field_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void _check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

Map<String, Object?> verifyNestedFieldWebAcceptance() {
  const fieldCounts = {
    'nested-results': 3,
    'private-result': 1,
    'private-instruction-result': 2,
    'unsupported-result': 2,
    'formula': 1,
    'instruction-whitespace': 1,
    'nested-instruction-whitespace': 2,
    'cached-controls': 1,
    'nested-cached-controls': 2,
  };
  for (final name in nestedFieldCases) {
    final source = nestedFieldFixture(name);
    final before = Uint8List.fromList(source);
    final parsed = parseLegacyWordDocument(source);
    final result = convertLegacyWordDocument(parsed);
    final archive = ZipDecoder().decodeBytes(result.bytes);
    final text = utf8.decode(archive.findFile('word/document.xml')!.content);
    final document = XmlDocument.parse(text);
    final states = <bool>[];
    final visible = StringBuffer();
    final allText = StringBuffer();
    var fields = 0;
    // Project display text from the emitted complex-field grammar, independent
    // of the parser's normalized storedResult and its source-CP representation.
    for (final run in document.findAllElements('r', namespace: _w)) {
      final marker = run.getElement('fldChar', namespace: _w);
      if (marker != null) {
        switch (marker.getAttribute('fldCharType', namespace: _w)) {
          case 'begin':
            states.add(false);
            fields++;
          case 'separate':
            _check(states.isNotEmpty && !states.last, '$name separator');
            states[states.length - 1] = true;
          case 'end':
            _check(states.isNotEmpty, '$name field end');
            states.removeLast();
          default:
            throw StateError('$name unknown field marker');
        }
      } else {
        for (final item in run.childElements) {
          if (item.name.namespaceUri != _w) continue;
          final value = switch (item.name.local) {
            't' => item.innerText,
            'tab' => '\t',
            'br' => switch (item.getAttribute('type', namespace: _w)) {
              'column' => '\x0e',
              'page' => '\f',
              _ => '\n',
            },
            _ => null,
          };
          if (value != null) {
            allText.write(value);
            if (states.every((state) => state)) visible.write(value);
          }
        }
      }
    }
    _check(states.isEmpty, '$name unclosed fields');
    _check(fields == fieldCounts[name], '$name duplicated/missing fields');
    _check(result.preservedCounts['fields'] == fields, '$name field counts');
    final expectedText = switch (name) {
      'private-result' => 'AZ',
      'formula' => 'A999Z',
      'instruction-whitespace' => 'ACachedZ',
      'cached-controls' => 'Aco\u2011op\u00aderate\x0enextZ',
      _ => 'AVisibleZ',
    };
    _check(visible.toString() == expectedText, '$name visible field result');
    if (name == 'formula') {
      _check(
        document.findAllElements('instrText', namespace: _w).single.innerText ==
            ' = 1 + 1 ',
        'formula instruction',
      );
      _check(
        document
                .findAllElements('fldChar', namespace: _w)
                .first
                .getAttribute('fldLock', namespace: _w) ==
            '1',
        'formula must remain locked without evaluation',
      );
    }
    if (name == 'instruction-whitespace') {
      _check(
        document.findAllElements('instrText', namespace: _w).single.innerText ==
            ' QUOTE "one\ttwo\rthree\nfour\r\nfive & <six> 😀" ',
        '$name changed quoted literal',
      );
    }
    if (name == 'nested-instruction-whitespace') {
      final instructions = document
          .findAllElements('instrText', namespace: _w)
          .map((e) => e.innerText)
          .toList();
      const expected = [
        ' IF "before\tafter" = "before\tafter" ',
        ' QUOTE "one\ttwo" ',
        ' "no\r\nyes" ',
      ];
      _check(instructions.length == expected.length, '$name instruction count');
      for (var i = 0; i < expected.length; i++) {
        _check(instructions[i] == expected[i], '$name changed slice $i');
      }
    }
    if (name == 'cached-controls') {
      _check(
        parsed.fields.single.storedResult == 'co\u2011op\u00aderate\x0enext',
        '$name normalized metadata differs from displayed controls',
      );
    }
    if (name == 'nested-cached-controls') {
      const cached =
          'co\u2011op\u00aderate\x0enext\fpage\nline\ncarriage\nnewline\ttab\tcell';
      _check(
        parsed.fields
                .singleWhere((field) => field.type == 'QUOTE')
                .storedResult ==
            cached,
        '$name normalized cached result',
      );
      _check(
        allText.toString() == 'A${cached}VisibleZ',
        '$name cached result XML',
      );
      final instructions = document
          .findAllElements('instrText', namespace: _w)
          .map((e) => e.innerText)
          .toList();
      const expected = [
        ' IF ',
        ' QUOTE "cached" ',
        ' = "comparison" "yes" "no" ',
      ];
      _check(instructions.length == expected.length, '$name instruction count');
      for (var i = 0; i < expected.length; i++) {
        _check(instructions[i] == expected[i], '$name instruction slice $i');
      }
    }
    _check(!text.contains('Private'), '$name private descendant escaped');
    _check(!text.contains('INCLUDETEXT'), '$name external field activated');
    if (name == 'unsupported-result') {
      final evidence = utf8.decode(
        archive.findFile('word/evidence/manifest.json')!.content,
      );
      _check(evidence.contains('INCLUDETEXT'), '$name missing inert evidence');
    }
    for (final part in archive) {
      if (!part.name.endsWith('.rels')) continue;
      final relationships = XmlDocument.parse(utf8.decode(part.content));
      _check(
        relationships.rootElement.childElements.every(
          (element) => element.getAttribute('TargetMode') != 'External',
        ),
        '$name external package relationship',
      );
    }
    _check(source.length == before.length, '$name source length');
    for (var index = 0; index < source.length; index++) {
      _check(source[index] == before[index], '$name source mutation');
    }
  }
  return {
    'cases': nestedFieldCases.length,
    'fieldCounts': fieldCounts,
    'balancedFields': true,
    'privateDescendantsSuppressed': true,
    'externalFieldsInert': true,
    'instructionWhitespacePreserved': true,
    'cachedControlsPreserved': true,
    'nestedCachedControlsPreserved': true,
    'sourceUnchanged': true,
  };
}
