// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

/// Portable producer for the retained independently generated native DOC.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Usage: shape_context_probe.dart NEW_DIRECTORY');
  }
  final output = Directory(arguments.single);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  final bytes = File(
    'test/fixtures/fidelity/officeart-shapes.doc',
  ).readAsBytesSync();
  final document = parseLegacyWordDocument(bytes);
  final converted = convertLegacyWordDocument(document);
  output.createSync(recursive: true);
  File(
    '${output.path}/officeart-shapes.docx',
  ).writeAsBytesSync(converted.bytes);
  final manifest = {
    'sourceBytes': bytes.length,
    'convertedBytes': converted.bytes.length,
    'counts': converted.preservedCounts,
    'limitations': converted.limitations.map((value) => value.name).toList(),
    'drawings': [
      for (final drawing in document.media.drawings)
        {
          'shapeId': drawing.shapeId,
          'anchorTwips': [
            drawing.leftTwips,
            drawing.topTwips,
            drawing.rightTwips,
            drawing.bottomTwips,
          ],
          'type': drawing.shape!.type,
          'groupShapeBooleanProperties':
              drawing.shape!.groupShapeBooleanProperties,
          'layoutInCell': drawing.shape!.layoutInCell,
          'unsupportedProperties': drawing.shape!.unsupportedProperties,
          'geometry': drawing.shape!.geometry?.preset ?? 'customPath',
          'editingHints': [
            for (final hint in drawing.shape!.geometry!.editingHints)
              {'vertexIndex': hint.vertexIndex, 'escape': hint.escape},
          ],
        },
    ],
  };
  File('${output.path}/manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
}
