import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Compile to JavaScript and execute to verify the complete portable path.
Future<void> main() async {
  final builder = XlsxWorkbookBuilder();
  builder.addSheet('Summary').addRow(<Object?>['Initial', 2]);
  final session = OfficeMacroSession(
    builder.build(),
    format: OfficeMacroFormat.xlsx,
  );
  final macro = OfficeMacro(
    name: 'Portable macro',
    format: OfficeMacroFormat.xlsx,
    steps: <OfficeMacroStep>[
      OfficeMacroStep(
        tool: 'xlsx.cellValue',
        arguments: <String, Object?>{'cell': 'A1', 'value': 42},
      ),
      OfficeMacroStep(
        tool: 'xlsx.cellFormula',
        arguments: <String, Object?>{'cell': 'A2', 'formula': 'A1*2'},
      ),
    ],
  );
  await session.run(macro);
  final book = SheetDeserializer().readBytes(session.bytes);
  if (book.sheets.first.cellA1('A2').value != 84 || session.revision != 1) {
    throw StateError('Portable macro did not recalculate correctly');
  }
  final before = base64Encode(session.bytes);
  try {
    await session.run(
      OfficeMacro(
        name: 'Reject late failure',
        format: OfficeMacroFormat.xlsx,
        steps: <OfficeMacroStep>[
          OfficeMacroStep(
            tool: 'xlsx.cellValue',
            arguments: <String, Object?>{'cell': 'A1', 'value': 99},
          ),
          OfficeMacroStep(
            tool: 'xlsx.cellValue',
            arguments: <String, Object?>{'cell': 'A0', 'value': 0},
          ),
        ],
      ),
    );
    throw StateError('Invalid cell unexpectedly succeeded');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed' || error.stepIndex != 1) rethrow;
  }
  if (base64Encode(session.bytes) != before || session.revision != 1) {
    throw StateError('Portable macro published a failed transaction');
  }
  final mcp = OfficeMacroMcp(session);
  final inspection = await mcp.callTool(
    'office_document_inspect',
    const <String, Object?>{},
  );
  if (inspection['isError'] != false) {
    throw StateError('Portable MCP inspection failed');
  }
  print(
    jsonEncode(<String, Object?>{
      'revision': session.revision,
      'A1': book.sheets.first.cellA1('A1').value,
      'A2': book.sheets.first.cellA1('A2').value,
      'lateFailurePreservedBytes': true,
      'mcpInspection': true,
    }),
  );
}
