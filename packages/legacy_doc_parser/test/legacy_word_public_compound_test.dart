// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/public_compound_fixture.dart';

void main() {
  for (final kind in publicCompoundKinds) {
    for (final mutation in publicCompoundMutationsFor(kind)) {
      test('$kind native activation verifies $mutation container bytes', () {
        final document = publicCompoundDocument(kind, mutation);
        final storage = kind == 'ole'
            ? document.media.embeddedObjects.single.storage
            : document.media.vbaProjects.single.storage;
        final original = storage.bytes.toList();
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
        final relations = archive.files
            .where((f) => f.name.endsWith('.rels'))
            .expand(
              (f) => XmlDocument.parse(
                utf8.decode(f.content),
              ).rootElement.childElements,
            )
            .where(
              (e) =>
                  e
                      .getAttribute('Type')
                      ?.endsWith(
                        kind == 'ole' ? '/oleObject' : '/vbaProject',
                      ) ==
                  true,
            );
        if (mutation == 'valid') {
          expect(native?.content, orderedEquals(original));
          expect(relations, hasLength(1));
          expect(
            result.preservedCounts[kind == 'ole'
                ? 'embeddedObjects'
                : 'vbaProjects'],
            1,
          );
        } else {
          expect(native, isNull);
          expect(relations, isEmpty);
          final manifest =
              jsonDecode(
                    utf8.decode(
                      archive.findFile('word/evidence/manifest.json')!.content,
                    ),
                  )
                  as Map;
          final record = (manifest['records'] as List).cast<Map>().singleWhere(
            (r) =>
                r['kind'] == (kind == 'ole' ? 'embeddedObject' : 'vbaProject'),
          );
          expect(
            archive.findFile(record['part'] as String)!.content,
            orderedEquals(original),
          );
          expect(
            result.limitations,
            contains(
              kind == 'ole'
                  ? LegacyWordConversionLimitation.embeddedObjects
                  : LegacyWordConversionLimitation.macrosSignatures,
            ),
          );
        }
        expect(storage.bytes, orderedEquals(original));
      });
    }

    test('$kind negative metadata still vetoes valid bytes', () {
      final result = convertLegacyWordDocument(
        publicCompoundDocument(kind, 'valid', metadataAllowsEmbedding: false),
        format: LegacyWordOutputFormat.docm,
      );
      final archive = ZipDecoder().decodeBytes(result.bytes);
      expect(
        archive.findFile(
          kind == 'ole'
              ? 'word/embeddings/oleObject1.bin'
              : 'word/vbaProject.bin',
        ),
        isNull,
      );
    });
  }

  test('valid project remains inert when DOCX is requested', () {
    final result = convertLegacyWordDocument(
      publicCompoundDocument('vba', 'valid'),
    );
    final archive = ZipDecoder().decodeBytes(result.bytes);
    expect(archive.findFile('word/vbaProject.bin'), isNull);
    expect(result.format, LegacyWordOutputFormat.docx);
  });
}
