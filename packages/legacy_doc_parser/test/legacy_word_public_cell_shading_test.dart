// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../tool/public_cell_shading_web_acceptance.dart';
import 'support/public_cell_shading_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void main() {
  test('shared cell shading acceptance also passes on the VM', () {
    expect(verifyPublicCellShadingWebAcceptance(), {
      'cases': 9,
      'htmlPreviews': 9,
      'unmappedEvidenceCases': 2,
      'malformedInputsRejected': 2,
    });
  });

  for (final item in publicCellShadingCases) {
    test('cell shading model preserves ${item.name}', () {
      final table = item.document().blocks.single as LegacyWordTable;
      final cell = table.rows.single.cells.single;
      expect(cell.shading, same(item.expected));
      expect(cell.formatting.shading, same(item.formatting));
    });

    test('cell shading DOCX preserves ${item.name}', () {
      final archive = ZipDecoder().decodeBytes(
        convertLegacyWordDocument(item.document()).bytes,
      );
      final xml = XmlDocument.parse(
        utf8.decode(archive.findFile('word/document.xml')!.content),
      );
      final shading = xml.findAllElements('shd', namespace: _w);
      final expected = item.expected;
      if (expected == null || expected.pattern == null) {
        expect(shading, isEmpty);
      } else {
        expect(shading, hasLength(1));
        expect(
          shading.single.getAttribute('val', namespace: _w),
          expected.pattern,
        );
        expect(
          shading.single.getAttribute('color', namespace: _w),
          expected.foregroundHex ?? 'auto',
        );
        expect(
          shading.single.getAttribute('fill', namespace: _w),
          expected.backgroundHex ?? 'auto',
        );
      }
      if (expected != null && expected.pattern == null) {
        final manifest = archive.findFile('word/evidence/manifest.json');
        expect(manifest, isNotNull);
        final evidence =
            jsonDecode(utf8.decode(manifest!.content)) as Map<String, dynamic>;
        final records = evidence['records'] as List<dynamic>;
        final record = records.cast<Map<String, dynamic>>().singleWhere(
          (entry) => entry['kind'] == 'shading',
        );
        expect(record['scope'], 'tableCell');
        expect(record['rawPattern'], expected.rawPattern);
        expect(record['foregroundHex'], expected.foregroundHex);
        expect(record['backgroundHex'], expected.backgroundHex);
      }
    });

    test('public HTML cell shading preserves ${item.name}', () {
      final html = renderLegacyWordHtml(item.document().blocks);
      if (item.previewColor == null) {
        expect(html, isNot(contains('background-color:')));
      } else {
        expect(html, contains('background-color:#${item.previewColor}'));
      }
      expect(
        html.contains('data-word-shading="approximate"'),
        item.approximatePreview,
      );
      expect(html, contains('A'));
    });
  }

  test('malformed formatting-only shading cannot bypass DOCX validation', () {
    final document = publicCellShadingDocument(
      formatting: const LegacyWordShading(
        pattern: 'invented-pattern',
        backgroundHex: 'FF0000',
      ),
    );
    expect(() => convertLegacyWordDocument(document), throwsFormatException);
  });

  test('malformed formatting-only color cannot bypass DOCX validation', () {
    final document = publicCellShadingDocument(
      formatting: const LegacyWordShading(
        pattern: 'clear',
        backgroundHex: 'not-a-color',
      ),
    );
    expect(
      () => convertLegacyWordDocument(document),
      throwsA(isA<LegacyWordConversionException>()),
    );
  });
}
