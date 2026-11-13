// SPDX-License-Identifier: MPL-2.0
// Read-only model and literal BLIP inspection for the retained Word14 source.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:legacy_doc_parser/src/bounded_cfb_reader.dart';

void main(List<String> arguments) {
  final path = arguments.single;
  final bytes = File(path).readAsBytesSync();
  final document = parseLegacyWordDocument(bytes);
  final cfb = BoundedCfbReader(bytes);
  final data = cfb.readPath('WordDocument');
  stdout.writeln(
    jsonEncode({
      'source': path,
      'sourceBytes': bytes.length,
      'drawings': [
        for (final drawing in document.media.drawings)
          {
            'shapeId': drawing.shapeId,
            'boundsTwips': [
              drawing.leftTwips,
              drawing.topTwips,
              drawing.rightTwips,
              drawing.bottomTwips,
            ],
            'shapeType': drawing.shape?.type,
            'sourceFlags': drawing.shape?.sourceFlags,
            'unsupportedProperties': drawing.shape?.unsupportedProperties,
            'fill': {
              'type': drawing.shape?.fill?.type,
              'enabled': drawing.shape?.fill?.enabled,
              'color': drawing.shape?.fill?.color,
              'opacity': drawing.shape?.fill?.opacityFixed16,
            },
            'line': {
              'type': drawing.shape?.line?.type,
              'enabled': drawing.shape?.line?.enabled,
              'widthEmu': drawing.shape?.line?.widthEmu,
              'dash': drawing.shape?.line?.dash,
              'opacity': drawing.shape?.line?.opacityFixed16,
            },
            'shadow': {
              'type': drawing.shape?.shadow?.type,
              'enabled': drawing.shape?.shadow?.enabled,
              'opacity': drawing.shape?.shadow?.opacityFixed16,
              'offset': [
                drawing.shape?.shadow?.offsetXEmu,
                drawing.shape?.shadow?.offsetYEmu,
              ],
            },
          },
      ],
      if (path.endsWith('word14-margin-origin.doc') && data != null)
        'retainedWord14DelayedBlips': [
          for (final offset in [3643, 5585, 5690])
            {
              'offset': offset,
              'stream': 'WordDocument',
              'header': data.sublist(offset, offset + 8),
              'length': ByteData.sublistView(
                data,
              ).getUint32(offset + 4, Endian.little),
              'prefix': data.sublist(offset + 8, offset + 105),
            },
        ],
    }),
  );
}
