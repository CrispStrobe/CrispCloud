// SPDX-License-Identifier: MPL-2.0
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

/// Adapter only. The Python author supplies binary goals/scales and expected
/// dimensions without importing the parser or its binary fixture writers.
void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw ArgumentError(
      'Usage: dart run tool/fidelity/picture_sizing_probe.dart INPUT OUTPUT',
    );
  }
  final output = Directory(arguments[1]);
  if (output.existsSync()) throw ArgumentError('Output already exists.');
  output.createSync(recursive: true);
  final records = <String, Object>{};
  final files = Directory(arguments[0]).listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files.where((file) => file.path.endsWith('.doc'))) {
    final name = file.uri.pathSegments.last.replaceFirst(RegExp(r'\.doc$'), '');
    final document = parseLegacyWordDocument(file.readAsBytesSync());
    final picture = document.media.pictures.single;
    final result = convertLegacyWordDocument(document);
    File('${output.path}/$name.docx').writeAsBytesSync(result.bytes);
    records[name] = {
      'widthTwips': picture.widthTwips,
      'heightTwips': picture.heightTwips,
      'cropFixed16': [
        picture.cropLeftFixed16,
        picture.cropTopFixed16,
        picture.cropRightFixed16,
        picture.cropBottomFixed16,
      ],
      'counts': result.preservedCounts,
    };
  }
  File('${output.path}/model.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(records)}\n',
  );
}
