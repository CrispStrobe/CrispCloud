// SPDX-License-Identifier: MPL-2.0
// Standalone public-model corpus: these inputs are not binary DOC documents.

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/public_metafile_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final cases = <Map<String, Object>>[];
  for (final format in [LegacyWordImageFormat.emf, LegacyWordImageFormat.wmf]) {
    for (final placement in publicMetafilePlacements) {
      for (final mutation in publicMetafileMutations) {
        final name = '${format.name}-$placement-$mutation';
        final model = publicMetafileDocument(format, mutation, placement);
        File(
          '${root.path}/$name.${format.name}',
        ).writeAsBytesSync(model.media.assets.single.bytes);
        File(
          '${root.path}/$name.docx',
        ).writeAsBytesSync(convertLegacyWordDocument(model).bytes);
        cases.add({
          'name': name,
          'format': format.name,
          'placement': placement,
          'mutation': mutation,
          'suppliedNativeEmbeddingAllowed': true,
          'expectedActiveImage': mutation == 'valid',
          'source': '$name.${format.name}',
          'output': '$name.docx',
        });
      }
    }
  }
  File(
    '${root.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
