import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

OfficeMacro _compile(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    source: source,
    moduleName: 'PortableControlFlow',
  ),
);

String _nested(int depth, String body) {
  final opening = <String>[];
  final closing = <String>[];
  for (var index = 0; index < depth; index++) {
    final pair = switch (index % 4) {
      0 => ('Do While True', 'Loop'),
      1 => ('While True', 'Wend'),
      2 => ('Select Case 1\nCase 1', 'End Select'),
      _ => ('With Worksheets(1)', 'End With'),
    };
    opening.add(pair.$1);
    closing.insert(0, pair.$2);
  }
  return '${opening.join('\n')}\n$body\n${closing.join('\n')}';
}

String _depthProgram(int frames, int blocks, int unary) {
  final operators = List<String>.filled(unary, '+').join();
  final source = StringBuffer('Sub Main()\n');
  source.writeln(
    _nested(
      blocks,
      'Worksheets(1).Range("A1").Value2 = ${operators}F1()\nExit Sub',
    ),
  );
  source.writeln('End Sub');
  for (var index = 1; index < frames; index++) {
    final value = index == frames - 1 ? '42' : 'F${index + 1}()';
    source.writeln('Function F$index() As Long');
    source.writeln(
      _nested(blocks, 'F$index = $operators$value\nExit Function'),
    );
    source.writeln('End Function');
  }
  return source.toString();
}

void _reject(String source, String code) {
  try {
    _compile(source);
    throw StateError('Invalid control-flow source unexpectedly compiled');
  } on OfficeVbaCompileException catch (error) {
    if (error.code != code || error.line < 1 || error.column < 1) rethrow;
  }
}

