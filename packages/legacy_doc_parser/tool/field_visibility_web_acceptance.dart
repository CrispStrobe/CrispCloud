// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/field_visibility_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

String? _hidden(XmlElement run) => run
    .getElement('rPr', namespace: _w)
    ?.getElement('vanish', namespace: _w)
    ?.getAttribute('val', namespace: _w);

Map<String, Object?> verifyFieldVisibilityCase(String name) {
  final source = fieldVisibilityFixture(name);
  final before = source.toList();
  final model = parseLegacyWordDocument(source);
  final conversion = convertLegacyWordDocument(model);
  final archive = ZipDecoder().decodeBytes(conversion.bytes);
  final document = XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content),
  );
  void check(bool condition, String message) {
    if (!condition) throw StateError('$name: $message');
  }

  final privateRoot = name == 'private-result';
  final sourceHiddenRoot = name == 'character-hidden-result';
  final stack = <(bool, bool)>[]; // Cached-result phase, hidden field scope.
  final visible = StringBuffer();
  var begins = 0, hiddenRuns = 0, visibleRuns = 0;
  for (final run in document.findAllElements('r', namespace: _w)) {
    final marker = run.getElement('fldChar', namespace: _w);
    final kind = marker?.getAttribute('fldCharType', namespace: _w);
    final hidden = _hidden(run);
    if (hidden == '1') hiddenRuns++;
    if (hidden == '0') visibleRuns++;
    if (kind == 'begin') {
      final expected = privateRoot || stack.any((s) => !s.$1 || s.$2);
      check(
        hidden == (expected || sourceHiddenRoot ? '1' : '0'),
        'begin run visibility $begins',
      );
      check(
        marker?.getAttribute('fldLock', namespace: _w) == '1',
        'field lock',
      );
      stack.add((false, expected));
      begins++;
    } else if (kind != null) {
      check(stack.isNotEmpty, 'unmatched field marker');
      check(
        hidden == (stack.last.$2 || sourceHiddenRoot ? '1' : '0'),
        '$kind visibility',
      );
      if (kind == 'separate') {
        check(!stack.last.$1, 'duplicate separator');
        stack[stack.length - 1] = (true, stack.last.$2);
      } else {
        check(kind == 'end', 'unknown field marker');
        stack.removeLast();
      }
    } else if (run.getElement('instrText', namespace: _w) != null) {
      check(stack.isNotEmpty, 'instruction outside field');
      check(
        hidden == (stack.last.$2 || sourceHiddenRoot ? '1' : '0'),
        'instruction visibility',
      );
    } else {
      if (stack.any((s) => s.$2)) {
        check(hidden == '1', 'instruction-context cached run visibility');
      }
      if (hidden == '1' || stack.any((s) => !s.$1 || s.$2)) continue;
      for (final item in run.childElements) {
        if (item.name.namespaceUri != _w) continue;
        final text = switch (item.name.local) {
          't' => item.innerText,
          'tab' => '\t',
          'br' => switch (item.getAttribute('type', namespace: _w)) {
            'column' => '\x0e',
            'page' => '\f',
            _ => '\n',
          },
          _ => '',
        };
        visible.write(text);
      }
    }
  }
  check(stack.isEmpty, 'unclosed field');
  check(begins == fieldVisibilityExpectedFields[name], 'native field count');
  check(conversion.preservedCounts['fields'] == begins, 'preservation count');
  check(
    visible.toString() == fieldVisibilityExpectedText[name],
    'display text',
  );
  if (name == 'character-hidden-result') {
    check(!model.fields.single.privateResult, 'ordinary hidden is not private');
    final field = model.fields.single;
    check(
      field.beginHidden && field.separatorHidden && field.endHidden,
      'source marker visibility',
    );
    check(
      field.instructionHiddenRanges.length == 1 &&
          field.instructionHiddenRanges.single == (0, field.instruction.length),
      'source instruction visibility',
    );
    final cached = document
        .findAllElements('r', namespace: _w)
        .singleWhere(
          (run) => run.getElement('t', namespace: _w)?.innerText == 'Secret',
        );
    check(_hidden(cached) == '1', 'ordinary hidden cache must stay hidden');
    check(model.plainText == 'AZ', 'hidden source display');
  }
  if (name == 'visible-result-child') {
    check(hiddenRuns == 0, 'visible result descendant must remain visible');
  }
  for (var i = 0; i < source.length; i++) {
    check(source[i] == before[i], 'source mutation');
  }
  return {
    'name': name,
    'fields': begins,
    'hiddenRuns': hiddenRuns,
    'visibleRuns': visibleRuns,
    'visibleText': visible.toString(),
  };
}

Map<String, Object?> verifyFieldVisibilityWebAcceptance() => {
  'cases': fieldVisibilityCases.length,
  'results': [
    for (final name in fieldVisibilityCases) verifyFieldVisibilityCase(name),
  ],
  'sourceUnchanged': true,
  'cachedResultsEvaluated': false,
  'nativeRenderingClaimed': false,
};

void main() => print(jsonEncode(verifyFieldVisibilityWebAcceptance()));
