// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/public_cell_shading_fixture.dart';

Map<String, int> verifyPublicCellShadingWebAcceptance() {
  const w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  var cases = 0, evidenceCases = 0;
  for (final item in publicCellShadingCases) {
    final document = item.document();
    final table = document.blocks.single as LegacyWordTable;
    final cell = table.rows.single.cells.single;
    final expected = item.expected;
    _require(
      _shadingRecord(cell.shading) == _shadingRecord(expected) &&
          _shadingRecord(cell.formatting.shading) ==
              _shadingRecord(item.formatting),
      'Public model shading changed: ${item.name}',
    );

    final archive = ZipDecoder().decodeBytes(
      convertLegacyWordDocument(document).bytes,
    );
    final xml = XmlDocument.parse(
      utf8.decode(archive.findFile('word/document.xml')!.content),
    );
    final shading = xml.findAllElements('shd', namespace: w).toList();
    if (expected == null || expected.pattern == null) {
      _require(shading.isEmpty, 'Invented active cell shading: ${item.name}');
    } else {
      _require(
        shading.length == 1 &&
            shading.single.getAttribute('val', namespace: w) ==
                expected.pattern &&
            shading.single.getAttribute('color', namespace: w) ==
                (expected.foregroundHex ?? 'auto') &&
            shading.single.getAttribute('fill', namespace: w) ==
                (expected.backgroundHex ?? 'auto'),
        'DOCX cell shading changed: ${item.name}',
      );
    }
    if (expected != null && expected.pattern == null) {
      final manifest = archive.findFile('word/evidence/manifest.json');
      _require(manifest != null, 'Missing unmapped cell shading evidence');
      final evidence = jsonDecode(utf8.decode(manifest!.content)) as Map;
      final records = (evidence['records'] as List)
          .cast<Map>()
          .where((record) => record['kind'] == 'shading')
          .toList();
      _require(records.length == 1, 'Ambiguous cell shading evidence');
      final record = records.single;
      _require(
        record['scope'] == 'tableCell' &&
            record['story'] == 'main' &&
            record['cp'] == 0 &&
            record['rawPattern'] == expected.rawPattern &&
            record['foregroundHex'] == expected.foregroundHex &&
            record['backgroundHex'] == expected.backgroundHex,
        'Unmapped cell shading evidence changed: ${item.name}',
      );
      evidenceCases++;
    }

    final html = renderLegacyWordHtml(document.blocks);
    _require(
      item.previewColor == null
          ? !html.contains('background-color:')
          : html.contains('background-color:#${item.previewColor}'),
      'HTML cell shading changed: ${item.name}',
    );
    _require(
      html.contains('data-word-shading="approximate"') ==
              item.approximatePreview &&
          html.contains('>A<'),
      'HTML cell shading qualification or text changed: ${item.name}',
    );
    cases++;
  }
  _reject(
    const LegacyWordShading(
      pattern: 'invented-pattern',
      backgroundHex: 'FF0000',
    ),
    invalidColor: false,
  );
  _reject(
    const LegacyWordShading(pattern: 'clear', backgroundHex: 'not-a-color'),
    invalidColor: true,
  );
  return {
    'cases': cases,
    'htmlPreviews': cases,
    'unmappedEvidenceCases': evidenceCases,
    'malformedInputsRejected': 2,
  };
}

String _shadingRecord(LegacyWordShading? value) => jsonEncode(
  value == null
      ? null
      : {
          'pattern': value.pattern,
          'rawPattern': value.rawPattern,
          'foregroundHex': value.foregroundHex,
          'backgroundHex': value.backgroundHex,
        },
);

void _reject(LegacyWordShading shading, {required bool invalidColor}) {
  try {
    convertLegacyWordDocument(publicCellShadingDocument(formatting: shading));
  } on FormatException {
    if (!invalidColor) return;
    rethrow;
  } on LegacyWordConversionException {
    if (invalidColor) return;
    rethrow;
  }
  throw StateError('Malformed direct cell shading was accepted.');
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
