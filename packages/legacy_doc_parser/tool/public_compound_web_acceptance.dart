// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/public_compound_fixture.dart';

Map<String, Object?> verifyPublicCompoundWebAcceptance() {
  var active = 0, inert = 0;
  for (final kind in publicCompoundKinds) {
    for (final mutation in publicCompoundMutationsFor(kind)) {
      final label = '$kind/$mutation';
      final document = publicCompoundDocument(kind, mutation);
      final source = kind == 'ole'
          ? document.media.embeddedObjects.single.storage.bytes
          : document.media.vbaProjects.single.storage.bytes;
      final original = source.toList();
      final result = convertLegacyWordDocument(
        document,
        format: LegacyWordOutputFormat.docm,
      );
      final archive = ZipDecoder().decodeBytes(result.bytes);
      final native = archive.findFile(
        kind == 'ole'
            ? 'word/embeddings/oleObject1.bin'
            : 'word/vbaProject.bin',
      );
      final valid = mutation == 'valid';
      if ((native != null) != valid) {
        throw StateError('$label unexpected native binary part');
      }
      var nativeRelations = 0;
      for (final file in archive.files.where((f) => f.name.endsWith('.rels'))) {
        final xml = XmlDocument.parse(utf8.decode(file.content));
        for (final relation in xml.rootElement.childElements) {
          if (relation.getAttribute('TargetMode') == 'External') {
            throw StateError('$label unexpected external relationship');
          }
          if (relation
                  .getAttribute('Type')
                  ?.endsWith(kind == 'ole' ? '/oleObject' : '/vbaProject') ==
              true) {
            nativeRelations++;
          }
        }
      }
      if (nativeRelations != (valid ? 1 : 0)) {
        throw StateError('$label unexpected native binary relationship');
      }
      if (valid) {
        _equal(native!.content, original, label);
        active++;
      } else {
        final manifest =
            jsonDecode(
                  utf8.decode(
                    archive.findFile('word/evidence/manifest.json')!.content,
                  ),
                )
                as Map;
        final record = (manifest['records'] as List).cast<Map>().singleWhere(
          (r) => r['kind'] == (kind == 'ole' ? 'embeddedObject' : 'vbaProject'),
        );
        _equal(
          archive.findFile(record['part'] as String)!.content,
          original,
          label,
        );
        if (!result.limitations.contains(
          kind == 'ole'
              ? LegacyWordConversionLimitation.embeddedObjects
              : LegacyWordConversionLimitation.macrosSignatures,
        )) {
          throw StateError('$label missing conversion limitation');
        }
        inert++;
      }
      _equal(source, original, '$label source');
    }
  }
  return {
    'cases': active + inert,
    'activeContainers': active,
    'inertContainers': inert,
    'sourceUnchanged': true,
    'rawEvidencePreserved': true,
    'externalRelationships': false,
    'vbaCodeValidityClaimed': false,
    'fullCfbConformanceClaimed': false,
  };
}

void _equal(List<int> actual, List<int> expected, String label) {
  if (actual.length != expected.length) throw StateError('$label byte length');
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) throw StateError('$label byte $i');
  }
}
