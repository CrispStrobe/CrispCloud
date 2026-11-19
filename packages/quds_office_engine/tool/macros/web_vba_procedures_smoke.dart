import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    source: source,
    moduleName: 'PortableProcedures',
  ),
);

/// Checks call scopes, exits, budgets, and publication after Dart-to-JS lowering.
Future<void> main() async {
  final builder = XlsxWorkbookBuilder();
  builder.addSheet('Summary').addRow(<Object?>['Before']);
  final session = OfficeMacroSession(
    builder.build(),
    format: OfficeMacroFormat.xlsx,
  );
  final macro = _compile('''
Option Explicit
Sub Main()
  Dim row As Long, amount As Long
  amount = 21
  With Worksheets("Summary")
    For row = 1 To 5
      If row = 4 Then
        Exit For
      End If
      WriteRow Worksheets("Summary"), row, Twice(amount)
    Next row
    .Range("B1").Value2 = amount
    .Range("B2").Value2 = row
    .Range("B3").Formula = "=SUM(A1:A3)"
  End With
End Sub
Sub WriteRow(ByVal sheet As Worksheet, ByVal row As Long, ByVal amount As Long)
  With sheet
    .Cells(row, 1).Value2 = amount
    Exit Sub
    .Cells(row, 1).Value2 = -1
  End With
End Sub
Function Twice(ByVal amount As Long) As Long
  amount = amount * 2
  Twice = amount
  Exit Function
  Twice = -1
End Function
''');
  if (macro.steps.length != 6) {
    throw StateError('Unexpected helper expansion: ${macro.steps.length}');
  }
  final original = base64Encode(session.bytes);
  await session.validate(macro);
  if (base64Encode(session.bytes) != original || session.revision != 0) {
    throw StateError('Procedure validation published changes');
  }
  await session.run(OfficeMacro.parse(macro.encode()));
  final sheet = SheetDeserializer().readBytes(session.bytes).sheets.single;
  if (sheet.cellA1('A3').value != 42 ||
      sheet.cellA1('A4').value != null ||
      sheet.cellA1('B1').value != 21 ||
      sheet.cellA1('B2').value != 4 ||
      sheet.cellA1('B3').value != 126) {
    throw StateError(
      'Procedure scopes, exits, or formulas changed in JavaScript',
    );
  }

  final failures = <(String, String)>[
    (
      '''
Sub Main()
End Sub
Sub Hidden()
  Call Hidden()
End Sub
''',
      'vba_unsupported',
    ),
    (
      '''
Sub Main()
  Dim index As Long
  For index = 1 To 8000
    Call Work()
  Next index
End Sub
Sub Work()
  Dim index As Long
  For index = 1 To 20
  Next index
End Sub
''',
      'vba_limit_exceeded',
    ),
    (
      '''
Sub Main()
  Worksheets(1).Range("A1").Value2 = Overflow()
End Sub
Function Overflow() As Double
  Overflow = 4294967296 * 4294967296
End Function
''',
      'vba_limit_exceeded',
    ),
  ];
  for (final (source, code) in failures) {
    try {
      _compile(source);
      throw StateError('Invalid helper module unexpectedly compiled');
    } on OfficeVbaCompileException catch (error) {
      if (error.code != code) rethrow;
    }
  }

  final beforeFailure = base64Encode(session.bytes);
  final failing = _compile('''
Sub Main()
  WriteValue Worksheets(1), 99
  WriteValue Worksheets("Missing"), 0
End Sub
Sub WriteValue(ByVal sheet As Worksheet, ByVal value As Long)
  sheet.Range("A1").Value2 = value
End Sub
''');
  try {
    await session.run(failing);
    throw StateError('Helper with missing worksheet unexpectedly ran');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed' || error.stepIndex != 1) rethrow;
  }
  if (base64Encode(session.bytes) != beforeFailure || session.revision != 1) {
    throw StateError('A failed helper plan changed the published workbook');
  }

  final mcp = OfficeMacroMcp(session);
  final compile = await mcp.callTool('office_macro_compile', <String, Object?>{
    'source': <String, Object?>{
      'language': 'vba-excel',
      'format': 'xlsx',
      'source': '''
Sub Main()
  Call PutText("Portable helpers")
End Sub
Sub PutText(ByVal text As String)
  Worksheets(1).Range("C1").Value2 = text
End Sub
''',
    },
  });
  if (compile['isError'] != false) {
    throw StateError('MCP helper compilation failed: $compile');
  }
  final content = compile['structuredContent']! as Map<String, Object?>;
  final run = await mcp.callTool('office_macro_run', <String, Object?>{
    'macro': content['macro'],
  });
  if (run['isError'] != false ||
      session.revision != 2 ||
      SheetDeserializer()
              .readBytes(session.bytes)
              .sheets
              .single
              .cellA1('C1')
              .value !=
          'Portable helpers') {
    throw StateError('MCP helper execution failed: $run');
  }

  print(
    jsonEncode(<String, Object?>{
      'language': 'vba-excel',
      'revision': session.revision,
      'steps': macro.steps.length,
      'byValCallerAmount': sheet.cellA1('B1').value,
      'exitForCounter': sheet.cellA1('B2').value,
      'formulaTotal': sheet.cellA1('B3').value,
      'procedureScopesAndExits': true,
      'recursionRejected': true,
      'sharedWorkBudget': true,
      'numericBounds': true,
      'validationPreservedBytes': true,
      'lateFailurePreservedBytes': true,
      'mcpCompileAndRun': true,
    }),
  );
}
