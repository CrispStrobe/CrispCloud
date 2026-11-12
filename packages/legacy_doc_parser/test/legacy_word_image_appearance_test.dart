// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/media_word_fixture.dart';

const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
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

void main() {
  test(
    'retained native image controls keep their verified occurrence and transform',
    () {
      const rotations = {
        'inline-horizontal': null,
        'floating-control': null,
        'floating-horizontal': null,
        'floating-vertical': '10800000',
        'floating-both': '10800000',
        'floating-quarter': '5400000',
        'floating-negative-quarter': '16200000',
        'floating-margin-quarter': '5400000',
        'floating-outline-shadow': null,
      };
      for (final entry in rotations.entries) {
        final bytes = File(
          'test/fixtures/fidelity/image-appearance/binary/${entry.key}.doc',
        ).readAsBytesSync();
        final result = convertLegacyWord(bytes);
        expect(result.preservedCounts['images'], 1);
        expect(
          result.preservedCounts[entry.key.startsWith('inline')
              ? 'pictureReferences'
              : 'drawingReferences'],
          1,
        );
        final transform = _xml(
          result,
        ).findAllElements('xfrm', namespace: _a).single;
        expect(transform.getAttribute('rot'), entry.value, reason: entry.key);
      }
    },
  );

  test('inline and floating FSP flips are emitted independently', () {
    for (final flags in [0x0a00, 0x0a40, 0x0a80, 0x0ac0]) {
      for (final bytes in [
        inlinePictureWordFixture(picture: inlinePictureData(shapeFlags: flags)),
        floatingPictureWordFixture(shapeFlags: flags),
      ]) {
        final xml = _xml(convertLegacyWord(bytes));
        final transform = xml.findAllElements('xfrm', namespace: _a).single;
        expect(transform.getAttribute('flipH'), flags & 0x40 != 0 ? '1' : null);
        expect(transform.getAttribute('flipV'), flags & 0x80 != 0 ? '1' : null);
        expect(transform.getAttribute('rot'), isNull);
      }
    }
  });

  test(
    'absolute quarter turns preserve the FSPA center and pre-rotation axes',
    () {
      for (final angle in [-90, 90, 180, 270]) {
        for (final origin in [0, 1]) {
          final xml = _xml(
            convertLegacyWord(
              floatingPictureWordFixture(
                imageProperties: {
                  4: angle * 65536,
                  0x0390: origin,
                  0x0392: origin,
                },
                anchorBounds: (-120, 240, 600, 1680),
              ),
            ),
          );
          final transform = xml.findAllElements('xfrm', namespace: _a).single;
          expect(transform.getAttribute('rot'), '${angle % 360 * 60000}');
          final extent = transform.findElements('ext', namespace: _a).single;
          final swapped = angle % 180 != 0;
          expect(extent.getAttribute('cx'), swapped ? '914400' : '457200');
          expect(extent.getAttribute('cy'), swapped ? '457200' : '914400');
          final horizontal = xml
              .findAllElements('positionH', namespace: _wp)
              .single;
          final vertical = xml
              .findAllElements('positionV', namespace: _wp)
              .single;
          expect(
            horizontal.getAttribute('relativeFrom'),
            origin == 0 ? 'margin' : 'page',
          );
          expect(
            vertical.getAttribute('relativeFrom'),
            origin == 0 ? 'margin' : 'page',
          );
          expect(horizontal.innerText, swapped ? '-304800' : '-76200');
          expect(vertical.innerText, swapped ? '381000' : '152400');
        }
      }
    },
  );

  test(
    'rotation mapping does not infer inline, arbitrary-angle or aligned extents',
    () {
      for (final bytes in [
        inlinePictureWordFixture(
          picture: inlinePictureData(properties: {4: 90 * 65536}),
        ),
        floatingPictureWordFixture(imageProperties: {4: 45 * 65536}),
        floatingPictureWordFixture(imageProperties: {4: 90 * 65536, 0x038f: 2}),
        floatingPictureWordFixture(imageProperties: {4: 90 * 65536, 0x0390: 4}),
      ]) {
        final result = convertLegacyWord(bytes);
        final transform = _xml(
          result,
        ).findAllElements('xfrm', namespace: _a).single;
        expect(transform.getAttribute('rot'), isNull);
        expect(
          result.limitations,
          contains(LegacyWordConversionLimitation.partialFormatting),
        );
        expect(
          ZipDecoder()
              .decodeBytes(result.bytes)
              .files
              .where((f) => f.name.endsWith('.json'))
              .any(
                (f) =>
                    utf8.decode(f.content).contains('unrenderedImageRotation'),
              ),
          isTrue,
        );
      }
    },
  );

  test(
    'group, master, unresolved transform and 3D contexts keep original evidence',
    () {
      for (final bytes in [
        floatingPictureWordFixture(shapeFlags: 0x0a42),
        floatingPictureWordFixture(shapeFlags: 0x0a60),
        floatingPictureWordFixture(
          shapeFlags: 0x0a40,
          imageProperties: {0x003f: 0x10001},
        ),
        floatingPictureWordFixture(
          shapeFlags: 0x0a40,
          imageProperties: {0x033f: 0x40004},
        ),
        floatingPictureWordFixture(
          shapeFlags: 0x0a40,
          imageProperties: {0x02ff: 0x80008},
        ),
      ]) {
        final result = convertLegacyWord(bytes);
        final transform = _xml(
          result,
        ).findAllElements('xfrm', namespace: _a).single;
        expect(transform.getAttribute('flipH'), isNull);
        expect(
          result.limitations,
          contains(LegacyWordConversionLimitation.partialFormatting),
        );
        expect(result.preservedCounts['evidenceArtifacts'], greaterThan(0));
      }
    },
  );

  test(
    'direct solid image outline retains width, color, alpha, dash and joins',
    () {
      final xml = _xml(
        convertLegacyWord(
          floatingPictureWordFixture(
            imageProperties: {
              0x01ff: 0x80008,
              0x01c0: 0x332211,
              0x01c1: 32768,
              0x01cb: 25400,
              0x01ce: 2,
              0x01d6: 1,
              0x01d7: 0,
            },
          ),
        ),
      );
      final line = xml.findAllElements('ln', namespace: _a).single;
      expect(line.getAttribute('w'), '25400');
      expect(line.getAttribute('cap'), 'rnd');
      expect(
        line
            .findAllElements('srgbClr', namespace: _a)
            .single
            .getAttribute('val'),
        '112233',
      );
      expect(
        line.findAllElements('alpha', namespace: _a).single.getAttribute('val'),
        '50000',
      );
      expect(
        line.findElements('prstDash', namespace: _a).single.getAttribute('val'),
        'sysDot',
      );
      expect(
        line.findElements('miter', namespace: _a).single.getAttribute('lim'),
        '800000',
      );
    },
  );

  test(
    'enabled outline writes source defaults and explicit false stays false',
    () {
      final enabled = _xml(
        convertLegacyWord(
          floatingPictureWordFixture(imageProperties: {0x01ff: 0x80008}),
        ),
      );
      final line = enabled.findAllElements('ln', namespace: _a).single;
      expect(line.getAttribute('w'), '9525');
      expect(line.getAttribute('cap'), 'flat');
      expect(line.findElements('round', namespace: _a), hasLength(1));
      expect(
        line.findElements('prstDash', namespace: _a).single.getAttribute('val'),
        'solid',
      );
      final disabled = _xml(
        convertLegacyWord(
          floatingPictureWordFixture(
            imageProperties: {0x01ff: 0x80000, 0x01c0: 0xff},
          ),
        ),
      );
      expect(disabled.findAllElements('noFill', namespace: _a), hasLength(1));
      expect(disabled.findAllElements('solidFill', namespace: _a), isEmpty);
    },
  );

  test(
    'simple enabled shadow retains signed offset, direct color and alpha',
    () {
      final xml = _xml(
        convertLegacyWord(
          floatingPictureWordFixture(
            imageProperties: {
              0x023f: 0x30002,
              0x0201: 0x665544,
              0x0204: 49152,
              0x0205: -12700,
              0x0206: 0,
            },
          ),
        ),
      );
      final shadow = xml.findAllElements('outerShdw', namespace: _a).single;
      expect(shadow.getAttribute('dist'), '12700');
      expect(shadow.getAttribute('dir'), '10800000');
      expect(shadow.getAttribute('blurRad'), '0');
      expect(shadow.getAttribute('rotWithShape'), '0');
      expect(
        shadow
            .findElements('srgbClr', namespace: _a)
            .single
            .getAttribute('val'),
        '445566',
      );
      expect(
        shadow
            .findAllElements('alpha', namespace: _a)
            .single
            .getAttribute('val'),
        '75000',
      );
    },
  );

  test(
    'unsupported line and shadow effects never become a simplified active effect',
    () {
      for (final properties in [
        {0x01ff: 0x80008, 0x01c0: 0x112233, 0x01c4: 1},
        {0x01ff: 0x80008, 0x01d0: 1},
        {0x01ff: 0x80008, 0x01c1: 65537},
        {0x023f: 0x20002, 0x0200: 1},
        {0x023f: 0x30003},
        {0x023f: 0x20002, 0x0203: 0xff},
        {0x023f: 0x20002, 0x0201: 0x01000000},
      ]) {
        final result = convertLegacyWord(
          floatingPictureWordFixture(imageProperties: properties),
        );
        final xml = _xml(result);
        expect(xml.findAllElements('ln', namespace: _a), isEmpty);
        expect(xml.findAllElements('outerShdw', namespace: _a), isEmpty);
        expect(
          result.limitations,
          contains(LegacyWordConversionLimitation.partialFormatting),
        );
      }
      final unspecified = _xml(
        convertLegacyWord(
          floatingPictureWordFixture(imageProperties: {0x0201: 0x665544}),
        ),
      );
      expect(unspecified.findAllElements('outerShdw', namespace: _a), isEmpty);
    },
  );

  test('quarter-turn output offsets retain the signed DrawingML bound', () {
    expect(
      () => convertLegacyWord(
        floatingPictureWordFixture(
          imageProperties: {4: 90 * 65536},
          anchorBounds: (-2000000, -2000000, 2000000, -1999999),
        ),
      ),
      throwsA(isA<LegacyWordConversionException>()),
    );
  });
}
