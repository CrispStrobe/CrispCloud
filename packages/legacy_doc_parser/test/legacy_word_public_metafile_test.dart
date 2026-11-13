// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/public_metafile_fixture.dart';
import 'support/metafile_fixture.dart';
import 'support/structured_word_fixture.dart';

void main() {
  for (final format in [LegacyWordImageFormat.emf, LegacyWordImageFormat.wmf]) {
    for (final placement in publicMetafilePlacements) {
      for (final mutation in publicMetafileMutations) {
        test('${format.name} $placement verifies $mutation raw bytes', () {
          final model = publicMetafileDocument(format, mutation, placement);
          final original = model.media.assets.single.bytes.toList();
          final result = convertLegacyWordDocument(model);
          final archive = ZipDecoder().decodeBytes(result.bytes);
          final images = archive.files.where(
            (f) => f.name.startsWith('word/media/'),
          );
          final valid = mutation == 'valid';
          expect(images, hasLength(valid ? 1 : 0));
          final relations = archive.files
              .where((f) => f.name.endsWith('.rels'))
              .expand(
                (f) => XmlDocument.parse(
                  utf8.decode(f.content),
                ).rootElement.childElements,
              )
              .where((e) => e.getAttribute('Type')?.endsWith('/image') == true);
          expect(relations, hasLength(valid ? 1 : 0));
          if (valid) {
            expect(images.single.content, orderedEquals(original));
          } else {
            final manifest =
                jsonDecode(
                      utf8.decode(
                        archive
                            .findFile('word/evidence/manifest.json')!
                            .content,
                      ),
                    )
                    as Map;
            final record = (manifest['records'] as List)
                .cast<Map>()
                .singleWhere((r) => r['kind'] == 'imageAsset');
            expect(
              archive.findFile(record['part'] as String)!.content,
              orderedEquals(original),
            );
            expect(
              result.limitations,
              contains(LegacyWordConversionLimitation.images),
            );
          }
          expect(model.media.assets.single.bytes, orderedEquals(original));
        });
      }
    }
    test('${format.name} metadata may still veto otherwise valid bytes', () {
      final model = publicMetafileDocument(
        format,
        'valid',
        'inline',
        metadataAllowsEmbedding: false,
      );
      final archive = ZipDecoder().decodeBytes(
        convertLegacyWordDocument(model).bytes,
      );
      expect(
        archive.files.where((f) => f.name.startsWith('word/media/')),
        isEmpty,
      );
    });
    test('${format.name} repeated references share validated image part', () {
      // Revalidating every occurrence would exceed the 64 MiB scan budget.
      // One immutable 1 MiB image remains within both scan/package limits.
      final data = List<int>.filled(1024 * 1024, 0);
      final bytes = format == LegacyWordImageFormat.emf
          ? emfFixture(
              records: [
                emfRecord(70, [...wordU32(data.length), ...data]),
              ],
            )
          : wmfFixture(records: [wmfRecord(0x7777, data)]);
      final result = convertLegacyWordDocument(
        publicMetafileDocument(
          format,
          'valid',
          'inline',
          references: 100,
          rawBytes: bytes,
        ),
      );
      final archive = ZipDecoder().decodeBytes(result.bytes);
      expect(
        archive.files.where((f) => f.name.startsWith('word/media/')),
        hasLength(1),
      );
      expect(result.preservedCounts['pictureReferences'], 100);
    });
  }
}
