@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_text_construction_smoke.dart' as portable;

OfficeMacro _source(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    source: source,
    moduleName: 'TextConstruction',
  ),
);

OfficeMacro _compile(String body) => _source('Sub Main()\n$body\nEnd Sub');

Object? _value(String expression) => _compile(
  'Worksheets(1).Range("A1").Value2 = $expression',
).steps.single.arguments['value'];

TypeMatcher<OfficeVbaCompileException> _error(String code) =>
    isA<OfficeVbaCompileException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.line, 'line', greaterThan(0))
        .having((e) => e.column, 'column', greaterThan(0));

void _reject(String expression, String code) =>
    expect(() => _value(expression), throwsA(_error(code)), reason: expression);

void main() {
  // Independent specification-derived expectations, not Office-host recordings.
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/space-function
  // https://learn.microsoft.com/en-us/office/vba/language/reference/user-interface-help/string-function
  // https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/de4b7500-260f-41c5-b2fd-082eddd5f0b2
  // https://learn.microsoft.com/en-us/openspecs/microsoft_general_purpose_programming_languages/ms-vbal/aab8e1d9-287d-4098-bf3a-14271eaa4b8e
  group('space and character repetition', () {
    for (final name in ['Space', r'Space$', 'sPaCe', r'sPaCe$']) {
      test('$name constructs exactly U+0020 spaces', () {
        expect(_value('$name(0)'), '');
        expect(_value('$name(1)'), ' ');
        expect(_value('"A" & $name(5) & "B"'), 'A     B');
        expect(_value('Len($name(32767))'), 32767);
      });
    }
    for (final name in ['String', r'String$', 'sTrInG', r'sTrInG$']) {
      test('$name repeats the first UTF-16 unit', () {
        expect(_value('$name(0, "ABC")'), '');
        expect(_value('$name(5, "*")'), '*****');
        expect(_value('$name(3, "ABC")'), 'AAA');
        expect(_value('$name(3, "éø")'), 'ééé');
        expect(_value('$name(3, "العربية")'), 'ااا');
        expect(_value('$name(2, ChrW(8364))'), '€€');
        expect(_value('Len($name(32767, "x"))'), 32767);
        // A scalar emoji is two code units. Its first unit can be examined
        // locally but cannot be published alone to a native Office document.
        expect(_value('Len($name(3, "😀"))'), 3);
        expect(_value('AscW($name(2, "😀"))'), -10179);
      });
    }
    test('actual scalar Variant payloads remain accepted', () {
      expect(_value('Space(CVar(3))'), '   ');
      expect(_value('String(CVar(3), CVar("yes"))'), 'yyy');
      expect(_value('ChrW(CVar(8364))'), '€');
      expect(_value('AscW(CVar("€ more"))'), 8364);
    });
    test('explicit conversions retain the existing strict scalar policy', () {
      expect(_value('Space(CLng("2"))'), '  ');
      expect(_value('String(2, CStr(42))'), '44');
      expect(_value('Space(CLng(Empty))'), '');
      expect(_value('ChrW(CLng("65"))'), 'A');
    });
  });

  group('UTF-16 construction and signed inspection', () {
    for (final name in ['ChrW', r'ChrW$', 'cHrW', r'cHrW$']) {
      for (final (code, signed) in <(int, int)>[
        (0, 0),
        (9, 9),
        (13, 13),
        (65, 65),
        (160, 160),
        (8364, 8364),
        (32767, 32767),
        (32768, -32768),
        (55295, -10241),
        (55357, -10179),
        (56832, -8704),
        (57344, -8192),
        (65535, -1),
        (-32768, -32768),
        (-32767, -32767),
        (-10179, -10179),
        (-8704, -8704),
        (-1, -1),
      ]) {
        test('AscW($name($code)) preserves the signed bit pattern', () {
          expect(_value('AscW($name($code))'), signed);
          expect(_value('Len($name($code))'), 1);
        });
      }
    }
    test('AscW examines only the first code unit', () {
      expect(_value('AscW("Apple")'), 65);
      expect(_value('aScW("€")'), 8364);
      expect(_value('AscW("😀suffix")'), -10179);
      expect(_value(r'AscW(Mid$("😀", 2, 1))'), -8704);
    });
    test('signed and unsigned surrogate construction agrees', () {
      expect(_value('ChrW(55357) & ChrW(56832)'), '😀');
      expect(_value(r'ChrW$(-10179) & ChrW$(-8704)'), '😀');
      expect(_value(r'String$(1, ChrW(55357)) & ChrW(56832)'), '😀');
    });
    test('the complete signed range has a portable inverse', () {
      // MS-VBAL's printed ChrW lower bound is -32767. The Quds contract
      // intentionally also admits -32768, so AscW(U+8000) can round-trip.
      expect(_value('ChrW(AscW(ChrW(32768)))'), '\u8000');
      expect(_value('ChrW(AscW(ChrW(65533)))'), '\ufffd');
    });
  });

  group('argument and resource boundaries', () {
    for (final bad in [
      '-1',
      '1.5',
      '2147483648',
      'True',
      '"2"',
      'Empty',
      'Null',
    ]) {
      test('length rejects $bad without implicit conversion', () {
        _reject('Space($bad)', 'vba_type_error');
        _reject('Space\$($bad)', 'vba_type_error');
        _reject('String($bad, "x")', 'vba_type_error');
      });
    }
    for (final bad in [
      '-32769',
      '65536',
      '1.5',
      'True',
      '"65"',
      'Empty',
      'Null',
    ]) {
      test('ChrW rejects $bad without truncation or wrapping', () {
        _reject('ChrW($bad)', 'vba_type_error');
        _reject('ChrW\$($bad)', 'vba_type_error');
      });
    }
    for (final bad in ['42', '256', '-1', 'CVar(42)']) {
      test('numeric String character $bad is explicitly unsupported', () {
        _reject('String(2, $bad)', 'vba_unsupported');
        _reject('String(0, $bad)', 'vba_unsupported');
      });
    }
    for (final bad in ['True', 'Empty', 'Null', 'CVar(Null)', '""']) {
      test('empty or non-String character $bad is refused even at zero', () {
        _reject('String(1, $bad)', 'vba_type_error');
        _reject('String(0, $bad)', 'vba_type_error');
      });
    }
    for (final bad in ['1', 'True', 'Empty', 'Null', 'CVar(1)', '""']) {
      test('AscW rejects $bad', () => _reject('AscW($bad)', 'vba_type_error'));
    }
    for (final expression in [
      'Space()',
      'Space(1, 2)',
      'String()',
      'String(1)',
      'String(1, "a", "b")',
      'ChrW()',
      'ChrW(65, 66)',
      'AscW()',
      'AscW("a", "b")',
    ]) {
      test('wrong arity is rejected: $expression', () {
        _reject(expression, 'vba_type_error');
      });
    }
    for (final expression in [
      'Space(number:=2)',
      'String(number:=2, character:="x")',
      'String(2, )',
      'String(, "x")',
      'ChrW(charcode:=65)',
      'AscW(stringvalue:="a")',
    ]) {
      test('named or omitted arguments remain unsupported: $expression', () {
        _reject(expression, 'vba_unsupported');
      });
    }
    for (final expression in [
      'Space(32768)',
      'Space(2147483647)',
      'String(32768, "a")',
      'String(2147483647, "a")',
    ]) {
      test('length is bounded before allocation: $expression', () {
        _reject(expression, 'vba_limit_exceeded');
      });
    }
    for (final expression in ['Space(25000)', 'String(25000, "x")']) {
      test('repeated construction shares the work budget: $expression', () {
        expect(
          () => _compile('''
Dim index As Long
Dim result As String
For index = 1 To 5
  result = $expression
Next index
'''),
          throwsA(_error('vba_limit_exceeded')),
        );
      });
    }
    test('generated strings still obey concatenation limits', () {
      _reject('Space(32767) & "x"', 'vba_limit_exceeded');
    });
    for (final (expression, code) in [
      ('Space(True)', 'vba_type_error'),
      ('String(2, 42)', 'vba_unsupported'),
      ('ChrW("65")', 'vba_type_error'),
      ('AscW(1)', 'vba_type_error'),
    ]) {
      test('inactive branches still type-check $expression', () {
        expect(
          () => _compile('''
Dim value As Variant
If False Then
  value = $expression
End If
'''),
          throwsA(_error(code)),
        );
      });
    }
    for (final name in ['Space', 'String', 'ChrW', 'AscW']) {
      test('new intrinsic name $name cannot be shadowed', () {
        expect(
          () => _compile('Dim $name As Long'),
          throwsA(_error('vba_name_error')),
        );
      });
    }
    for (final expression in ['ChrW(55357)', 'String(2, "😀")']) {
      test('isolated surrogates remain refused at native publication', () {
        _reject(expression, 'vba_type_error');
      });
    }
  });

  test('String arguments execute once in source order', () {
    final plan = _source('''
Function CountValue() As Long
  Worksheets(1).Range("A1").Value2 = "count"
  CountValue = 2
End Function
Function CharacterValue() As String
  Worksheets(1).Range("A2").Value2 = "character"
  CharacterValue = "XYZ"
End Function
Sub Main()
  Worksheets(1).Range("A3").Value2 = String(CountValue(), CharacterValue())
End Sub
''');
    expect(plan.steps.map((step) => step.arguments['value']), [
      'count',
      'character',
      'XX',
    ]);
  });

  test('all three dialects share typed helpers and Unicode construction', () {
    for (final (language, format, target, field) in [
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
Function BuildLabel(ByVal marker As String) As String
  BuildLabel = String\$(2, marker) & Space\$(2) & ChrW(55357) & ChrW(56832)
End Function
Sub Main()
  $target BuildLabel(ChrW(8364)) & ":" & CStr(AscW("😀"))
End Sub
''',
        ),
      );
      expect(plan.steps.single.arguments[field], '€€  😀:-10179');
    }
  });

  test(
    'complete Word example survives DOCM, validation and recording',
    () async {
      final receipt = await portable.runTextConstructionExample(
        File('example/macros/word_text_construction.bas').readAsStringSync(),
      );
      expect(receipt['operations'], 5);
      expect(receipt['revision'], 1);
      expect(receipt['additionalReopens'], 2);
      expect(receipt['recordedSteps'], 5);
      expect(receipt['opaqueVbaPreserved'], isTrue);
      expect(receipt['richFormattingPreserved'], isTrue);
      expect(receipt['lateRollback'], isTrue);
      expect(receipt['policyDenials'], 3);
      expect(receipt['text'], portable.textConstructionExpected);
    },
  );

  test(
    'ChrW can construct a supported Word tab without a new paragraph',
    () async {
      final session = OfficeMacroSession(
        (DocxDocumentBuilder()..paragraph('Report')).build(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(
        portable.textConstructionPlan(
          'ActiveDocument.Paragraphs(1).Range.InsertBefore ChrW(9)',
        ),
      );
      final document = WordDeserializer().readBytes(session.bytes);
      expect(document.paragraphs, hasLength(1));
      expect(document.paragraphs.single.text, '\tReport');
    },
  );

  for (final expression in ['ChrW(0)', 'ChrW(13)', 'ChrW(55357)']) {
    test(
      'generated forbidden Word text retains publication guard: $expression',
      () {
        expect(
          () => portable.textConstructionPlan(
            'ActiveDocument.Paragraphs(1).Range.InsertBefore $expression',
          ),
          throwsA(isA<OfficeVbaCompileException>()),
        );
      },
    );
  }
}
