import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordLists',
    source: source,
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Matcher _error([String? code]) {
  final result = isA<OfficeVbaCompileException>()
      .having((error) => error.moduleName, 'module', 'WordLists')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? result
      : result.having((error) => error.code, 'code', code);
}

const _list = 'ActiveDocument.Paragraphs(2).Range.ListFormat';

void main() {
  for (final (method, tool, arguments)
      in <(String, String, Map<String, Object?>)>[
        ('ApplyBulletDefault', 'docx.listDefault', {'numbered': false}),
        ('ApplyNumberDefault', 'docx.listDefault', {'numbered': true}),
        ('RemoveNumbers', 'docx.removeNumbers', {'numberType': 'all'}),
      ]) {
    for (final call in <String>[
      '$_list.$method',
      '$_list.$method()',
      'Call $_list.$method',
      'Call $_list.$method()',
    ]) {
      test('optional default in $call', () {
        final step = _compile(call).steps.single;
        expect(step.tool, tool);
        expect(step.arguments, {'paragraph': 1, ...arguments});
      });
    }
  }

  for (final method in <String>['ApplyBulletDefault', 'ApplyNumberDefault']) {
    for (final call in <String>[
      '$_list.$method wdWord8ListBehavior',
      '$_list.$method(0)',
      'Call $_list.$method(wdWord8ListBehavior)',
      '$_list.$method DefaultListBehavior:=0',
      'Call $_list.$method(DEFAULTLISTBEHAVIOR:=CVar(wdWord8ListBehavior))',
    ]) {
      test('binds list behavior in $call', () {
        final step = _compile(call).steps.single;
        expect(step.tool, 'docx.listDefault');
        expect(step.arguments, {
          'paragraph': 1,
          'numbered': method == 'ApplyNumberDefault',
        });
      });
    }
  }

  for (final (constant, value, native) in <(String, int, String)>[
    ('wdNumberParagraph', 1, 'paragraph'),
    ('wdNumberAllNumbers', 3, 'all'),
  ]) {
    for (final call in <String>[
      '$_list.RemoveNumbers $constant',
      '$_list.RemoveNumbers($value)',
      'Call $_list.RemoveNumbers($constant)',
      '$_list.RemoveNumbers NumberType:=$constant',
      'Call $_list.RemoveNumbers(NUMBerType:=$value)',
    ]) {
      test('binds number kind in $call', () {
        expect(_compile(call).steps.single.arguments, {
          'paragraph': 1,
          'numberType': native,
        });
      });
    }
  }

  test(
    'typed aliases and ByVal rebinding retain their paragraph selectors',
    () {
      final macro = _source('''
Sub Edit(ByVal target As ListFormat)
  target.ApplyNumberDefault
  Set target = ThisDocument.Paragraphs(3).Range.ListFormat
  target.RemoveNumbers NumberType:=wdNumberParagraph
End Sub
Sub Main()
  Dim current As ListFormat
  Dim retained As ListFormat
  Set current = ThisDocument.Paragraphs.Item(1).Range.ListFormat
  Set retained = current
  Set current = Application.ActiveDocument.Paragraphs(2).Range.ListFormat
  Edit target:=retained
  With current
    .ApplyBulletDefault
  End With
  retained.RemoveNumbers
End Sub
''');
      expect(macro.steps.map((step) => step.arguments['paragraph']), [
        0,
        2,
        1,
        0,
      ]);
      expect(macro.steps.map((step) => step.tool), [
        'docx.listDefault',
        'docx.removeNumbers',
        'docx.listDefault',
        'docx.removeNumbers',
      ]);
    },
  );

  test('nested With retains the range and list receiver', () {
    final macro = _compile('''
With ActiveDocument
  With .Paragraphs.Item(3).Range
    With .ListFormat
      .RemoveNumbers
      .ApplyNumberDefault
    End With
    .Font.Bold = True
  End With
End With
''');
    expect(macro.steps.map((step) => step.arguments['paragraph']), [2, 2, 2]);
    expect(macro.steps.last.tool, 'docx.runFormat');
  });

  test(
    'receiver and optional expression each execute once in source order',
    () {
      final macro = _source('''
Function Index() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "receiver"
  Index = 2
End Function
Function Behavior() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "argument"
  Behavior = wdWord8ListBehavior
End Function
Sub Main()
  ThisDocument.Paragraphs(Index()).Range.ListFormat.ApplyBulletDefault _
      DefaultListBehavior:=Behavior()
End Sub
''');
      expect(macro.steps.map((step) => step.tool), [
        'docx.replaceText',
        'docx.replaceText',
        'docx.listDefault',
      ]);
      expect(macro.steps[0].arguments['text'], 'receiver');
      expect(macro.steps[1].arguments['text'], 'argument');
      expect(macro.steps[2].arguments['paragraph'], 1);
    },
  );

  test('local typed arrays and explicit numeric Variants remain supported', () {
    final macro = _compile('''
Dim kinds(1 To 2) As Long
Dim kind As Variant
kinds(1) = wdNumberParagraph
kinds(2) = wdNumberAllNumbers
For Each kind In kinds
  $_list.RemoveNumbers NumberType:=kind
Next kind
''');
    expect(macro.steps.map((step) => step.arguments['numberType']), [
      'paragraph',
      'all',
    ]);
  });

  for (final method in <String>[
    'ApplyBulletDefault',
    'ApplyNumberDefault',
    'RemoveNumbers',
  ]) {
    for (final argument in <String>[
      'True',
      '"0"',
      'Empty',
      'Null',
      '0.5',
      'CVar(True)',
    ]) {
      test('$method rejects noninteger argument $argument', () {
        expect(
          () => _compile('$_list.$method($argument)'),
          throwsA(_error('vba_type_error')),
        );
      });
    }
    test('$method rejects unknown names in dead code', () {
      expect(
        () => _compile('If False Then\n$_list.$method Unknown:=0\nEnd If'),
        throwsA(_error('vba_name_error')),
      );
    });
    test('$method rejects excess and omitted argument slots', () {
      for (final arguments in <String>['0, 0', ',', '0,']) {
        expect(
          () => _compile('Call $_list.$method($arguments)'),
          throwsA(_error('vba_type_error')),
        );
      }
    });
  }

  for (final method in <String>['ApplyBulletDefault', 'ApplyNumberDefault']) {
    for (final argument in <String>[
      'wdWord9ListBehavior',
      'wdWord10ListBehavior',
      '-1',
      '3',
    ]) {
      test('$method refuses unsupported list behavior $argument', () {
        expect(
          () => _compile('$_list.$method $argument'),
          throwsA(_error('vba_unsupported')),
        );
      });
    }
  }
  for (final argument in <String>['wdNumberListNum', '0', '-1', '4']) {
    test('RemoveNumbers refuses unsupported kind $argument', () {
      expect(
        () => _compile('$_list.RemoveNumbers $argument'),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  for (final body in <String>[
    'Dim target As ListFormat\ntarget.ApplyBulletDefault',
    'Dim target As ListFormat\nSet target = ActiveDocument.Paragraphs(1).Range',
    'Dim target As Variant\nSet target = $_list',
    'Dim target As ListFormat\nSet target = New ListFormat',
    'Dim target As ListFormat\ntarget = $_list',
    'Dim value As Long\nvalue = $_list.ListType',
    'Dim value As Variant\nvalue = $_list.RemoveNumbers()',
    'Dim value As Long\nvalue = $_list.ListLevelNumber',
    '$_list.ListIndent 1',
    '$_list.ApplyListTemplate 1',
    'ActiveDocument.Paragraphs(1).ListFormat.RemoveNumbers',
    'ActiveDocument.Paragraphs(1).Format.ListFormat.RemoveNumbers',
    'ActiveDocument.Paragraphs(1).Range.ListFormat().RemoveNumbers',
    'ActiveDocument.Paragraphs(1).Range.RemoveNumbers',
    'ActiveDocument.Paragraphs(1).TabStops.ApplyBulletDefault',
    'Call $_list.ApplyBulletDefault 0',
    '$_list.RemoveNumbers DefaultListBehavior:=0',
    '$_list.ApplyBulletDefault NumberType:=1',
    '$_list.ApplyNumberDefault DefaultListBehavior:=0, DefaultListBehavior:=0',
  ]) {
    test('refuses unsupported ListFormat shape: $body', () {
      expect(() => _compile(body), throwsA(_error()));
    });
  }

  test('optional object parameters and invalid unused helpers are checked', () {
    expect(
      () => _source('''
Sub Main()
End Sub
Sub Edit(Optional ByVal target As ListFormat)
End Sub
'''),
      throwsA(_error()),
    );
    expect(
      () => _source('''
Sub Main()
End Sub
Sub Edit(ByVal target As Variant)
  target.RemoveNumbers
End Sub
'''),
      throwsA(_error('vba_type_error')),
    );
  });

  for (final (language, format) in <(String, OfficeMacroFormat)>[
    ('vba-excel', OfficeMacroFormat.xlsx),
    ('vba-powerpoint', OfficeMacroFormat.pptx),
  ]) {
    test('ListFormat declarations are isolated from $language', () {
      expect(
        () => OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: language,
            format: format,
            moduleName: 'WordLists',
            source: 'Sub Main()\nDim target As ListFormat\nEnd Sub',
          ),
        ),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  test('list writes retain aggregate compiler operation limits', () {
    expect(
      () => _compile('''
Dim i As Long
For i = 1 To 10001
  $_list.RemoveNumbers
Next i
'''),
      throwsA(_error('vba_limit_exceeded')),
    );
  });
}
