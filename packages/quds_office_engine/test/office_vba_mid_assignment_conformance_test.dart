import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_mid_assignment_smoke.dart';
import 'support/vba_conformance.dart';

OfficeMacro _compile(String source, String dialect) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: dialect,
        format: switch (dialect) {
          'vba-word' => OfficeMacroFormat.docx,
          'vba-powerpoint' => OfficeMacroFormat.pptx,
          _ => OfficeMacroFormat.xlsx,
        },
        moduleName: 'MidConformance',
        source: source,
      ),
    );

TypeMatcher<OfficeVbaCompileException> _diagnostic(String code) =>
    isA<OfficeVbaCompileException>().having(
      (error) => error.code,
      'code',
      code,
    );

String _module(String body) => 'Sub Main()\n$body\nEnd Sub\n';

void main() {
  final source = File(
    'test/fixtures/vba_conformance/mid_assignment_v1.json',
  ).readAsStringSync();
  final suites = midAssignmentSuites(source);

  for (final suite in suites) {
    group('${suite.dialect} canonical Mid assignment corpus', () {
      for (final fixture in suite.cases) {
        test('${fixture.feature}: ${fixture.id}', () {
          expect(runVbaConformanceCase(fixture)['actual'], fixture.expected);
        });
      }
    });
  }

  test('the same source-derived oracle qualifies all three adapters', () {
    expect(suites.map((suite) => suite.dialect).toSet(), {
      'vba-word',
      'vba-excel',
      'vba-powerpoint',
    });
    for (final suite in suites) {
      expect(suite.id, 'vba-mid-assignment');
      expect(suite.cases, hasLength(77));
      expect(
        suite.cases.where((fixture) => fixture.expected.containsKey('steps')),
        hasLength(41),
      );
      expect(
        suite.cases.where(
          (fixture) => fixture.expected.containsKey('diagnostic'),
        ),
        hasLength(36),
      );
      expect(suite.cases.map((fixture) => fixture.provenance['kind']).toSet(), {
        'spec-derived',
        'dialect-contract',
      });
      expect(
        suite.cases.where((fixture) => fixture.provenance.containsKey('host')),
        isEmpty,
      );
      expect(
        canonicalVbaConformanceJson(runVbaConformanceSuite(suite)),
        canonicalVbaConformanceJson(runVbaConformanceSuite(suite)),
      );
    }
  });

  for (final dialect in midAssignmentSinks.keys) {
    group('$dialect strict text boundaries', () {
      for (final replacement in ['1', 'True', 'Empty', 'Null']) {
        test('replacement $replacement is not implicitly converted', () {
          expect(
            () => _compile(
              _module('''
Dim text As String
text = "abcdef"
Mid(text, 2, 2) = $replacement
'''),
              dialect,
            ),
            throwsA(_diagnostic('vba_type_error')),
          );
        });
      }

      for (final initial in ['1', 'True', 'Empty', 'Null']) {
        test('Variant target $initial is not implicitly converted', () {
          expect(
            () => _compile(
              _module('''
Dim text As Variant
text = $initial
Mid(text, 2, 2) = "XY"
'''),
              dialect,
            ),
            throwsA(_diagnostic('vba_type_error')),
          );
        });
      }

      for (final index in [
        '0',
        '-1',
        '7',
        '2147483648',
        '1.5',
        '"2"',
        'True',
        'Empty',
        'Null',
      ]) {
        test(
          'start $index refuses even an empty replacement and zero count',
          () {
            expect(
              () => _compile(
                _module('''
Dim text As String
text = "abcdef"
Mid(text, $index, 0) = ""
'''),
                dialect,
              ),
              throwsA(_diagnostic('vba_type_error')),
            );
          },
        );
      }

      for (final length in [
        '-1',
        '2147483648',
        '1.5',
        '"2"',
        'True',
        'Empty',
        'Null',
      ]) {
        test('length $length is a strict nonnegative signed-32 integer', () {
          expect(
            () => _compile(
              _module('''
Dim text As String
text = "abcdef"
Mid(text, 2, $length) = "XY"
'''),
              dialect,
            ),
            throwsA(_diagnostic('vba_type_error')),
          );
        });
      }

      test('an empty target has no valid start even for a no-op', () {
        expect(
          () => _compile(
            _module('Dim text As String\nMid(text, 1, 0) = ""'),
            dialect,
          ),
          throwsA(_diagnostic('vba_type_error')),
        );
      });

      for (final assignment in [
        'Mid(text, 1, 1) = Left\$("😀", 1)',
        'Mid(text, 2, 1) = Right\$("😀", 1)',
      ]) {
        test(
          'unpaired UTF-16 cannot cross the native output boundary: $assignment',
          () {
            expect(
              () => _compile(
                _module('''
Dim text As String
text = "xx"
$assignment
${midAssignmentSinks[dialect]} = text
'''),
                dialect,
              ),
              throwsA(_diagnostic('vba_type_error')),
            );
          },
        );
      }

      test('a local splice cannot read live document text', () {
        expect(
          () => _compile(
            _module('''
Dim text As String
text = "abcdef"
Mid(text, 2) = ${midAssignmentSinks[dialect]}
'''),
            dialect,
          ),
          throwsA(_diagnostic('vba_unsupported')),
        );
      });
    });
  }
}
