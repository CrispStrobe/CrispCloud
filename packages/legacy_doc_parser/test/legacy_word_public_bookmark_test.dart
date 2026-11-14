// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../tool/public_bookmark_web_acceptance.dart';
import 'support/public_bookmark_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void main() {
  test('shared public bookmark acceptance also passes on the VM', () {
    expect(verifyPublicBookmarkWebAcceptance(), {
      'visibleCases': 18,
      'auxiliaryOwnerCases': 7,
      'hiddenEvidenceCases': 3,
      'malformedInputsRejected': 34,
      'convertedPackages': 21,
      'sourceMetadataUnchanged': true,
    });
  });

  for (final hidden in [false, true]) {
    for (final mutation in publicBookmarkInvalidCases) {
      test('public bookmark $mutation hidden=$hidden rejects', () {
        expect(
          () => convertLegacyWordDocument(
            publicBookmarkDocument(mutation, hidden: hidden),
          ),
          throwsA(
            anyOf(isA<FormatException>(), isA<LegacyWordConversionException>()),
          ),
        );
      });
    }
  }
  for (final mutation in publicBookmarkValidCases) {
    test('public bookmark $mutation retains its name and range', () {
      final document = publicBookmarkDocument(mutation);
      final result = convertLegacyWordDocument(document);
      final archive = ZipDecoder().decodeBytes(result.bytes);
      final part = publicBookmarkOutputPart(mutation);
      final xml = XmlDocument.parse(
        utf8.decode(archive.findFile(part)!.content),
      );
      final start = xml.findAllElements('bookmarkStart', namespace: _w).single;
      final end = xml.findAllElements('bookmarkEnd', namespace: _w).single;
      final source = document.bookmarks.single;
      expect(start.getAttribute('name', namespace: _w), source.name);
      expect(
        start.getAttribute('id', namespace: _w),
        end.getAttribute('id', namespace: _w),
      );
      expect(
        start.getAttribute('colFirst', namespace: _w),
        source.firstCell?.toString(),
      );
      expect(
        start.getAttribute('colLast', namespace: _w),
        source.lastCell?.toString(),
      );
      expect(result.preservedCounts['bookmarks'], 1);
    });
  }
  for (final mutation in ['valid', 'first-column', 'last-column']) {
    test('hidden valid bookmark $mutation retains complete inert metadata', () {
      final document = publicBookmarkDocument(mutation, hidden: true);
      final result = convertLegacyWordDocument(document);
      final archive = ZipDecoder().decodeBytes(result.bytes);
      final xml = XmlDocument.parse(
        utf8.decode(archive.findFile('word/document.xml')!.content),
      );
      expect(xml.findAllElements('bookmarkStart', namespace: _w), isEmpty);
      final manifest =
          jsonDecode(
                utf8.decode(
                  archive.findFile('word/evidence/manifest.json')!.content,
                ),
              )
              as Map;
      final record = (manifest['records'] as List).cast<Map>().singleWhere(
        (record) => record['kind'] == 'bookmark',
      );
      final source = document.bookmarks.single;
      expect(record['name'], source.name);
      expect(
        (record['startCp'], record['endCp']),
        (source.startCp, source.endCp),
      );
      expect(
        (record['firstCell'], record['lastCell']),
        (source.firstCell, source.lastCell),
      );
      expect(result.preservedCounts['bookmarks'] ?? 0, 0);
    });
  }
}
