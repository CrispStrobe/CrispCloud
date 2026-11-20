import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _compile(String source) =>
    const OfficeVbaWordMacroLanguage().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordUnit',
        source: source,
      ),
    );

String _module(String body, {String declarations = ''}) =>
    '''
Option Explicit
Sub Main()
Dim target As Range
$declarations
Set target = ThisDocument.Paragraphs(1).Range
$body
End Sub
''';

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'WordUnit')
        .having((error) => error.entryPoint, 'entry', 'Main')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0));

void _reject(String body, String code, {String declarations = ''}) => expect(
  () => _compile(_module(body, declarations: declarations)),
  throwsA(_error(code)),
  reason: body,
);

Map<String, Object?> _step(String tool, Map<String, Object?> arguments) =>
    <String, Object?>{'tool': 'docx.$tool', 'arguments': arguments};

List<Map<String, Object?>> _steps(OfficeMacro plan) => <Map<String, Object?>>[
  for (final step in plan.steps) step.toJson(),
];

void main() {
  group('explicit Word dialect', () {
    test('registry selects DOCX and native JSON round-trips the plan', () {
      final source = OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        source: _module('target.InsertBefore "Hello"'),
      );
      final plan = OfficeMacroLanguages().compile(source);
      expect(plan.format, OfficeMacroFormat.docx);
      expect(_steps(plan), <Object?>[
        _step('replaceText', <String, Object?>{
          'paragraph': 0,
          'start': 0,
          'end': 0,
          'text': 'Hello',
        }),
      ]);
      expect(
        OfficeMacro.parse(jsonEncode(plan.toJson())).toJson(),
        plan.toJson(),
      );
    });

    for (final format in <OfficeMacroFormat>[
      OfficeMacroFormat.xlsx,
      OfficeMacroFormat.pptx,
    ]) {
      test('Word adapter refuses ${format.name} before source parsing', () {
        expect(
          () => const OfficeVbaWordMacroLanguage().compile(
            OfficeMacroSource(
              language: 'vba-word',
              format: format,
              moduleName: 'WordUnit',
              source: 'not a module',
            ),
          ),
          throwsA(
            _error('vba_unsupported')
                .having((error) => error.line, 'line', 1)
                .having((error) => error.column, 'column', 1),
          ),
        );
      });
    }

    test('normal, parenthesized, Call and leading-dot method forms agree', () {
      final plan = _compile(
        _module('''
target.InsertBefore "a"
target.InsertBefore("b")
Call target.InsertBefore("c")
With target
  .InsertBefore "d"
  Call .InsertBefore("e")
End With
target.InsertBefore ""
'''),
      );
      expect(plan.steps.map((step) => step.arguments['text']), <String>[
        'a',
        'b',
        'c',
        'd',
        'e',
        '',
      ]);
      expect(
        plan.steps.every((step) => step.tool == 'docx.replaceText'),
        isTrue,
      );
    });

    test(
      'aliases, ByVal and nested With emit precise native format fields',
      () {
        final plan = _compile('''
Option Explicit
Sub Main()
Dim documentAlias As Document, paragraphAlias As Paragraph, rangeAlias As Range
Set documentAlias = ThisDocument
Set paragraphAlias = documentAlias.Paragraphs(3)
Set rangeAlias = paragraphAlias.Range
Call FormatParagraph(documentAlias, paragraphAlias, rangeAlias)
End Sub
Sub FormatParagraph(ByVal doc As Document, ByVal para As Paragraph, ByVal text As Range)
With doc
  With .Paragraphs(3)
    With .Range
      .InsertBefore "prefix"
      With .Font
        .Bold = True
        .Italic = False
        .Size = 12.5
        .Name = "Aptos"
        .Color = RGB(17, 34, 51)
      End With
      With .ParagraphFormat
        .Alignment = wdAlignParagraphJustify
        .SpaceBefore = 0.05
        .SpaceAfter = 1.5
      End With
    End With
  End With
End With
para.Range.InsertBefore "second"
text.Font.Bold = False
End Sub
''');
        expect(_steps(plan), <Object?>[
          _step('replaceText', <String, Object?>{
            'paragraph': 2,
            'start': 0,
            'end': 0,
            'text': 'prefix',
          }),
          for (final fields in <Map<String, Object?>>[
            <String, Object?>{'bold': true},
            <String, Object?>{'italic': false},
            <String, Object?>{'size': 12.5},
            <String, Object?>{'font': 'Aptos'},
            <String, Object?>{'color': '112233'},
          ])
            _step('runFormat', <String, Object?>{'paragraph': 2, ...fields}),
          _step('paragraphFormat', <String, Object?>{
            'paragraph': 2,
            'alignment': 'justify',
          }),
          _step('paragraphFormat', <String, Object?>{
            'paragraph': 2,
            'before': 0.05,
          }),
          _step('paragraphFormat', <String, Object?>{
            'paragraph': 2,
            'after': 1.5,
          }),
          _step('replaceText', <String, Object?>{
            'paragraph': 2,
            'start': 0,
            'end': 0,
            'text': 'second',
          }),
          _step('runFormat', <String, Object?>{'paragraph': 2, 'bold': false}),
        ]);
      },
    );

    test(
      'method receiver and argument are each evaluated once in that order',
      () {
        final plan = _compile('''
Sub Main()
ThisDocument.Paragraphs(Choose()).Range.InsertBefore MakeText()
End Sub
Function Choose() As Long
ThisDocument.Paragraphs(1).Range.InsertBefore "receiver"
Choose = 2
End Function
Function MakeText() As String
ThisDocument.Paragraphs(1).Range.InsertBefore "argument"
MakeText = "result"
End Function
''');
        expect(plan.steps.map((step) => step.arguments['text']), <String>[
          'receiver',
          'argument',
          'result',
        ]);
        expect(plan.steps.map((step) => step.arguments['paragraph']), <int>[
          0,
          0,
          1,
        ]);
      },
    );

    test('Word enum constants work in Const and array bounds', () {
      final plan = _compile('''
Const LastAlignment As Long = wdAlignParagraphJustify
Sub Main()
Dim values(wdAlignParagraphLeft To LastAlignment) As Long
Dim index As Long
For index = LBound(values) To UBound(values)
  values(index) = index
  ThisDocument.Paragraphs(1).Range.ParagraphFormat.Alignment = values(index)
Next index
End Sub
''');
      expect(plan.steps.map((step) => step.arguments['alignment']), <String>[
        'left',
        'center',
        'right',
        'justify',
      ]);
    });

    test(
      'shared Variant, dynamic arrays, iteration and helpers remain available',
      () {
        final plan = _compile('''
Sub Main()
Dim values() As Variant, value As Variant
ReDim values(1 To 3)
values(2) = Null
values(3) = 2.5
For Each value In values
  ThisDocument.Paragraphs(1).Range.InsertBefore LabelFor(value)
Next value
Erase values
End Sub
Function LabelFor(ByVal value As Variant) As String
If IsEmpty(value) Then
  LabelFor = "empty"
ElseIf IsNull(value) Then
  LabelFor = "null"
Else
  LabelFor = CStr(CLng(value))
End If
End Function
''');
        expect(plan.steps.map((step) => step.arguments['text']), <String>[
          'empty',
          'null',
          '2',
        ]);
      },
    );

    test('maximum source selector is still document-independent', () {
      final plan = _compile('''
Sub Main()
ThisDocument.Paragraphs(9007199254740991).Range.InsertBefore "x"
End Sub
''');
      expect(plan.steps.single.arguments['paragraph'], 9007199254740990);
    });

    test(
      'internal surrogate slices can be measured or recombined before publication',
      () {
        final plan = _compile(
          _module(r'''
high = Left$("😀", 1)
low = Right$("😀", 1)
target.InsertBefore CStr(Len(high)) & high & low
''', declarations: 'Dim high As String, low As String'),
        );
        expect(plan.steps.single.arguments['text'], '1😀');
      },
    );

    test('tabs and supplementary text survive the native plan', () {
      final plan = _compile(
        _module('target.InsertBefore "A\t😀${String.fromCharCode(0x1fffe)}B"'),
      );
      expect(
        plan.steps.single.arguments['text'],
        'A\t😀${String.fromCharCode(0x1fffe)}B',
      );
    });
  });

  group('strict Word values and serialization bounds', () {
    for (final expression in <String>[
      '0',
      '-1',
      '1.5',
      'True',
      '"1"',
      'Empty',
      'Null',
    ]) {
      test('Paragraphs refuses actual selector $expression', () {
        _reject(
          '''
index = $expression
ThisDocument.Paragraphs(index).Range.InsertBefore "x"
''',
          'vba_type_error',
          declarations: 'Dim index As Variant',
        );
      });
    }
    for (final property in <String>['Bold', 'Italic']) {
      for (final value in <String>['0', '-1', '"True"', 'Empty', 'Null']) {
        test('Font.$property requires Boolean rather than Variant $value', () {
          _reject(
            'value = $value\ntarget.Font.$property = value',
            'vba_type_error',
            declarations: 'Dim value As Variant',
          );
        });
      }
    }
    for (final property in <String>['Size', 'Color']) {
      for (final value in <String>['True', '"12"', 'Empty', 'Null']) {
        test('Font.$property requires numeric rather than Variant $value', () {
          _reject(
            'value = $value\ntarget.Font.$property = value',
            'vba_type_error',
            declarations: 'Dim value As Variant',
          );
        });
      }
    }
    for (final property in <String>['Alignment', 'SpaceBefore', 'SpaceAfter']) {
      for (final value in <String>['False', '"0"', 'Empty', 'Null']) {
        test(
          'ParagraphFormat.$property requires numeric rather than Variant $value',
          () {
            _reject(
              'value = $value\ntarget.ParagraphFormat.$property = value',
              'vba_type_error',
              declarations: 'Dim value As Variant',
            );
          },
        );
      }
    }
    for (final value in <String>['1', 'True', 'Empty', 'Null']) {
      test('InsertBefore requires actual String for $value', () {
        _reject(
          'value = $value\ntarget.InsertBefore value',
          'vba_type_error',
          declarations: 'Dim value As Variant',
        );
      });
      test('Font.Name requires actual String for $value', () {
        _reject(
          'value = $value\ntarget.Font.Name = value',
          'vba_type_error',
          declarations: 'Dim value As Variant',
        );
      });
    }
    for (final size in <String>['0', '-0.5', '0.25', '12.25', '1638.5']) {
      test('Font.Size refuses nonrepresentable or bounded size $size', () {
        _reject('target.Font.Size = $size', 'vba_type_error');
      });
    }
    test('font half-point and spacing twip boundaries are exact', () {
      final plan = _compile(
        _module('''
target.Font.Size = 0.5
target.Font.Size = 1638
target.ParagraphFormat.SpaceBefore = 0
target.ParagraphFormat.SpaceAfter = 107374182.35
'''),
      );
      expect(plan.steps.map((step) => step.arguments), <Object?>[
        <String, Object?>{'paragraph': 0, 'size': 0.5},
        <String, Object?>{'paragraph': 0, 'size': 1638},
        <String, Object?>{'paragraph': 0, 'before': 0},
        <String, Object?>{'paragraph': 0, 'after': 107374182.35},
      ]);
    });
    for (final spacing in <String>['-0.05', '0.01', '1.125', '107374182.4']) {
      for (final property in <String>['SpaceBefore', 'SpaceAfter']) {
        test(
          '$property refuses nonrepresentable or bounded spacing $spacing',
          () {
            _reject(
              'target.ParagraphFormat.$property = $spacing',
              'vba_type_error',
            );
          },
        );
      }
    }
    for (final alignment in <String>['-1', '4', '9999999']) {
      test('unsupported alignment $alignment fails explicitly', () {
        _reject(
          'target.ParagraphFormat.Alignment = $alignment',
          'vba_unsupported',
        );
      });
    }
    test('fractional alignment fails strict integral validation', () {
      _reject('target.ParagraphFormat.Alignment = 0.5', 'vba_type_error');
    });
    for (final code in <int>[
      ...List<int>.generate(
        32,
        (index) => index,
      ).where((code) => code != 9 && code != 10 && code != 13),
      0xfffe,
      0xffff,
    ]) {
      test(
        'InsertBefore refuses XML-invalid unit U+${code.toRadixString(16)}',
        () {
          _reject(
            'target.InsertBefore "a${String.fromCharCode(code)}b"',
            'vba_type_error',
          );
        },
      );
    }
    for (final name in <String>[
      '',
      'A\tB',
      'A${String.fromCharCode(0xffff)}B',
    ]) {
      test('font name refuses unsafe/empty attribute ${jsonEncode(name)}', () {
        _reject('target.Font.Name = "$name"', 'vba_type_error');
      });
    }
    for (final lineBreak in <String>['\r', '\n', '\r\n']) {
      test(
        'literal line break ${jsonEncode(lineBreak)} fails lexical validation',
        () {
          _reject('target.InsertBefore "a${lineBreak}b"', 'vba_syntax_error');
        },
      );
    }
    test(
      'publication rejects an isolated surrogate but does not replace it',
      () {
        _reject(r'target.InsertBefore Left$("😀", 1)', 'vba_type_error');
      },
    );
  });

  group('Word object boundaries', () {
    for (final type in <String>['Document', 'Paragraph', 'Range']) {
      for (final value in <String>['Empty', 'Null', '1', '"x"']) {
        test(
          '$type cannot receive scalar $value through Set even in dead code',
          () {
            _reject(
              '''
If False Then
  Set destination = $value
End If
''',
              'vba_type_error',
              declarations: 'Dim destination As $type',
            );
          },
        );
      }
      test('$type objects must be assigned with Set', () {
        final expression = switch (type) {
          'Document' => 'ThisDocument',
          'Paragraph' => 'ThisDocument.Paragraphs(1)',
          _ => 'ThisDocument.Paragraphs(1).Range',
        };
        _reject(
          'destination = $expression',
          'vba_type_error',
          declarations: 'Dim destination As $type',
        );
      });
      test('$type arrays remain forbidden', () {
        _reject(
          '',
          'vba_unsupported',
          declarations: 'Dim values(0 To 1) As $type',
        );
      });
      test('$type function returns remain forbidden', () {
        expect(
          () => _compile(
            '${_module('')}\nFunction ObjectValue() As $type\nEnd Function',
          ),
          throwsA(_error('vba_unsupported')),
        );
      });
    }
    for (final member in <String>[
      'target.Text = "replacement"',
      'target.Value2 = "spreadsheet"',
      'target.ClearContents',
      'target.Interior.Color = RGB(1,2,3)',
      'target.Font.Underline = True',
      'target.ParagraphFormat.LeftIndent = 12',
      'value = target.Text',
      'value = target.Start',
      'value = target.End',
      'value = target.Count',
      'Dim sheet As Worksheet',
      'Worksheets(1).Range("A1").Value2 = "x"',
      'ThisWorkbook.Worksheets(1).Range("A1").Value2 = "x"',
    ]) {
      test('unsupported object path is rejected in unused code: $member', () {
        _reject(
          'If False Then\n$member\nEnd If',
          'vba_unsupported',
          declarations: 'Dim value As Variant',
        );
      });
    }
    test('Paragraphs cannot expose a live collection without an index', () {
      _reject(
        'value = ThisDocument.Paragraphs.Count',
        'vba_type_error',
        declarations: 'Dim value As Variant',
      );
    });
    for (final object in <String>[
      'ActiveDocument',
      'Selection',
      'Application',
    ]) {
      test('ambient $object is never consulted', () {
        _reject(
          '$object.Paragraphs(1).Range.InsertBefore "x"',
          'vba_name_error',
        );
      });
    }
    test('Word ranges cannot be enumerated', () {
      _reject(
        'For Each item In target\nNext item',
        'vba_unsupported',
        declarations: 'Dim item As Range',
      );
    });
    test('unbound object references retain explicit Set requirement', () {
      _reject(
        'documentAlias.Paragraphs(1).Range.InsertBefore "x"',
        'vba_unsupported',
        declarations: 'Dim documentAlias As Document',
      );
    });
    for (final syntax in <String>[
      'target.InsertBefore',
      'target.InsertBefore()',
      'target.InsertBefore "x", "y"',
    ]) {
      test('InsertBefore requires one argument: $syntax', () {
        _reject(syntax, 'vba_type_error');
      });
    }
    test('Call method syntax requires parentheses', () {
      _reject('Call target.InsertBefore "x"', 'vba_unsupported');
    });
    test('Word names do not newly reserve Excel variable identifiers', () {
      final plan = const OfficeVbaMacroLanguage().compile(
        OfficeMacroSource(
          language: 'vba-excel',
          format: OfficeMacroFormat.xlsx,
          source: '''
Sub Main()
Dim ThisDocument As Long, Paragraphs As Long, wdAlignParagraphLeft As Long
ThisDocument = 1
Paragraphs = 2
wdAlignParagraphLeft = 3
Worksheets(1).Range("A1").Value2 = ThisDocument + Paragraphs + wdAlignParagraphLeft
End Sub
''',
        ),
      );
      expect(plan.steps.single.arguments['value'], 6);
    });
  });

  group('shared resource limits', () {
    test('empty loops remain bounded in Word', () {
      _reject('Do\nLoop', 'vba_limit_exceeded');
    });
    test(
      'repeated insertion charges string publication against shared work',
      () {
        _reject(
          '''
text = "x"
For index = 1 To 14
  text = text & text
Next index
For index = 1 To 8
  target.InsertBefore text
Next index
''',
          'vba_limit_exceeded',
          declarations: 'Dim text As String, index As Long',
        );
      },
    );
    test('Word emission cannot exceed the shared operation limit', () {
      _reject(
        'For index = 1 To 10001\n  target.Font.Bold = True\nNext index',
        'vba_limit_exceeded',
        declarations: 'Dim index As Long',
      );
    });
  });
}
