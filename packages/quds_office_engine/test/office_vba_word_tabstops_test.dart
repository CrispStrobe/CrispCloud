import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordTabs',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Matcher _error([String? code]) {
  final result = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'WordTabs')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? result
      : result.having((error) => error.code, 'code', code);
}

const _tabs = 'ActiveDocument.Paragraphs(2).TabStops';

void main() {
  for (final selector in <String>[
    'ActiveDocument.Paragraphs(2).TabStops',
    'ThisDocument.Paragraphs.Item(2).Format.TabStops',
    'Application.ActiveDocument.Paragraphs(2).Range.ParagraphFormat.TabStops',
  ]) {
    test('typed collection from $selector', () {
      final macro = _compile('''
Dim stops As TabStops
Set stops = $selector
With stops
  .ClearAll
  .Add Position:=72
End With
''');
      expect(macro.steps.map((step) => step.tool), [
        'docx.clearTabStops',
        'docx.tabStop',
      ]);
      expect(macro.steps.map((step) => step.arguments), [
        {'paragraph': 1},
        {'paragraph': 1, 'position': 72, 'alignment': 'left', 'leader': 'none'},
      ]);
    });
  }

  for (final call in <String>[
    '$_tabs.Add 72, wdAlignTabRight, wdTabLeaderDots',
    '$_tabs.Add(72, wdAlignTabRight, wdTabLeaderDots)',
    'Call $_tabs.Add(72, wdAlignTabRight, wdTabLeaderDots)',
    '$_tabs.Add Leader:=wdTabLeaderDots, POSITION:=72, Alignment:=wdAlignTabRight',
    'Call $_tabs.Add(72, Leader:=wdTabLeaderDots, Alignment:=wdAlignTabRight)',
  ]) {
    test('binds Add statement $call', () {
      expect(_compile(call).steps.single.arguments, {
        'paragraph': 1,
        'position': 72,
        'alignment': 'right',
        'leader': 'dot',
      });
    });
  }

  for (final call in <String>[
    '$_tabs.Add 72, , wdTabLeaderDots',
    'Call $_tabs.Add(72, , wdTabLeaderDots)',
    '$_tabs.Add Position:=72, Leader:=wdTabLeaderDots',
  ]) {
    test('omitted alignment uses left: $call', () {
      expect(_compile(call).steps.single.arguments, {
        'paragraph': 1,
        'position': 72,
        'alignment': 'left',
        'leader': 'dot',
      });
    });
  }

  for (final call in <String>[
    '$_tabs.Add 72',
    '$_tabs.Add 72,',
    'Call $_tabs.Add(72,,)',
    '$_tabs.Add(Position:=72)',
  ]) {
    test('omitted optionals use left and spaces: $call', () {
      expect(_compile(call).steps.single.arguments, {
        'paragraph': 1,
        'position': 72,
        'alignment': 'left',
        'leader': 'none',
      });
    });
  }

  for (final call in <String>[
    '$_tabs.ClearAll',
    '$_tabs.ClearAll()',
    'Call $_tabs.ClearAll',
    'Call $_tabs.ClearAll()',
  ]) {
    test('zero-argument ClearAll: $call', () {
      final step = _compile(call).steps.single;
      expect(step.tool, 'docx.clearTabStops');
      expect(step.arguments, {'paragraph': 1});
    });
  }

  // Independent enum expectations from Microsoft's WdTabAlignment and
  // WdTabLeader definitions, not from the compiler's constant tables.
  for (final (constant, value, native) in <(String, int, String)>[
    ('wdAlignTabLeft', 0, 'left'),
    ('wdAlignTabCenter', 1, 'center'),
    ('wdAlignTabRight', 2, 'right'),
    ('wdAlignTabDecimal', 3, 'decimal'),
  ]) {
    test('$constant keeps the Word alignment enum', () {
      final plan = _compile('''
$_tabs.Add 72, $constant
$_tabs.Add 144, $value
''');
      expect(plan.steps.map((step) => step.arguments['alignment']), [
        native,
        native,
      ]);
    });
  }

  for (final (constant, value, native) in <(String, int, String)>[
    ('wdTabLeaderSpaces', 0, 'none'),
    ('wdTabLeaderDots', 1, 'dot'),
    ('wdTabLeaderDashes', 2, 'hyphen'),
    ('wdTabLeaderLines', 3, 'underscore'),
  ]) {
    test('$constant keeps the Word leader enum', () {
      final plan = _compile('''
$_tabs.Add 72, , $constant
$_tabs.Add 144, , $value
''');
      expect(plan.steps.map((step) => step.arguments['leader']), [
        native,
        native,
      ]);
    });
  }

  for (final points in <double>[-1584, -72.05, -0.05, 0, 0.05, 72.15, 1584]) {
    test('exact signed twentieth-point position $points', () {
      expect(
        _compile('$_tabs.Add $points').steps.single.arguments['position'],
        points,
      );
    });
  }

  test(
    'receiver and named argument expressions execute once in source order',
    () {
      final macro = _source('''
Sub Main()
  ActiveDocument.Paragraphs(Mark(2)).TabStops.Add _
    Leader:=Mark(1), Position:=Mark(72), Alignment:=Mark(3)
End Sub
Function Mark(ByVal value As Long) As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore CStr(value)
  Mark = value
End Function
''');
      expect(macro.steps.take(4).map((step) => step.arguments['text']), [
        '2',
        '1',
        '72',
        '3',
      ]);
      expect(macro.steps.last.arguments, {
        'paragraph': 1,
        'position': 72,
        'alignment': 'decimal',
        'leader': 'dot',
      });
      expect(macro.steps, hasLength(5));
    },
  );

  test('alias and ByVal rebinding keep each selected paragraph', () {
    final macro = _source('''
Sub Edit(ByVal target As TabStops, Optional ByVal position As Double = 72)
  target.Add Position:=position
  Set target = ThisDocument.Paragraphs(3).TabStops
  target.ClearAll
End Sub
Sub Main()
  Dim stops As TabStops
  Dim retained As TabStops
  Set stops = ThisDocument.Paragraphs(1).Format.TabStops
  Set retained = stops
  Set stops = ThisDocument.Paragraphs(2).Range.ParagraphFormat.TabStops
  Edit target:=retained
  With stops
    .Add 144, wdAlignTabCenter
  End With
  retained.ClearAll
End Sub
''');
    expect(macro.steps.map((step) => step.arguments['paragraph']), [
      0,
      2,
      1,
      0,
    ]);
    expect(macro.steps.map((step) => step.tool), [
      'docx.tabStop',
      'docx.clearTabStops',
      'docx.tabStop',
      'docx.clearTabStops',
    ]);
  });

  test(
    'local arrays and Variant numbers retain the scalar argument contract',
    () {
      final macro = _compile('''
Dim positions(1 To 2) As Double
Dim position As Variant
positions(1) = -12.5
positions(2) = 72.05
For Each position In positions
  $_tabs.Add Position:=position, Leader:=CVar(wdTabLeaderDashes)
Next position
''');
      expect(macro.steps.map((step) => step.arguments['position']), [
        -12.5,
        72.05,
      ]);
      expect(macro.steps.map((step) => step.arguments['leader']), [
        'hyphen',
        'hyphen',
      ]);
    },
  );

  for (final (arguments, code) in <(String, String)>[
    ('', 'vba_type_error'),
    (', 0, 0', 'vba_type_error'),
    ('Alignment:=1', 'vba_type_error'),
    ('Position:=72, Position:=144', 'vba_type_error'),
    ('72, Position:=144', 'vba_type_error'),
    ('72, , Alignment:=1', 'vba_type_error'),
    ('Position:=72, 1', 'vba_type_error'),
    ('Position:=72, , 1', 'vba_type_error'),
    ('72, 0, 0, 0', 'vba_type_error'),
    ('Position:=72, Unknown:=0', 'vba_name_error'),
    ('True', 'vba_type_error'),
    ('"72"', 'vba_type_error'),
    ('Null', 'vba_type_error'),
    ('Empty', 'vba_type_error'),
    ('0.001', 'vba_type_error'),
    ('1584.05', 'vba_type_error'),
    ('-1584.05', 'vba_type_error'),
    ('72, True', 'vba_type_error'),
    ('72, 0.5', 'vba_type_error'),
    ('72, wdAlignTabBar', 'vba_unsupported'),
    ('72, wdAlignTabList', 'vba_unsupported'),
    ('72, -1', 'vba_unsupported'),
    ('72, , "1"', 'vba_type_error'),
    ('72, , wdTabLeaderHeavy', 'vba_unsupported'),
    ('72, , wdTabLeaderMiddleDot', 'vba_unsupported'),
    ('72, , -1', 'vba_unsupported'),
  ]) {
    test('reject invalid Add($arguments)', () {
      expect(
        () => _compile('Call $_tabs.Add($arguments)'),
        throwsA(_error(code)),
      );
    });
  }

  for (final body in <String>[
    'Dim stops As TabStops\nstops.Add 72',
    'Dim stops As TabStops\nSet stops = ActiveDocument.Paragraphs(1).Range',
    'Dim stops As Variant\nSet stops = $_tabs',
    'Dim stops As TabStops\nSet stops = New TabStops',
    'Dim value As Long\nvalue = $_tabs.Count',
    '$_tabs.Item(1).Clear',
    '$_tabs.ClearAll 72',
    '$_tabs.ClearAll(Position:=72)',
    'ActiveDocument.Paragraphs(1).Range.TabStops.Add 72',
    'ActiveDocument.Paragraphs.TabStops.ClearAll',
    'ActiveDocument.Paragraphs(1).TabStops = $_tabs',
    'Set ActiveDocument.Paragraphs(1).TabStops = $_tabs',
    'Dim value As Variant\nvalue = $_tabs.Add(72)',
    'Dim stops As TabStops\nSet stops = $_tabs.Add(72)',
    'ActiveDocument.Paragraphs(1).Range.Add 72',
    'ActiveDocument.Paragraphs(1).Format.ClearAll',
    'Call $_tabs.Add 72',
  ]) {
    test('reject unsupported collection shape: $body', () {
      expect(() => _compile(body), throwsA(_error()));
    });
  }

  test('invalid member binding is rejected even in a nonexecuted branch', () {
    expect(
      () => _compile('''
If False Then
  $_tabs.Add Position:=72, Unknown:=0
End If
'''),
      throwsA(_error('vba_name_error')),
    );
  });

  test('optional object parameters remain unsupported', () {
    expect(
      () => _source('''
Sub Main()
End Sub
Sub Edit(Optional ByVal stops As TabStops)
End Sub
'''),
      throwsA(_error()),
    );
  });

  for (final (language, format) in <(String, OfficeMacroFormat)>[
    ('vba-excel', OfficeMacroFormat.xlsx),
    ('vba-powerpoint', OfficeMacroFormat.pptx),
  ]) {
    test('TabStops declaration is isolated from $language', () {
      expect(
        () => OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: language,
            format: format,
            moduleName: 'WordTabs',
            source: 'Sub Main()\nDim stops As TabStops\nEnd Sub',
          ),
        ),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  test('tab operations retain aggregate compiler resource limits', () {
    expect(
      () => _compile('''
Dim i As Long
For i = 1 To 10001
  $_tabs.ClearAll
Next i
'''),
      throwsA(_error('vba_limit_exceeded')),
    );
  });
}
