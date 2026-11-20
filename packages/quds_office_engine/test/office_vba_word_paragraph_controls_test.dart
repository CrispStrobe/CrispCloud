import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'ParagraphControls',
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
      .having((error) => error.moduleName, 'module', 'ParagraphControls')
      .having((error) => error.line, 'line', greaterThan(0))
      .having((error) => error.column, 'column', greaterThan(0));
  return code == null
      ? matcher
      : matcher.having((error) => error.code, 'code', code);
}

const _paragraph = 'ActiveDocument.Paragraphs(2)';
const _format = '$_paragraph.Format';
const _controls = <(String, String)>[
  ('OpenUp', 'open'),
  ('CloseUp', 'close'),
  ('OpenOrCloseUp', 'toggle'),
];

void main() {
  for (final receiver in [
    _paragraph,
    _format,
    '$_paragraph.Range.ParagraphFormat',
  ]) {
    for (final (method, action) in _controls) {
      for (final statement in [
        '$receiver.$method',
        '$receiver.$method()',
        'Call $receiver.$method',
        'Call $receiver.$method()',
        'call ${receiver.toLowerCase()}.${method.toLowerCase()}()',
      ]) {
        test('spacing control statement: $statement', () {
          final step = _compile(statement).steps.single;
          expect(step.tool, 'docx.paragraphSpaceBefore');
          expect(step.arguments, {'paragraph': 1, 'action': action});
        });
      }
    }
  }

  test('Paragraph aliases and named ByVal helpers retain their selector', () {
    final plan = _source('''
Option Explicit
Sub Adjust(ByVal target As Paragraph)
  target.OpenUp
  Set target = Application.ActiveDocument.Paragraphs(4)
  Call target.CloseUp()
End Sub
Sub Main()
  Dim original As Paragraph
  Dim retained As Paragraph
  Set original = ThisDocument.Paragraphs.Item(1)
  Set retained = original
  Set original = ActiveDocument.Paragraphs(2)
  Adjust target:=retained
  retained.OpenOrCloseUp
  original.CloseUp()
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 0, 'action': 'open'},
      {'paragraph': 3, 'action': 'close'},
      {'paragraph': 0, 'action': 'toggle'},
      {'paragraph': 1, 'action': 'close'},
    ]);
  });

  test(
    'ParagraphFormat aliases survive helper rebinding and other aliases',
    () {
      final plan = _source('''
Option Explicit
Sub Adjust(ByVal target As ParagraphFormat)
  target.CloseUp
  Set target = ThisDocument.Paragraphs(3).Format
  Call target.OpenOrCloseUp
End Sub
Sub Main()
  Dim original As ParagraphFormat
  Dim retained As ParagraphFormat
  Set original = Application.ActiveDocument.Paragraphs(1).Range.ParagraphFormat
  Set retained = original
  Set original = ActiveDocument.Paragraphs(2).Format
  Adjust target:=retained
  original.OpenUp
  retained.OpenOrCloseUp
End Sub
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 0, 'action': 'close'},
        {'paragraph': 2, 'action': 'toggle'},
        {'paragraph': 1, 'action': 'open'},
        {'paragraph': 0, 'action': 'toggle'},
      ]);
    },
  );

  test('nested With restores Paragraph and ParagraphFormat receivers', () {
    final plan = _compile('''
With Application
  With .ActiveDocument.Paragraphs
    With .Item(3)
      .OpenUp
      With .Range
        With .ParagraphFormat
          Call .OpenOrCloseUp()
          With ThisDocument.Paragraphs(1)
            Call .CloseUp
          End With
          .CloseUp()
        End With
      End With
      Call .OpenOrCloseUp()
    End With
  End With
End With
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 2, 'action': 'open'},
      {'paragraph': 2, 'action': 'toggle'},
      {'paragraph': 0, 'action': 'close'},
      {'paragraph': 2, 'action': 'close'},
      {'paragraph': 2, 'action': 'toggle'},
    ]);
  });

  test('With captures a bound selector before its variable is rebound', () {
    final plan = _compile('''
Dim target As Paragraph
Set target = ThisDocument.Paragraphs(1)
With target
  Set target = ThisDocument.Paragraphs(2)
  .OpenUp
  target.CloseUp
  .OpenOrCloseUp
End With
''');
    expect(plan.steps.map((step) => step.arguments['paragraph']), [0, 1, 0]);
    expect(plan.steps.map((step) => step.arguments['action']), [
      'open',
      'close',
      'toggle',
    ]);
  });

  for (final (method, action) in _controls) {
    test('$method captures a side-effecting paragraph index exactly once', () {
      final plan = _source('''
Function Target() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "selector"
  Target = 2
End Function
Sub Main()
  Call ThisDocument.Paragraphs(Target()).Format.$method()
End Sub
''');
      expect(plan.steps.map((step) => step.tool), [
        'docx.replaceText',
        'docx.paragraphSpaceBefore',
      ]);
      expect(plan.steps.first.arguments, {
        'paragraph': 0,
        'start': 0,
        'end': 0,
        'text': 'selector',
      });
      expect(plan.steps.last.arguments, {'paragraph': 1, 'action': action});
    });
  }

  test(
    'source scalar loops choose paragraphs without reading document state',
    () {
      final plan = _compile('''
Dim i As Long
For i = 1 To 3
  With ActiveDocument.Paragraphs(i)
    If i = 2 Then
      .OpenUp
    Else
      .Format.OpenOrCloseUp
    End If
  End With
Next i
''');
      expect(plan.steps.map((step) => step.arguments), [
        {'paragraph': 0, 'action': 'toggle'},
        {'paragraph': 1, 'action': 'open'},
        {'paragraph': 2, 'action': 'toggle'},
      ]);
    },
  );

  test('repeated toggles remain ordered native operations', () {
    final plan = _compile('''
$_format.SpaceBefore = 6
$_paragraph.OpenOrCloseUp
$_format.OpenOrCloseUp
$_format.OpenUp
$_paragraph.CloseUp
$_format.SpaceAfter = 8
''');
    expect(plan.steps.map((step) => step.tool), [
      'docx.paragraphFormat',
      'docx.paragraphSpaceBefore',
      'docx.paragraphSpaceBefore',
      'docx.paragraphSpaceBefore',
      'docx.paragraphSpaceBefore',
      'docx.paragraphFormat',
    ]);
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 1, 'before': 6.0},
      {'paragraph': 1, 'action': 'toggle'},
      {'paragraph': 1, 'action': 'toggle'},
      {'paragraph': 1, 'action': 'open'},
      {'paragraph': 1, 'action': 'close'},
      {'paragraph': 1, 'after': 8.0},
    ]);
  });

  test('controls preserve a completed custom line-spacing pair', () {
    final plan = _compile('''
$_paragraph.OpenUp
$_format.LineSpacingRule = wdLineSpaceExactly
$_format.LineSpacing = 14.25
$_format.CloseUp
$_format.OpenOrCloseUp
''');
    expect(plan.steps.map((step) => step.arguments), [
      {'paragraph': 1, 'action': 'open'},
      {'paragraph': 1, 'rule': 'exact', 'points': 14.25},
      {'paragraph': 1, 'action': 'close'},
      {'paragraph': 1, 'action': 'toggle'},
    ]);
  });

  for (final (method, _) in _controls) {
    for (final receiver in [_paragraph, _format]) {
      test(
        '$receiver.$method cannot interrupt a pending line-spacing pair',
        () {
          expect(
            () => _compile('''
$_format.LineSpacingRule = wdLineSpaceMultiple
$receiver.$method
$_format.LineSpacing = 18
'''),
            throwsA(_error('vba_unsupported')),
          );
        },
      );
    }
    test('$method in a point-value helper cannot interrupt a pending pair', () {
      expect(
        () => _source('''
Function Amount() As Double
  ThisDocument.Paragraphs(3).$method
  Amount = 18
End Function
Sub Main()
  $_format.LineSpacingRule = wdLineSpaceAtLeast
  $_format.LineSpacing = Amount()
End Sub
'''),
        throwsA(_error('vba_unsupported')),
      );
    });
  }

  for (final (method, _) in _controls) {
    for (final arguments in ['1', '1, 2', ',', 'Amount:=12', 'Empty']) {
      test('$method rejects arguments in an unused helper: $arguments', () {
        expect(
          () => _source('''
Sub Unused(ByVal target As ParagraphFormat)
  Call target.$method($arguments)
End Sub
Sub Main()
End Sub
'''),
          throwsA(_error()),
        );
      });
      test('$method rejects bare arguments in a dead branch: $arguments', () {
        expect(
          () => _compile('''
If False Then
  $_paragraph.$method $arguments
End If
'''),
          throwsA(_error()),
        );
      });
    }
  }

  for (final receiver in [
    'Application',
    'ActiveDocument',
    'ActiveDocument.Paragraphs',
    '$_paragraph.Range',
    '$_paragraph.Range.Font',
    '$_paragraph.TabStops',
    '$_paragraph.Range.ListFormat',
  ]) {
    for (final (method, _) in _controls) {
      test('wrong receiver refuses $receiver.$method in unused source', () {
        expect(
          () => _source('''
Sub Unused()
  $receiver.$method
End Sub
Sub Main()
End Sub
'''),
          throwsA(_error()),
        );
      });
    }
  }

  for (final (method, _) in _controls) {
    for (final body in [
      'Dim value As Variant\nvalue = $_format.$method',
      'Dim value As Variant\nvalue = $_paragraph.$method()',
      '$_format.$method = 0',
      'Let $_paragraph.$method = 12',
      'Set $_format.$method = $_format',
      'With $_paragraph.$method\nEnd With',
      'Dim target As Paragraph\ntarget.$method',
      'Dim target As ParagraphFormat\ntarget.$method',
    ]) {
      test(
        '$method refuses reads, property writes and unbound selectors: $body',
        () {
          expect(() => _compile(body), throwsA(_error()));
        },
      );
    }
  }

  test(
    'rejected arguments are diagnosed before a side-effecting argument runs',
    () {
      expect(
        () => _source('''
Function InvalidArgument() As Long
  Dim divisor As Long
  divisor = 0
  InvalidArgument = 1 / divisor
End Function
Sub Main()
  $_paragraph.OpenUp InvalidArgument()
End Sub
'''),
        throwsA(_error('vba_type_error')),
      );
    },
  );

  test(
    'a valid zero-argument method in unreachable code emits no operation',
    () {
      final plan = _compile('''
If False Then
  $_paragraph.OpenUp
End If
$_format.CloseUp
''');
      expect(plan.steps.single.arguments, {'paragraph': 1, 'action': 'close'});
    },
  );

  test('maximum supported operation count accepts spacing controls', () {
    final plan = _compile('''
Dim i As Long
For i = 1 To 10000
  $_paragraph.OpenOrCloseUp
Next i
''');
    expect(plan.steps, hasLength(10000));
    expect(plan.steps.last.arguments, {'paragraph': 1, 'action': 'toggle'});
  });

  for (final (method, _) in _controls) {
    test('$method obeys the aggregate native operation limit', () {
      expect(
        () => _compile('''
Dim i As Long
For i = 1 To 10001
  $_format.$method
Next i
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  }

  test('selector side effects share the native operation budget', () {
    expect(
      () => _source('''
Function Target() As Long
  ThisDocument.Paragraphs(1).Range.InsertBefore "index"
  Target = 2
End Function
Sub Main()
  Dim i As Long
  For i = 1 To 9999
    $_paragraph.CloseUp
  Next i
  ThisDocument.Paragraphs(Target()).OpenUp
End Sub
'''),
      throwsA(_error('vba_limit_exceeded')),
    );
  });

  for (final (language, format) in <(String, OfficeMacroFormat)>[
    ('vba-excel', OfficeMacroFormat.xlsx),
    ('vba-powerpoint', OfficeMacroFormat.pptx),
  ]) {
    test('paragraph spacing controls cannot leak into $language', () {
      expect(
        () => OfficeMacroLanguages().compile(
          OfficeMacroSource(
            language: language,
            format: format,
            moduleName: 'ParagraphControls',
            source: 'Sub Main()\n$_paragraph.OpenOrCloseUp\nEnd Sub',
          ),
        ),
        throwsA(_error()),
      );
    });
  }
}
