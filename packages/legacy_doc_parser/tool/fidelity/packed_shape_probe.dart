// SPDX-License-Identifier: MPL-2.0
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/media_word_fixture.dart';
import '../../test/support/officeart_shape_fixture.dart';
import '../../test/support/structured_word_fixture.dart';

/// Equivalent independently authored OfficeArt POINT encodings. No expected
/// coordinates are read back from the converter to construct these sources.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError(
      'Usage: dart run tool/fidelity/packed_shape_probe.dart NEW_DIRECTORY',
    );
  }
  final directory = Directory(arguments.single);
  if (directory.existsSync()) throw ArgumentError('Output already exists.');
  directory.createSync(recursive: true);
  const points = [(-100, -200), (300, -200), (300, 0), (100, 400), (-100, 400)];
  const values = {
    0x0140: -100,
    0x0141: -200,
    0x0142: 300,
    0x0143: 400,
    0x0181: 0x00cc6633,
    0x01c0: 0x00000000,
    0x01cb: 25400,
  };
  for (final (flip, bits) in [('none', 0), ('xy', 0xc0)]) {
    for (final encoding in ['full', 'packed', 'packed-header-excluded']) {
      final vertices = encoding == 'full'
          ? shapeVertices(points)
          : shapeArray(0xfff0, [
              for (final (x, y) in points) [...wordU16(x), ...wordU16(y)],
            ]);
      final bytes = officeArtShapeWordFixture(
        type: 0,
        flags: 0x0a00 | bits,
        rawPropertyRecord: shapePropertyRecord(
          values: values,
          complex: {
            0x0145: vertices,
            0x0146: shapeSegments([0x4000, 0x0001, 0x2001, 0x6001, 0x8000]),
          },
          complexLengths: {
            if (encoding == 'packed-header-excluded')
              0x0145: vertices.length - 6,
          },
        ),
        // MS-ODRAW 2.2.11 places these Word position properties in tertiary
        // FOPT. Native DOC consumers do not necessarily consult ordinary FOPT
        // for them, even when the numeric property IDs are identical.
        additionalProperties: [
          officeArtRecord(
            0xf122,
            [
              for (final entry in const {
                0x038f: 0,
                0x0390: 1,
                0x0391: 0,
                0x0392: 1,
              }.entries) ...[...wordU16(entry.key), ...wordU32(entry.value)],
            ],
            version: 3,
            instance: 4,
          ),
        ],
      );
      final name = '$encoding-$flip';
      File('${directory.path}/$name.doc').writeAsBytesSync(bytes);
      File(
        '${directory.path}/$name.docx',
      ).writeAsBytesSync(convertLegacyWord(bytes).bytes);
    }
  }
}
