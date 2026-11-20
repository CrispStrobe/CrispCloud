import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-powerpoint',
    format: OfficeMacroFormat.pptx,
    moduleName: 'DeckUnit',
    source: source,
  ),
);

String _module(String body, {String declarations = ''}) =>
    '''
Option Explicit
Sub Main()
Dim target As Shape
$declarations
Set target = ActivePresentation.Slides(2).Shapes(3)
$body
End Sub
''';

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'DeckUnit')
        .having((error) => error.entryPoint, 'entry', 'Main')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0));

void _reject(String body, String code, {String declarations = ''}) => expect(
  () => _compile(_module(body, declarations: declarations)),
  throwsA(_error(code)),
  reason: body,
);

Map<String, Object?> _step(String op, Map<String, Object?> fields) =>
    <String, Object?>{
      'tool': 'pptx.$op',
      'arguments': <String, Object?>{
        'topLevel': true,
        'slide': 1,
        'shape': 2,
        ...fields,
      },
    };

void main() {
  test('registry compiles an immutable presentation plan', () {
    final plan = _compile(_module('target.TextFrame.TextRange.Text = "Hello"'));
    expect(plan.format, OfficeMacroFormat.pptx);
    expect(plan.steps.single.toJson(), _step('shapeText', {'text': 'Hello'}));
    expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
    expect(() => plan.steps.add(plan.steps.single), throwsUnsupportedError);
  });

  for (final format in <OfficeMacroFormat>[
    OfficeMacroFormat.docx,
    OfficeMacroFormat.xlsx,
  ]) {
    test('wrong ${format.name} host fails before parsing', () {
      expect(
        () => const OfficeVbaPowerPointMacroLanguage().compile(
          OfficeMacroSource(
            language: 'vba-powerpoint',
            format: format,
            moduleName: 'DeckUnit',
            source: 'this is not a module',
          ),
        ),
        throwsA(
          _error('vba_unsupported').having((error) => error.line, 'line', 1),
        ),
      );
    });
  }

  test('typed aliases, nested With and ByVal share source-only bindings', () {
    final plan = _compile('''
Option Explicit
Sub Main()
Dim deck As Presentation, selected As Slide, target As Shape, text As TextRange
Set deck = Application.ActivePresentation
Set selected = deck.Slides.Item(2)
Set target = selected.Shapes.Item(3)
Set text = target.TextFrame.TextRange
Call FormatText(deck, selected, target, text)
End Sub
Sub FormatText(ByVal deck As Presentation, ByVal selected As Slide, ByVal target As Shape, ByVal text As TextRange)
With text
  .Text = "Quarterly report"
  With .Font
    .Name = "Aptos"
    .Size = 24.25
    .Bold = msoTrue
    .Italic = False
    .Underline = msoFalse
    .Color.RGB = RGB(17, 34, 51)
  End With
  .ParagraphFormat.Alignment = ppAlignCenter
End With
With target
  .Left = -12.5
  .Top = 36
  .Width = 240
  .Height = 80.5
  .Rotation = -15
End With
End Sub
''');
    expect(plan.steps.map((step) => step.toJson()), <Object?>[
      _step('shapeText', {'text': 'Quarterly report'}),
      for (final field in <Map<String, Object?>>[
        {'font': 'Aptos'},
        {'size': 24.25},
        {'bold': true},
        {'italic': false},
        {'underline': false},
        {'color': '112233'},
        {'alignment': 'center'},
      ])
        _step('shapeFormat', field),
      for (final field in <Map<String, Object?>>[
        {'x': -12.5},
        {'y': 36},
        {'width': 240},
        {'height': 80.5},
        {'rotation': -15},
      ])
        _step('shapeGeometry', field),
    ]);
  });

  test('exact names retain case and spaces; Item and indexed forms agree', () {
    final plan = _compile('''
Sub Main()
ActivePresentation.Slides(1).Shapes(" Title 1 ").TextFrame.TextRange.Text = "A"
Application.ActivePresentation.Slides.Item(1).Shapes.Item(" Title 1 ").TextFrame.TextRange.Font.Bold = True
End Sub
''');
    expect(plan.steps[0].arguments, <String, Object?>{
      'topLevel': true,
      'slide': 0,
      'shapeName': ' Title 1 ',
      'text': 'A',
    });
    expect(plan.steps[1].arguments, <String, Object?>{
      'topLevel': true,
      'slide': 0,
      'shapeName': ' Title 1 ',
      'bold': true,
    });
  });

  test('arrays, source loops and helpers can address explicit slides', () {
    final plan = _compile('''
Option Explicit
Const LastSlide As Long = ppAlignRight
Sub Main()
Dim captions(1 To LastSlide) As String, index As Long
captions(1) = "One"
captions(2) = "Two"
captions(3) = "Three"
For index = 1 To UBound(captions)
  Call WriteTitle(ActivePresentation.Slides(index).Shapes("Title"), captions(index))
Next index
End Sub
Sub WriteTitle(ByVal target As Shape, ByVal caption As String)
target.TextFrame.TextRange.Text = caption
End Sub
''');
    expect(plan.steps.map((step) => step.arguments), <Object?>[
      {'topLevel': true, 'slide': 0, 'shapeName': 'Title', 'text': 'One'},
      {'topLevel': true, 'slide': 1, 'shapeName': 'Title', 'text': 'Two'},
      {'topLevel': true, 'slide': 2, 'shapeName': 'Title', 'text': 'Three'},
    ]);
  });

  test('ByVal rebinding cannot change the caller shape', () {
    final plan = _compile(
      _module('''
Call Rebind(target)
target.TextFrame.TextRange.Text = "caller"
''').replaceFirst('End Sub', '''End Sub
Sub Rebind(ByVal local As Shape)
Set local = ActivePresentation.Slides(1).Shapes(1)
local.TextFrame.TextRange.Text = "helper"
End Sub'''),
    );
    expect(plan.steps[0].arguments, {
      'topLevel': true,
      'slide': 0,
      'shape': 0,
      'text': 'helper',
    });
    expect(plan.steps[1].arguments, {
      'topLevel': true,
      'slide': 1,
      'shape': 2,
      'text': 'caller',
    });
  });

  for (final (source, native) in <(String, String)>[
    ('ppAlignLeft', 'left'),
    ('ppAlignCenter', 'center'),
    ('ppAlignRight', 'right'),
    ('ppAlignJustify', 'justify'),
  ]) {
    test('Microsoft alignment $source maps to $native', () {
      expect(
        _compile(
          _module(
            'target.TextFrame.TextRange.ParagraphFormat.Alignment = $source',
          ),
        ).steps.single.arguments['alignment'],
        native,
      );
    });
  }

  test(
    'hundredth point font values avoid floating multiplication artifacts',
    () {
      expect(
        _compile(
          _module('target.TextFrame.TextRange.Font.Size = 1.1'),
        ).steps.single.arguments['size'],
        1.1,
      );
    },
  );

  test('XML-safe Unicode and tab text survives plan JSON', () {
    final text = 'A\t📊';
    final plan = _compile(_module('target.TextFrame.TextRange.Text = "$text"'));
    expect(
      OfficeMacro.parse(plan.encode()).steps.single.arguments['text'],
      text,
    );
  });

  test('font names enforce native length and whitespace boundaries', () {
    final valid = List<String>.filled(255, 'A').join();
    final invalid = '${valid}A';
    expect(
      _compile(
        _module('target.TextFrame.TextRange.Font.Name = "$valid"'),
      ).steps.single.arguments['font'],
      valid,
    );
    for (final value in <String>['   ', invalid, 'Font\u007fName']) {
      _reject(
        'target.TextFrame.TextRange.Font.Name = "$value"',
        'vba_type_error',
      );
    }
  });

  test('font-name constraints do not trim or limit exact shape names', () {
    final name = '  ${List<String>.filled(256, 'A').join()}  ';
    final plan = _compile('''
Sub Main()
ActivePresentation.Slides(1).Shapes("$name").TextFrame.TextRange.Text = "x"
End Sub
''');
    expect(plan.steps.single.arguments['shapeName'], name);
  });

  for (final source in <String>[
    'value = target.TextFrame.TextRange.Text',
    'value = target.Width',
    'value = target.TextFrame.TextRange.Font.Bold',
    'value = target.TextFrame.TextRange.Font.Color.RGB',
    'value = ActivePresentation.Slides.Count',
    'value = ActivePresentation.Slides(1).Shapes.Count',
    'target.Fill.ForeColor.RGB = RGB(1, 2, 3)',
    'target.TextFrame.TextRange.Characters(1, 2).Text = "x"',
    'ThisWorkbook.Worksheets(1).Range("A1").Value = 1',
    'ThisDocument.Paragraphs(1).Range.Font.Bold = True',
    'Worksheets(1).Range("A1").Value = 1',
    'target.TextFrame.TextRange.ClearContents',
  ]) {
    test('unsupported path fails even in inactive code: $source', () {
      _reject(
        'If False Then\n$source\nEnd If',
        'vba_unsupported',
        declarations: 'Dim value As Variant',
      );
    });
  }

  for (final source in <String>[
    'target.TextFrame.TextRange.Font.Bold = "True"',
    'target.TextFrame.TextRange.Text = True',
    'target.TextFrame.TextRange.Font.Color.RGB = "red"',
    'Set target = Empty',
    'Set target = ActivePresentation',
    'target = ActivePresentation.Slides(1).Shapes(1)',
    'value = target',
    'Set target = ActivePresentation.Slides(True).Shapes(1)',
  ]) {
    test('static types fail even in inactive code: $source', () {
      _reject(
        'If False Then\n$source\nEnd If',
        'vba_type_error',
        declarations: 'Dim value As Variant',
      );
    });
  }

  for (final selector in <String>['0', '-1', '1.5', '2147483648']) {
    test('slide and shape selector $selector is refused', () {
      _reject(
        'Set target = ActivePresentation.Slides($selector).Shapes(1)',
        'vba_type_error',
      );
      _reject(
        'Set target = ActivePresentation.Slides(1).Shapes($selector)',
        'vba_type_error',
      );
    });
  }

  for (final value in <String>[
    'msoCTrue',
    'msoTriStateMixed',
    'msoTriStateToggle',
    '2',
    '0.5',
  ]) {
    test('unsupported tri-state $value cannot publish formatting', () {
      _reject(
        'target.TextFrame.TextRange.Font.Bold = $value',
        'vba_type_error',
      );
    });
  }

  for (final assignment in <String>[
    'target.Width = 0',
    'target.Height = -1',
    'target.Left = 9007199254740991',
    'target.Rotation = 9007199254740991',
    'target.TextFrame.TextRange.Font.Size = 0.99',
    'target.TextFrame.TextRange.Font.Size = 4001',
    'target.TextFrame.TextRange.Font.Size = 12.345',
    'target.TextFrame.TextRange.Font.Name = ""',
    'Set target = ActivePresentation.Slides(1).Shapes("")',
  ]) {
    test(
      'value boundary fails: $assignment',
      () => _reject(assignment, 'vba_type_error'),
    );
  }

  for (final value in <String>[
    'ppAlignmentMixed',
    'ppAlignDistribute',
    'ppAlignThaiDistribute',
    'ppAlignJustifyLow',
    '0',
  ]) {
    test(
      'unsupported alignment $value is explicit',
      () => _reject(
        'target.TextFrame.TextRange.ParagraphFormat.Alignment = $value',
        'vba_unsupported',
      ),
    );
  }

  test('broken UTF-16 and XML control characters cannot be emitted', () {
    for (final text in <String>[
      String.fromCharCode(0xd800),
      '\u0001',
      '\uffff',
    ]) {
      _reject('target.TextFrame.TextRange.Text = "$text"', 'vba_type_error');
    }
  });

  test('shared work limit refuses a partial plan', () {
    _reject(
      '''
For index = 1 To 100000
target.TextFrame.TextRange.Text = "x"
Next index
''',
      'vba_limit_exceeded',
      declarations: 'Dim index As Long',
    );
  });

  test('source cannot shadow host or enum names', () {
    for (final name in <String>[
      'ActivePresentation',
      'Application',
      'msoTrue',
      'ppAlignLeft',
    ]) {
      expect(
        () => _compile('Sub Main()\nDim $name As Long\nEnd Sub'),
        throwsA(_error('vba_name_error')),
      );
    }
  });

  test('PowerPoint collection iteration requires unavailable live reads', () {
    _reject(
      'For Each item In ActivePresentation.Slides\nNext item',
      'vba_unsupported',
      declarations: 'Dim item As Slide',
    );
  });

  test('uninitialized typed objects produce a source diagnostic', () {
    _reject(
      'unbound.Text = "x"',
      'vba_unsupported',
      declarations: 'Dim unbound As TextRange',
    );
  });
}
