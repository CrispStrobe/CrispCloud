// SPDX-License-Identifier: MPL-2.0
// Public model boundaries must behave identically on the VM and compiled JS.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/public_metafile_fixture.dart';

Map<String, Object?> verifyPublicMetafileWebAcceptance() {
  var active = 0, inert = 0;
  for (final format in [LegacyWordImageFormat.emf, LegacyWordImageFormat.wmf]) {
    for (final placement in publicMetafilePlacements) {
      for (final mutation in publicMetafileMutations) {
        final label = '${format.name}/$placement/$mutation';
        final model = publicMetafileDocument(format, mutation, placement);
        final original = model.media.assets.single.bytes.toList();
        final result = convertLegacyWordDocument(model);
        final archive = ZipDecoder().decodeBytes(result.bytes);
        final images = archive.files.where(
          (f) => f.name.startsWith('word/media/'),
        );
        final valid = mutation == 'valid';
        if (images.length != (valid ? 1 : 0)) {
          throw StateError('$label unexpected native image parts');
        }
        var imageRelations = 0;
        for (final file in archive.files.where(
          (f) => f.name.endsWith('.rels'),
        )) {
          final xml = XmlDocument.parse(utf8.decode(file.content));
          for (final relation in xml.rootElement.childElements) {
            if (relation.getAttribute('TargetMode') == 'External') {
              throw StateError('$label unexpected external relationship');
            }
            if (relation.getAttribute('Type')?.endsWith('/image') == true) {
              imageRelations++;
            }
          }
        }
        if (imageRelations != (valid ? 1 : 0)) {
          throw StateError('$label unexpected native image relationship');
        }
        if (valid) {
          _equal(images.single.content, original, label);
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
            (r) => r['kind'] == 'imageAsset',
          );
          _equal(
            archive.findFile(record['part'] as String)!.content,
            original,
            label,
          );
          if (!result.limitations.contains(
            LegacyWordConversionLimitation.images,
          )) {
            throw StateError('$label missing conversion limitation');
          }
          inert++;
        }
        _equal(model.media.assets.single.bytes, original, '$label source');
      }
    }
  }
  return {
    'cases': active + inert,
    'activeImages': active,
    'inertImages': inert,
    'sourceUnchanged': true,
    'rawEvidencePreserved': true,
    'externalRelationships': false,
  };
}

void _equal(List<int> actual, List<int> expected, String label) {
  if (actual.length != expected.length) throw StateError('$label byte length');
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) throw StateError('$label byte $i');
  }
}
