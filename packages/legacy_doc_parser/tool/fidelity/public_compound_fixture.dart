// SPDX-License-Identifier: MPL-2.0
// Standalone public-model corpus. Raw CFB storage inputs are not DOC documents;
// schema validation does not validate or execute their OLE or VBA contents.

import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/public_compound_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply a new output directory.');
  }
  final root = Directory(arguments.single);
  if (root.existsSync()) throw ArgumentError('Output already exists.');
  root.createSync(recursive: true);
  final cases = <Map<String, Object>>[];
  for (final kind in publicCompoundKinds) {
    for (final mutation in publicCompoundMutationsFor(kind)) {
      final name = '$kind-$mutation';
      final model = publicCompoundDocument(kind, mutation);
      final storage = kind == 'ole'
          ? model.media.embeddedObjects.single.storage
          : model.media.vbaProjects.single.storage;
      File('${root.path}/$name.bin').writeAsBytesSync(storage.bytes);
      File('${root.path}/$name.docm').writeAsBytesSync(
        convertLegacyWordDocument(
          model,
          format: LegacyWordOutputFormat.docm,
        ).bytes,
      );
      cases.add({
        'name': name,
        'inputKind': 'public-model-compound-storage',
        'kind': kind,
        'mutation': mutation,
        'suppliedPositiveActivationMetadata': true,
        'separateStreamMetadataIsSynthetic': true,
        'expectedActiveContainer': mutation == 'valid',
        'source': '$name.bin',
        'output': '$name.docm',
        'codeValidityClaimed': false,
      });
    }
  }
  File(
    '${root.path}/cases.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(cases)}\n');
}
