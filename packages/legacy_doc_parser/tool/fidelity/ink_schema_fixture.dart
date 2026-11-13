// SPDX-License-Identifier: MPL-2.0
// OfficeArt wrappers are independently authored fixture records. Their ISFs
// are exact outputs of the separately retained actual Windows WPF oracle.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/officeart_shape_fixture.dart';
import '../../test/support/structured_word_fixture.dart';

const inkSchemaCases = [
  'polyline-solid',
  'single-dot',
  'paint-ellipse-alpha',
  'multiple-strokes',
  'pressure-ramp',
  'signed-quantization',
];

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Expected a new output directory.');
  }
  final repository = File.fromUri(Platform.script).parent.parent.parent;
  final directory = Directory(arguments.single);
  if (directory.existsSync()) throw ArgumentError('Output already exists.');
  directory.createSync(recursive: true);
  final records = <Map<String, Object?>>[];
  for (final name in inkSchemaCases) {
    for (final mode in ['compressed', 'uncompressed']) {
      final payload = File(
        '${repository.path}/test/fixtures/ink_wpf/$name/$mode.isf',
      ).readAsBytesSync();
      final source = officeArtShapeWordFixture(
        values: {0x073f: 0x00090009},
        complex: {
          0x0700: Uint8List.fromList([
            0x34,
            0x1a,
            0x7c,
            0x93,
            0x1d,
            0x15,
            0x10,
            0x46,
            0x9c,
            0xa6,
            0xa8,
            0xcc,
            0x9b,
            0xdb,
            0x5d,
            0x83,
            ...wordU32(payload.length),
            ...payload,
          ]),
        },
      );
      final document = parseLegacyWordDocument(source);
      final ink = document.media.drawings.single.shape!.ink!;
      final decoded = ink.decoding!;
      if (decoded.status != LegacyWordInkDecodeStatus.decoded ||
          decoded.strokes.isEmpty ||
          base64Encode(ink.data!) != base64Encode(payload)) {
        throw StateError(
          'ISF source retention or complete decode failed: $name-$mode',
        );
      }
      final converted = convertLegacyWordDocument(document);
      File('${directory.path}/$name-$mode.doc').writeAsBytesSync(source);
      File(
        '${directory.path}/$name-$mode.docx',
      ).writeAsBytesSync(converted.bytes);
      records.add({
        'name': '$name-$mode',
        'strokeCount': decoded.strokes.length,
        'pointCount': decoded.pointCount,
        'sourceIsfBase64': base64Encode(payload),
        'preservedCounts': converted.preservedCounts,
        'nativeInkEmitted': false,
      });
    }
  }
  File('${directory.path}/ink-cases.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(records)}\n',
  );
}
