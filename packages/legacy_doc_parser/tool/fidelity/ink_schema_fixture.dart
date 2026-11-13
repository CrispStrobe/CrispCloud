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
const inkHeaderSchemaCases = {
  'affine-transform':
      'affine-scale-translate-2-half-100-minus50-float-and-double/input.isf',
  'compact-translate': 'translate-100-minus50-float-and-double/input.isf',
  'pressure-2047-full': 'pressure-explicit-0-2047/input.isf',
  'pressure-2047-compact': 'pressure-explicit-0-2047/roundtrip.isf',
};

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Expected a new output directory.');
  }
  final repository = File.fromUri(Platform.script).parent.parent.parent;
  final directory = Directory(arguments.single);
  if (directory.existsSync()) throw ArgumentError('Output already exists.');
  directory.createSync(recursive: true);
  final records = <Map<String, Object?>>[];
  final fixtures = [
    for (final name in inkSchemaCases)
      for (final mode in ['compressed', 'uncompressed'])
        (name: '$name-$mode', path: 'ink_wpf/$name/$mode.isf'),
    for (final entry in inkHeaderSchemaCases.entries)
      (name: entry.key, path: 'ink_wpf_headers/${entry.value}'),
  ];
  for (final fixture in fixtures) {
    final name = fixture.name;
    final payload = File(
      '${repository.path}/test/fixtures/${fixture.path}',
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
      throw StateError('ISF source retention or complete decode failed: $name');
    }
    final converted = convertLegacyWordDocument(document);
    File('${directory.path}/$name.doc').writeAsBytesSync(source);
    File('${directory.path}/$name.docx').writeAsBytesSync(converted.bytes);
    records.add({
      'name': name,
      'strokeCount': decoded.strokes.length,
      'pointCount': decoded.pointCount,
      'sourceIsfBase64': base64Encode(payload),
      'preservedCounts': converted.preservedCounts,
      'nativeInkEmitted': false,
    });
  }
  File('${directory.path}/ink-cases.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(records)}\n',
  );
}
