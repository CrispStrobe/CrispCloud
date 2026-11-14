// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import 'story_word_fixture.dart';

const displayFieldEvidenceCases = [
  'active',
  'hidden',
  'private',
  'unsupported-type',
  'mislabeled-instruction',
  'unsupported-ancestor',
  'private-ancestor',
  'supported-instruction-child',
  'xml-control-original',
  'surrogate-original',
  'sparse-metadata',
];

LegacyWordDocument displayFieldEvidenceDocument(
  String name, {
  required bool sourceRecord,
  bool includeRevision = true,
}) {
  if (!displayFieldEvidenceCases.contains(name)) {
    throw ArgumentError.value(name);
  }
  final text = switch (name) {
    'unsupported-type' ||
    'mislabeled-instruction' => 'A\x13 DDEAUTO server topic item \x142.\x15Z\r',
    'unsupported-ancestor' =>
      'A\x13 DDEAUTO \x13 LISTNUM \x142.\x15 topic item \x14Cache\x15Z\r',
    'private-ancestor' =>
      'A\x13 QUOTE "private" \x14\x13 LISTNUM \x142.\x15\x15Z\r',
    'supported-instruction-child' =>
      'A\x13 QUOTE \x13 LISTNUM \x142.\x15 \x14Cache\x15Z\r',
    _ => 'A\x13 LISTNUM \x142.\x15Z\r',
  };
  final positions = <int>[], records = <int>[];
  var depth = 0;
  for (var cp = 0; cp < text.length; cp++) {
    final unit = text.codeUnitAt(cp);
    if (!const [19, 20, 21].contains(unit)) continue;
    positions.add(cp);
    var flags = 0;
    if (unit == 19) depth++;
    if (unit == 21) {
      flags = 0x80 | (depth > 1 ? 0x40 : 0);
      if ((name == 'private' || name == 'private-ancestor') && depth == 1) {
        flags |= 0x20;
      }
      depth--;
    }
    records.addAll([unit, flags]);
  }
  final parsed = parseLegacyWordDocument(
    storyWordFixture(
      main: text,
      tablePairs: {
        16: storyPlc([...positions, 0xffffffff], records),
      },
    ),
  );
  final target = parsed.fields.firstWhere(
    (field) => field.type == 'LISTNUM',
    orElse: () => parsed.fields.single,
  );
  final change = LegacyWordDisplayFieldRevision(
    original: switch (name) {
      'xml-control-original' => 'old\t',
      'surrogate-original' => 'old${String.fromCharCode(0xd800)}',
      _ => 'OLD_SECRET',
    },
    hidden: name == 'hidden',
    revision: name == 'sparse-metadata'
        ? const LegacyWordRevisionInfo()
        : LegacyWordRevisionInfo(
            author: 'Revision & author',
            time: DateTime.utc(2026, 11, 13, 12, 34, 56, 789, 123),
            authorIndex: 7,
            rawDate: 0xfedcba98,
            saveId: 0x1234abcd,
            reason: 0x002b,
          ),
    sourceRecord: sourceRecord
        ? Uint8List.fromList(List.generate(39, (i) => (i * 17 + 3) & 255))
        : null,
  );
  return LegacyWordDocument(
    blocks: parsed.blocks,
    sections: parsed.sections,
    plainText: parsed.plainText,
    safeHtml: parsed.safeHtml,
    fields: [
      for (final field in parsed.fields)
        LegacyWordField(
          id: field.id,
          storyId: field.storyId,
          startCp: field.startCp,
          endCp: field.endCp,
          separatorCp: field.separatorCp,
          parentId: field.parentId,
          instruction: field.instruction,
          storedResult: field.storedResult,
          type: name == 'mislabeled-instruction' ? 'LISTNUM' : field.type,
          privateResult: field.privateResult,
          locked: field.locked,
          dirty: field.dirty,
          displayRevision: includeRevision && field.id == target.id
              ? change
              : null,
        ),
    ],
  );
}

bool displayFieldNativeHistoryExpected(String name, LegacyWordFieldMode mode) =>
    mode == LegacyWordFieldMode.preserve &&
    const [
      'active',
      'supported-instruction-child',
      'sparse-metadata',
    ].contains(name);
