import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

OfficeMacro _compile(String source) => const OfficeVbaMacroLanguage().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    source: source,
    moduleName: 'PortableArrays',
  ),
);

String _nested(int depth, String body, {bool allForEach = false}) {
  final opening = <String>[];
  final closing = <String>[];
  for (var index = 0; index < depth; index++) {
    final pair = allForEach
        ? ('For Each item$index In seed', 'Next item$index')
        : switch (index % 4) {
            0 => ('For Each item$index In seed', 'Next item$index'),
            1 => ('Do While True', 'Loop'),
            2 => ('Select Case 1\nCase 1', 'End Select'),
            _ => ('With Worksheets(1)', 'End With'),
          };
    opening.add(pair.$1);
    closing.insert(0, pair.$2);
  }
  return '${opening.join('\n')}\n$body\n${closing.join('\n')}';
}

String _depthProgram(
  int frames,
  int blocks,
  int unary, {
  bool allForEach = false,
}) {
  final operators = List<String>.filled(unary, '+').join();
  final declarations = StringBuffer('Dim seed(0) As Long\n');
  for (var index = 0; index < blocks; index += allForEach ? 1 : 4) {
    declarations.writeln('Dim item$index As Variant');
  }
  final source = StringBuffer('Option Explicit\nSub Main()\n$declarations');
  source.writeln(
    _nested(
      blocks,
      'Worksheets(1).Range("A1").Value2 = ${operators}F1()\nExit Sub',
      allForEach: allForEach,
    ),
  );
  source.writeln('End Sub');
  for (var index = 1; index < frames; index++) {
    final value = index == frames - 1 ? '42' : 'F${index + 1}()';
    source.writeln('Function F$index() As Long\n$declarations');
    source.writeln(
      _nested(
        blocks,
        'F$index = $operators$value\nExit Function',
        allForEach: allForEach,
      ),
    );
    source.writeln('End Function');
  }
  return source.toString();
}

void _reject(String source, String code) {
  try {
    _compile(source);
    throw StateError('Invalid array source unexpectedly compiled');
  } on OfficeVbaCompileException catch (error) {
    if (error.code != code || error.line < 1 || error.column < 1) rethrow;
  }
}

