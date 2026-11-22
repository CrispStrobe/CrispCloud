import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

Map<String, Object?> summary(Object doc) {
  final data = OfficeOperationCatalog.inspect(doc);
  return switch (doc) {
    SmlWorkbook() => {
      'sheets': (data['sheets'] as List)
          .cast<Map<String, Object?>>()
          .map(
            (sheet) => {
              ...sheet,
              'cells': (sheet['cells'] as List)
                  .cast<Map<String, Object?>>()
                  .where(
                    (cell) => cell['formula'] != null || cell['value'] != null,
                  )
                  .map(
                    (cell) => {
                      'cell': cell['cell'],
                      'formula': cell['formula'],
                      if (cell['formula'] == null) 'value': cell['value'],
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    },
    PmlPresentation() => {
      'slides': (data['slides'] as List)
          .cast<Map<String, Object?>>()
          .map(
            (slide) => {
              'notes': slide['notes'],
              'hidden': slide['hidden'],
              'shapes': (slide['shapes'] as List)
                  .cast<Map<String, Object?>>()
                  .map(
                    (shape) => [
                      shape['text'],
                      shape['picture'],
                      for (final axis in [
                        'x',
                        'y',
                        'width',
                        'height',
                        'rotation',
                      ])
                        ((shape[axis] as num) * 100).round(),
                    ],
                  )
                  .toList(),
            },
          )
          .toList(),
      'sections': doc.sections.map((s) => s.name).toList(),
    },
    _ => throw StateError('Unexpected format'),
  };
}

Object wordSnapshot(WmlDocument doc) => {
  'fields': WordZotero.fields(
    doc,
  ).map((f) => [f.citation?.toJson(), f.cachedText, f.canEdit]).toList(),
  'tables': doc.sections
      .expand((section) => section.blocks.whereType<WmlTable>())
      .map(
        (table) => table.rows
            .map(
              (row) => row.cells
                  .map(
                    (cell) => [
                      cell.borderTop,
                      cell.borderBottom,
                      cell.borderLeft,
                      cell.borderRight,
                      cell.vMerge.name,
                    ],
                  )
                  .toList(),
            )
            .toList(),
      )
      .toList(),
};

void main() {
  final output = Platform.environment['CRISP_OFFICE_ORACLE_OUTPUT'];
  if (output == null || output.isEmpty) {
    throw StateError(
      'Set CRISP_OFFICE_ORACLE_OUTPUT to the native app output directory.',
    );
  }
  for (final name in [
    'native.xlsx',
    'native.pptx',
    'slide-arrange.pptx',
    'slide-sections.pptx',
  ]) {
    test('Microsoft app save and CrispOffice reopen: $name', () async {
      final format = name.endsWith('xlsx')
          ? OfficeMacroFormat.xlsx
          : OfficeMacroFormat.pptx;
      final source = OfficeOperationCatalog.open(
        File('test/fixtures/fidelity/$name').readAsBytesSync(),
        format,
      );
      final saved = OfficeOperationCatalog.open(
        File('$output/microsoft/$name').readAsBytesSync(),
        format,
      );
      final reopened = OfficeOperationCatalog.open(
        await OfficeOperationCatalog.save(saved),
        format,
      );
      expect(summary(reopened), summary(saved), reason: 'CrispOffice reopen');
      expect(summary(saved), summary(source), reason: 'native app save');
    });
  }
  for (final kind in ['coloured-sides', 'merged-colour', 'retained-cell']) {
    test('Word save maintains Zotero fields and table edges: $kind', () {
      final reader = WordDeserializer();
      final source = reader.readBytes(
        File('$output/word-border-input/$kind.docx').readAsBytesSync(),
      );
      final saved = reader.readBytes(
        File('$output/word-borders/$kind-word.docx').readAsBytesSync(),
      );
      expect(WordZotero.fields(saved), isNotEmpty);
      expect(WordFieldSpans.unbalanced(saved), isEmpty);
      final reopened = reader.readBytes(WordSerializer().writeBytes(saved));
      expect(
        wordSnapshot(reopened),
        wordSnapshot(saved),
        reason: 'CrispOffice reopen',
      );
      expect(
        wordSnapshot(saved),
        wordSnapshot(source),
        reason: 'Word native save',
      );
    });
  }
}
