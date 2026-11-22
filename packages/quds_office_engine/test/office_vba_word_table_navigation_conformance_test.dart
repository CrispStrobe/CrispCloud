import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

import 'support/vba_conformance.dart';

void main() {
  final suite = VbaConformanceSuite.parse(
    File(
      'test/fixtures/vba_conformance/word_table_navigation_v1.json',
    ).readAsStringSync(),
  );
  for (final fixture in suite.cases) {
    test('${fixture.feature}: ${fixture.id}', () {
      expect(runVbaConformanceCase(fixture)['actual'], fixture.expected);
    });
  }

  test(
    'independent corpus distinguishes specifications from dialect limits',
    () {
      expect(suite.id, 'vba-word-table-navigation');
      expect(suite.dialect, 'vba-word');
      expect(suite.cases, hasLength(32));
      expect(
        suite.cases.where((value) => value.expected.containsKey('steps')),
        hasLength(20),
      );
      expect(
        suite.cases.where((value) => value.expected.containsKey('diagnostic')),
        hasLength(12),
      );
      expect(suite.cases.map((value) => value.provenance['kind']).toSet(), {
        'spec-derived',
        'dialect-contract',
      });
      expect(
        suite.cases.any((value) => value.provenance.containsKey('host')),
        isFalse,
      );
    },
  );

  test('complete report example emits ten ordered native cell operations', () {
    final macro = OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'TableNavigationExample',
        source: File(
          'example/macros/word_table_navigation.bas',
        ).readAsStringSync(),
      ),
    );
    expect(macro.steps.map((step) => step.tool), [
      'docx.tableCellRangeText',
      'docx.runFormat',
      'docx.tableCellRangeText',
      'docx.runFormat',
      'docx.tableCellRangeText',
      'docx.tableCellRangeText',
      'docx.tableCellRangeInsertAfter',
      'docx.runFormat',
      'docx.paragraphFormat',
      'docx.tableCellRangeInsertBefore',
    ]);
    expect(macro.steps.map((step) => step.arguments), [
      {'table': 0, 'row': 0, 'column': 0, 'text': 'Item'},
      {
        'paragraph': 0,
        'story': 'tableCell',
        'table': 0,
        'row': 0,
        'column': 0,
        'bold': true,
      },
      {'table': 0, 'row': 0, 'column': 1, 'text': 'Status'},
      {
        'paragraph': 0,
        'story': 'tableCell',
        'table': 0,
        'row': 0,
        'column': 1,
        'bold': true,
      },
      {'table': 0, 'row': 1, 'column': 0, 'text': 'Quarterly report'},
      {'table': 0, 'row': 1, 'column': 1, 'text': 'Ready'},
      {'table': 0, 'row': 1, 'column': 1, 'text': '\tReviewed'},
      {
        'paragraph': 0,
        'story': 'tableCell',
        'table': 0,
        'row': 1,
        'column': 1,
        'color': '008000',
      },
      {
        'paragraph': 0,
        'story': 'tableCell',
        'table': 0,
        'row': 1,
        'column': 1,
        'alignment': 'right',
      },
      {'table': 0, 'row': 1, 'column': 0, 'text': 'Document: '},
    ]);
    expect(OfficeMacro.parse(macro.encode()).toJson(), macro.toJson());
  });
}