/// Runs new For Each frames at the combined nesting limits in a cold process,
/// then checks portable indexing, live slots, range metadata and atomic runs.
Future<void> main() async {
  for (final allForEach in <bool>[true, false]) {
    final depth = _compile(_depthProgram(32, 32, 63, allForEach: allForEach));
    if (depth.steps.length != 1 ||
        depth.steps.single.arguments['value'] != 42) {
      throw StateError(
        'Combined array/procedure/block/expression depth changed',
      );
    }
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
  Dim amounts(-1 To 2) As Long, amount As Variant
  Dim row As Long, total As Long, target As Range
  amounts(-1) = 1
  amounts(0) = 2
  amounts(1) = 3
  amounts(2) = 4
  row = 1
  For Each amount In amounts
    If row = 1 Then
      amounts(0) = 20
    End If
    Worksheets("Summary").Cells(row, 1).Value2 = amount
    total = total + amount
    amount = 999
    row = row + 1
  Next amount
  With Worksheets("Summary")
    For Each target In .Range("B1:C2")
      target.Value2 = target.Row * 100 + target.Column
      Set target = .Range("Z9")
    Next target
    .Range("C4").Formula = "=SUM(A1:A4)"
    .Range("D1").Value2 = amounts(-1)
    .Range("D2").Value2 = total
    .Range("D3").Value2 = LBound(amounts, 1)
    .Range("D4").Value2 = UBound(amounts)
  End With
End Sub
''');
  if (macro.steps.length != 13) throw StateError('Unexpected array expansion');
  final rangeCells = macro.steps
      .skip(4)
      .take(4)
      .map((step) => step.arguments['cell'])
      .toList();
  if (jsonEncode(rangeCells) != '["B1","C1","B2","C2"]') {
    throw StateError('For Each range did not expand in row-major order');
  }
  final original = base64Encode(session.bytes);
  await session.validate(macro);
  if (base64Encode(session.bytes) != original || session.revision != 0) {
    throw StateError('Array-plan validation published changes');
  }
  await session.run(OfficeMacro.parse(macro.encode()));
  final sheet = SheetDeserializer().readBytes(session.bytes).sheets.single;
  const expected = <String, Object>{
    'A1': 1,
    'A2': 20,
    'A3': 3,
    'A4': 4,
    'B1': 102,
    'C1': 103,
    'B2': 202,
    'C2': 203,
    'C4': 28,
    'D1': 1,
    'D2': 28,
    'D3': -1,
    'D4': 2,
  };
  for (final entry in expected.entries) {
    if (sheet.cellA1(entry.key).value != entry.value) {
      throw StateError('Array/range result changed at ${entry.key}');
    }
  }
  if (sheet.cellA1('Z9').value != null) {
    throw StateError('Rebinding a Range iteration variable changed the source');
  }

  final exact = _compile('''
Sub Main()
  Dim values(-2147483648 To -2147479553) As Long
  values(-2147483648) = 17
  values(-2147479553) = 23
  Worksheets(1).Range("A1").Value2 = values(LBound(values)) + values(UBound(values))
End Sub
''');
  if (exact.steps.single.arguments['value'] != 40) {
    throw StateError('Exact array allocation/negative-boundary result changed');
  }
  _reject('''
Sub Main()
  Dim values(0 To 4096) As Long
End Sub
''', 'vba_limit_exceeded');
  _reject('''
Sub Main()
  Dim a(4095) As Long, b(4095) As Long
  Dim c(4095) As Long, d(4095) As Long, e(0) As Long
End Sub
''', 'vba_limit_exceeded');
  _reject('''
Sub Main()
  Dim values(1 To 2) As Long
  Worksheets(1).Range("A1").Value2 = values(0)
End Sub
''', 'vba_subscript_out_of_range');
  _reject('''
Sub Main()
  Dim values(1 To 2) As Long
  values(1.5) = 0
End Sub
''', 'vba_type_error');
  _reject('''
Sub Main()
  Dim cell As Range
  For Each cell In Worksheets(1).Range("A1:XFD1048576")
  Next cell
End Sub
''', 'vba_limit_exceeded');
  _reject('''
Sub Main()
  Exit Sub
End Sub
Sub Hidden()
  Dim values(2) As Long, item As Variant
  For Each item In values
    Call Shell("unsupported")
  Next item
End Sub
''', 'vba_unsupported');

  final beforeFailure = base64Encode(session.bytes);
  final failing = _compile('''
Sub Main()
  Dim names(1 To 2) As String, name As Variant
  names(1) = "Summary"
  names(2) = "Missing"
  For Each name In names
    Worksheets(name).Range("A1").Value2 = 999
  Next name
End Sub
''');
  try {
    await session.run(failing);
    throw StateError('Missing array-selected worksheet unexpectedly ran');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed' || error.stepIndex != 1) rethrow;
  }
  if (base64Encode(session.bytes) != beforeFailure || session.revision != 1) {
    throw StateError('Failed array-selected step changed the workbook');
  }

  final mcp = OfficeMacroMcp(session);
  final compiled = await mcp.callTool('office_macro_compile', <String, Object?>{
    'source': <String, Object?>{
      'language': 'vba-excel',
      'format': 'xlsx',
      'source': '''
Sub Main()
  Dim words(0) As String, word As Variant
  words(0) = "Portable arrays"
  For Each word In words
    Worksheets(1).Range("E1").Value2 = word
  Next word
End Sub
''',
    },
  });
  if (compiled['isError'] != false) {
    throw StateError('MCP array compile failed: $compiled');
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
              .cellA1('E1')
              .value !=
          'Portable arrays') {
    throw StateError('MCP array execution failed: $run');
  }
  print(
    jsonEncode(<String, Object?>{
      'language': 'vba-excel',
      'revision': session.revision,
      'steps': macro.steps.length,
      'formulaTotal': sheet.cellA1('C4').value,
      'coldDepthStress':
          '32 procedure frames / 32 For Each blocks / 63 unary operators, then mixed blocks',
      'liveArraySlotsAndIndependentControlVariables': true,
      'rangeSnapshotAndRowMajorOrder': true,
      'exactArrayAllocationAndNegativeBounds': true,
      'boundedArraysAndRangeIteration': true,
      'staticInactiveChecks': true,
      'validationPreservedBytes': true,
      'lateFailurePreservedBytes': true,
      'mcpCompileAndRun': true,
    }),
  );
}
