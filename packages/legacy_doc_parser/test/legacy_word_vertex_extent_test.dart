// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/media_word_fixture.dart';
import 'support/officeart_shape_fixture.dart';
import 'support/structured_word_fixture.dart';

Uint8List _source(
  Uint8List vertices, {
  required int declared,
  int property = 0x0145,
  List<int> trailing = const [],
}) => officeArtShapeWordFixture(
  type: 0,
  rawPropertyRecord: officeArtRecord(
    0xf00b,
    [
      ...wordU16(property | 0x8000),
      ...wordU32(declared),
      ...vertices,
      ...trailing,
    ],
    version: 3,
    instance: 1,
  ),
);

void main() {
  test(
    'complete pVertices lengths retain ordinary validation without recovery',
    () {
      final vertices = shapeVertices([(10, 20), (30, 40)]);
      final document = parseLegacyWordDocument(
        _source(vertices, declared: vertices.length),
      );
      expect(document.media.drawings.single.shape!.geometry!.path, isNotEmpty);
      expect(document.media.notices, isEmpty);
    },
  );

  test(
    'exact header-excluded vertex length records bounded source evidence',
    () {
      for (final vertices in [
        shapeVertices([(10, 20), (30, 40)]),
        shapeArray(0xfff0, [
          [...wordU16(10), ...wordU16(20)],
          [...wordU16(30), ...wordU16(40)],
        ]),
      ]) {
        final document = parseLegacyWordDocument(
          _source(vertices, declared: vertices.length - 6),
        );
        final notice = document.media.notices.singleWhere(
          (value) =>
              value.issue == LegacyWordMediaIssue.recoveredVertexArrayLength,
        );
        expect(notice.source.structure, 'OfficeArtFOPT/pVertices');
        expect(notice.source.length, vertices.length + 14);
        expect(document.media.artifacts, isNotEmpty);
        expect(
          convertLegacyWordDocument(document).limitations,
          contains(LegacyWordConversionLimitation.partialFormatting),
        );
      }
    },
  );

  test(
    'a header exemption never absorbs mismatched counts, tails or other arrays',
    () {
      final vertices = shapeVertices([(10, 20), (30, 40)]);
      for (final declared in [0, vertices.length - 7, vertices.length - 5]) {
        expect(
          () => parseLegacyWordDocument(_source(vertices, declared: declared)),
          throwsFormatException,
        );
      }
      expect(
        () => parseLegacyWordDocument(
          _source(vertices, declared: vertices.length - 6, trailing: [0]),
        ),
        throwsFormatException,
      );
      expect(
        () => parseLegacyWordDocument(
          _source(vertices, declared: vertices.length - 6, property: 0x0146),
        ),
        throwsFormatException,
      );
      final badCount = Uint8List.fromList(vertices)..[0] = 1;
      expect(
        () => parseLegacyWordDocument(
          _source(badCount, declared: vertices.length - 6),
        ),
        throwsFormatException,
      );
    },
  );
}
