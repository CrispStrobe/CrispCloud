import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordArgumentShapes',
    source: source,
  ),
);

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'WordArgumentShapes');

void main() {
  for (final (type, selector, property, value, operation, fields)
      in <(String, String, String, String, String, Map<String, Object?>)>[
        (
          'Font',
          'Range.Font',
          'Bold',
          'True',
          'docx.runFormat',
          {'bold': true},
        ),
        (
          'ParagraphFormat',
          'Format',
          'ReadingOrder',
          'wdReadingOrderLtr',
          'docx.paragraphFormat',
          {'rtl': false},
        ),
      ]) {
    test('$type rejects Variant object binding in an unreachable branch', () {
      expect(
        () => _compile('''Sub Main()
  Dim target As $type
  Dim value As Variant
  If False Then
    Set target = value
  End If
End Sub
'''),
        throwsA(
          _error('vba_type_error')
              .having((error) => error.line, 'line', 5)
              .having((error) => error.column, 'column', 18),
        ),
      );
    });

    test('$type rejects an unused named helper argument with Variant type', () {
      expect(
        () => _compile('''Sub Main()
End Sub
Sub Unused()
  Dim value As Variant
  Apply target:=value
End Sub
Sub Apply(ByVal target As $type)
End Sub
'''),
        throwsA(
          _error('vba_type_error')
              .having((error) => error.line, 'line', 5)
              .having((error) => error.column, 'column', 17),
        ),
      );
    });

    test('$type remains a supported required named ByVal object parameter', () {
      final plan = _compile('''Sub Main()
  Dim target As $type
  Set target = ActiveDocument.Paragraphs(2).$selector
  Apply target:=target
End Sub
Sub Apply(ByVal target As $type)
  target.$property = $value
End Sub
''');
      expect(plan.steps, hasLength(1));
      expect(plan.steps.single.tool, operation);
      expect(plan.steps.single.arguments, {'paragraph': 1, ...fields});
    });

    test('$type remains forbidden as an optional object parameter', () {
      expect(
        () => _compile('''Sub Main()
End Sub
Sub Unused(Optional ByVal target As $type)
End Sub
'''),
        throwsA(_error('vba_unsupported')),
      );
    });
  }
}
