// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

const imageAppearanceCases = [
  'inline-horizontal',
  'floating-control',
  'floating-horizontal',
  'floating-vertical',
  'floating-both',
  'floating-quarter',
  'floating-negative-quarter',
  'floating-margin-quarter',
  'floating-outline-shadow',
];

Map<String, Object?> _shape(LegacyWordOfficeArtShape? shape) => shape == null
    ? const {}
    : {
        'rotationFixed16': shape.rotationFixed16,
        'flipHorizontal': shape.flipHorizontal,
        'flipVertical': shape.flipVertical,
        'unsupportedProperties': shape.unsupportedProperties,
        if (shape.line case final line?)
          'line': {
            'enabled': line.enabled,
            'type': line.type,
            'color': line.color,
            'widthEmu': line.widthEmu,
            'opacityFixed16': line.opacityFixed16,
            'dash': line.dash,
            'join': line.join,
            'cap': line.cap,
          },
        if (shape.shadow case final shadow?)
          'shadow': {
            'enabled': shadow.enabled,
            'type': shadow.type,
            'color': shadow.color,
            'opacityFixed16': shadow.opacityFixed16,
            'offsetXEmu': shadow.offsetXEmu,
            'offsetYEmu': shadow.offsetYEmu,
            'obscured': shadow.obscured,
          },
      };

void main(List<String> arguments) {
  if (arguments.length != 1 && arguments.length != 2) {
    throw ArgumentError(
      'Usage: image_appearance_probe.dart [source-folder] output-folder',
    );
  }
  final source = Directory(
    arguments.length == 2
        ? arguments.first
        : 'test/fixtures/fidelity/image-appearance/binary',
  );
  final output = Directory(arguments.last);
  if (output.existsSync()) {
    throw ArgumentError('Output must be a new directory.');
  }
  output.createSync(recursive: true);
  final records = <String, Object?>{};
  for (final name in imageAppearanceCases) {
    final bytes = File('${source.path}/$name.doc').readAsBytesSync();
    final document = parseLegacyWordDocument(bytes);
    final conversion = convertLegacyWordDocument(document);
    File('${output.path}/$name.docx').writeAsBytesSync(conversion.bytes);
    records[name] = {
      'pictures': [
        for (final picture in document.media.pictures)
          {
            'cp': picture.cp,
            'imageId': picture.imageId,
            'widthTwips': picture.widthTwips,
            'heightTwips': picture.heightTwips,
            'shape': _shape(picture.shape),
          },
      ],
      'drawings': [
        for (final drawing in document.media.drawings)
          {
            'cp': drawing.anchorCp,
            'imageId': drawing.imageId,
            'shapeId': drawing.shapeId,
            'anchorTwips': [
              drawing.leftTwips,
              drawing.topTwips,
              drawing.rightTwips,
              drawing.bottomTwips,
            ],
            'horizontalOrigin': drawing.horizontalOrigin,
            'verticalOrigin': drawing.verticalOrigin,
            'horizontalRelativeTo':
                drawing.shape?.position?.horizontalRelativeTo,
            'verticalRelativeTo': drawing.shape?.position?.verticalRelativeTo,
            'shape': _shape(drawing.shape),
          },
      ],
      'counts': conversion.preservedCounts,
      'limitations': conversion.limitations.map((value) => value.name).toList(),
    };
  }
  File('${output.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(records)}\n',
  );
}
