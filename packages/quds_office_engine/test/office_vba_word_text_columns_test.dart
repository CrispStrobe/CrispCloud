import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordTextColumns',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('''
Option Explicit
Sub Main()
$body
End Sub
''');

Matcher _error([String? code]) {
  final matcher = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'WordTextColumns')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? matcher
      : matcher.having((error) => error.code, 'code', code);
}

const _columns =
    'Application.ActiveDocument.Sections.Item(2).PageSetup.TextColumns';

void main() {
  for (final statement in [
    '$_columns.SetCount 3',
    '$_columns.SetCount(3)',
    '$_columns.SetCount NumColumns:=3',
    '$_columns.SetCount(NumColumns:=3)',
    'Call $_columns.SetCount(3)',
    'Call $_columns.SetCount(NumColumns:=3)',
    'call ${_columns.toLowerCase()}.setcount(nUmCoLuMnS:=3)',
  ]) {
    test('SetCount preserves the explicit section: $statement', () {
      final step = _compile(statement).steps.single;
      expect(step.tool, 'docx.textColumns');
      expect(step.arguments, {'section': 1, 'count': 3});
    });
  }

  for (final (expression, count) in [
    ('1', 1),
    ('45', 45),
    ('3.0', 3),
    ('CLng(CVar(2))', 2),
  ]) {
    test('SetCount accepts bounded exact integers: $expression', () {
      expect(
        _compile('$_columns.SetCount $expression').steps.single.arguments,
        {'section': 1, 'count': count},
      );
    });
  }

  for (final (expression, points) in [
    ('0', 0),
    ('0.05', 0.05),
    ('18', 18),
    ('107374182.35', 107374182.35),
    ('InchesToPoints(0.25)', 18),
    ('Application.MillimetersToPoints(Millimeters:=6.35)', 18),
  ]) {
    test('Spacing emits exact native point values: $expression', () {
      final step = _compile('$_columns.Spacing = $expression').steps.single;
      expect(step.tool, 'docx.textColumns');
      expect(step.arguments, {'section': 1, 'spacing': points});
    });
  }

  for (final value in [true, false]) {
    test('LineBetween accepts explicit Boolean $value', () {
      expect(
        _compile('$_columns.LineBetween = $value').steps.single.arguments,
        {'section': 1, 'lineBetween': value},
      );
    });
  }

  test('typed aliases, ByVal rebinding and named helpers retain identity', () {
    final plan = _source('''
Option Explicit
Sub Configure(ByVal target As TextColumns, Optional ByVal count As Long = 2)
  target.SetCount NumColumns:=count
  Set target = ThisDocument.Sections(3).PageSetup.TextColumns
  target.LineBetween = True
