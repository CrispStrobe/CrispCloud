// SPDX-License-Identifier: MPL-2.0
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/officeart_shape_fixture.dart';

/// Authored binary geometry, independent of the emitted VML path spelling.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError(
      'Usage: dart run tool/fidelity/shape_probe.dart NEW_DIRECTORY',
    );
  }
  final directory = Directory(arguments.single);
  if (directory.existsSync()) throw ArgumentError('Output already exists.');
  directory.createSync(recursive: true);
  for (final (name, type) in [('rect', 1), ('ellipse', 3), ('line', 20)]) {
    final bytes = officeArtShapeWordFixture(
      type: type,
      values: {0x0181: 0x00cc6633, 0x01c0: 0x00000000, 0x01cb: 25400},
    );
    File('${directory.path}/$name.doc').writeAsBytesSync(bytes);
    File(
      '${directory.path}/$name.docx',
    ).writeAsBytesSync(convertLegacyWord(bytes).bytes);
  }
  for (final axis in ['h', 'v']) {
    for (final (flip, bits) in [
      ('none', 0),
      ('x', 0x40),
      ('y', 0x80),
      ('xy', 0xc0),
    ]) {
      final name = 'line-$axis-$flip';
      final bytes = officeArtShapeWordFixture(
        type: 20,
        flags: 0x0a00 | bits,
        values: {0x01c0: 0x00000000, 0x01cb: 25400},
        anchorBounds: axis == 'h'
            ? (120, 240, 1560, 240)
            : (120, 240, 120, 960),
      );
      File('${directory.path}/$name.doc').writeAsBytesSync(bytes);
      File(
        '${directory.path}/$name.docx',
      ).writeAsBytesSync(convertLegacyWord(bytes).bytes);
    }
  }
  final custom = officeArtShapeWordFixture(
    type: 0,
    values: {
      0x0181: 0x00cc6633,
      0x01c0: 0x00000000,
      0x01cb: 25400,
      0x0140: -100,
      0x0141: -200,
      0x0142: 300,
      0x0143: 400,
    },
    complex: {
      0x0145: shapeVertices([
        (-100, -200),
        (300, -200),
        (300, 0),
        (100, 400),
        (-100, 400),
      ]),
      0x0146: shapeSegments([0x4000, 0x0001, 0x2001, 0x6001, 0x8000]),
    },
  );
  File('${directory.path}/custom.doc').writeAsBytesSync(custom);
  File(
    '${directory.path}/custom.docx',
  ).writeAsBytesSync(convertLegacyWord(custom).bytes);
}
