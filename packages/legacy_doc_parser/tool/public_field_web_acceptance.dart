// SPDX-License-Identifier: MPL-2.0
// Exercise caller-built source ownership in the actual JavaScript converter.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/story_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void _check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

LegacyWordField _field(
  LegacyWordField field, {
  int? id,
  String? storyId,
  int offset = 0,
  int? endCp,
  bool clearParent = false,
}) => LegacyWordField(
  id: id ?? field.id,
  storyId: storyId ?? field.storyId,
  startCp: field.startCp + offset,
  endCp: endCp ?? field.endCp + offset,
  separatorCp: field.separatorCp == null ? null : field.separatorCp! + offset,
  parentId: clearParent ? null : field.parentId,
  instruction: field.instruction,
  storedResult: field.storedResult,
  type: field.type,
);

LegacyWordDocument _document(
  LegacyWordDocument original,
  Iterable<LegacyWordField> fields,
) => LegacyWordDocument(
  blocks: original.blocks,
  sections: original.sections,
  plainText: original.plainText,
  safeHtml: original.safeHtml,
  fields: fields.toList(),
);

Map<String, Object?> verifyPublicFieldWebAcceptance() {
  const source =
      'A\x13 QUOTE "outer" \x14before\x13 PAGE \x142\x15after\x15'
      '\x13 PAGE \x143\x15Z\r';
  final parsed = parseLegacyWordDocument(storyWordFixture(main: source));
  final outer = parsed.fields.singleWhere((field) => field.type == 'QUOTE');
  final child = parsed.fields.singleWhere((field) => field.parentId != null);
  final last = parsed.fields.singleWhere(
    (field) => field.startCp >= outer.endCp,
  );
  final inert = parseLegacyWordDocument(
    storyWordFixture(main: 'A\x13 DDEAUTO server topic item \x14Cached\x15Z\r'),
  );
  final malformed = <String, LegacyWordDocument>{
    'crossing-roots': _document(parsed, [
      _field(outer, endCp: last.separatorCp! + 2),
      child,
      last,
    ]),
    'duplicate-range': _document(parsed, [
      ...parsed.fields,
      _field(last, id: 999),
    ]),
    'missing-parent': _document(parsed, [
      outer,
      _field(child, clearParent: true),
      last,
    ]),
    'shared-separator': _document(parsed, [
      outer,
      _field(child, offset: outer.separatorCp! - child.startCp),
      last,
    ]),
    'missing-inert-story': _document(inert, [
      _field(inert.fields.single, storyId: 'missing'),
    ]),
    'negative-inert-start': _document(inert, [
      _field(inert.fields.single, offset: -2),
    ]),
    'past-story-end': _document(parsed, [
      outer,
      child,
      _field(last, endCp: source.length + 1),
    ]),
  };
  for (final entry in malformed.entries) {
    var rejected = false;
    try {
      convertLegacyWordDocument(entry.value);
    } on FormatException {
      rejected = true;
    }
    _check(rejected, 'accepted public field ${entry.key}');
  }

  final converted = convertLegacyWordDocument(
    _document(parsed, parsed.fields.reversed),
  );
  final xml = XmlDocument.parse(
    utf8.decode(
      ZipDecoder()
          .decodeBytes(converted.bytes)
          .findFile('word/document.xml')!
          .content,
    ),
  );
  final states = <bool>[];
  final visible = StringBuffer();
  var fields = 0;
  for (final run in xml.findAllElements('r', namespace: _w)) {
    final marker = run.getElement('fldChar', namespace: _w);
    if (marker != null) {
      switch (marker.getAttribute('fldCharType', namespace: _w)) {
        case 'begin':
          states.add(false);
          fields++;
        case 'separate':
          _check(
            states.isNotEmpty && !states.last,
            'duplicate field separator',
          );
          states[states.length - 1] = true;
        case 'end':
          _check(states.isNotEmpty, 'unmatched field end');
          states.removeLast();
      }
    } else if (states.every((state) => state)) {
      for (final text in run.findElements('t', namespace: _w)) {
        visible.write(text.innerText);
      }
    }
  }
  _check(fields == 3 && states.isEmpty, 'valid public field scopes changed');
  _check(
    visible.toString() == 'Abefore2after3Z',
    'valid public field results changed',
  );
  return {
    'malformedRangesRejected': malformed.keys.toList(),
    'reverseModelOrderPreserved': true,
    'balancedFields': fields,
    'visibleTextPreserved': true,
  };
}
