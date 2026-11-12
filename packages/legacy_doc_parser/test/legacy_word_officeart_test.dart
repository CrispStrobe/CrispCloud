// SPDX-License-Identifier: MPL-2.0
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';

import 'support/media_word_fixture.dart';
import 'support/officeart_shape_fixture.dart';
import 'support/structured_word_fixture.dart';

LegacyWordOfficeArtShape _shape(Uint8List data) =>
    parseLegacyWordDocument(data).media.drawings.single.shape!;

void main() {
  test('resolves FSP presets, signed rotation, and independent flips', () {
    for (final entry in {
      1: 'rect',
      2: 'roundRect',
      3: 'ellipse',
      20: 'line',
      202: 'rect',
    }.entries) {
      final shape = _shape(
        officeArtShapeWordFixture(
          type: entry.key,
          flags: 0x0ac0,
          values: {4: -45 * 65536},
        ),
      );
      expect(shape.type, entry.key);
      expect(shape.geometry!.preset, entry.value);
      expect(shape.rotationFixed16, -45 * 65536);
      expect(shape.flipHorizontal, isTrue);
      expect(shape.flipVertical, isTrue);
      expect(shape.unsupportedProperties, isEmpty);
    }
  });

  test('keeps textbox margins, enum values and used Boolean flags', () {
    final text = _shape(
      officeArtShapeWordFixture(
        type: 202,
        values: {
          0x0081: -12700,
          0x0082: 25400,
          0x0083: 38100,
          0x0084: 0,
          0x0085: 2,
          0x0087: 4,
          0x0088: 2,
          0x0089: 3,
          0x00bf: 0x000a0002,
        },
      ),
    ).text!;
    expect(
      [
        text.insetLeftEmu,
        text.insetTopEmu,
        text.insetRightEmu,
        text.insetBottomEmu,
      ],
      [-12700, 25400, 38100, 0],
    );
    expect(
      [text.wrapMode, text.anchor, text.flow, text.fontDirection],
      [2, 4, 2, 3],
    );
    expect(text.fitShapeToText, isTrue);
    expect(text.autoTextMargin, isFalse);
    final unused = _shape(
      officeArtShapeWordFixture(values: {0x00bf: 0xffff}),
    ).text!;
    expect(unused.fitShapeToText, isNull);
    expect(unused.autoTextMargin, isNull);
    expect(unused.insetLeftEmu, isNull);
  });

  test('cascades only explicitly used Boolean bits across property layers', () {
    final shape = _shape(
      officeArtShapeWordFixture(
        defaults: {
          0x00bf: 0x000a000a,
          0x01bf: 0x00100010,
          0x01ff: 0x00080008,
          0x0181: 0x000000ff,
        },
        values: {0x00bf: 0x00020000, 0x01bf: 0x00100000, 0x01ff: 0x00080000},
        additionalProperties: [
          shapePropertyRecord(values: {0x00bf: 0x00040004}),
        ],
      ),
    );
    expect(shape.text!.fitShapeToText, isFalse);
    expect(shape.text!.autoTextMargin, isTrue);
    expect(shape.fill!.enabled, isFalse);
    expect(shape.fill!.color, 'FF0000');
    expect(shape.line!.enabled, isFalse);
  });

  test('resolves direct fill, line and offset-shadow properties', () {
    final shape = _shape(
      officeArtShapeWordFixture(
        values: {
          0x0181: 0x00332211,
          0x0182: 32768,
          0x01bf: 0x00100010,
          0x01c0: 0x00aabbcc,
          0x01c1: 16384,
          0x01cb: 25400,
          0x01ce: 8,
          0x01d6: 1,
          0x01d7: 2,
          0x01ff: 0x00080008,
          0x0200: 0,
          0x0201: 0x00665544,
          0x0204: 49152,
          0x0205: -12700,
          0x0206: 25400,
          0x023f: 0x00030002,
        },
      ),
    );
    expect(shape.fill!.color, '112233');
    expect(shape.fill!.opacityFixed16, 32768);
    expect(shape.line!.color, 'CCBBAA');
    expect(shape.line!.widthEmu, 25400);
    expect([shape.line!.dash, shape.line!.join, shape.line!.cap], [8, 1, 2]);
    expect(shape.shadow!.enabled, isTrue);
    expect(shape.shadow!.obscured, isFalse);
    expect(shape.shadow!.color, '445566');
    expect(shape.shadow!.offsetXEmu, -12700);
    expect(shape.shadow!.offsetYEmu, 25400);
    expect(shape.unsupportedProperties, isEmpty);
  });

  test(
    'does not turn system colors, gradients or unknown effects into RGB',
    () {
      final document = parseLegacyWordDocument(
        officeArtShapeWordFixture(
          values: {
            0x0180: 7,
            0x0181: 0x08000001,
            0x0182: 65537,
            0x01c0: 0x010000fe,
            0x0200: 4,
            0x0280: 42,
          },
        ),
      );
      final shape = document.media.drawings.single.shape!;
      expect(shape.fill!.color, isNull);
      expect(shape.fill!.opacityFixed16, isNull);
      expect(shape.line!.color, isNull);
      expect(
        shape.unsupportedProperties,
        containsAll([0x0180, 0x0181, 0x0182, 0x01c0, 0x0200, 0x0280]),
      );
      expect(
        document.media.notices.map((n) => n.issue),
        contains(LegacyWordMediaIssue.unsupportedDrawing),
      );
      expect(document.media.artifacts, isNotEmpty);
    },
  );

  test(
    'parses custom line/Bezier segments and lets them override shapePath',
    () {
      final shape = _shape(
        officeArtShapeWordFixture(
          type: 0,
          values: {
            0x0140: -100,
            0x0141: -200,
            0x0142: 300,
            0x0143: 400,
            0x0144: 1,
          },
          complex: {
            0x0145: shapeVertices([
              (-10, 20),
              (50, 60),
              (70, 80),
              (90, 100),
              (110, 120),
            ]),
            0x0146: shapeSegments([0x4000, 0x0001, 0x2001, 0x6001, 0x8000]),
          },
        ),
      );
      final geometry = shape.geometry!;
      expect(geometry.preset, isNull);
      expect(geometry.bounds.left, -100);
      expect(geometry.bounds.height, 600);
      expect(geometry.path.map((c) => c.kind), [
        LegacyWordOfficeArtPathKind.move,
        LegacyWordOfficeArtPathKind.line,
        LegacyWordOfficeArtPathKind.cubic,
        LegacyWordOfficeArtPathKind.close,
      ]);
      expect(geometry.path[2].points.map((p) => (p.x, p.y)), [
        (70, 80),
        (90, 100),
        (110, 120),
      ]);
      expect(() => geometry.path.clear(), throwsUnsupportedError);
      expect(() => geometry.path.first.points.clear(), throwsUnsupportedError);
    },
  );

  test('handles simple open/closed straight and cubic paths', () {
    for (final mode in [0, 1, 2, 3]) {
      final geometry = _shape(
        officeArtShapeWordFixture(
          type: 0,
          values: {0x0144: mode},
          complex: {
            0x0145: shapeVertices([(0, 0), (30, 10), (60, 10), (90, 0)]),
          },
        ),
      ).geometry!;
      expect(
        geometry.path[1].kind,
        mode <= 1
            ? LegacyWordOfficeArtPathKind.line
            : LegacyWordOfficeArtPathKind.cubic,
      );
      expect(
        geometry.path.last.kind == LegacyWordOfficeArtPathKind.close,
        mode.isOdd,
      );
    }
  });

  test(
    'retains unknown point sizes, guides, escapes and unknown presets as evidence',
    () {
      final fixtures = [
        officeArtShapeWordFixture(type: 201),
        officeArtShapeWordFixture(values: {0x0147: 123}),
        officeArtShapeWordFixture(
          type: 0,
          complex: {
            0x0145: shapeArray(12, [List.filled(12, 0)]),
          },
        ),
        officeArtShapeWordFixture(
          type: 0,
          complex: {
            0x0145: shapeVertices([(0x80000001, 0)]),
          },
        ),
        officeArtShapeWordFixture(
          type: 0,
          complex: {
            0x0145: shapeVertices([(0, 0)]),
            0x0146: shapeSegments([0xa001]),
          },
        ),
      ];
      for (final fixture in fixtures) {
        final document = parseLegacyWordDocument(fixture);
        expect(document.media.drawings.single.shape!.geometry, isNull);
        expect(
          document.media.notices.map((n) => n.issue),
          contains(LegacyWordMediaIssue.unsupportedDrawing),
        );
      }
    },
  );

  test(
    'supports native packed POINTs and the exact header-excluding length convention',
    () {
      final vertices = shapeArray(0xfff0, [
        [...wordU16(-10), ...wordU16(20)],
        [...wordU16(100), ...wordU16(-200)],
      ]);
      for (final excludeHeader in [false, true]) {
        final shape = _shape(
          officeArtShapeWordFixture(
            type: 0,
            rawPropertyRecord: shapePropertyRecord(
              values: {0x0144: 4, 0x0181: 0x00332211},
              complex: {
                0x0145: vertices,
                0x0146: shapeSegments([0x4000, 0xb300, 1, 0xb300, 0x8000]),
                0x0380: Uint8List.fromList([65, 0, 0, 0]),
              },
              complexLengths: {
                0x0145: vertices.length - (excludeHeader ? 6 : 0),
              },
            ),
          ),
        );
        expect(
          shape.geometry!.path.map(
            (c) => c.points.map((p) => (p.x, p.y)).toList(),
          ),
          [
            [(-10, 20)],
            [(100, -200)],
          ],
        );
        expect(shape.fill!.color, '112233');
        expect(shape.unsupportedProperties, contains(0x0146));
      }
      final array = shapeArray(0xfff0, [
        [...wordU16(40000), ...wordU16(50000)],
      ]);
      final arc = _shape(
        officeArtShapeWordFixture(
          type: 19,
          values: {0x0144: 0},
          complex: {0x0145: array},
        ),
      );
      expect(arc.geometry!.path.first.points.single.x, 40000);
    },
  );

  test(
    'keeps path no-fill/no-line escapes separate from enabled shape styles',
    () {
      final shape = _shape(
        officeArtShapeWordFixture(
          type: 0,
          values: {0x01bf: 0x00100010, 0x01ff: 0x00080008},
          complex: {
            0x0145: shapeVertices([(0, 0), (100, 100)]),
            0x0146: shapeSegments([0x4000, 0xaa00, 1, 0xab00, 0x8000]),
          },
        ),
      );
      expect(shape.fill!.enabled, isTrue);
      expect(shape.line!.enabled, isTrue);
      expect(shape.geometry!.fill, isFalse);
      expect(shape.geometry!.stroke, isFalse);
      expect(shape.unsupportedProperties, isEmpty);
    },
  );

  test(
    'retains explicit native Word positioning independently of SPA origins',
    () {
      final drawing = parseLegacyWordDocument(
        officeArtShapeWordFixture(
          values: {0x038f: 2, 0x0390: 0, 0x0391: 5, 0x0392: 3},
        ),
      ).media.drawings.single;
      expect(drawing.horizontalOrigin, 1);
      expect(drawing.verticalOrigin, 2);
      expect(drawing.shape!.position!.horizontalMode, 2);
      expect(drawing.shape!.position!.horizontalRelativeTo, 0);
      expect(drawing.shape!.position!.verticalMode, 5);
      expect(drawing.shape!.position!.verticalRelativeTo, 3);
    },
  );

  test('caps inherited path expansion across referenced shapes', () {
    final properties = shapePropertyRecord(
      complex: {
        0x0145: shapeVertices([(0, 0)]),
        0x0146: shapeSegments([0x4000, ...List.filled(16382, 0x6001), 0x8000]),
      },
    );
    final records = [
      for (var i = 0; i < 7; i++)
        officeArtRecord(
          0xf004,
          officeArtRecord(
            0xf00a,
            [...wordU32(1025 + i), ...wordU32(0x0a00)],
            version: 2,
            instance: 0,
          ),
          version: 15,
        ),
    ];
    final drawings = Uint8List.fromList([
      ...officeArtRecord(0xf000, properties, version: 15),
      0,
      ...officeArtRecord(
        0xf002,
        officeArtRecord(0xf003, [
          for (final record in records) ...record,
        ], version: 15),
        version: 15,
      ),
    ]);
    final bytes = StructuredWordFixture(
      pieces: const [WordFixturePiece('A\x08B\r')],
      extraTablePairs: {40: drawingAnchor(), 50: drawings},
      characterRuns: [
        WordFixtureFkpRun(8192, 8196, properties: wordSprm(0x0855, [1])),
      ],
    ).build();
    expect(() => parseLegacyWordDocument(bytes), throwsFormatException);
  });

  test(
    'rejects malformed complex extents, segment references and duplicate properties',
    () {
      final badVertices = [
        Uint8List(0),
        shapeArray(8, [wordU32(0)]),
        shapeArray(8, [List.filled(8, 0)], allocated: 0),
        Uint8List.fromList([
          ...wordU16(16385),
          ...wordU16(16385),
          ...wordU16(8),
        ]),
      ];
      for (final vertices in badVertices) {
        expect(
          () => _shape(
            officeArtShapeWordFixture(type: 0, complex: {0x0145: vertices}),
          ),
          throwsFormatException,
        );
      }
      for (final segments in [
        [0x0001, 0x8000],
        [0x4001, 0x8000],
        [0x4000, 0x2001, 0x8000],
        [0x4000, 0x6000, 0x8000],
        [0x4000, 0x8001],
        [0x4000],
      ]) {
        expect(
          () => _shape(
            officeArtShapeWordFixture(
              type: 0,
              complex: {
                0x0145: shapeVertices([(0, 0)]),
                0x0146: shapeSegments(segments),
              },
            ),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => _shape(
          officeArtShapeWordFixture(
            rawPropertyRecord: officeArtRecord(
              0xf00b,
              [...wordU16(4), ...wordU32(1), ...wordU16(4), ...wordU32(2)],
              version: 3,
              instance: 2,
            ),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'also exposes transforms and text settings on referenced inline pictures',
    () {
      final picture = parseLegacyWordDocument(
        inlinePictureWordFixture(
          picture: inlinePictureData(
            shapeFlags: 0x0a40,
            properties: {4: 90 * 65536, 0x0081: 12700},
          ),
        ),
      ).media.pictures.single;
      expect(picture.shape!.type, 75);
      expect(picture.shape!.flipHorizontal, isTrue);
      expect(picture.shape!.rotationFixed16, 90 * 65536);
      expect(picture.shape!.text!.insetLeftEmu, 12700);
    },
  );
}
