import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';

// Portable source-compiler receipt: run on Dart VM and compiled JavaScript and
// compare the complete stdout bytes. Expectations are specification-derived
// and bounded-dialect checks, not observations from an installed Office host.
const _cases = <(String, String)>[
  ('StrComp("ABCD", "abcd")', '-1'),
  ('StrComp("abcd", "ABCD", vbBinaryCompare)', '1'),
  ('StrComp("same", "same", 0)', '0'),
  ('StrComp("abc", "abcd")', '-1'),
  ('StrComp("abcd", "abc")', '1'),
  ('StrComp(Empty, "")', '0'),
  ('StrComp("x", Empty)', '1'),
  ('StrComp(ChrW(0), "")', '1'),
  ('StrComp("😀", ChrW(57344))', '-1'),
  ('StrComp(ChrW(57344), "😀")', '1'),
  (r'StrComp(Mid$("😀", 2, 1), Mid$("😁", 2, 1))', '-1'),
  ('StrComp(CVar("é"), "é")', '1'),
  ('IsNull(StrComp(Null, "x"))', 'True'),
  ('IsNull(StrComp("x", Null, 0))', 'True'),
  ('IsNull(StrComp(Null, Empty))', 'True'),
];
const _refusals = <(String, String)>[
  ('StrComp(Null, "x", vbTextCompare)', 'vba_unsupported'),
  ('StrComp("x", Null, vbUseCompareOption)', 'vba_unsupported'),
  ('StrComp(Null, "x", Null)', 'vba_invalid_use_of_null'),
  ('StrComp("x", "y", Empty)', 'vba_type_error'),
  ('StrComp(CVar(1), "1")', 'vba_type_error'),
  ('StrComp(Null, CVar(True))', 'vba_type_error'),
  ('StrComp("a", "b", 0.5)', 'vba_type_error'),
  ('StrComp("a", "b", compare:=0)', 'vba_unsupported'),
];
const _hosts = <(String, OfficeMacroFormat)>[
  ('vba-word', OfficeMacroFormat.docx),
  ('vba-excel', OfficeMacroFormat.xlsx),
  ('vba-powerpoint', OfficeMacroFormat.pptx),
];

OfficeMacro _source(String host, OfficeMacroFormat format, String body) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: host,
        format: format,
        moduleName: 'StringComparisonSmoke',
        source: 'Sub Main()\n$body\nEnd Sub',
      ),
    );

OfficeMacro _expression(
  String host,
  OfficeMacroFormat format,
  String expression,
) => _source(host, format, switch (host) {
  'vba-word' =>
    'ActiveDocument.Tables(1).Cell(1, 1).Range.Text = CStr($expression)',
  'vba-excel' => 'Worksheets(1).Range("A1").Value2 = CStr($expression)',
  _ =>
    'ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text = CStr($expression)',
});

void main() {
  final receipts = <Map<String, Object?>>[];
  for (final (host, format) in _hosts) {
    for (final (expression, expected) in _cases) {
      final plan = _expression(host, format, expression);
      final step = plan.steps.single;
      final actual = step.arguments[host == 'vba-excel' ? 'value' : 'text'];
      if (actual != expected) {
        throw StateError('$host $expression: $actual, expected $expected');
      }
      receipts.add({
        'host': host,
        'expression': expression,
        'result': actual,
        'arguments': step.arguments,
      });
    }
    for (final (expression, expected) in _refusals) {
      try {
        _expression(host, format, expression);
        throw StateError('$host accepted $expression');
      } on OfficeVbaCompileException catch (error) {
        if (error.code != expected || error.line < 1 || error.column < 1) {
          throw StateError(
            '$host $expression: ${error.code}, expected $expected',
          );
        }
        receipts.add({
          'host': host,
          'expression': expression,
          'error': error.code,
          'line': error.line,
          'column': error.column,
        });
      }
    }
    try {
      _source(host, format, '''
Dim text As String, result As Variant, index As Long
text = "${'a' * 20000}"
For index = 1 To 3
  result = StrComp(text, text)
Next index
''');
      throw StateError('$host failed to meter repeated comparisons');
    } on OfficeVbaCompileException catch (error) {
      if (error.code != 'vba_limit_exceeded') rethrow;
      receipts.add({'host': host, 'workLimit': error.code});
    }
  }
  print(jsonEncode({'cases': receipts.length, 'receipts': receipts}));
}
