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
const _w10 = 'urn:schemas-microsoft-com:office:word';
const _wp =
    'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';

XmlDocument _xml(LegacyWordDocument document) {
  final result = convertLegacyWordDocument(document);
  final archive = ZipDecoder().decodeBytes(result.bytes);
  return XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content),
  );
}

void main() {
  test('Word FOPT origins override per axis without rewriting SPA offsets', () {
    for (var origin = 0; origin < 4; origin++) {
      final document = parseLegacyWordDocument(
        officeArtShapeWordFixture(
          values: {0x0390: origin, 0x0392: origin},
          anchorBounds: (-413, 827, 1027, 1547),
        ),
      );
      final drawing = document.media.drawings.single;
      final position = drawing.shape!.position!;
      expect(position.horizontalRelativeTo, origin);
      expect(position.verticalRelativeTo, origin);
      expect([drawing.horizontalOrigin, drawing.verticalOrigin], [1, 2]);
      expect([drawing.leftTwips, drawing.topTwips], [-413, 827]);
      expect(drawing.shape!.unsupportedProperties, isEmpty);
      final xml = _xml(document);
      final shape = xml.findAllElements('shape', namespace: _v).single;
      final style = shape.getAttribute('style')!;
      expect(style, contains('margin-left:-20.65pt;margin-top:41.35pt;'));
      expect(
        style,
        contains(
          'mso-position-horizontal-relative:'
          '${['margin', 'page', 'text', 'char'][origin]};',
        ),
      );
      expect(
        style,
        contains(
          'mso-position-vertical-relative:'
          '${['margin', 'page', 'text', 'line'][origin]};',
        ),
      );
      final wrap = xml.findAllElements('wrap', namespace: _w10).single;
      expect(
        wrap.getAttribute('anchorx'),
        origin < 3 ? ['margin', 'page', 'text'][origin] : null,
      );
      expect(
        wrap.getAttribute('anchory'),
        origin < 3 ? ['margin', 'page', 'text'][origin] : null,
      );
    }
  });

  test('an absent explicit axis retains its distinct SPA origin', () {
    final document = parseLegacyWordDocument(
      officeArtShapeWordFixture(values: {0x0392: 0}),
    );
    final position = document.media.drawings.single.shape!.position!;
    expect(position.horizontalRelativeTo, isNull);
    expect(position.verticalRelativeTo, 0);
    final style = _xml(
      document,
    ).findAllElements('shape', namespace: _v).single.getAttribute('style')!;
    expect(style, contains('mso-position-horizontal-relative:page;'));
    expect(style, contains('mso-position-vertical-relative:margin;'));
  });

  test('DrawingML retains signed offsets and maps each documented origin', () {
    for (var origin = 0; origin < 4; origin++) {
      final xml = _xml(
        parseLegacyWordDocument(
          floatingPictureWordFixture(
            imageProperties: {0x0390: origin, 0x0392: origin},
            anchorBounds: (937, -257, 2377, 463),
          ),
        ),
      );
      final h = xml.findAllElements('positionH', namespace: _wp).single;
      final v = xml.findAllElements('positionV', namespace: _wp).single;
      expect(
        h.getAttribute('relativeFrom'),
        ['margin', 'page', 'column', 'character'][origin],
      );
      expect(
        v.getAttribute('relativeFrom'),
        ['margin', 'page', 'paragraph', 'line'][origin],
      );
      expect(h.getElement('posOffset', namespace: _wp)!.innerText, '594995');
      expect(v.getElement('posOffset', namespace: _wp)!.innerText, '-163195');
    }
  });

  test('alignment modes stay native instead of becoming cached offsets', () {
    for (var mode = 1; mode <= 5; mode++) {
      final xml = _xml(
        parseLegacyWordDocument(
          floatingPictureWordFixture(
            imageProperties: {0x038f: mode, 0x0390: 1, 0x0391: mode, 0x0392: 0},
          ),
        ),
      );
      final h = xml.findAllElements('positionH', namespace: _wp).single;
      final v = xml.findAllElements('positionV', namespace: _wp).single;
      expect(
        h.getElement('align', namespace: _wp)!.innerText,
        ['', 'left', 'center', 'right', 'inside', 'outside'][mode],
      );
      expect(
        v.getElement('align', namespace: _wp)!.innerText,
        ['', 'top', 'center', 'bottom', 'inside', 'outside'][mode],
      );
      expect(h.findElements('posOffset', namespace: _wp), isEmpty);
      expect(v.findElements('posOffset', namespace: _wp), isEmpty);
    }
  });

  test(
    'unknown raw origins remain evidence and never select an enum alias',
    () {
      final document = parseLegacyWordDocument(
        floatingPictureWordFixture(
          imageProperties: {0x0390: 4, 0x0392: 0xffffffff, 0x038f: 6},
        ),
      );
      final shape = document.media.drawings.single.shape!;
      expect(shape.position!.horizontalRelativeTo, 4);
      expect(shape.position!.verticalRelativeTo, 0xffffffff);
      expect(shape.position!.horizontalMode, 6);
      expect(
        shape.unsupportedProperties,
        containsAll([0x038f, 0x0390, 0x0392]),
      );
      expect(
        document.warnings,
        contains(LegacyWordWarning.floatingObjectsOmitted),
      );
      final xml = _xml(document);
      expect(
        xml
            .findAllElements('positionH', namespace: _wp)
            .single
            .getAttribute('relativeFrom'),
        'page',
      );
      expect(
        xml
            .findAllElements('positionV', namespace: _wp)
            .single
            .getAttribute('relativeFrom'),
        'paragraph',
      );
    },
  );

  test(
    'complex position records remain unsupported instead of being decoded',
    () {
      final document = parseLegacyWordDocument(
        officeArtShapeWordFixture(
          complex: {
            0x0390: Uint8List.fromList([1, 0, 0, 0]),
          },
        ),
      );
      final shape = document.media.drawings.single.shape!;
      expect(shape.position!.horizontalRelativeTo, isNull);
      expect(shape.unsupportedProperties, contains(0x0390));
      expect(_xml(document).findAllElements('shape', namespace: _v), isEmpty);
    },
  );

  for (final name in [
    'linked-textboxes.doc',
    'linked-textboxes-extended.doc',
  ]) {
    test('native $name keeps authored positions and explicit page origins', () {
      final document = parseLegacyWordDocument(
        File('test/fixtures/word_native/$name').readAsBytesSync(),
      );
      final drawings = document.media.drawings
          .where((drawing) => drawing.textboxId != null)
          .toList();
      final boxes = _xml(
        document,
      ).findAllElements('rect', namespace: _v).toList();
      expect(drawings, hasLength(2));
      expect(boxes, hasLength(2));
      for (var index = 0; index < 2; index++) {
        final drawing = drawings[index];
        expect(drawing.shape!.position!.horizontalRelativeTo, 1);
        expect(drawing.shape!.position!.verticalRelativeTo, 1);
        final style = boxes[index].getAttribute('style')!;
        expect(style, contains('mso-position-horizontal-relative:page;'));
        expect(style, contains('mso-position-vertical-relative:page;'));
        expect(style, contains('margin-left:${drawing.leftTwips / 20}pt;'));
        expect(style, contains('margin-top:${drawing.topTwips / 20}pt;'));
      }
    });
  }

  test(
    'independent Word16 binary retains its explicit page-relative images',
    () {
      final bytes = File(
        'test/fixtures/word_native/word16-page-origin.doc',
      ).readAsBytesSync();
      final document = parseLegacyWordDocument(bytes);
      final drawings = {for (final d in document.media.drawings) d.shapeId: d};
      expect(drawings.keys, containsAll([1026, 1027]));
      expect(drawings[1026]!.topTwips, 45);
      expect(drawings[1027]!.topTwips, 594);
      for (final drawing in drawings.values) {
        expect(drawing.verticalOrigin, 1);
        expect(drawing.shape!.position!.verticalRelativeTo, 1);
      }
      for (final position in _xml(
        document,
      ).findAllElements('positionV', namespace: _wp)) {
        expect(position.getAttribute('relativeFrom'), 'page');
      }
    },
  );

  test('independent Word14 binary contains zero-valued margin FOPT', () {
    // This source observation is independent of the production enum reader.
    // Whole-document handling and the ignored spare-range recovery have their
    // own tests in legacy_word_textbox_spare_test.dart.
    final file = BoundedCfbReader(
      File(
        'test/fixtures/word_native/word14-margin-origin.doc',
      ).readAsBytesSync(),
    );
    final table = file.readPath('1Table')!;
    expect(table.sublist(16168, 16174), [0x90, 0x03, 0, 0, 0, 0]);
    final spa = ByteData.sublistView(table, 28138, 28164);
    expect(spa.getUint32(0, Endian.little), 1028);
    expect((spa.getUint16(20, Endian.little) >> 1) & 3, 0);
    expect(spa.getInt32(4, Endian.little), 5460);
  });
}
