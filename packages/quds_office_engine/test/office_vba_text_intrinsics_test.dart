import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

OfficeMacro _source(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    source: source,
    moduleName: 'TextIntrinsics',
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Object? _value(String expression) => _compile(
  'Worksheets(1).Range("A1").Value2 = $expression',
).steps.single.arguments['value'];

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.moduleName, 'module', 'TextIntrinsics')
        .having((e) => e.line, 'line', greaterThan(0))
        .having((e) => e.column, 'column', greaterThan(0));

void _reject(String expression, String code) =>
    expect(() => _value(expression), throwsA(_error(code)), reason: expression);

void main() {
  // Specification-derived scalar expectations, not recorded Office-host runs.
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/instr-function
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/instrrev-function
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/replace-function
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/ltrim-rtrim-and-trim-functions
  // https://learn.microsoft.com/en-us/office/vba/language/concepts/getting-started/returning-strings-from-functions
  group('binary UTF-16 search', () {
    for (final (expression, expected) in <(String, int)>[
      ('InStr("XXpXXpXXPXXP", "P")', 9),
      ('InStr(4, "XXpXXpXXPXXP", "p", vbBinaryCompare)', 6),
      ('InStr(10, "XXpXXpXXPXXP", "P", 0)', 12),
      ('InStr(7, "XXpXXpXXPXXP", "p")', 0),
      ('InStr("ababa", "aba")', 1),
      ('InStr(2, "ababa", "aba")', 3),
      ('InStr("ABABDABACDABABCABAB", "ABABCABAB")', 11),
      ('InStr("abc", "abcd")', 0),
      ('InStr(4, "abc", "a")', 0),
      ('InStr(2147483647, "abc", "a")', 0),
      ('InStr("", "")', 0),
      ('InStr("", "a")', 0),
      ('InStr("abc", "")', 1),
      ('InStr(2, "abc", "")', 2),
      ('InStr(10, "abc", "")', 10),
      ('InStr("A😀B😀C", "😀")', 2),
      ('InStr(3, "A😀B😀C", "😀")', 5),
      (r'InStr("😀", Mid$("😀", 2, 1))', 2),
      ('InStrRev("XXpXXpXXPXXP", "P")', 12),
      ('InStrRev("XXpXXpXXPXXP", "P", -1, vbBinaryCompare)', 12),
      ('InStrRev("XXpXXpXXPXXP", "P", 11, 0)', 9),
      ('InStrRev("XXpXXpXXPXXP", "p", 12)', 6),
      ('InStrRev("aaaa", "aa")', 3),
      ('InStrRev("aaaa", "aa", 3)', 2),
      ('InStrRev("aaaa", "aa", 1)', 0),
      ('InStrRev("ABABDABACDABABCABAB", "ABABCABAB")', 11),
      ('InStrRev("abc", "abcd")', 0),
      ('InStrRev("abc", "a", 4)', 0),
      ('InStrRev("abc", "a", 2147483647)', 0),
      ('InStrRev("", "")', 0),
      ('InStrRev("", "a")', 0),
      ('InStrRev("abc", "")', 3),
      ('InStrRev("abc", "", 2)', 2),
      ('InStrRev("abc", "", 4)', 0),
      ('InStrRev("A😀B😀C", "😀")', 5),
      ('InStrRev("A😀B😀C", "😀", 5)', 2),
      ('InStrRev("A😀B😀C", "😀", 2)', 0),
      (r'InStrRev("😀😀", Mid$("😀", 2, 1), 3)', 2),
    ]) {
      test('$expression = $expected', () {
        expect(_value(expression), expected);
      });
    }
  });

  group('bounded replacement', () {
    for (final (expression, expected) in <(String, String)>[
      ('Replace("abcabc", "a", "X")', 'XbcXbc'),
      ('Replace("abcabc", "a", "X", 4)', 'Xbc'),
      ('Replace("abcabc", "a", "X", 2)', 'bcXbc'),
      ('Replace("abcabc", "a", "X", 2, 0)', 'bcabc'),
      ('Replace("abcabc", "", "X", 2)', 'bcabc'),
      ('Replace("abcabc", "q", "X", 2)', 'bcabc'),
      ('Replace("aaaa", "aa", "X")', 'XX'),
      ('Replace("aaaa", "aa", "X", 1, 1)', 'Xaa'),
      ('Replace("aaaa", "aa", "X", 1, -1, vbBinaryCompare)', 'XX'),
      ('Replace("aaa", "aa", "X")', 'Xa'),
      ('Replace("a", "a", "aa")', 'aa'),
      ('Replace("ABabAB", "AB", "x", 1, 2147483647, 0)', 'xabx'),
      ('Replace("a-b-c", "-", "")', 'abc'),
      ('Replace("aaaa", "aa", "")', ''),
      ('Replace("", "a", "X")', ''),
      ('Replace("", "", "X")', ''),
      ('Replace("abc", "a", "X", 4)', ''),
      ('Replace("abc", "a", "X", 2147483647)', ''),
      ('Replace("abc", "", "X", 4)', ''),
      ('Replace("abc", "a", "X", 4, 0)', ''),
      ('Replace("A😀B😀C", "😀", "X")', 'AXBXC'),
      ('Replace("A😀B😀C", "😀", "X", 4, 1)', 'BXC'),
    ]) {
      test('$expression produces the specified suffix', () {
        expect(_value(expression), expected);
      });
    }
    test('substring boundaries retain code units before final output', () {
      expect(_value(r'Len(Replace("😀", Mid$("😀", 2, 1), ""))'), 1);
      expect(
        _value(r'Replace("😀", Mid$("😀", 2, 1), "") & Mid$("😀", 2, 1)'),
        '😀',
      );
    });
  });

  group('trim only U+0020 spaces', () {
    for (final name in <String>['Trim', r'Trim$', 'tRiM', r'tRiM$']) {
      test('$name trims both edges and retains interior spacing', () {
        expect(_value('$name("  a  b  ")'), 'a  b');
        expect(_value('$name("   ")'), '');
        expect(_value('$name("")'), '');
        expect(_value('$name("abc")'), 'abc');
        expect(_value('$name("  \t a \t  ")'), '\t a \t');
        expect(_value('$name(" \u00a0\u2003\u3000 ")'), '\u00a0\u2003\u3000');
      });
    }
    for (final name in <String>['LTrim', r'LTrim$', 'lTrIm', r'lTrIm$']) {
      test('$name trims only the left edge', () {
        expect(_value('$name("  a  b  ")'), 'a  b  ');
        expect(_value('$name("   ")'), '');
        expect(_value('$name("  \t a \t  ")'), '\t a \t  ');
      });
    }
    for (final name in <String>['RTrim', r'RTrim$', 'rTrIm', r'rTrIm$']) {
      test('$name trims only the right edge', () {
        expect(_value('$name("  a  b  ")'), '  a  b');
        expect(_value('$name("   ")'), '');
        expect(_value('$name("  \t a \t  ")'), '  \t a \t');
      });
    }
  });

  group('strict argument contract', () {
    for (final bad in <String>[
      '0',
      '-1',
      '1.5',
      '2147483648',
      'True',
      '"1"',
      'Null',
      'Empty',
    ]) {
      test('forward start rejects $bad even for empty input', () {
        _reject('InStr($bad, "", "")', 'vba_type_error');
        _reject('Replace("", "", "", $bad)', 'vba_type_error');
      });
    }
    for (final bad in <String>[
      '0',
      '-2',
      '1.5',
      '2147483648',
      'True',
      '"1"',
      'Null',
      'Empty',
    ]) {
      test('reverse start rejects $bad even for empty input', () {
        _reject('InStrRev("", "", $bad)', 'vba_type_error');
      });
    }
    for (final bad in <String>[
      '-2',
      '1.5',
      '2147483648',
      'True',
      '"1"',
      'Null',
      'Empty',
    ]) {
      test('count rejects $bad even for a no-op replacement', () {
        _reject('Replace("", "", "", 1, $bad)', 'vba_type_error');
        _reject('Replace("a", "", "b", 2, $bad)', 'vba_type_error');
      });
    }
    for (final bad in <String>[
      'vbTextCompare',
      'vbDatabaseCompare',
      'vbUseCompareOption',
      '3',
      '1031',
    ]) {
      test('comparison mode $bad is explicitly refused before shortcuts', () {
        _reject('InStr(1, "", "", $bad)', 'vba_unsupported');
        _reject('InStrRev("", "", -1, $bad)', 'vba_unsupported');
        _reject('Replace("", "", "", 1, 0, $bad)', 'vba_unsupported');
      });
    }
    for (final bad in <String>['0.5', 'True', '"0"', 'Null', 'Empty']) {
      test('comparison mode requires actual integral numbers: $bad', () {
        _reject('InStr(1, "", "", $bad)', 'vba_type_error');
        _reject('InStrRev("", "", -1, $bad)', 'vba_type_error');
        _reject('Replace("", "", "", 1, 0, $bad)', 'vba_type_error');
      });
    }
    for (final bad in <String>[
      '1',
      'True',
      'Empty',
      'Null',
      'CVar(1)',
      'CVar(Null)',
    ]) {
      test(
        'string operands reject scalar coercion and Null propagation: $bad',
        () {
          for (final expression in <String>[
            'InStr($bad, "x")',
            'InStr("x", $bad)',
            'InStrRev($bad, "x")',
            'InStrRev("x", $bad)',
            'Replace($bad, "x", "y")',
            'Replace("x", $bad, "y")',
            'Replace("x", "y", $bad)',
            'Trim($bad)',
            'Trim\$($bad)',
            'LTrim($bad)',
            'RTrim\$($bad)',
          ]) {
            _reject(expression, 'vba_type_error');
          }
        },
      );
    }
    test('actual String Variants are admitted', () {
      expect(_value('Trim(CVar(" a "))'), 'a');
      expect(_value('Replace(CVar("aba"), CVar("a"), CVar("x"))'), 'xbx');
      expect(_value('InStr(CVar("aba"), CVar("b"))'), 2);
    });
    for (final expression in <String>[
      'InStr()',
      'InStr("a")',
      'InStr(1, "a", "a", 0, 0)',
      'InStrRev()',
      'InStrRev("a")',
      'InStrRev("a", "a", 1, 0, 0)',
      'Replace()',
      'Replace("a", "b")',
      'Replace("a", "a", "b", 1, 1, 0, 0)',
      'Trim()',
      'Trim("a", "b")',
      r'LTrim$()',
      r'RTrim$("a", "b")',
    ]) {
      test('reject wrong arity: $expression', () {
        _reject(expression, 'vba_type_error');
      });
    }
    for (final expression in <String>[
      'InStr(, "abc", "a")',
      'InStr(1, "abc", "a", )',
      'InStrRev("abc", "a", , 0)',
      'Replace("abc", "a", "x", , 1)',
      'Replace("abc", "a", "x", 1, , 0)',
      'Trim(string:=" a ")',
      'InStr(start:=1, string1:="abc", string2:="a")',
      'InStrRev(stringcheck:="abc", stringmatch:="a")',
      'Replace(expression:="abc", find:="a", replace:="x")',
    ]) {
      test('reject named/interior omitted arguments: $expression', () {
        _reject(expression, 'vba_unsupported');
      });
    }
    for (final unsupported in <String>[
      r'Replace$("a", "a", "x")',
      r'InStr$("a", "a")',
      'InStrB("a", "a")',
    ]) {
      test('does not infer unsupported aliases: $unsupported', () {
        expect(
          () => _value(unsupported),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      });
    }
    for (final compare in ['Binary', 'Text', 'Database']) {
      test('Option Compare $compare remains unsupported', () {
        expect(
          () => _source('Option Compare $compare\nSub Main()\nEnd Sub'),
          throwsA(_error('vba_unsupported')),
        );
      });
    }
  });

  test('all dialects share binary intrinsics and constants', () {
    for (final (language, format, statement, field) in [
      (
        'vba-word',
        OfficeMacroFormat.docx,
        'ActiveDocument.Paragraphs(1).Range.InsertBefore',
        'text',
      ),
      (
        'vba-excel',
        OfficeMacroFormat.xlsx,
        'Worksheets(1).Range("A1").Value2 =',
        'value',
      ),
      (
        'vba-powerpoint',
        OfficeMacroFormat.pptx,
        'ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text =',
        'text',
      ),
    ]) {
      final plan = OfficeMacroLanguages().compile(
        OfficeMacroSource(
          language: language,
          format: format,
          source:
              '''
Sub Main()
  Dim label As String
  label = Replace(Trim\$("  report-a  "), "a", "b", 1, -1, vbBinaryCompare)
  $statement label & ":" & CStr(InStrRev(label, "-"))
End Sub
''',
        ),
      );
      expect(plan.steps.single.arguments[field], 'report-b:7');
    }
  });

  test('evaluates source argument expressions once in written order', () {
    final plan = _source('''
Function Mark(ByVal label As String, ByVal value As String) As String
  Worksheets(1).Range("A1").Value2 = label
  Mark = value
End Function
Sub Main()
  Worksheets(1).Range("A2").Value2 = Replace(Mark("source", "aba"), Mark("find", "a"), Mark("replacement", "x"))
End Sub
''');
    expect(plan.steps.map((s) => s.arguments['value']), [
      'source',
      'find',
      'replacement',
      'xbx',
    ]);
  });

  test('type/shape checks visit unused helpers and inactive branches', () {
    for (final expression in <String>[
      'InStr("a", True)',
      'Trim(1)',
      'Replace("a", "b")',
      'InStrRev("a", "b", , 0)',
    ]) {
      final expected = expression.contains(', ,')
          ? 'vba_unsupported'
          : 'vba_type_error';
      for (final source in <String>[
        'Sub Main()\nDim x As Variant\nIf False Then\nx = $expression\nEnd If\nEnd Sub',
        'Sub Main()\nEnd Sub\nSub Unused()\nDim x As Variant\nx = $expression\nEnd Sub',
      ]) {
        expect(() => _source(source), throwsA(_error(expected)));
      }
    }
  });

  group('bounded scan and allocation work', () {
    final longText = 'a' * 20000;
    for (final expression in <String>[
      'InStr(text, "b")',
      'InStrRev(text, "b")',
      'Replace(text, "b", "x")',
      'Trim(text)',
      r'LTrim$(text)',
      r'RTrim$(text)',
    ]) {
      test('repeated discarded results consume work: $expression', () {
        expect(
          () => _compile('''
Dim text As String, value As Variant, i As Long
text = "$longText"
For i = 1 To 6
  value = $expression
Next i
'''),
          throwsA(_error('vba_limit_exceeded')),
        );
      });
    }
    test('trimming all spaces charges scans although result is empty', () {
      final spaces = ' ' * 20000;
      expect(
        () => _compile('''
Dim text As String, value As String, i As Long
text = "$spaces"
For i = 1 To 6
  value = Trim(text)
Next i
'''),
        throwsA(_error('vba_limit_exceeded')),
      );
    });
    test('repetitive patterns stay within a linear scan budget', () {
      final text = '${'a' * 18000}b';
      final pattern = '${'a' * 6000}b';
      expect(_value('InStr("$text", "$pattern")'), 12001);
      expect(_value('InStrRev("$text", "$pattern")'), 12001);
    });
    test('replacement expansion is refused before output construction', () {
      final text = 'a' * 8192;
      _reject('Replace("$text", "a", "abcdefghij")', 'vba_limit_exceeded');
    });
    test('accepts exact result limit and rejects the next code unit', () {
      final suffix = 'a' * 32766;
      expect(
        (_value('Replace("X", "X", "$suffix" & "b")') as String).length,
        32767,
      );
      _reject('Replace("XXX", "X", "$suffix", 1, 1)', 'vba_limit_exceeded');
    });
    test('count limit prevents unnecessary scanning and output growth', () {
      final text = 'a' * 20000;
      expect(
        (_value('Replace("$text", "a", "X", 1, 1)') as String),
        'X${'a' * 19999}',
      );
    });
    test('a late invalid search publishes no partial plan', () {
      expect(
        () => _compile('''
Worksheets(1).Range("A1").Value2 = "earlier"
Worksheets(1).Range("A2").Value2 = InStrRev("abc", "b", 0)
'''),
        throwsA(_error('vba_type_error')),
      );
    });
  });
}