/// Runs cold depth stress before warming up the JavaScript evaluator, then
/// checks document execution, shared limits, rollback, and MCP compilation.
Future<void> main() async {
  final depth = _compile(_depthProgram(32, 32, 63));
  if (depth.steps.length != 1 || depth.steps.single.arguments['value'] != 42) {
    throw StateError('Combined procedure/block/expression depth changed');
  }
  _reject(_depthProgram(33, 32, 63), 'vba_limit_exceeded');
  _reject(_depthProgram(32, 33, 63), 'vba_limit_exceeded');

  final builder = XlsxWorkbookBuilder();
  builder.addSheet('Summary').addRow(<Object?>['Before']);
  final session = OfficeMacroSession(
    builder.build(),
    format: OfficeMacroFormat.xlsx,
  );
  final macro = _compile('''
Option Explicit
Sub Main()
  Dim row As Long
  row = 1
  With Worksheets("Summary")
    Do While row <= 4
      Select Case row
        Case 1
          .Cells(row, 1).Value2 = 10
        Case 2 To 3
          .Cells(row, 1).Value2 = row * 10
        Case Else
          .Cells(row, 1).Value2 = 40
      End Select
      row = row + 1
    Loop
    Do
      row = row - 1
    Loop Until row = 4
    While row > 0
      .Cells(row, 2).Value2 = row
      row = row - 1
    Wend
    Do
      Select Case 0
        Case 0
          Exit Do
      End Select
    Loop While NotReached()
    .Range("C1").Formula = "=SUM(A1:A4)"
  End With
End Sub
Function NotReached() As Boolean
  Worksheets("Summary").Range("Z1").Value2 = 999
  NotReached = True
End Function
''');
  if (macro.steps.length != 9) throw StateError('Unexpected loop expansion');
  final original = base64Encode(session.bytes);
  await session.validate(macro);
  if (base64Encode(session.bytes) != original || session.revision != 0) {
    throw StateError('Control-flow validation published changes');
  }
  await session.run(OfficeMacro.parse(macro.encode()));
  final sheet = SheetDeserializer().readBytes(session.bytes).sheets.single;
  for (var row = 1; row <= 4; row++) {
    if (sheet.cellA1('A$row').value != row * 10 ||
        sheet.cellA1('B$row').value != row) {
      throw StateError('Conditional loop/case result changed at row $row');
    }
  }
  if (sheet.cellA1('C1').value != 100 || sheet.cellA1('Z1').value != null) {
    throw StateError('Formula or posttest Exit Do semantics changed');
  }

  final ordering = _compile('''
Sub Main()
  Select Case Mark(2)
    Case Mark(1), Mark(2), Mark(3)
      Worksheets(1).Range("B1").Value2 = 20
    Case Mark(4)
      Worksheets(1).Range("B1").Value2 = 40
  End Select
  Select Case 0
    Case Mark(1) To Mark(3)
    Case Else
      Worksheets(1).Range("B2").Value2 = 0
  End Select
End Sub
Function Mark(ByVal amount As Long) As Long
  Worksheets(1).Range("A1").Value2 = amount
  Mark = amount
End Function
''');
  final values = ordering.steps.map((step) => step.arguments['value']).toList();
  if (jsonEncode(values) != '[2,1,2,20,1,3,0]') {
    throw StateError(
      'Selector, alternative, or range evaluation order changed: $values',
    );
  }

  for (final body in <String>[
    'Do\nLoop',
    'Do While True\nLoop',
    'Do Until False\nLoop',
    'Do\nLoop While True',
    'Do\nLoop Until False',
    'While True\nWend',
  ]) {
    _reject('Sub Main()\n$body\nEnd Sub', 'vba_limit_exceeded');
  }
  _reject('''
Sub Main()
  Select Case 1
    Case 1
      Exit Sub
    Case 2
      Call Shell("unsupported")
  End Select
End Sub
''', 'vba_unsupported');

  final beforeFailure = base64Encode(session.bytes);
  final failing = _compile('''
Sub Main()
  For row = 1 To 2
    Do
      Select Case row
        Case 1
          Worksheets(1).Range("A1").Value2 = 999
        Case Else
          Worksheets("Missing").Range("A1").Value2 = 999
      End Select
      Exit Do
    Loop
  Next row
End Sub
''');
  try {
    await session.run(failing);
    throw StateError('Missing selected worksheet unexpectedly ran');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed' || error.stepIndex != 1) rethrow;
  }
  if (base64Encode(session.bytes) != beforeFailure || session.revision != 1) {
    throw StateError('Failed selected case changed the published workbook');
  }

  final mcp = OfficeMacroMcp(session);
  final compiled = await mcp.callTool('office_macro_compile', <String, Object?>{
    'source': <String, Object?>{
      'language': 'vba-excel',
      'format': 'xlsx',
      'source': '''
Sub Main()
  Select Case "ready"
    Case "pending", "ready"
      Worksheets(1).Range("D1").Value2 = "Portable control flow"
  End Select
End Sub
''',
    },
  });
  if (compiled['isError'] != false) {
    throw StateError('MCP compile failed: $compiled');
  }
  final content = compiled['structuredContent']! as Map<String, Object?>;
  final run = await mcp.callTool('office_macro_run', <String, Object?>{
    'macro': content['macro'],
  });
  if (run['isError'] != false ||
      session.revision != 2 ||
      SheetDeserializer()
              .readBytes(session.bytes)
              .sheets
              .single
              .cellA1('D1')
              .value !=
          'Portable control flow') {
    throw StateError('MCP control-flow execution failed: $run');
  }
  print(
    jsonEncode(<String, Object?>{
      'language': 'vba-excel',
      'revision': session.revision,
      'steps': macro.steps.length,
      'formulaTotal': sheet.cellA1('C1').value,
      'coldDepthStress':
          '32 procedure frames / 32 mixed blocks / 63 unary operators',
      'orderedCasesAndEagerRangeBounds': true,
      'sharedLoopWorkBudget': true,
      'staticInactiveChecks': true,
      'validationPreservedBytes': true,
      'lateFailurePreservedBytes': true,
      'mcpCompileAndRun': true,
    }),
  );
}
