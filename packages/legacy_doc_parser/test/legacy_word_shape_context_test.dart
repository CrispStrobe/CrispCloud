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

const _v = 'urn:schemas-microsoft-com:vml';
const _o = 'urn:schemas-microsoft-com:office:office';
const _wp =
    'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';

XmlDocument _xml(LegacyWordStructuredConversion result) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder()
        .decodeBytes(result.bytes)
        .findFile('word/document.xml')!
        .content,
  ),
);

LegacyWordOfficeArtShape _shape(Uint8List bytes) =>
    parseLegacyWordDocument(bytes).media.drawings.single.shape!;

bool _sameBytes(List<int> first, List<int> second) =>
    first.length == second.length &&
    first.indexed.every((entry) => entry.$2 == second[entry.$1]);

void main() {
  test('inactive solid background colors do not suppress resolved shapes', () {
    for (final fillType in [null, 0]) {
      for (final lineType in [null, 0]) {
        for (final opaqueWord in [null, 0x00000200, 0x02000000]) {
          final bytes = officeArtShapeWordFixture(
            values: {
              if (fillType != null) 0x0180: fillType,
              if (lineType != null) 0x01c4: lineType,
              if (opaqueWord != null) 0x01ff: opaqueWord,
              // Even a system color remains inactive; it is never resolved as RGB.
              0x0183: 0x08000001,
              0x01c2: 0x08000002,
              0x0181: 0x00332211,
              0x01c0: 0x00665544,
            },
          );
          final parsed = _shape(bytes);
          expect(parsed.unsupportedProperties, isEmpty);
          final result = convertLegacyWord(bytes);
          final shape = _xml(
            result,
          ).findAllElements('shape', namespace: _v).single;
          expect(shape.getAttribute('fillcolor'), '#112233');
          expect(shape.getAttribute('strokecolor'), '#445566');
          expect(result.preservedCounts['editableShapes'], 1);
          expect(result.preservedCounts['evidenceArtifacts'], greaterThan(0));
        }
      }
    }
  });

  test('active or unresolved background colors retain strict paint guards', () {
    for (final values in [
      for (final type in [1, 2, 3, 7, 10]) {0x0180: type, 0x0183: 0xffffff},
      for (final type in [1, 2, 3, 5]) {0x01c4: type, 0x01c2: 0xffffff},
      {0x01ff: 0x02000200, 0x01c2: 0xffffff},
    ]) {
      final bytes = officeArtShapeWordFixture(values: values);
      final result = convertLegacyWord(bytes);
      expect(_shape(bytes).unsupportedProperties, isNotEmpty);
      expect(result.preservedCounts['editableShapes'], isNull);
      expect(_xml(result).findAllElements('shape', namespace: _v), isEmpty);
    }
    for (final (property, values) in [
      (0x0183, <int, int>{}),
      (0x01c2, <int, int>{}),
      (0x0180, {0x0183: 0}),
      (0x01c4, {0x01c2: 0}),
      (0x01ff, {0x01c2: 0}),
    ]) {
      final bytes = officeArtShapeWordFixture(
        values: values,
        complex: {property: Uint8List(4)},
      );
      expect(_shape(bytes).unsupportedProperties, isNotEmpty);
      expect(
        convertLegacyWord(bytes).preservedCounts['editableShapes'],
        isNull,
      );
    }
  });

  test(
    'explicit cell layout maps to VML and DrawingML with source defaults',
    () {
      for (final (raw, layout, attribute) in [
        (null, null, null),
        (0x0000ffff, null, null),
        (0x80000000, false, 'f'),
        (0x80008000, true, 't'),
      ]) {
        final values = {if (raw != null) 0x03bf: raw};
        final bytes = officeArtShapeWordFixture(values: values);
        final parsed = _shape(bytes);
        expect(parsed.groupShapeBooleanProperties, raw);
        expect(parsed.layoutInCell, layout);
        expect(parsed.unsupportedProperties, isEmpty);
        final shape = _xml(
          convertLegacyWord(bytes),
        ).findAllElements('shape', namespace: _v).single;
        expect(shape.getAttribute('allowincell', namespace: _o), attribute);
        final anchor = _xml(
          convertLegacyWord(
            floatingPictureWordFixture(imageProperties: values),
          ),
        ).findAllElements('anchor', namespace: _wp).single;
        expect(
          anchor.getAttribute('layoutInCell'),
          layout == false ? '0' : '1',
        );
      }
    },
  );

  test('group use bits cascade without erasing other inherited semantics', () {
    final bytes = officeArtShapeWordFixture(
      defaults: {0x03bf: 0x00020002}, // Explicitly hidden.
      values: {0x03bf: 0x80000000}, // Explicitly outside cells only.
    );
    final parsed = _shape(bytes);
    expect(parsed.groupShapeBooleanProperties, 0x80020002);
    expect(parsed.layoutInCell, false);
    expect(parsed.unsupportedProperties, contains(0x03bf));
    expect(convertLegacyWord(bytes).preservedCounts['editableShapes'], isNull);
    final inherited = _shape(
      officeArtShapeWordFixture(
        defaults: {0x03bf: 0x80008000},
        values: {0x03bf: 0x00020002},
        additionalProperties: [
          shapePropertyRecord(values: {0x03bf: 0x80000000}),
        ],
      ),
    );
    expect(inherited.groupShapeBooleanProperties, 0x80020002);
    expect(inherited.layoutInCell, false);
    expect(inherited.unsupportedProperties, contains(0x03bf));
    final unusedChild = _shape(
      officeArtShapeWordFixture(
        defaults: {0x03bf: 0x80000000},
        values: {0x03bf: 0x0000ffff},
      ),
    );
    expect(unusedChild.layoutInCell, false);
    expect(unusedChild.unsupportedProperties, isEmpty);
  });

  test(
    'every other used group bit and complex group word stays unsupported',
    () {
      for (var bit = 0; bit < 15; bit++) {
        for (final enabled in [false, true]) {
          final bytes = officeArtShapeWordFixture(
            values: {
              0x03bf: 0x80000000 + (1 << (bit + 16)) + (enabled ? 1 << bit : 0),
            },
          );
          expect(_shape(bytes).unsupportedProperties, contains(0x03bf));
          expect(
            convertLegacyWord(bytes).preservedCounts['editableShapes'],
            isNull,
          );
        }
      }
      final bytes = officeArtShapeWordFixture(complex: {0x03bf: Uint8List(4)});
      expect(_shape(bytes).unsupportedProperties, contains(0x03bf));
      expect(
        convertLegacyWord(bytes).preservedCounts['editableShapes'],
        isNull,
      );
      for (final bad in [-1, 0x100000000]) {
        expect(
          () => LegacyWordOfficeArtShape(
            type: 1,
            groupShapeBooleanProperties: bad,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'zero-count SymmetricCurve preserves geometry and vertex editing hints',
    () {
      final bytes = officeArtShapeWordFixture(
        type: 0,
        complex: {
          0x0145: shapeVertices([(0, 0), (10, 0), (10, 10), (20, 10)]),
          0x0146: shapeSegments([0x4000, 0xb300, 0x2001, 0xb300, 0x8000]),
        },
      );
      final geometry = _shape(bytes).geometry!;
      expect(geometry.path.map((command) => command.kind), [
        LegacyWordOfficeArtPathKind.move,
        LegacyWordOfficeArtPathKind.cubic,
      ]);
      expect(
        geometry.editingHints.map((hint) => (hint.vertexIndex, hint.escape)),
        [(0, 0x13), (3, 0x13)],
      );
      expect(() => geometry.editingHints.clear(), throwsUnsupportedError);
      final result = convertLegacyWord(bytes);
      final shape = _xml(result).findAllElements('shape', namespace: _v).single;
      expect(shape.getAttribute('path'), 'm0,0c10,0,10,10,20,10e');
      expect(result.preservedCounts['shapePathEditingHints'], 2);
      expect(
        result.limitations,
        contains(LegacyWordConversionLimitation.partialFormatting),
      );
      final evidence =
          jsonDecode(
                utf8.decode(
                  ZipDecoder()
                      .decodeBytes(result.bytes)
                      .findFile('word/evidence/manifest.json')!
                      .content,
                ),
              )
              as Map;
      expect(
        (evidence['records'] as List).where(
          (record) => record['kind'] == 'pathEditingHints',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'other escapes and misplaced hints cannot bypass strict path checks',
    () {
      for (final segments in [
        [0xb300, 0x4000, 0x8000],
        [0x4000, 0x8000, 0xb300],
        for (final escape in [
          0xb301,
          0xd300,
          0xb200,
          0xa000,
          0xaa00,
          0xab00,
          0xb500,
          0xb600,
          0xbf00,
        ])
          [0x4000, escape, 0x8000],
      ]) {
        final bytes = officeArtShapeWordFixture(
          type: 0,
          complex: {
            0x0145: shapeVertices([(0, 0)]),
            0x0146: shapeSegments(segments),
          },
        );
        expect(_shape(bytes).geometry, isNull);
        expect(_shape(bytes).unsupportedProperties, contains(0x0146));
        expect(
          convertLegacyWord(bytes).preservedCounts['editableShapes'],
          isNull,
        );
      }
      for (final segments in [
        [0x4000, 0xb300, 0x2001, 0x8000],
        [0x4000, 0xb300],
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
    },
  );

  test(
    'retained native shapes keep three geometries and unchanged OfficeArt',
    () {
      final source = File(
        'test/fixtures/fidelity/officeart-shapes.doc',
      ).readAsBytesSync();
      final document = parseLegacyWordDocument(source);
      expect(document.media.drawings, hasLength(3));
      expect(
        document.media.drawings.map((drawing) => drawing.shape!.layoutInCell),
        everyElement(false),
      );
      expect(
        document.media.drawings.expand(
          (drawing) => drawing.shape!.unsupportedProperties,
        ),
        isEmpty,
      );
      expect(
        document.media.drawings.last.shape!.geometry!.editingHints,
        hasLength(5),
      );
      final result = convertLegacyWordDocument(document);
      expect(result.preservedCounts['editableShapes'], 3);
      expect(result.preservedCounts['shapePathEditingHints'], 5);
      final archive = ZipDecoder().decodeBytes(result.bytes);
      for (final artifact in document.media.artifacts) {
        expect(
          archive.files.any(
            (file) =>
                file.content.length == artifact.bytes.length &&
                _sameBytes(file.content, artifact.bytes),
          ),
          isTrue,
        );
      }
    },
  );
}
