import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    source: source,
    moduleName: 'StringComparison',
  ),
);

OfficeMacro _body(String body) => _source('Sub Main()\n$body\nEnd Sub');

Object? _value(String expression) => _body(
  'Worksheets(1).Range("A1").Value2 = $expression',
).steps.single.arguments['value'];

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.moduleName, 'module', 'StringComparison')
        .having((e) => e.line, 'line', greaterThan(0))
        .having((e) => e.column, 'column', greaterThan(0));

void _reject(String expression, String code) =>
    expect(() => _value(expression), throwsA(_error(code)), reason: expression);

void main() {
  // Specification-derived results and explicit dialect limits, not recorded
  // Microsoft Office-host observations. Empty uses the dialect's empty String
  // value; numeric/Boolean text coercions and nonbinary Compare remain refused.
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/strcomp-function
  // https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/9541f02a-e173-47a7-8c0f-4d91813c1c88
  group('binary UTF-16 ordering', () {
    for (final (arguments, expected) in <(String, int)>[
      ('"", ""', 0),
      ('"", "a"', -1),
      ('"a", ""', 1),
      ('"same", "same"', 0),
      ('"a", "b"', -1),
      ('"b", "a"', 1),
      ('"abc", "abcd"', -1),
      ('"abcd", "abc"', 1),
      ('"abx", "aby"', -1),
      ('"ABCD", "abcd"', -1),
      ('"abcd", "ABCD"', 1),
      ('"9", "10"', 1),
      ('"é", "é"', 1),
      ('"😀", "😁"', -1),
      ('"😀", ChrW(57344)', -1),
      ('ChrW(57344), "😀"', 1),
      ('ChrW(0), ""', 1),
      ('"a" & ChrW(0), "a"', 1),
      ('ChrW(0), ChrW(1)', -1),
      ('ChrW(-1), ChrW(32767)', 1),
      (r'Mid$("😀", 1, 1), Mid$("😁", 1, 1)', 0),
      (r'Mid$("😀", 2, 1), Mid$("😁", 2, 1)', -1),
      ('Empty, ""', 0),
      ('"", Empty', 0),
      ('Empty, Empty', 0),
      ('Empty, "a"', -1),
      ('"a", Empty', 1),
      ('CVar("b"), CVar("a")', 1),
      ('CVar(Empty), CVar("")', 0),
    ]) {
      test('StrComp($arguments) returns $expected', () {
        expect(_value('StrComp($arguments)'), expected);
        expect(_value('StrComp($arguments, vbBinaryCompare)'), expected);
      });
    }
    test('case-insensitive intrinsic and exact numeric comparison mode', () {
      expect(_value('sTrCoMp("a", "b", CVar(0))'), -1);
      expect(_value('StrComp("a", "b", -0.0)'), -1);
    });
    test('String and uninitialized Variant locals retain their types', () {
      final plan = _body('''
Dim text As String, emptyValue As Variant, result As Long
text = ""
result = StrComp(text, emptyValue)
Worksheets(1).Range("A1").Value2 = result
''');
      expect(plan.steps.single.arguments['value'], 0);
    });
  });

  group('Null propagation and conversion boundaries', () {
    for (final arguments in [
      'Null, "text"',
      '"text", Null',
      'Null, Null',
      'Null, Empty',
      'Empty, Null',
      'CVar(Null), CVar("text")',
    ]) {
      test('StrComp($arguments) retains Null', () {
        expect(_value('IsNull(StrComp($arguments))'), true);
        expect(_value('IsNull(StrComp($arguments, 0))'), true);
      });
    }
    test('a Null result remains available in a Variant array and branch', () {
      final plan = _body('''
Dim results(1 To 2) As Variant, value As Variant
results(1) = StrComp(Null, "x")
results(2) = StrComp("b", "a")
For Each value In results
  If IsNull(value) Then
    Worksheets(1).Range("A1").Value2 = "missing"
  Else
    Worksheets(1).Range("A1").Value2 = value
  End If
Next value
''');
      expect(plan.steps.map((step) => step.arguments['value']), ['missing', 1]);
    });
    test('Null cannot silently become a typed result or a native value', () {
      expect(
        () => _body('Dim result As Long\nresult = StrComp(Null, "")'),
        throwsA(_error('vba_invalid_use_of_null')),
      );
      _reject('StrComp(Null, "")', 'vba_invalid_use_of_null');
      _reject('CStr(StrComp("", Null))', 'vba_invalid_use_of_null');
    });
    for (final arguments in [
      'Null, "x", Null',
      '"x", Null, CVar(Null)',
      '"a", "b", Null',
    ]) {
      test('Null Compare is always invalid: $arguments', () {
        _reject('StrComp($arguments)', 'vba_invalid_use_of_null');
      });
    }
    for (final mode in [
      'vbTextCompare',
      'vbDatabaseCompare',
      'vbUseCompareOption',
      '3',
      'CVar(1)',
    ]) {
      test('unsupported Compare is checked even with Null text: $mode', () {
        _reject('StrComp("a", "b", $mode)', 'vba_unsupported');
        _reject('StrComp(Null, "b", $mode)', 'vba_unsupported');
        _reject('StrComp("a", Null, $mode)', 'vba_unsupported');
      });
    }
    for (final mode in [
      'Empty',
      'True',
      '"0"',
      '0.5',
      'CVar(False)',
      'CVar("0")',
    ]) {
      test('Compare requires an actual exact number: $mode', () {
        _reject('StrComp(Null, "b", $mode)', 'vba_type_error');
      });
    }
    for (final input in ['1', 'True', 'CVar(1)', 'CVar(False)']) {
      test('text conversion must be explicit: $input', () {
        _reject('StrComp($input, "1")', 'vba_type_error');
        _reject('StrComp("1", $input)', 'vba_type_error');
        _reject('StrComp(Null, $input)', 'vba_type_error');
      });
    }
    test('explicit scalar conversions compose with StrComp', () {
      expect(_value('StrComp(CStr(12), "12")'), 0);
      expect(_value('StrComp(CStr(True), "True")'), 0);
      expect(_value('CStr(StrComp("x", "y"))'), '-1');
    });
  });

  group('binding, helpers and source evaluation', () {
    for (final expression in [
      'StrComp()',
      'StrComp("a")',
      'StrComp("a", "b", 0, 0)',
      'StrComp(Worksheets(1), "a")',
    ]) {
      test('invalid call is diagnosed: $expression', () {
        _reject(expression, 'vba_type_error');
      });
    }
    for (final expression in [
      'StrComp(string1:="a", string2:="b")',
      'StrComp("a", "b", compare:=0)',
      'StrComp("a", , 0)',
      'StrComp("a", "b", )',
    ]) {
      test('named and omitted arguments stay unsupported: $expression', () {
        _reject(expression, 'vba_unsupported');
      });
    }
    test('invalid dead code is checked', () {
      expect(
        () => _source('''
Sub Main()
End Sub
Sub Unused()
  Dim result As Variant
  Exit Sub
  result = StrComp(True, "x")
End Sub
'''),
        throwsA(_error('vba_type_error')),
      );
    });
    test('intrinsic cannot be shadowed by a local, helper or parameter', () {
      for (final source in [
        'Sub Main()\nDim StrComp As Long\nEnd Sub',
        'Sub Main()\nEnd Sub\nSub StrComp()\nEnd Sub',
        'Sub Main()\nEnd Sub\nSub Helper(ByVal StrComp As String)\nEnd Sub',
      ]) {
        expect(() => _source(source), throwsA(_error('vba_name_error')));
      }
    });
    test('constant and optional-default expression rules remain bounded', () {
      for (final source in [
        'Const X As Long = StrComp("a", "a")\nSub Main()\nEnd Sub',
        'Sub Main()\nEnd Sub\nSub Helper(Optional ByVal x As Long = StrComp("a", "a"))\nEnd Sub',
      ]) {
        expect(() => _source(source), throwsA(_error('vba_unsupported')));
      }
    });
    test('Option Compare modes remain explicitly unsupported', () {
      expect(
        () => _source('Option Compare Text\nSub Main()\nEnd Sub'),
        throwsA(_error('vba_unsupported')),
      );
    });
    test('argument helpers run once in source order before the result', () {
      final plan = _source('''
Function LeftText() As String
  Worksheets(1).Range("B1").Value2 = "left"
  LeftText = "a"
End Function
Function RightText() As String
  Worksheets(1).Range("B1").Value2 = "right"
  RightText = "b"
End Function
Function Mode() As Long
  Worksheets(1).Range("B1").Value2 = "mode"
  Mode = 0
End Function
Sub Main()
  Worksheets(1).Range("A1").Value2 = StrComp(LeftText(), RightText(), Mode())
End Sub
''');
      expect(plan.steps.map((step) => step.arguments['value']), [
        'left',
        'right',
        'mode',
        -1,
      ]);
    });
    test('named module-helper arguments retain their source order', () {
      final plan = _source('''
Function CompareNames(ByVal first As Variant, Optional ByVal second As String = "a") As Variant
  CompareNames = StrComp(first, second)
End Function
Sub Main()
  Worksheets(1).Range("A1").Value2 = CompareNames(second:="b", first:="a")
  Worksheets(1).Range("A2").Value2 = IsNull(CompareNames(Null))
End Sub
''');
      expect(plan.steps.map((step) => step.arguments['value']), [-1, true]);
    });
    test('a late failure never returns an earlier partial plan', () {
      expect(
        () => _body('''
Worksheets(1).Range("A1").Value2 = "earlier"
Worksheets(1).Range("A2").Value2 = StrComp(Null, "x", vbTextCompare)
'''),
        throwsA(_error('vba_unsupported')),
      );
    });
  });

  group('metered comparison work', () {
    final longText = 'a' * 20000;
    test('a complete comparison is linear and fits the shared budget', () {
      expect(_value('StrComp("$longText", "$longText")'), 0);
      expect(_value('StrComp("${longText}x", "${longText}y")'), -1);
    });
    test('repeated equal values cannot bypass scanning charges', () {
      expect(
        () => _body('''
Dim text As String, result As Variant, index As Long
text = "$longText"
For index = 1 To 3
  result = StrComp(text, text)
Next index
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
    test('early differences do not scan the remaining long suffix', () {
      final plan = _body('''
Dim leftText As String, rightText As String, result As Long, index As Long
leftText = "a$longText"
rightText = "b$longText"
For index = 1 To 1000
  result = StrComp(leftText, rightText)
Next index
Worksheets(1).Range("A1").Value2 = result
''');
      expect(plan.steps.single.arguments['value'], -1);
    });
  });

  group('shared Word and PowerPoint adapters', () {
    test(
      'Word branches on source comparisons before table and font writes',
      () {
        final plan = const OfficeVbaWordMacroLanguage().compile(
          OfficeMacroSource(
            language: 'vba-word',
            format: OfficeMacroFormat.docx,
            source: '''
Sub Main()
  Dim names(1 To 2) As String, index As Long
  names(1) = "Alpha"
  names(2) = "Beta"
  For index = 1 To 2
    If StrComp(names(index), "Beta", vbBinaryCompare) < 0 Then
      ActiveDocument.Tables(1).Cell(index, 1).Range.Text = "Earlier: " & names(index)
    Else
      ActiveDocument.Tables(1).Cell(index, 1).Range.Text = names(index)
    End If
  Next index
  ActiveDocument.Paragraphs(1).Range.Font.Bold = StrComp(names(1), names(2)) < 0
End Sub
''',
          ),
        );
        expect(plan.steps.map((step) => step.arguments), [
          {'table': 0, 'row': 0, 'column': 0, 'text': 'Earlier: Alpha'},
          {'table': 0, 'row': 1, 'column': 0, 'text': 'Beta'},
          {'paragraph': 0, 'bold': true},
        ]);
      },
    );
    test('PowerPoint uses the same comparison in text and geometry', () {
      final plan = const OfficeVbaPowerPointMacroLanguage().compile(
        OfficeMacroSource(
          language: 'vba-powerpoint',
          format: OfficeMacroFormat.pptx,
          source: '''
Sub Main()
  With ActivePresentation.Slides(1).Shapes(1)
    .Left = 12 + StrComp("b", "a")
    .TextFrame.TextRange.Text = CStr(StrComp(Empty, ""))
  End With
End Sub
''',
        ),
      );
      expect(plan.steps[0].arguments['x'], 13);
      expect(plan.steps[1].arguments['text'], '0');
    });
  });
}
