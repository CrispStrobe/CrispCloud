// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/media_word_fixture.dart';
import 'support/officeart_shape_fixture.dart';

const _v = 'urn:schemas-microsoft-com:vml';
const _wp =
    'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';

XmlDocument _xml(LegacyWordDocument document) => XmlDocument.parse(
  utf8.decode(
    ZipDecoder()
        .decodeBytes(convertLegacyWordDocument(document).bytes)
        .findFile('word/document.xml')!
        .content,
  ),
);

void main() {
  test('literal wrap distances retain side, unit and explicit zero', () {
    final document = parseLegacyWordDocument(
      officeArtShapeWordFixture(
        values: {0x0384: 0, 0x0385: 12700, 0x0386: 25400, 0x0387: 45720},
        anchorBounds: (-413, 827, 1027, 1547),
      ),
    );
    final drawing = document.media.drawings.single;
    final wrap = drawing.shape!.wrapDistances!;
    expect(
      [wrap.leftEmu, wrap.topEmu, wrap.rightEmu, wrap.bottomEmu],
      [0, 12700, 25400, 45720],
    );
    expect(drawing.shape!.unsupportedProperties, isEmpty);
    final style = _xml(
      document,
    ).findAllElements('shape', namespace: _v).single.getAttribute('style')!;
    expect(style, contains('mso-wrap-distance-left:0.0pt;'));
    expect(style, contains('mso-wrap-distance-top:1.0pt;'));
    expect(style, contains('mso-wrap-distance-right:2.0pt;'));
    expect(style, contains('mso-wrap-distance-bottom:3.6pt;'));
    expect(style, contains('margin-left:-20.65pt;margin-top:41.35pt;'));
    expect(style, contains('width:72.0pt;height:36.0pt;'));
  });

  test(
    'source default records inherit per side and explicit zero overrides',
    () {
      final document = parseLegacyWordDocument(
        officeArtShapeWordFixture(
          defaults: {0x0384: 45720, 0x0385: 25400, 0x0387: 38100},
          values: {0x0384: 0, 0x0386: 12700},
        ),
      );
      final wrap = document.media.drawings.single.shape!.wrapDistances!;
      expect(
        [wrap.leftEmu, wrap.topEmu, wrap.rightEmu, wrap.bottomEmu],
        [0, 25400, 12700, 38100],
      );
    },
  );

  test('absence does not invent explicit VML clearance properties', () {
    final document = parseLegacyWordDocument(officeArtShapeWordFixture());
    expect(document.media.drawings.single.shape!.wrapDistances, isNull);
    final style = _xml(
      document,
    ).findAllElements('shape', namespace: _v).single.getAttribute('style')!;
    expect(style, isNot(contains('mso-wrap-distance-')));
    final partial = parseLegacyWordDocument(
      officeArtShapeWordFixture(values: {0x0385: 0}),
    );
    final partialStyle = _xml(
      partial,
    ).findAllElements('shape', namespace: _v).single.getAttribute('style')!;
    expect(partialStyle, contains('mso-wrap-distance-top:0.0pt;'));
    expect(partialStyle, isNot(contains('mso-wrap-distance-left:')));
    expect(partialStyle, isNot(contains('mso-wrap-distance-right:')));
    expect(partialStyle, isNot(contains('mso-wrap-distance-bottom:')));
  });

  test(
    'floating picture distances remain exact EMUs independent of position',
    () {
      final document = parseLegacyWordDocument(
        floatingPictureWordFixture(
          imageProperties: {
            0x0384: 0,
            0x0385: 45720,
            0x0386: 635,
            0x0387: 12700,
          },
          anchorBounds: (937, -257, 2377, 463),
        ),
      );
      final xml = _xml(document);
      final anchor = xml.findAllElements('anchor', namespace: _wp).single;
      expect(anchor.getAttribute('distL'), '0');
      expect(anchor.getAttribute('distT'), '45720');
      expect(anchor.getAttribute('distR'), '635');
      expect(anchor.getAttribute('distB'), '12700');
      expect(
        xml.findAllElements('positionH', namespace: _wp).single.innerText,
        '594995',
      );
      expect(
        xml.findAllElements('positionV', namespace: _wp).single.innerText,
        '-163195',
      );
    },
  );

  for (final id in [0x0384, 0x0385, 0x0386, 0x0387]) {
    test('wrap property 0x${id.toRadixString(16)} rejects a BLIP flag', () {
      expect(
        () => parseLegacyWordDocument(
          officeArtShapeWordFixture(values: {id | 0x4000: 45720}),
        ),
        throwsFormatException,
      );
    });

    test(
      'complex wrap property 0x${id.toRadixString(16)} stays unsupported',
      () {
        final document = parseLegacyWordDocument(
          officeArtShapeWordFixture(
            complex: {
              id: Uint8List.fromList([0x98, 0xb2, 0, 0]),
            },
          ),
        );
        final shape = document.media.drawings.single.shape!;
        expect(shape.unsupportedProperties, contains(id));
        final wrap = shape.wrapDistances!;
        expect([
          wrap.leftEmu,
          wrap.topEmu,
          wrap.rightEmu,
          wrap.bottomEmu,
        ], everyElement(isNull));
        expect(_xml(document).findAllElements('shape', namespace: _v), isEmpty);
      },
    );

    test(
      'negative wrap property 0x${id.toRadixString(16)} is not unsigned size',
      () {
        final document = parseLegacyWordDocument(
          floatingPictureWordFixture(imageProperties: {id: 0xffffffff}),
        );
        expect(
          document.media.drawings.single.shape!.unsupportedProperties,
          contains(id),
        );
        final anchor = _xml(
          document,
        ).findAllElements('anchor', namespace: _wp).single;
        for (final attribute in ['distL', 'distT', 'distR', 'distB']) {
          expect(anchor.getAttribute(attribute), '0');
        }
        expect(
          document.warnings,
          contains(LegacyWordWarning.floatingObjectsOmitted),
        );
      },
    );
  }

  test(
    'unsupported adjacent properties still prevent plain shape substitution',
    () {
      final document = parseLegacyWordDocument(
        officeArtShapeWordFixture(values: {0x0385: 45720, 0x0388: 1}),
      );
      expect(
        document.media.drawings.single.shape!.unsupportedProperties,
        contains(0x0388),
      );
      expect(_xml(document).findAllElements('shape', namespace: _v), isEmpty);
    },
  );

  test('six Word14 textboxes retain their independently stored clearances', () {
    final bytes = File(
      'test/fixtures/word_native/word14-margin-origin.doc',
    ).readAsBytesSync();
    final table = BoundedCfbReader(bytes).readPath('1Table')!;
    // Literal source offsets/bytes, independent of the FOPT decoder and DOCX
    // writer. Each record stores top and bottom at 45720 EMU (3.6 pt).
    for (final offset in [5595, 7602, 12007, 13991, 15976, 26158]) {
      expect(table.sublist(offset, offset + 12), [
        0x85,
        0x03,
        0x98,
        0xb2,
        0,
        0,
        0x87,
        0x03,
        0x98,
        0xb2,
        0,
        0,
      ]);
    }
    final document = parseLegacyWordDocument(bytes);
    final drawings = document.media.drawings
        .where((drawing) => drawing.textboxId != null)
        .toList();
    final boxes = _xml(
      document,
    ).findAllElements('rect', namespace: _v).toList();
    expect(drawings, hasLength(6));
    expect(boxes, hasLength(6));
    for (var i = 0; i < drawings.length; i++) {
      final drawing = drawings[i];
      final wrap = drawing.shape!.wrapDistances!;
      expect(
        [wrap.leftEmu, wrap.topEmu, wrap.rightEmu, wrap.bottomEmu],
        [null, 45720, null, 45720],
      );
      final style = boxes[i].getAttribute('style')!;
      expect(style, contains('mso-wrap-distance-top:3.6pt;'));
      expect(style, contains('mso-wrap-distance-bottom:3.6pt;'));
      expect(style, contains('margin-left:${drawing.leftTwips / 20}pt;'));
      expect(style, contains('margin-top:${drawing.topTwips / 20}pt;'));
      expect(style, isNot(contains('mso-wrap-distance-left:')));
      expect(style, isNot(contains('mso-wrap-distance-right:')));
    }
  });
}
