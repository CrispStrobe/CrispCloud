// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/media_word_fixture.dart';
import 'support/officeart_shape_fixture.dart';
import 'support/structured_word_fixture.dart';

const _v = 'urn:schemas-microsoft-com:vml';
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
XmlDocument _xml(LegacyWordStructuredConversion result) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder()
        .decodeBytes(result.bytes)
        .findFile('word/document.xml')!
        .content,
  ),
);

void main() {
  test(
    'resolved binary rectangles, ellipses and lines become editable shapes',
    () {
      for (final (type, tag) in [(1, 'shape'), (3, 'oval'), (20, 'shape')]) {
        final result = convertLegacyWord(officeArtShapeWordFixture(type: type));
        final xml = _xml(result),
            shape = xml.findAllElements(tag, namespace: _v).single;
        expect(result.preservedCounts['editableShapes'], 1);
        expect(shape.getAttribute('coordsize'), '21600,21600');
        expect(shape.getAttribute('strokeweight'), '0.75pt');
        final stroke = shape.findElements('stroke', namespace: _v).single;
        expect(stroke.getAttribute('endcap'), 'flat');
        expect(stroke.getAttribute('joinstyle'), 'round');
        expect(
          shape.getAttribute('style'),
          contains('width:72.0pt;height:36.0pt'),
        );
        if (type == 1) {
          expect(
            shape.getAttribute('path'),
            'm0,0l21600,0,21600,21600,0,21600xe',
          );
        } else if (type == 20) {
          expect(shape.getAttribute('path'), 'm0,0l21600,21600e');
          expect(shape.getAttribute('filled'), 'f');
        }
        expect(xml.findAllElements('blip', namespace: '*'), isEmpty);
      }
    },
  );

  test('negative-origin paths retain move, line, cubic and close commands', () {
    final result = convertLegacyWord(
      officeArtShapeWordFixture(
        type: 0,
        values: {0x0140: -100, 0x0141: -200, 0x0142: 300, 0x0143: 400},
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
    final shape = _xml(result).findAllElements('shape', namespace: _v).single;
    expect(shape.getAttribute('coordorigin'), '-100,-200');
    expect(shape.getAttribute('coordsize'), '400,600');
    expect(shape.getAttribute('path'), 'm-10,20l50,60c70,80,90,100,110,120xe');
    expect(result.preservedCounts['shapePathCommands'], 4);
  });

  test(
    'horizontal and vertical lines keep zero extent and independent flips',
    () {
      for (final axis in ['h', 'v']) {
        for (final (flip, bits) in [
          ('none', 0),
          ('x', 0x40),
          ('y', 0x80),
          ('x y', 0xc0),
        ]) {
          final result = convertLegacyWord(
            officeArtShapeWordFixture(
              type: 20,
              flags: 0x0a00 | bits,
              anchorBounds: axis == 'h'
                  ? (120, 240, 1560, 240)
                  : (120, 240, 120, 960),
            ),
          );
          final xml = _xml(result),
              line = xml.findAllElements('line', namespace: _v).single;
          expect(line.getAttribute('from'), '6.0pt,12.0pt');
          expect(
            line.getAttribute('to'),
            axis == 'h' ? '78.0pt,12.0pt' : '6.0pt,48.0pt',
          );
          expect(line.getAttribute('coordsize'), isNull);
          expect(line.getAttribute('path'), isNull);
          expect(line.getAttribute('filled'), 'f');
          final style = line.getAttribute('style')!;
          expect(style, isNot(contains('width:')));
          expect(style, isNot(contains('height:')));
          expect(style, isNot(contains('margin-left:')));
          expect(style, isNot(contains('margin-top:')));
          if (flip == 'none') {
            expect(style, isNot(contains('flip:')));
          } else {
            expect(style, contains('flip:$flip'));
          }
          expect(result.preservedCounts['editableShapes'], 1);
        }
      }
    },
  );

  test(
    'zero-area non-lines and invalid line extents remain unrendered evidence',
    () {
      for (final type in [1, 3, 75, 202]) {
        for (final bounds in [(120, 240, 1560, 240), (120, 240, 120, 960)]) {
          final result = convertLegacyWord(
            officeArtShapeWordFixture(type: type, anchorBounds: bounds),
          );
          expect(result.preservedCounts['editableShapes'], isNull);
          expect(_xml(result).findAllElements('pict', namespace: _w), isEmpty);
          expect(result.preservedCounts['evidenceArtifacts'], greaterThan(0));
        }
      }
      for (final bounds in [
        (120, 240, 120, 240), // A point is not a finite-length line.
        (120, 240, 119, 240),
        (120, 240, 120, 239),
        (0, 0, 2000001, 0),
        (0, 0, 0, 2000001),
      ]) {
        final result = convertLegacyWord(
          officeArtShapeWordFixture(type: 20, anchorBounds: bounds),
        );
        expect(result.preservedCounts['editableShapes'], isNull);
        expect(_xml(result).findAllElements('pict', namespace: _w), isEmpty);
      }
      final image = convertLegacyWord(
        floatingPictureWordFixture(anchorBounds: (120, 240, 1560, 240)),
      );
      expect(image.preservedCounts['images'], isNull);
      expect(_xml(image).findAllElements('drawing', namespace: _w), isEmpty);
      expect(image.preservedCounts['evidenceArtifacts'], greaterThan(0));
    },
  );

  test(
    'source solid paint, opacity, line properties and shadow remain editable',
    () {
      final xml = _xml(
        convertLegacyWord(
          officeArtShapeWordFixture(
            flags: 0x0ac0,
            values: {
              4: -45 * 65536,
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
        ),
      );
      final shape = xml.findAllElements('shape', namespace: _v).single;
      expect(shape.getAttribute('style'), contains('rotation:-45.0;flip:x y'));
      expect(shape.getAttribute('fillcolor'), '#112233');
      expect(shape.getAttribute('strokecolor'), '#CCBBAA');
      expect(shape.getAttribute('strokeweight'), '2.0pt');
      expect(
        xml
            .findAllElements('fill', namespace: _v)
            .single
            .getAttribute('opacity'),
        '0.5',
      );
      final stroke = xml.findAllElements('stroke', namespace: _v).single;
      expect(stroke.getAttribute('opacity'), '0.25');
      expect(stroke.getAttribute('dashstyle'), 'dashdot');
      expect(stroke.getAttribute('joinstyle'), 'miter');
      expect(stroke.getAttribute('endcap'), 'flat');
      final shadow = xml.findAllElements('shadow', namespace: _v).single;
      expect(shadow.getAttribute('on'), 't');
      expect(shadow.getAttribute('color'), '#445566');
      expect(shadow.getAttribute('opacity'), '0.75');
      expect(shadow.getAttribute('offset'), '-1.0pt,2.0pt');
      expect(shadow.getAttribute('obscured'), 'f');
    },
  );

  test(
    'unknown geometry and effects stay evidence instead of simplified drawings',
    () {
      for (final bytes in [
        officeArtShapeWordFixture(type: 201),
        officeArtShapeWordFixture(type: 2),
        officeArtShapeWordFixture(values: {0x0180: 7}),
        officeArtShapeWordFixture(values: {0x0200: 4}),
        officeArtShapeWordFixture(values: {0x0280: 1}),
        officeArtShapeWordFixture(values: {0x00c0: 1}),
        officeArtShapeWordFixture(values: {0x03bf: 0x00020002}),
        officeArtShapeWordFixture(flags: 0x0a02),
        officeArtShapeWordFixture(flags: 0x0a20),
      ]) {
        final result = convertLegacyWord(bytes);
        expect(result.preservedCounts['editableShapes'], isNull);
        expect(_xml(result).findAllElements('pict', namespace: _w), isEmpty);
        expect(result.preservedCounts['evidenceArtifacts'], greaterThan(0));
      }
    },
  );

  test('deleted or hidden occurrences retain their source presentation', () {
    final deleted = convertLegacyWord(officeArtShapeWordFixture(flags: 0x0a08));
    expect(deleted.preservedCounts['editableShapes'], isNull);
    final hidden = _xml(
      convertLegacyWord(
        officeArtShapeWordFixture(
          characterProperties: [
            ...wordSprm(0x083c, [1]),
            ...wordSprm(0x0800, [1]),
          ],
        ),
      ),
    );
    final pict = hidden.findAllElements('pict', namespace: _w).single;
    expect(
      pict.parent!
          .findElements('rPr', namespace: _w)
          .single
          .findElements('vanish', namespace: _w),
      hasLength(1),
    );
    expect((pict.parent!.parent as XmlElement).name.local, 'del');
  });

  test(
    'caller-provided malformed geometry cannot be serialized as active markup',
    () {
      final base = parseLegacyWordDocument(officeArtShapeWordFixture());
      final old = base.media.drawings.single;
      LegacyWordDocument withShape(LegacyWordOfficeArtShape shape) =>
          LegacyWordDocument(
            blocks: base.blocks,
            sections: base.sections,
            plainText: base.plainText,
            safeHtml: '',
            media: LegacyWordMediaCatalog.from(
              drawings: [
                LegacyWordDrawing(
                  shapeId: old.shapeId,
                  anchorCp: old.anchorCp,
                  headerStory: false,
                  leftTwips: old.leftTwips,
                  topTwips: old.topTwips,
                  rightTwips: old.rightTwips,
                  bottomTwips: old.bottomTwips,
                  horizontalOrigin: old.horizontalOrigin,
                  verticalOrigin: old.verticalOrigin,
                  wrapMode: old.wrapMode,
                  wrapSide: old.wrapSide,
                  behindText: old.behindText,
                  anchorLocked: false,
                  source: old.source,
                  shape: shape,
                ),
              ],
            ),
          );
      final invalidPath = LegacyWordOfficeArtGeometry(
        bounds: const LegacyWordVectorBounds(0, 0, 100, 100),
        path: [
          LegacyWordOfficeArtPathCommand(LegacyWordOfficeArtPathKind.line, [
            const LegacyWordOfficeArtPoint(1, 2),
          ]),
        ],
      );
      expect(
        () => convertLegacyWordDocument(
          withShape(LegacyWordOfficeArtShape(type: 0, geometry: invalidPath)),
        ),
        throwsFormatException,
      );
      expect(
        () => convertLegacyWordDocument(
          withShape(
            LegacyWordOfficeArtShape(
              type: 1,
              geometry: old.shape!.geometry,
              fill: const LegacyWordOfficeArtFill(color: '"/><script/>'),
            ),
          ),
        ),
        throwsA(isA<LegacyWordConversionException>()),
      );
    },
  );
}
