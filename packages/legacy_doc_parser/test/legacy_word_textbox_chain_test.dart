// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/media_word_fixture.dart';
import 'support/officeart_shape_fixture.dart';
import 'support/story_word_fixture.dart';
import 'support/structured_word_fixture.dart';

Uint8List _source({
  int declared = 2,
  int secondIndex = 1,
  int secondStory = 1,
  int? next = 43,
  int? lastNext,
  int? conflictingId,
}) {
  const text = 'One\rTwo\r';
  List<int> shape(int id, int index, int? nextId) => officeArtRecord(0xf004, [
    ...officeArtRecord(
      0xf00a,
      [...wordU32(id), ...wordU32(0xa00)],
      version: 2,
      instance: 202,
    ),
    ...shapePropertyRecord(
      values: {
        0x0080: conflictingId ?? ((id == 42 ? 1 : secondStory) << 16 | index),
        if (nextId != null) 0x008a: nextId,
      },
    ),
    ...officeArtRecord(
      0xf00d,
      wordU32((id == 42 ? 1 : secondStory) << 16 | index),
    ),
  ], version: 15);
  List<int> anchor(int id) => [
    ...wordU32(id),
    ...wordU32(0),
    ...wordU32(0),
    ...wordU32(2880),
    ...wordU32(840),
    ...wordU16(0x6a),
    ...wordU32(0),
  ];
  return storyWordFixture(
    main: 'A\x08B\x08C\r',
    textboxes: '${text}x',
    characterRuns: [
      WordFixtureFkpRun(8192, 28672, properties: wordSprm(0x0855, [1])),
    ],
    tablePairs: {
      40: storyPlc([1, 3, 0xffffffff], [...anchor(42), ...anchor(43)]),
      50: [
        ...officeArtRecord(0xf000, [], version: 15),
        0,
        ...officeArtRecord(
          0xf002,
          officeArtRecord(0xf003, [
            ...shape(42, 0, next),
            ...shape(43, secondIndex, lastNext),
          ], version: 15),
          version: 15,
        ),
      ],
      56: storyPlc(
        [0, text.length, text.length + 1],
        [
          ...wordU32(declared),
          ...wordU32(0),
          ...wordU16(0),
          ...wordU32(0),
          ...wordU32(42),
          ...wordU32(0),
          ...List.filled(22, 0),
        ],
      ),
    },
  );
}

void main() {
  test(
    'conforming chain validates unique contiguous indices and next links',
    () {
      final document = parseLegacyWordDocument(_source());
      expect(document.textboxReferences.single.chainLength, 2);
      expect(document.textboxReferences.single.declaredChainLength, isNull);
      expect(document.textboxReferences.single.anchors.map((a) => a.shapeId), [
        42,
        43,
      ]);
      expect(
        document.warnings,
        isNot(contains(LegacyWordWarning.recoveredTextboxChainLength)),
      );
    },
  );

  test('only a fully corroborated declared-one chain can be recovered', () {
    final document = parseLegacyWordDocument(_source(declared: 1));
    final reference = document.textboxReferences.single;
    expect(reference.chainLength, 2);
    expect(reference.declaredChainLength, 1);
    expect(
      document.warnings,
      contains(LegacyWordWarning.recoveredTextboxChainLength),
    );
    final output = convertLegacyWordDocument(document);
    final zip = ZipDecoder().decodeBytes(output.bytes);
    final manifest =
        jsonDecode(
              utf8.decode(zip.findFile('word/evidence/manifest.json')!.content),
            )
            as Map<String, dynamic>;
    final chain = (manifest['records'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((r) => r['kind'] == 'textboxChain');
    expect(chain['declaredLength'], 1);
    expect(chain['resolvedLength'], 2);
  });

  test(
    'gaps, conflicting identifiers, missing links and cycles still fail',
    () {
      for (final input in [
        _source(declared: 3),
        _source(declared: 1, next: null),
        _source(declared: 1, next: 99),
        _source(declared: 1, secondIndex: 2),
        _source(declared: 2, secondIndex: 2),
        _source(declared: 1, secondIndex: 0),
        _source(declared: 1, secondStory: 2),
        _source(declared: 1, lastNext: 42),
        _source(declared: 1, conflictingId: 0x20000),
      ]) {
        expect(() => parseLegacyWordDocument(input), throwsFormatException);
      }
    },
  );

  test('authored native DOC keeps the linked story and discloses recovery', () {
    final document = parseLegacyWordDocument(
      File('test/fixtures/word_native/linked-textboxes.doc').readAsBytesSync(),
    );
    final reference = document.textboxReferences.single;
    expect(reference.chainLength, 2);
    expect(reference.declaredChainLength, 1);
    expect(reference.anchors.map((a) => a.chainIndex), [0, 1]);
    expect(
      document.warnings,
      contains(LegacyWordWarning.recoveredTextboxChainLength),
    );
    final converted = convertLegacyWordDocument(document);
    final zip = ZipDecoder().decodeBytes(converted.bytes);
    final xml = XmlDocument.parse(
      utf8.decode(zip.findFile('word/document.xml')!.content),
    );
    final boxes = xml
        .findAllElements(
          'txbxContent',
          namespace:
              'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
        )
        .toList();
    expect(boxes, hasLength(2));
    for (final marker in [
      'ONE',
      'TWO',
      'THREE',
      'FOUR',
      'FIVE',
      'SIX',
      'SEVEN',
      'EIGHT',
    ]) {
      expect(
        RegExp('FLOW_$marker').allMatches(xml.toXmlString()),
        hasLength(1),
      );
    }
    expect(boxes.last.innerText.trim(), isEmpty);
  });
}
