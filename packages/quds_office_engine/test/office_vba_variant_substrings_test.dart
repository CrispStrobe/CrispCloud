import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_cell_paragraphs_smoke.dart' as fixture;
import '../tool/macros/web_vba_word_mid_assignment_smoke.dart' as word;

OfficeMacro _source(
  String source, {
  String language = 'vba-excel',
  OfficeMacroFormat format = OfficeMacroFormat.xlsx,
}) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: language,
    format: format,
    source: source,
    moduleName: 'VariantSubstrings',
  ),
);

OfficeMacro _body(String body) => _source('Sub Main()\n$body\nEnd Sub');

Object? _value(String expression) => _body(
  'Worksheets(1).Range("A1").Value2 = $expression',
).steps.single.arguments['value'];

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.moduleName, 'module', 'VariantSubstrings')
        .having((error) => error.line, 'line', greaterThan(0))
        .having((error) => error.column, 'column', greaterThan(0));

void _reject(String expression, String code) =>
    expect(() => _value(expression), throwsA(_error(code)), reason: expression);

List<Object?> _values(OfficeMacro plan) => [
  for (final step in plan.steps) step.arguments['value'],
];

void main() {
  // Published Microsoft function contracts and explicit dialect restrictions.
  // No installed Office host supplied these expected values.
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/left-function
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/right-function
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/mid-function
  group('Variant substring values', () {
    for (final (expression, expected) in <(String, String)>[
      ('Left("abcdef", 2)', 'ab'),
      ('Right("abcdef", 2)', 'ef'),
      ('Mid("abcdef", 2, 3)', 'bcd'),
      ('Mid("abcdef", 4)', 'def'),
      ('Left("", 1)', ''),
      ('Right("", 1)', ''),
      ('Mid("", 1)', ''),
      ('Left("abc", 0)', ''),
      ('Right("abc", -0.0)', ''),
      ('Mid("abc", 2, 0)', ''),
      ('Mid("abc", 4)', ''),
      ('Mid("abc", 2147483647, 2147483647)', ''),
      ('Left("abc", 2147483647)', 'abc'),
      ('Right("abc", 2147483647)', 'abc'),
      ('Mid("abc", 2, 2147483647)', 'bc'),
      ('Left(Empty, 3)', ''),
      ('Right(CVar(Empty), 0)', ''),
      ('Mid(Empty, 1)', ''),
      ('Mid(Empty, 99, 1)', ''),
      ('Left(CVar("abc"), CVar(2.0))', 'ab'),
      ('Right(CVar("abc"), CVar(2))', 'bc'),
      ('mId(CVar("abc"), CVar(2), CVar(1))', 'b'),
      ('lEfT(rIgHt(mId("abcdef", 2), 4), 3)', 'cde'),
      ('Mid("a""b", 2, 1)', '"'),
      ('Left("東京", 1)', '東'),
      ('Right("سالم", 2)', 'لم'),
      ('Mid("A😀B", 2, 2)', '😀'),
      ('Left("A😀B", 3)', 'A😀'),
      ('Right("A😀B", 3)', '😀B'),
      ('Mid("e\u0301x", 2, 1)', '\u0301'),
    ]) {
      test(expression, () => expect(_value(expression), expected));
    }

    test('Empty becomes an empty String and is no longer Empty', () {
      expect(_value('IsEmpty(Left(Empty, 1))'), isFalse);
      expect(_value('IsEmpty(Right(Empty, 1))'), isFalse);
      expect(_value('IsEmpty(Mid(Empty, 1))'), isFalse);
      expect(_value('Len(Mid(Empty, 1))'), 0);
    });

    test('non-Null results assign to typed String locals and helpers', () {
      final plan = _source('''
Sub Main()
  Dim value As String
  value = Left("ABC-0042", 3)
  Worksheets(1).Range("A1").Value2 = value
  Worksheets(1).Range("A2").Value2 = Extract("ABC-0042")
End Sub
Function Extract(ByVal value As String) As String
  Extract = Mid(value, 5)
End Function
''');
      expect(_values(plan), ['ABC', '0042']);
    });

    test('array elements retain String/Empty/Null ownership through loops', () {
      final plan = _body('''
Dim parts(1 To 3) As Variant, results(1 To 3) As Variant
Dim emptyValue As Variant, item As Variant, index As Long
parts(1) = "ABC-0042"
parts(2) = Null
parts(3) = emptyValue
For index = 1 To 3
  results(index) = Mid(parts(index), 5, 4)
Next index
For Each item In results
  If IsNull(item) Then
    Worksheets(1).Range("A1").Value2 = "missing"
  Else
    Worksheets(1).Range("A1").Value2 = item
  End If
Next item
Worksheets(1).Range("A2").Value2 = parts(1)
Worksheets(1).Range("A3").Value2 = IsEmpty(parts(3))
''');
      expect(_values(plan), ['0042', 'missing', '', 'ABC-0042', true]);
    });

    test('dynamic String arrays retain bounds and copied substring values', () {
      final plan = _body('''
Dim parts() As String
ReDim parts(-1 To 0)
parts(-1) = Left("alpha", 2)
parts(0) = Right("omega", 2)
ReDim Preserve parts(-1 To 1)
parts(1) = Mid("ABC-0042", 5)
Worksheets(1).Range("A1").Value2 = Join(parts, "|")
Worksheets(1).Range("A2").Value2 = LBound(parts)
Worksheets(1).Range("A3").Value2 = UBound(parts)
''');
      expect(_values(plan), ['al|ga|0042', -1, 1]);
    });

    test(
      'statement and expression Mid coexist without retargeting aliases',
      () {
        final plan = _body(r'''
Dim label As String, copy As String
label = "abcdef"
copy = label
Mid(label, 2, 3) = Mid(label, 4)
Mid$(label, 1, 1) = Left("XYZ", 1)
Worksheets(1).Range("A1").Value2 = label
Worksheets(1).Range("A2").Value2 = Mid(label, 2, 3)
Worksheets(1).Range("A3").Value2 = copy
''');
        expect(_values(plan), ['Xdefef', 'def', 'abcdef']);
      },
    );
  });

  group('Null propagation and explicit coercion', () {
    for (final expression in [
      'Left(Null, 0)',
      'Left(CVar(Null), 2147483647)',
      'Right(Null, 1)',
      'Right(CVar(Null), 0)',
      'Mid(Null, 1)',
      'Mid(Null, 2147483647, 0)',
      'Mid(CVar(Null), 2, 2147483647)',
      'Mid(Right(Left(Null, 3), 2), 1)',
      'Left(StrComp(Null, "a"), 1)',
    ]) {
      test('$expression propagates Null', () {
        expect(_value('IsNull($expression)'), isTrue);
      });
    }

    test('a Null return remains Variant through a named helper argument', () {
      final plan = _source('''
Function Tail(ByVal input As Variant) As Variant
  Tail = Mid(input, 2)
End Function
Sub Main()
  Dim result As Variant
  result = Tail(input:=Null)
  Worksheets(1).Range("A1").Value2 = IsNull(result)
  Worksheets(1).Range("A2").Value2 = Tail(input:="abc")
End Sub
''');
      expect(_values(plan), [true, 'bc']);
    });

    for (final expression in [
      'Left(Null, 1)',
      'Right(Null, 1)',
      'Mid(Null, 1)',
    ]) {
      test('$expression cannot implicitly become a String or cell value', () {
        expect(
          () => _body('Dim text As String\ntext = $expression'),
          throwsA(_error('vba_invalid_use_of_null')),
        );
        _reject(expression, 'vba_invalid_use_of_null');
        _reject('CStr($expression)', 'vba_invalid_use_of_null');
      });
    }

    for (final argument in ['42', 'True', 'CVar(42)', 'CVar(False)']) {
      test('String coercion remains explicit for $argument', () {
        _reject('Left($argument, 1)', 'vba_type_error');
        _reject('Right($argument, 1)', 'vba_type_error');
        _reject('Mid($argument, 1)', 'vba_type_error');
      });
    }

    test('explicit scalar conversions remain usable', () {
      expect(_value('Left(CStr(42), 1)'), '4');
      expect(_value('Right(CStr(True), 3)'), 'rue');
      expect(_value('Mid(CStr(-42), 2)'), '42');
    });

    test(
      'String-returning dollar forms retain their strict Empty/Null rule',
      () {
        for (final state in ['Empty', 'Null']) {
          _reject('Left\$($state, 1)', 'vba_type_error');
          _reject('Right\$($state, 1)', 'vba_type_error');
          _reject('Mid\$($state, 1)', 'vba_type_error');
        }
        expect(_value(r'Left$("abc", 2)'), 'ab');
        expect(_value(r'Right$("abc", 2)'), 'bc');
        expect(_value(r'Mid$("abc", 2)'), 'bc');
      },
    );
  });

  group('numeric boundaries before Null propagation', () {
    // This is an explicit dialect rule. It does not assert which invalid
    // argument an installed Office version reports first.
    for (final argument in [
      '-1',
      '1.5',
      '2147483648',
      '"1"',
      'True',
      'Empty',
      'Null',
      'CVar("1")',
    ]) {
      test('invalid length $argument is refused for String/Empty/Null', () {
        for (final input in ['"abc"', 'Empty', 'Null']) {
          _reject('Left($input, $argument)', 'vba_type_error');
          _reject('Right($input, $argument)', 'vba_type_error');
          _reject('Mid($input, 99, $argument)', 'vba_type_error');
        }
      });
    }
    for (final argument in [
      '0',
      '-1',
      '1.5',
      '2147483648',
      '"1"',
      'True',
      'Empty',
      'Null',
    ]) {
      test('invalid start $argument is refused even with Null input', () {
        _reject('Mid(Null, $argument)', 'vba_type_error');
        _reject('Mid(Null, $argument, 0)', 'vba_type_error');
      });
    }

    test('invalid length retains its exact source diagnostic location', () {
      const statement = '  result = Mid(Null, 99, -1)';
      expect(
        () => _body(statement),
        throwsA(
          _error('vba_type_error')
              .having((error) => error.line, 'line', 2)
              .having(
                (error) => error.column,
                'column',
                statement.indexOf('-1') + 1,
              ),
        ),
      );
    });
  });

  group('binding and argument evaluation', () {
    test(
      'evaluates each supplied helper once in written order before Null',
      () {
        final plan = _source('''
Sub Main()
  Dim result As Variant
  result = Mid(TextValue(), StartValue(), CountValue())
  Worksheets(1).Range("A1").Value2 = IsNull(result)
  result = Left(TextValue(), CountValue())
  Worksheets(1).Range("A2").Value2 = IsNull(result)
  result = Right(TextValue(), CountValue())
  Worksheets(1).Range("A3").Value2 = IsNull(result)
End Sub
Function TextValue() As Variant
  Worksheets(1).Range("Z1").Value2 = "text"
  TextValue = Null
End Function
Function StartValue() As Long
  Worksheets(1).Range("Z2").Value2 = "start"
  StartValue = 2
End Function
Function CountValue() As Long
  Worksheets(1).Range("Z3").Value2 = "length"
  CountValue = 0
End Function
''');
        expect(_values(plan), [
          'text',
          'start',
          'length',
          true,
          'text',
          'length',
          true,
          'text',
          'length',
          true,
        ]);
      },
    );

    test('later argument expressions still run before index validation', () {
      expect(
        () => _source('''
Sub Main()
  Dim result As Variant
  result = Mid(Null, 0, Fail())
End Sub
Function Fail() As Long
  Fail = 1 / 0
End Function
'''),
        throwsA(_error('vba_arithmetic_error')),
      );
    });

    for (final expression in [
      'Left()',
      'Left("abc")',
      'Left("abc", 1, 2)',
      'Right()',
      'Right("abc")',
      'Right("abc", 1, 2)',
      'Mid()',
      'Mid("abc")',
      'Mid("abc", 1, 2, 3)',
      'Left(Worksheets(1), 1)',
    ]) {
      test('bad arity or object input: $expression', () {
        _reject(expression, 'vba_type_error');
      });
    }

    for (final expression in [
      'Left(string:="abc", length:=1)',
      'Right("abc", length:=1)',
      'Mid("abc", start:=1)',
      'Mid("abc",,1)',
      'Mid("abc",1,)',
    ]) {
      test('named and omitted arguments remain unsupported: $expression', () {
        _reject(expression, 'vba_unsupported');
      });
    }

    test('unused procedures and inactive branches retain static checks', () {
      expect(
        () => _body('If False Then\nresult = Left("a", True)\nEnd If'),
        throwsA(_error('vba_type_error')),
      );
      expect(
        () => _source('''
Sub Main()
End Sub
Sub Unused()
  result = Mid("a")
End Sub
'''),
        throwsA(_error('vba_type_error')),
      );
      expect(
        () => _source('''
Sub Main()
End Sub
Function Recursive() As Variant
  Recursive = Left(Recursive(), 1)
End Function
'''),
        throwsA(_error('vba_unsupported')),
      );
    });

    test('new intrinsic names are reserved and not statement calls', () {
      for (final name in ['Left', 'Right', 'Mid']) {
        expect(
          () => _body('Dim $name As String'),
          throwsA(_error('vba_name_error')),
        );
        expect(
          () => _source(
            'Sub Main()\nEnd Sub\nFunction $name() As String\nEnd Function',
          ),
          throwsA(_error('vba_name_error')),
        );
        expect(
          () => _body('Call $name("abc", 1)'),
          throwsA(_error('vba_unsupported')),
        );
      }
    });

    test('whole arrays, byte forms and constant calls remain unsupported', () {
      expect(
        () => _body('Dim values(1) As String\nresult = Left(values, 1)'),
        throwsA(_error('vba_type_error')),
      );
      for (final name in ['LeftB', 'RightB', 'MidB']) {
        _reject('$name("abc", 1)', 'vba_unsupported');
      }
      expect(
        () => _body('Const value As String = Left("abc", 1)'),
        throwsA(_error('vba_unsupported')),
      );
    });
  });

  group('portable UTF-16 and native publication', () {
    test('internal surrogate units can be inspected and recombined', () {
      final plan = _body(r'''
Dim high As String, low As Variant, parts(1 To 2) As Variant
high = Left("😀", 1)
low = Right("😀", 1)
parts(1) = Mid("A😀B", 2, 1)
parts(2) = Mid("A😀B", 3, 1)
Worksheets(1).Range("A1").Value2 = Len(high)
Worksheets(1).Range("A2").Value2 = Len(low)
Worksheets(1).Range("A3").Value2 = high & low
Worksheets(1).Range("A4").Value2 = "A" & parts(1) & parts(2) & "B"
''');
      expect(_values(plan), [1, 1, '😀', 'A😀B']);
      expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
    });

    for (final (language, format, target) in [
      ('vba-excel', OfficeMacroFormat.xlsx, 'Worksheets(1).Range("A1").Value2'),
      (
        'vba-word',
        OfficeMacroFormat.docx,
        'ActiveDocument.Tables(1).Cell(1, 1).Range.Text',
      ),
      (
        'vba-powerpoint',
        OfficeMacroFormat.pptx,
        'ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text',
      ),
    ]) {
      test('$language shares substring and nullable branch behavior', () {
        final plan = _source(
          '''
Sub Main()
  Dim label As String, source As Variant
  source = Null
  label = Left("INV-0042", 3) & ":" & Right("INV-0042", 4)
  If IsNull(Mid(source, 2)) Then
    label = label & Mid(" / pending", 1)
  End If
  $target = label
End Sub
''',
          language: language,
          format: format,
        );
        final arguments = plan.steps.single.arguments;
        expect(
          arguments[language == 'vba-excel' ? 'value' : 'text'],
          'INV:0042 / pending',
        );
        expect(OfficeMacro.parse(plan.encode()).toJson(), plan.toJson());
      });

      test('$language refuses unrecombined surrogate output', () {
        for (final expression in [
          'Left("😀", 1)',
          'Right("😀", 1)',
          'Mid("A😀B", 2, 1)',
        ]) {
          expect(
            () => _source(
              'Sub Main()\n$target = $expression\nEnd Sub',
              language: language,
              format: format,
            ),
            throwsA(_error('vba_type_error')),
          );
        }
      });
    }

    for (final macroEnabled in [false, true]) {
      test(
        'Word native save and replay preserves untouched package content (macro-enabled=$macroEnabled)',
        () async {
          final input = word.wordMidAssignmentInput(macroEnabled: macroEnabled);
          final baseline = word.wordMidAssignmentUntouched(input);
          final plan = word.wordMidAssignmentPlan('''
Dim missing As Variant
missing = Null
ActiveDocument.Tables(1).Cell(1, 1).Range.Text = Left("INV-0042", 3)
ActiveDocument.Tables(1).Cell(1, 2).Range.Text = Right("INV-0042", 4)
ActiveDocument.Tables(1).Cell(2, 1).Range.Text = Mid("A😀B", 2, 2)
If IsNull(Mid(missing, 2)) Then
  ActiveDocument.Tables(1).Cell(2, 2).Range.Text = "pending"
End If
''');
          final session = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.docx,
          );
          await session.validate(plan);
          expect(session.bytes, input);
          expect(session.revision, 0);
          await session.run(OfficeMacro.parse(plan.encode()));
          expect(session.revision, 1);
          final recorder = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.docx,
          )..startRecording('Variant substring report');
          for (final step in plan.steps) {
            await recorder.callTool(step.tool, step.arguments);
          }
          final recorded = recorder.stopRecording();
          expect(recorded.steps, hasLength(4));
          final replay = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.docx,
          );
          await replay.run(recorded);
          for (final bytes in [session.bytes, replay.bytes]) {
            final document = WordDeserializer().readBytes(bytes);
            expect(
              fixture.wordCellParagraphs(document).map((cell) => cell.text),
              ['INV', '0042', '😀', 'pending', 'second 0/0'],
            );
            expect(word.wordMidAssignmentUntouched(bytes), baseline);
            final saved = WordSerializer().writeBytes(document);
            expect(word.wordMidAssignmentUntouched(saved), baseline);
            expect(
              fixture
                  .wordCellParagraphs(WordDeserializer().readBytes(saved))
                  .take(4)
                  .map((cell) => cell.text),
              ['INV', '0042', '😀', 'pending'],
            );
          }
        },
      );
    }

    test(
      'late native selector failure rolls back bytes and recording',
      () async {
        final input = word.wordMidAssignmentInput();
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.docx,
        );
        session.startRecording('Rollback');
        final plan = word.wordMidAssignmentPlan('''
ActiveDocument.Tables(1).Cell(1, 1).Range.Text = Left("changed", 4)
ActiveDocument.Tables(999).Cell(1, 1).Range.Text = Mid("rejected", 2)
''');
        await expectLater(
          session.run(plan),
          throwsA(isA<OfficeMacroException>()),
        );
        expect(base64Encode(session.bytes), base64Encode(input));
        expect(session.revision, 0);
        expect(session.stopRecording().steps, isEmpty);
      },
    );

    test(
      'a late compile error never publishes an earlier source operation',
      () {
        expect(
          () => _body('''
Worksheets(1).Range("A1").Value2 = Left("earlier", 3)
Worksheets(1).Range("A2").Value2 = Mid(Null, 0)
'''),
          throwsA(_error('vba_type_error')),
        );
      },
    );
  });

  group('bounded substring work and array storage', () {
    final large = 'x' * 32767;
    for (final expression in [
      'Left(text, 2147483647)',
      'Right(text, 2147483647)',
      'Mid(text, 1)',
    ]) {
      test('$expression charges complete copied results', () {
        String program(int count) =>
            '''
Dim text As String, result As Variant, index As Long
text = "$large"
For index = 1 To $count
  result = $expression
Next index
Worksheets(1).Range("A1").Value2 = Len(result)
''';
        expect(_values(_body(program(3))), [32767]);
        expect(() => _body(program(4)), throwsA(_error('vba_limit_exceeded')));
      });
    }

    test(
      'bounded output length, not an enormous requested count, is charged',
      () {
        expect(_value('Left("abc", 2147483647)'), 'abc');
        expect(_value('Mid("abc", 2147483647, 2147483647)'), '');
        expect(_value('IsNull(Mid(Null, 2147483647, 2147483647))'), isTrue);
        expect(
          () => _value('Left("$large" & "x", 1)'),
          throwsA(_error('vba_limit_exceeded')),
        );
      },
    );

    test('Variant substring array assignments retain occupancy bounds', () {
      String program(int length) =>
          '''
Dim text As String, items(0 To 32) As Variant, index As Long
text = "$large"
For index = 0 To 31
  items(index) = text
Next index
items(32) = Left(text, $length)
Worksheets(1).Range("A1").Value2 = Len(items(32))
''';
      expect(_values(_body(program(32))), [32]);
      expect(() => _body(program(33)), throwsA(_error('vba_limit_exceeded')));
    });

    test('source evaluation is metered even when every result is Null', () {
      expect(
        () => _body('''
Dim value As Variant, index As Long
For index = 1 To 2147483647
  value = Mid(Null, 1)
Next index
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
  });
}
