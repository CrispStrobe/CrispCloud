// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/story_word_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

LegacyWordDocument _document(
  String text,
  List<LegacyWordField> Function(List<LegacyWordField>) update,
) {
  final parsed = parseLegacyWordDocument(storyWordFixture(main: text));
  return LegacyWordDocument(
    blocks: parsed.blocks,
    sections: parsed.sections,
    plainText: parsed.plainText,
    safeHtml: parsed.safeHtml,
    fields: update(parsed.fields),
  );
}

LegacyWordField _field(
  LegacyWordField field, {
  int? id,
  String? storyId,
  int offset = 0,
  int? endCp,
  int? parentId,
  bool clearParent = false,
}) => LegacyWordField(
  id: id ?? field.id,
  storyId: storyId ?? field.storyId,
  startCp: field.startCp + offset,
  endCp: endCp ?? field.endCp + offset,
  separatorCp: field.separatorCp == null ? null : field.separatorCp! + offset,
  parentId: clearParent ? null : parentId ?? field.parentId,
  instruction: field.instruction,
  storedResult: field.storedResult,
  type: field.type,
  privateResult: field.privateResult,
);

List<String> _markers(LegacyWordDocument document) {
  final result = convertLegacyWordDocument(document);
  final xml = XmlDocument.parse(
    utf8.decode(
      ZipDecoder()
          .decodeBytes(result.bytes)
          .findFile('word/document.xml')!
          .content,
    ),
  );
  return [
    for (final element in xml.findAllElements('fldChar', namespace: _w))
      element.getAttribute('fldCharType', namespace: _w)!,
  ];
}

void main() {
  const adjacent = 'A\x13 PAGE \x141\x15\x13 PAGE \x142\x15Z\r';
  const instruction = 'A\x13 QUOTE \x13 PAGE \x142\x15\x14Outer\x15Z\r';
  const result = 'A\x13 QUOTE "outer" \x14\x13 PAGE \x142\x15\x15Z\r';

  test('rejects crossing root field ranges before writing field events', () {
    final document = _document(adjacent, (fields) {
      final first = fields.reduce((a, b) => a.startCp < b.startCp ? a : b);
      final second = fields.singleWhere((field) => field.id != first.id);
      return [_field(first, endCp: second.separatorCp! + 2), second];
    });
    expect(() => convertLegacyWordDocument(document), throwsFormatException);
  });

  test('rejects two field identities owning the same source range', () {
    final document = _document(
      adjacent,
      (fields) => [...fields, _field(fields.first, id: 999)],
    );
    expect(() => convertLegacyWordDocument(document), throwsFormatException);
  });

  for (final (name, source) in [
    ('instruction', instruction),
    ('result', result),
  ]) {
    test('rejects a missing parent for a nested $name field', () {
      final document = _document(
        source,
        (fields) => [
          for (final field in fields) _field(field, clearParent: true),
        ],
      );
      expect(() => convertLegacyWordDocument(document), throwsFormatException);
    });
  }

  test('rejects a nested field assigned to its grandparent', () {
    final document = _document('A\x13 QUOTE "outer" \x14pre\x13 REF Name '
        '\x14pre\x13 PAGE \x142\x15post\x15post\x15Z\r', (fields) {
      final parent = fields.singleWhere((field) => field.type == 'QUOTE');
      return [
        for (final field in fields)
          field.type == 'PAGE' ? _field(field, parentId: parent.id) : field,
      ];
    });
    expect(() => convertLegacyWordDocument(document), throwsFormatException);
  });

  test('rejects a child that shares the parent separator position', () {
    final document = _document(result, (fields) {
      final child = fields.singleWhere((field) => field.type == 'PAGE');
      return [
        for (final field in fields)
          field.id == child.id ? _field(field, offset: -1) : field,
      ];
    });
    expect(() => convertLegacyWordDocument(document), throwsFormatException);
  });

  const inert = 'A\x13 DDEAUTO server topic item \x14Cached\x15Z\r';
  test('rejects an unknown story even when the field remains inert', () {
    final document = _document(
      inert,
      (fields) => [_field(fields.single, storyId: 'missing')],
    );
    expect(() => convertLegacyWordDocument(document), throwsFormatException);
  });

  test('rejects an inert field beginning before its story', () {
    final document = _document(
      inert,
      (fields) => [_field(fields.single, offset: -2)],
    );
    expect(() => convertLegacyWordDocument(document), throwsFormatException);
  });

  for (final (name, source) in [
    ('supported', 'A\x13 PAGE \x142\x15Z\r'),
    ('inert', inert),
  ]) {
    test('rejects a $name field ending beyond its story', () {
      final document = _document(
        source,
        (fields) => [_field(fields.single, endCp: source.length + 1)],
      );
      expect(() => convertLegacyWordDocument(document), throwsFormatException);
    });
  }

  test('accepts adjacent fields provided in reverse source order', () {
    final document = _document(adjacent, (fields) => fields.reversed.toList());
    expect(_markers(document), [
      'begin',
      'separate',
      'end',
      'begin',
      'separate',
      'end',
    ]);
  });

  test('accepts an instruction child ending at its parent separator', () {
    final document = _document(
      instruction,
      (fields) => fields.reversed.toList(),
    );
    expect(_markers(document), [
      'begin',
      'begin',
      'separate',
      'end',
      'separate',
      'end',
    ]);
  });

  test('accepts a result child adjacent to its parent separator and end', () {
    final document = _document(result, (fields) => fields.reversed.toList());
    expect(_markers(document), [
      'begin',
      'separate',
      'begin',
      'separate',
      'end',
      'end',
    ]);
  });
}
