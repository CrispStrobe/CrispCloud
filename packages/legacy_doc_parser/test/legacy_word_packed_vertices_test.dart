// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/officeart_shape_fixture.dart';
import 'support/structured_word_fixture.dart';

Uint8List _packed(List<(int, int)> points, {int? allocated}) =>
    shapeArray(0xfff0, [
      for (final (x, y) in points) [...wordU16(x), ...wordU16(y)],
    ], allocated: allocated);

LegacyWordOfficeArtShape _shape(Uint8List vertices, {int type = 0}) =>
    parseLegacyWordDocument(
      officeArtShapeWordFixture(type: type, complex: {0x0145: vertices}),
    ).media.drawings.single.shape!;

void main() {
  test('packed POINTs retain signed values and exact control-point order', () {
    const points = [(-32768, 32767), (-10, -20), (0, 0), (32767, -32768)];
    for (final excludeHeader in [false, true]) {
      final vertices = _packed(points);
      final source = officeArtShapeWordFixture(
        type: 0,
        rawPropertyRecord: shapePropertyRecord(
          values: {0x0144: 2},
          complex: {0x0145: vertices},
          complexLengths: {if (excludeHeader) 0x0145: vertices.length - 6},
        ),
      );
      final before = Uint8List.fromList(source);
      final document = parseLegacyWordDocument(source);
      final geometry = document.media.drawings.single.shape!.geometry!;
      expect(geometry.path.map((command) => command.kind), [
        LegacyWordOfficeArtPathKind.move,
        LegacyWordOfficeArtPathKind.cubic,
      ]);
      expect(
        geometry.path
            .expand((command) => command.points)
            .map((p) => (p.x, p.y)),
        points,
      );
      expect(
        document.media.drawings.single.shape!.unsupportedProperties,
        isEmpty,
      );
      expect(
        document.media.notices.any(
          (notice) =>
              notice.issue == LegacyWordMediaIssue.recoveredVertexArrayLength,
        ),
        excludeHeader,
      );
      expect(source, before);
      expect(() => geometry.path.first.points.clear(), throwsUnsupportedError);
    }
  });

  test('packed coordinates use the same simple open and closed path rules', () {
    for (final mode in [0, 1, 2, 3]) {
      final document = parseLegacyWordDocument(
        officeArtShapeWordFixture(
          type: 0,
          values: {0x0144: mode},
          complex: {
            0x0145: _packed([(-30, 0), (0, 10), (30, 10), (60, 0)]),
          },
        ),
      );
      final path = document.media.drawings.single.shape!.geometry!.path;
      expect(
        path[1].kind,
        mode <= 1
            ? LegacyWordOfficeArtPathKind.line
            : LegacyWordOfficeArtPathKind.cubic,
      );
      expect(path.last.kind == LegacyWordOfficeArtPathKind.close, mode.isOdd);
    }
  });

  test(
    'packed explicit segments emit the identical editable path as 32-bit points',
    () {
      const points = [
        (-100, -200),
        (300, -200),
        (300, 0),
        (100, 400),
        (-100, 400),
      ];
      String? reference;
      for (final vertices in [shapeVertices(points), _packed(points)]) {
        final converted = convertLegacyWord(
          officeArtShapeWordFixture(
            type: 0,
            values: {0x0140: -100, 0x0141: -200, 0x0142: 300, 0x0143: 400},
            complex: {
              0x0145: vertices,
              0x0146: shapeSegments([0x4000, 0x0001, 0x2001, 0x6001, 0x8000]),
            },
          ),
        );
        final xml = XmlDocument.parse(
          utf8.decode(
            ZipDecoder()
                .decodeBytes(converted.bytes)
                .findFile('word/document.xml')!
                .content,
          ),
        );
        final shape = xml
            .findAllElements(
              'shape',
              namespace: 'urn:schemas-microsoft-com:vml',
            )
            .single;
        final path = shape.getAttribute('path')!;
        expect(path, 'm-100,-200l300,-200c300,0,100,400,-100,400xe');
        expect(path, reference ??= path);
        expect(converted.preservedCounts['editableShapes'], 1);
        expect(converted.preservedCounts['shapePathCommands'], 4);
      }
    },
  );

  test(
    'unknown point forms and the unverified unsigned arc convention stay inert',
    () {
      for (final (vertices, type) in [
        (
          shapeArray(4, [
            [0, 0, 0, 0],
          ]),
          0,
        ),
        (_packed([(40000, 50000)]), 19),
      ]) {
        final shape = _shape(vertices, type: type);
        expect(shape.geometry, isNull);
        expect(shape.unsupportedProperties, contains(0x0145));
      }
    },
  );

  test('packed point extents, allocations and count limits remain strict', () {
    final valid = _packed([(1, 2), (3, 4)]);
    for (final malformed in [
      Uint8List(0),
      Uint8List.sublistView(valid, 0, valid.length - 1),
      Uint8List.fromList([...valid, 0]),
      _packed([(1, 2)], allocated: 0),
      Uint8List.fromList([
        ...wordU16(16385),
        ...wordU16(16385),
        ...wordU16(0xfff0),
      ]),
      Uint8List.fromList(valid)..[0] = 3,
    ]) {
      expect(() => _shape(malformed), throwsFormatException);
    }
  });

  test('packed point encoding never relaxes segment reference consumption', () {
    for (final segments in [
      [0x4000, 0x2001, 0x8000],
      [0x4000, 0x8000],
      [0x0001, 0x8000],
    ]) {
      expect(
        () => parseLegacyWordDocument(
          officeArtShapeWordFixture(
            type: 0,
            complex: {
              0x0145: _packed([(0, 0), (10, 20)]),
              0x0146: shapeSegments(segments),
            },
          ),
        ),
        throwsFormatException,
      );
    }
  });
}
