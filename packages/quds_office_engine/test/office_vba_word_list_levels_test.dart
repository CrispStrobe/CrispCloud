import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordListLevels',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Matcher _error([String? code]) {
  final matcher = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'WordListLevels')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? matcher
      : matcher.having((error) => error.code, 'code', code);
}

const _list = 'ActiveDocument.Paragraphs(2).Range.ListFormat';

void main() {
  for (final (method, tool, args) in <(String, String, Map<String, Object?>)>[
    ('ApplyOutlineNumberDefault', 'docx.listOutlineDefault', {}),
    ('ListIndent', 'docx.listLevel', {'delta': 1}),
    ('ListOutdent', 'docx.listLevel', {'delta': -1}),
  ]) {
    for (final statement in [
      '$_list.$method',
      '$_list.$method()',
      'Call $_list.$method',
      'Call $_list.$method()',
      'call ${_list.toLowerCase()}.${method.toLowerCase()}()',
    ]) {
      test('list-level statement: $statement', () {
        final step = _compile(statement).steps.single;
        expect(step.tool, tool);
        expect(step.arguments, {'paragraph': 1, ...args});
      });
    }
  }

  for (var level = 1; level <= 9; level++) {
    test('ListLevelNumber $level maps to native ${level - 1}', () {
      final step = _compile('$_list.ListLevelNumber = $level').steps.single;
      expect(step.tool, 'docx.listLevel');
      expect(step.arguments, {'paragraph': 1, 'level': level - 1});
    });
  }

  for (final expression in ['CVar(3)', 'CDbl(3)', '1 + 2', '(3)']) {
    test('ListLevelNumber accepts exact numeric expression $expression', () {
      expect(
        _compile(
          'Let $_list.ListLevelNumber = $expression',
        ).steps.single.arguments,
        {'paragraph': 1, 'level': 2},
      );
    });
  }

  for (final statement in [
    '$_list.ApplyOutlineNumberDefault wdWord8ListBehavior',
    '$_list.ApplyOutlineNumberDefault(0)',
    'Call $_list.ApplyOutlineNumberDefault(wdWord8ListBehavior)',
    '$_list.ApplyOutlineNumberDefault DefaultListBehavior:=0',
    'Call $_list.ApplyOutlineNumberDefault(DEFAULTLISTBEHAVIOR:=CVar(0))',
  ]) {
    test('outline default optional behavior: $statement', () {
      final step = _compile(statement).steps.single;
      expect(step.tool, 'docx.listOutlineDefault');
      expect(step.arguments, {'paragraph': 1});
    });
  }

  test('aliases and ByVal helper rebinding retain selected paragraphs', () {
    final plan = _source('''
Sub Promote(ByVal target As ListFormat, ByVal depth As Long)
  target.ListLevelNumber = depth
  target.ListIndent
  Set target = ThisDocument.Paragraphs(4).Range.ListFormat
  Call target.ListOutdent()
End Sub
Sub Main()
  Dim current As ListFormat
  Dim retained As ListFormat
  Set current = ThisDocument.Paragraphs.Item(1).Range.ListFormat
  Set retained = current
  Set current = Application.ActiveDocument.Paragraphs(2).Range.ListFormat
  retained.ApplyOutlineNumberDefault
  Promote depth:=2, target:=retained
  With current
    .ListLevelNumber = 3
  End With
  retained.ListOutdent
End Sub
''');
    expect(plan.steps.map((step) => step.arguments['paragraph']), [
      0,
      0,
      0,
      3,
      1,
      0,
    ]);
    expect(plan.steps.map((step) => step.arguments['level']), [
      null,
      1,
      null,
      null,
      2,
      null,
    ]);
    expect(plan.steps.map((step) => step.arguments['delta']), [
      null,
      null,
      1,
      -1,
      null,
      -1,
    ]);
  });

  test('nested With and scalar arrays select successive levels', () {
    final plan = _compile('''
Dim levels(1 To 3) As Long
Dim level As Variant
levels(1) = 1
levels(2) = 5
levels(3) = 9
With ActiveDocument
  With .Paragraphs(3).Range
    With .ListFormat
      .ApplyOutlineNumberDefault
      For Each level In levels
        .ListLevelNumber = level
      Next level
      Call .ListOutdent()
    End With
    .Font.Bold = True
  End With
End With
''');
    expect(
      plan.steps.map((step) => step.arguments['paragraph']),
      everyElement(2),
    );
    expect(plan.steps.skip(1).take(3).map((step) => step.arguments['level']), [
      0,
      4,
      8,
    ]);
    expect(plan.steps.last.tool, 'docx.runFormat');
  });

  test(
    'outline method captures receiver before optional argument once each',
    () {
      final plan = _source('''
Function Index() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "receiver"
  Index = 2
End Function
Function Behavior() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "argument"
  Behavior = 0
End Function
Sub Main()
  ThisDocument.Paragraphs(Index()).Range.ListFormat.ApplyOutlineNumberDefault _
      DefaultListBehavior:=Behavior()
End Sub
''');
      expect(plan.steps.map((step) => step.tool), [
        'docx.replaceText',
        'docx.replaceText',
        'docx.listOutlineDefault',
      ]);
      expect(plan.steps.take(2).map((step) => step.arguments['text']), [
        'receiver',
        'argument',
      ]);
      expect(plan.steps.last.arguments, {'paragraph': 1});
    },
  );

  test(
    'level assignment retains scalar property RHS then selector evaluation',
    () {
      final plan = _source('''
Function Index() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "receiver"
  Index = 2
End Function
Function Depth() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "value"
  Depth = 3
End Function
Sub Main()
  ThisDocument.Paragraphs(Index()).Range.ListFormat.ListLevelNumber = Depth()
End Sub
''');
      expect(plan.steps.map((step) => step.tool), [
        'docx.replaceText',
        'docx.replaceText',
        'docx.listLevel',
      ]);
      expect(plan.steps.take(2).map((step) => step.arguments['text']), [
        'value',
        'receiver',
      ]);
      expect(plan.steps.last.arguments, {'paragraph': 1, 'level': 2});
    },
  );

  for (final value in [
    '0',
    '-1',
    '10',
    '1.5',
    'True',
    '"2"',
    'Empty',
    'Null',
    'CVar(False)',
    '2147483647',
  ]) {
    test('ListLevelNumber refuses nonlevel value $value', () {
      expect(
        () => _compile('$_list.ListLevelNumber = $value'),
        throwsA(_error('vba_type_error')),
      );
    });
  }

  for (final method in ['ListIndent', 'ListOutdent']) {
    for (final args in ['1', '0, 0', ',', 'Level:=2']) {
      test('$method refuses arguments in unused helper: $args', () {
        expect(
          () => _source('''
Sub Main()
End Sub
Sub Unused(ByVal target As ListFormat)
  Call target.$method($args)
End Sub
'''),
          throwsA(_error()),
        );
      });
    }
  }

  for (final value in ['True', '"0"', 'Empty', 'Null', '0.5', 'CVar(True)']) {
    test('outline behavior refuses noninteger $value', () {
      expect(
        () => _compile('$_list.ApplyOutlineNumberDefault($value)'),
        throwsA(_error('vba_type_error')),
      );
    });
  }

  for (final value in [
    'wdWord9ListBehavior',
    'wdWord10ListBehavior',
    '-1',
    '3',
  ]) {
    test('outline behavior refuses unsupported $value', () {
      expect(
        () => _compile('$_list.ApplyOutlineNumberDefault $value'),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  test('outline unknown names and duplicate binding fail in dead code', () {
    expect(
      () => _compile(
        'If False Then\n$_list.ApplyOutlineNumberDefault Level:=1\nEnd If',
      ),
      throwsA(_error('vba_name_error')),
    );
    expect(
      () => _compile(
        'If False Then\n$_list.ApplyOutlineNumberDefault DefaultListBehavior:=0, DefaultListBehavior:=0\nEnd If',
      ),
      throwsA(_error('vba_type_error')),
    );
  });

  for (final body in [
    'Dim value As Long\nvalue = $_list.ListLevelNumber',
    'Dim value As Variant\nvalue = $_list.ListIndent()',
    'Dim value As Variant\nvalue = $_list.ApplyOutlineNumberDefault()',
    '$_list.ListLevelNumber() = 2',
    '$_list.ListLevelNumber(1) = 2',
    'Set $_list.ListLevelNumber = 2',
    'Call $_list.ListLevelNumber(2)',
    'Dim target As ListFormat\ntarget.ListLevelNumber = 2',
    'Dim target As ListFormat\ntarget.ListIndent',
    'ActiveDocument.Paragraphs(1).Format.ListLevelNumber = 2',
    'ActiveDocument.Paragraphs(1).Range.ListIndent',
    'ActiveDocument.Paragraphs(1).TabStops.ApplyOutlineNumberDefault',
    'ActiveDocument.Paragraphs(1).ListFormat.ListOutdent',
    'Call $_list.ApplyOutlineNumberDefault 0',
    '$_list.ApplyOutlineNumberDefault NumberType:=1',
    '$_list.ListLevelNumber = ActiveDocument',
  ]) {
    test('unsupported level shape is checked: $body', () {
      expect(() => _compile(body), throwsA(_error()));
    });
  }

  test('omitted Variant is not silently converted into a level', () {
    expect(
      () => _source('''
Sub Edit(ByVal target As ListFormat, Optional ByVal level As Variant)
  target.ListLevelNumber = level
End Sub
Sub Main()
  Edit target:=$_list
End Sub
'''),
      throwsA(_error()),
    );
  });

  for (final statement in [
    '$_list.ListIndent',
    '$_list.ListLevelNumber = 2',
    '$_list.ApplyOutlineNumberDefault',
  ]) {
    test('list-level writes retain aggregate operation limit: $statement', () {
      expect(
        () => _compile('Dim i As Long\nFor i = 1 To 10001\n$statement\nNext i'),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  }

  for (final (language, format) in <(String, OfficeMacroFormat)>[
    ('vba-excel', OfficeMacroFormat.xlsx),
    ('vba-powerpoint', OfficeMacroFormat.pptx),
  ]) {
    test('list levels cannot leak into $language', () {
      expect(
        () => OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: language,
            format: format,
            moduleName: 'WordListLevels',
            source: 'Sub Main()\n$_list.ListLevelNumber = 2\nEnd Sub',
          ),
        ),
        throwsA(_error()),
      );
    });
  }
}
