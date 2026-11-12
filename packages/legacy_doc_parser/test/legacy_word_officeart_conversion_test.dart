// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/media_word_fixture.dart';
import 'support/officeart_shape_fixture.dart';
import 'support/structured_word_fixture.dart';

const _v = 'urn:schemas-microsoft-com:vml';
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _wp =
    'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';

(LegacyWordStructuredConversion, XmlDocument) _convert(Uint8List source) {
  final copy = convertLegacyWord(source);
  final zip = ZipDecoder().decodeBytes(copy.bytes);
  for (final part in zip.files) {
    if (part.name.endsWith('.xml') || part.name.endsWith('.rels')) {
      XmlDocument.parse(utf8.decode(part.content));
    }
  }
  return (
    copy,
    XmlDocument.parse(utf8.decode(zip.findFile('word/document.xml')!.content)),
  );
}

void main() {
  test('emits referenced presets as editable native VML geometry', () {
    for (final entry in {
      1: 'rect',
      2: 'roundrect',
      3: 'oval',
      20: 'shape',
    }.entries) {
      final (copy, xml) = _convert(officeArtShapeWordFixture(type: entry.key));
      expect(xml.findAllElements(entry.value, namespace: _v), hasLength(1));
      expect(xml.findAllElements('imagedata', namespace: _v), isEmpty);
      expect(copy.preservedCounts['editableShapes'], 1);
      expect(copy.preservedCounts['drawingReferences'], 1);
      expect(copy.preservedCounts['images'], isNull);
      if (entry.key == 20) {
        expect(
          xml
              .findAllElements('shape', namespace: _v)
              .single
              .getAttribute('path'),
          'm0,0l21600,21600e',
        );
      }
    }
  });

  test(
    'emits exact resolved path coordinates and separate no-fill/no-line commands',
    () {
      final (_, xml) = _convert(
        officeArtShapeWordFixture(
          type: 0,
          values: {0x0140: -10, 0x0141: -20, 0x0142: 100, 0x0143: 200},
          complex: {
            0x0145: shapeVertices([(-10, 0), (20, 40), (60, 70), (90, 100)]),
            0x0146: shapeSegments([
              0x4000,
              0x2001,
              0x6001,
              0xaa00,
              0xab00,
              0x8000,
            ]),
          },
        ),
      );
      final shape = xml.findAllElements('shape', namespace: _v).single;
      expect(shape.getAttribute('coordorigin'), '-10,-20');
      expect(shape.getAttribute('coordsize'), '110,220');
      expect(shape.getAttribute('path'), 'm-10,0c20,40,60,70,90,100xnfnse');
    },
  );

  test(
    'keeps explicit paint, transforms and offset shadows in native shape output',
    () {
      final (_, xml) = _convert(
        officeArtShapeWordFixture(
          flags: 0x0ac0,
          values: {
            4: 90 * 65536,
            0x0181: 0x00332211,
            0x0182: 32768,
            0x01bf: 0x00100010,
            0x01c0: 0x00665544,
            0x01c1: 16384,
            0x01cb: 25400,
            0x01ce: 8,
            0x01d6: 1,
            0x01d7: 0,
            0x01ff: 0x00080008,
            0x0200: 0,
            0x0201: 0x00998877,
            0x0204: 32768,
            0x0205: -12700,
            0x0206: 38100,
            0x023f: 0x00030002,
          },
        ),
      );
      final shape = xml.findAllElements('rect', namespace: _v).single;
      expect(shape.getAttribute('style'), contains('rotation:90;flip:xy;'));
      expect(shape.getAttribute('fillcolor'), '#112233');
      expect(shape.getAttribute('strokecolor'), '#445566');
      expect(shape.getAttribute('strokeweight'), '2pt');
      expect(
        shape
            .findElements('fill', namespace: _v)
            .single
            .getAttribute('opacity'),
        '0.5',
      );
      final stroke = shape.findElements('stroke', namespace: _v).single;
      expect(stroke.getAttribute('dashstyle'), 'dashdot');
      expect(stroke.getAttribute('joinstyle'), 'miter');
      expect(stroke.getAttribute('endcap'), 'round');
      expect(stroke.getAttribute('opacity'), '0.25');
      final shadow = shape.findElements('shadow', namespace: _v).single;
      expect(shadow.getAttribute('color'), '#778899');
      expect(shadow.getAttribute('offset'), '-1pt,3pt');
      expect(shadow.getAttribute('obscured'), 'f');
    },
  );

  test('maps binary dash enums separately for VML and DrawingML', () {
    // Independent output expectations. VML dashstyle is a string, so parsing
    // the XML alone cannot detect a case error that renders as a solid line.
    const expected = {
      0: ('solid', 'solid'),
      1: ('shortdash', 'sysDash'),
      2: ('shortdot', 'sysDot'),
      3: ('shortdashdot', 'sysDashDot'),
      4: ('shortdashdotdot', 'sysDashDotDot'),
      5: ('dot', 'dot'),
      6: ('dash', 'dash'),
      7: ('longdash', 'lgDash'),
      8: ('dashdot', 'dashDot'),
      9: ('longdashdot', 'lgDashDot'),
      10: ('longdashdotdot', 'lgDashDotDot'),
    };
    for (final entry in expected.entries) {
      final properties = {0x01ce: entry.key, 0x01ff: 0x00080008};
      final (_, shapeXml) = _convert(
        officeArtShapeWordFixture(values: properties),
      );
      expect(
        shapeXml
            .findAllElements('stroke', namespace: _v)
            .single
            .getAttribute('dashstyle'),
        entry.value.$1,
        reason: 'VML binary dash enum ${entry.key}',
      );
      final (_, pictureXml) = _convert(
        inlinePictureWordFixture(
          picture: inlinePictureData(properties: properties),
        ),
      );
      expect(
        pictureXml
            .findAllElements('prstDash', namespace: _a)
            .single
            .getAttribute('val'),
        entry.value.$2,
        reason: 'DrawingML binary dash enum ${entry.key}',
      );
    }
  });

  test(
    'retains original picture bytes while adding DrawingML transforms and effects',
    () {
      final (copy, xml) = _convert(
        inlinePictureWordFixture(
          picture: inlinePictureData(
            shapeFlags: 0x0a40,
            properties: {
              4: -45 * 65536,
              0x01c0: 0x00332211,
              0x01cb: 12700,
              0x01ce: 3,
              0x01c1: 32768,
              0x01ff: 0x00080008,
              0x023f: 0x00020002,
              0x0201: 0x00665544,
              0x0205: 38100,
              0x0206: 50800,
            },
          ),
        ),
      );
      final transform = xml.findAllElements('xfrm', namespace: _a).single;
      expect(transform.getAttribute('rot'), '18900000');
      expect(transform.getAttribute('flipH'), '1');
      expect(
        xml
            .findAllElements('prstDash', namespace: _a)
            .single
            .getAttribute('val'),
        'sysDashDot',
      );
      expect(
        xml
            .findAllElements('outerShdw', namespace: _a)
            .single
            .getAttribute('dist'),
        '63500',
      );
      final zip = ZipDecoder().decodeBytes(copy.bytes);
      expect(
        zip.findFile('word/media/image1.png')!.content,
        orderedEquals(mediaFixturePng()),
      );
    },
  );

  test('unused line Boolean words do not invent a border around pictures', () {
    final (_, xml) = _convert(
      inlinePictureWordFixture(
        picture: inlinePictureData(properties: {0x01ff: 8}),
      ),
    );
    expect(xml.findAllElements('ln', namespace: _a), isEmpty);
  });

  test(
    'uses native explicit positioning and alignment ahead of unchanged SPA',
    () {
      final values = {0x038f: 2, 0x0390: 0, 0x0391: 5, 0x0392: 3};
      final (_, shapeXml) = _convert(officeArtShapeWordFixture(values: values));
      final style = shapeXml
          .findAllElements('rect', namespace: _v)
          .single
          .getAttribute('style')!;
      expect(style, contains('mso-position-horizontal-relative:margin;'));
      expect(style, contains('mso-position-vertical-relative:line;'));
      expect(style, contains('mso-position-horizontal:center;'));
      expect(style, contains('mso-position-vertical:outside;'));
      final (_, pictureXml) = _convert(
        floatingPictureWordFixture(imageProperties: values),
      );
      final h = pictureXml.findAllElements('positionH', namespace: _wp).single;
      final v = pictureXml.findAllElements('positionV', namespace: _wp).single;
      expect(h.getAttribute('relativeFrom'), 'margin');
      expect(v.getAttribute('relativeFrom'), 'line');
      expect(
        h.findElements('align', namespace: _wp).single.innerText,
        'center',
      );
      expect(
        v.findElements('align', namespace: _wp).single.innerText,
        'outside',
      );
      expect(h.findElements('posOffset', namespace: _wp), isEmpty);
    },
  );

  test(
    'retains hidden/deleted revision state and never activates deleted shape records',
    () {
      final (_, tracked) = _convert(
        officeArtShapeWordFixture(
          characterProperties: [
            ...wordSprm(0x083c, [1]),
            ...wordSprm(0x0800, [1]),
          ],
        ),
      );
      expect(tracked.findAllElements('del', namespace: _w), isNotEmpty);
      final shape = tracked.findAllElements('rect', namespace: _v).single;
      final run = shape.ancestors.whereType<XmlElement>().firstWhere(
        (e) => e.name.local == 'r',
      );
      expect(run.findAllElements('vanish', namespace: _w), isNotEmpty);
      final (copy, deleted) = _convert(
        officeArtShapeWordFixture(flags: 0x0a08),
      );
      expect(deleted.findAllElements('rect', namespace: _v), isEmpty);
      expect(copy.preservedCounts['editableShapes'], isNull);
    },
  );

  test(
    'unsupported presets and effects remain disclosed inert source evidence',
    () {
      final (missing, xml) = _convert(officeArtShapeWordFixture(type: 201));
      expect(xml.findAllElements('pict', namespace: _w), isEmpty);
      expect(
        missing.limitations,
        contains(LegacyWordConversionLimitation.embeddedObjects),
      );
      final (partial, supported) = _convert(
        officeArtShapeWordFixture(
          values: {0x023f: 0x00020002, 0x0200: 4, 0x0280: 1},
        ),
      );
      expect(supported.findAllElements('rect', namespace: _v), hasLength(1));
      expect(supported.findAllElements('shadow', namespace: _v), isEmpty);
      expect(
        partial.limitations,
        contains(LegacyWordConversionLimitation.partialFormatting),
      );
      final zip = ZipDecoder().decodeBytes(partial.bytes);
      expect(
        zip.files.where((p) => p.name.startsWith('word/evidence/')),
        isNotEmpty,
      );
    },
  );
}