End Sub
Sub Main()
  Dim original As TextColumns
  Dim retained As TextColumns
  Set original = ThisDocument.Sections(1).PageSetup.TextColumns
  Set retained = original
  Set original = ThisDocument.Sections(2).PageSetup.TextColumns
  Configure count:=3, target:=retained
  original.Spacing = 12.5
  retained.LineBetween = False
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'section': 0, 'count': 3},
      {'section': 2, 'lineBetween': true},
      {'section': 1, 'spacing': 12.5},
      {'section': 0, 'lineBetween': false},
    ]);
  });

  test('nested With captures the original column selector', () {
    final plan = _compile('''
Dim target As TextColumns
Set target = ThisDocument.Sections(1).PageSetup.TextColumns
With target
  Set target = ThisDocument.Sections(3).PageSetup.TextColumns
  With Application.ActiveDocument.Sections
    With .Item(2).PageSetup
      With .TextColumns
        .SetCount NumColumns:=2
        .Spacing = 24
      End With
    End With
  End With
  .LineBetween = True
  target.SetCount 1
End With
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'section': 1, 'count': 2},
      {'section': 1, 'spacing': 24},
      {'section': 0, 'lineBetween': true},
      {'section': 2, 'count': 1},
    ]);
  });

  test('SetCount evaluates receiver then argument exactly once', () {
    final plan = _source('''
Function PickSection() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "section"
  PickSection = 2
End Function
Function PickCount() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "count"
  PickCount = 3
End Function
Sub Main()
  Call ThisDocument.Sections(PickSection()).PageSetup.TextColumns.SetCount(NumColumns:=PickCount())
End Sub
''');
    expect(plan.steps.map((step) => step.tool), [
      'docx.replaceText',
      'docx.replaceText',
      'docx.textColumns',
    ]);
    expect(plan.steps[0].arguments['text'], 'section');
    expect(plan.steps[1].arguments['text'], 'count');
    expect(plan.steps.last.arguments, {'section': 1, 'count': 3});
  });

  test('bounded loop emits each section operation in order', () {
    final plan = _compile('''
Dim i As Long
For i = 1 To 3
  ThisDocument.Sections(i).PageSetup.TextColumns.SetCount i
Next i
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'section': 0, 'count': 1},
      {'section': 1, 'count': 2},
      {'section': 2, 'count': 3},
    ]);
  });

  for (final expression in [
    '0',
    '-1',
    '46',
    '2147483648',
    '1.5',
    'True',
    '"2"',
    'Null',
    'Empty',
  ]) {
    test('SetCount refuses invalid count $expression', () {
      expect(
        () => _compile('$_columns.SetCount $expression'),
        throwsA(_error('vba_type_error')),
      );
    });
  }

  for (final expression in [
    '-0.05',
    '0.01',
    '107374182.4',
    'True',
    '"18"',
    'Null',
    'Empty',
  ]) {
    test('Spacing refuses invalid value $expression', () {
      expect(
        () => _compile('$_columns.Spacing = $expression'),
        throwsA(_error('vba_type_error')),
      );
    });
  }

  for (final expression in ['0', '-1', '1', '"True"', 'Null', 'Empty']) {
    test('LineBetween refuses implicit Boolean conversion $expression', () {
      expect(
        () => _compile('$_columns.LineBetween = $expression'),
        throwsA(_error('vba_type_error')),
      );
    });
  }

  for (final statement in [
    '$_columns.SetCount',
    '$_columns.SetCount()',
    '$_columns.SetCount 2, 3',
    '$_columns.SetCount NumColumns:=2, NumColumns:=3',
    '$_columns.SetCount(,)',
    'Call $_columns.SetCount',
    '$_columns.SetCount = 2',
    '$_columns.Spacing(1) = 18',
    '$_columns.LineBetween(True) = False',
    'Set $_columns.Spacing = 18',
    'ThisDocument.Sections(1).PageSetup.SetCount 2',
    'ThisDocument.Paragraphs(1).Range.SetCount 2',
    'Dim target As TextColumns\ntarget.SetCount 2',
    'Dim target As TextColumns\nSet target = ThisDocument.Sections(1).PageSetup',
    'Dim target As PageSetup\nSet target = $_columns',
  ]) {
    test('refuses malformed or incompatible call: $statement', () {
      expect(() => _compile(statement), throwsA(_error()));
    });
  }

  test('SetCount names its official NumColumns parameter', () {
    expect(
      () => _compile('$_columns.SetCount Count:=2'),
      throwsA(_error('vba_name_error')),
    );
  });

  for (final statement in [
    '$_columns.EvenlySpaced = True',
    '$_columns.Width = 100',
    '$_columns.Add',
    '$_columns.Item(1).SpaceAfter = 18',
    'ThisDocument.Sections(1).PageSetup.TextColumns(1).Width = 100',
    'ThisDocument.PageSetup.TextColumns.SetCount 2',
    'Dim value As Long\nvalue = $_columns.Count',
    'Dim value As Double\nvalue = $_columns.Spacing',
    'Dim value As Boolean\nvalue = $_columns.LineBetween',
    'Dim value As Long\nvalue = $_columns.SetCount(2)',
    'Dim target As TextColumns\nSet target = New TextColumns',
  ]) {
    test('keeps unsupported column objects/reads explicit: $statement', () {
      expect(() => _compile(statement), throwsA(_error()));
    });
  }

  test('unused helpers are checked before any operation is returned', () {
    expect(
      () => _source('''
Sub Unused(ByVal target As TextColumns)
  target.SetCount Count:=2
End Sub
Sub Main()
  ThisDocument.Paragraphs(1).Range.InsertBefore "unpublished"
End Sub
'''),
      throwsA(_error('vba_name_error')),
    );
  });

  for (final binding in [
    'Dim columns As TextColumns\nSet columns = value',
    'Configure target:=value',
  ]) {
    test('unused helper rejects scalar Variant as TextColumns: $binding', () {
      expect(
        () => _source('''
Sub Configure(ByVal target As TextColumns)
  target.SetCount 2
End Sub
Sub Unused()
  Dim value As Variant
  $binding
End Sub
Sub Main()
End Sub
'''),
        throwsA(_error('vba_type_error')),
      );
    });
  }

  test('dead branches still reject scalar Variant column bindings', () {
    expect(
      () => _compile('''
Dim value As Variant
Dim columns As TextColumns
If False Then
  Set columns = value
End If
'''),
      throwsA(_error('vba_type_error')),
    );
  });

  for (final statement in [
    '$_columns.SetCount 2',
    '$_columns.Spacing = 18',
    '$_columns.LineBetween = True',
  ]) {
    test(
      'column write cannot interrupt custom paragraph spacing: $statement',
      () {
        expect(
          () => _compile('''
ThisDocument.Paragraphs(1).Format.LineSpacingRule = wdLineSpaceExactly
$statement
ThisDocument.Paragraphs(1).Format.LineSpacing = 14
'''),
          throwsA(_error('vba_unsupported')),
        );
      },
    );
  }

  test('source operations retain the shared emission budget', () {
    expect(
      () => _compile('''
Dim i As Long
For i = 1 To 10001
  $_columns.LineBetween = True
Next i
'''),
      throwsA(_error('vba_limit_exceeded')),
    );
  });

  test('the complete example emits its six intended section writes', () {
    final plan = _source(
      File('example/macros/word_text_columns.bas').readAsStringSync(),
    );
    expect(plan.steps.map((step) => step.tool).toSet(), {'docx.textColumns'});
    expect(plan.steps.map((step) => step.arguments), [
      {'section': 0, 'count': 2},
      {'section': 0, 'spacing': 18},
      {'section': 0, 'lineBetween': true},
      {'section': 1, 'count': 3},
      {'section': 1, 'spacing': 18},
      {'section': 1, 'lineBetween': false},
    ]);
  });
}
