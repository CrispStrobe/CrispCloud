import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Compile and execute the Excel VBA subset with the portable JavaScript API.
Future<void> main() async {
  final builder = XlsxWorkbookBuilder();
  builder.addSheet('Summary').addRow(<Object?>['Before']);
  final session = OfficeMacroSession(
    builder.build(),
    format: OfficeMacroFormat.xlsx,
  );
  final languages = OfficeMacroLanguages();
  // Native Dart integers and JavaScript numbers must reject the same unsafe
  // arithmetic, including products that would otherwise wrap a VM integer.
  for (final expression in <String>[
    '4294967296 * 4294967296',
    '1e20',
    '9007199254740991 + 1',
  ]) {
    try {
      languages.compile(
        OfficeMacroSource(
          language: 'vba-excel',
          format: OfficeMacroFormat.xlsx,
          source:
              'Sub Main()\n'
              'Worksheets(1).Range("A1").Value2 = $expression\n'
              'End Sub',
        ),
      );
      throw StateError('Unsafe arithmetic unexpectedly compiled: $expression');
    } on OfficeVbaCompileException catch (error) {
      if (error.code != 'vba_limit_exceeded') rethrow;
    }
  }
  final precedence = languages.compile(
    OfficeMacroSource(
      language: 'vba-excel',
      format: OfficeMacroFormat.xlsx,
      source:
          'Sub Main()\n'
          'Worksheets(1).Range("A1").Value2 = True Or False Xor True\n'
          'Worksheets(1).Range("A2").Value2 = (-0.0 = 0.0)\n'
          'End Sub',
    ),
  );
  if (precedence.steps.first.arguments['value'] != false ||
      precedence.steps.last.arguments['value'] != true) {
    throw StateError('VBA comparisons or precedence changed in JavaScript');
  }
  final macro = languages.compile(
    OfficeMacroSource(
      language: 'vba-excel',
      format: OfficeMacroFormat.xlsx,
      source: '''
Option Explicit
Sub Main()
    Dim row As Long
    With ThisWorkbook.Worksheets("summary")
        For row = 1 To 3
            .Cells(row, 1).Value2 = row * 14
        Next row
        .Range("B1").Formula = "=SUM(A1:A3)"
        .Range("A1:B1").Font.Bold = True
        .Range("B1").Interior.Color = RGB(10, 20, 30)
    End With
End Sub
''',
    ),
  );
  final input = base64Encode(session.bytes);
  await session.validate(macro);
  if (base64Encode(session.bytes) != input || session.revision != 0) {
    throw StateError('VBA validation published a document');
  }
  await session.run(macro);
  final book = SheetDeserializer().readBytes(session.bytes);
  final sheet = book.sheets.single;
  if (sheet.cellA1('A3').value != 42 ||
      sheet.cellA1('B1').value != 84 ||
      !sheet.cellA1('B1').fontBold ||
      sheet.cellA1('B1').fillRgb != '0A141E' ||
      session.revision != 1) {
    throw StateError('Compiled VBA did not produce the expected workbook');
  }
  final beforeFailure = base64Encode(session.bytes);
  final failing = languages.compile(
    OfficeMacroSource(
      language: 'vba-excel',
      format: OfficeMacroFormat.xlsx,
      source: '''
Sub Main()
    Worksheets(1).Range("A1").Value2 = 99
    Worksheets("Missing").Range("A1").Value2 = 0
End Sub
''',
    ),
  );
  try {
    await session.run(failing);
    throw StateError('Missing VBA worksheet unexpectedly succeeded');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed' || error.stepIndex != 1) rethrow;
  }
  if (base64Encode(session.bytes) != beforeFailure || session.revision != 1) {
    throw StateError('Compiled VBA published a failed transaction');
  }
  final mcp = OfficeMacroMcp(session);
  final compiled = await mcp.callTool('office_macro_compile', <String, Object?>{
    'source': <String, Object?>{
      'language': 'vba-excel',
      'format': 'xlsx',
      'source':
          'Sub Main()\n'
          'Worksheets(1).Range("C1").Value2 = "Portable VBA"\n'
          'End Sub',
    },
  });
  if (compiled['isError'] != false || session.revision != 1) {
    throw StateError('Portable MCP VBA compilation failed');
  }
  final content = compiled['structuredContent']! as Map<String, Object?>;
  final result = await mcp.callTool('office_macro_run', <String, Object?>{
    'macro': content['macro'],
  });
  if (result['isError'] != false ||
      session.revision != 2 ||
      SheetDeserializer()
              .readBytes(session.bytes)
              .sheets
              .single
              .cellA1('C1')
              .value !=
          'Portable VBA') {
    throw StateError('Portable MCP compiled VBA playback failed');
  }
  print(
    jsonEncode(<String, Object?>{
      'language': 'vba-excel',
      'revision': session.revision,
      'A3': sheet.cellA1('A3').value,
      'B1': sheet.cellA1('B1').value,
      'fill': sheet.cellA1('B1').fillRgb,
      'validationPreservedBytes': true,
      'lateFailurePreservedBytes': true,
      'mcpCompileAndRun': true,
      'numericBoundsAndPrecedence': true,
    }),
  );
}
