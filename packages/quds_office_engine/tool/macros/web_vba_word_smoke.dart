import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

/// Exercise Word VBA compilation and real DOCX transactions under JavaScript.
Future<void> main() async {
  final builder = DocxDocumentBuilder()
    ..paragraph('Original')
    ..paragraph('Value');
  final original = builder.build();
  final session = OfficeMacroSession(original, format: OfficeMacroFormat.docx);
  final languages = OfficeMacroLanguages();
  final macro = languages.compile(
    OfficeMacroSource(
      language: 'vba-word',
      format: OfficeMacroFormat.docx,
      source: '''
Option Explicit
Sub Prefix(ByVal target As Range, ByVal text As String)
    target.InsertBefore text
End Sub
Sub Main()
    Dim target As Range
    Dim values(1 To 2) As Variant
    values(1) = "2.5"
    Set target = ThisDocument.Paragraphs(1).Range
    Call Prefix(target, "Heading 😀: ")
    target.Font.Bold = True
    target.Font.Italic = True
    target.Font.Name = "Arial"
    target.Font.Size = 14.5
    target.Font.Color = RGB(10, 20, 30)
    target.ParagraphFormat.Alignment = wdAlignParagraphCenter
    target.ParagraphFormat.SpaceBefore = 0.05
    target.ParagraphFormat.SpaceAfter = 6.25
    If IsEmpty(values(2)) Then
        ThisDocument.Paragraphs(2).Range.InsertBefore CStr(CLng(values(1))) & " "
    End If
End Sub
''',
    ),
  );
  if (macro.steps.length != 10 || macro.format != OfficeMacroFormat.docx) {
    throw StateError('Word VBA did not produce the expected native plan');
  }
  final originalBytes = base64Encode(original);
  session.startRecording('Portable Word VBA');
  await session.validate(macro);
  if (base64Encode(session.bytes) != originalBytes || session.revision != 0) {
    throw StateError('Word VBA validation published a document');
  }
  await session.run(macro);
  final document = WordDeserializer().readBytes(session.bytes);
  final paragraphs = document.paragraphs.toList();
  if (paragraphs.length != 2 ||
      paragraphs[0].text != 'Heading 😀: Original' ||
      paragraphs[1].text != '2 Value' ||
      paragraphs[0].properties.justification != WmlJustification.center ||
      paragraphs[0].properties.spacingBefore != 0.05 ||
      paragraphs[0].properties.spacingAfter != 6.25 ||
      session.revision != 1) {
    throw StateError(
      'Word VBA text or paragraph formatting did not round-trip',
    );
  }
  for (final run in paragraphs[0].inlines.whereType<WmlRun>()) {
    final properties = run.properties;
    if (!properties.bold ||
        !properties.italic ||
        properties.asciiFont != 'Arial' ||
        properties.fontSizeHalfPoints != 29 ||
        properties.color != '0A141E') {
      throw StateError('Word VBA font formatting did not round-trip');
    }
  }
  final beforeFailure = base64Encode(session.bytes);
  final failing = languages.compile(
    OfficeMacroSource(
      language: 'vba-word',
      format: OfficeMacroFormat.docx,
      source: '''
Sub Main()
    ThisDocument.Paragraphs(1).Range.InsertBefore "Do not publish "
    ThisDocument.Paragraphs(99).Range.InsertBefore "Missing paragraph"
End Sub
''',
    ),
  );
  for (final validate in [true, false]) {
    try {
      if (validate) {
        await session.validate(failing);
      } else {
        await session.run(failing);
      }
      throw StateError('Missing Word paragraph unexpectedly succeeded');
    } on OfficeMacroException catch (error) {
      if (error.code != 'operation_failed' || error.stepIndex != 1) rethrow;
    }
    if (base64Encode(session.bytes) != beforeFailure || session.revision != 1) {
      throw StateError('Word VBA published a failed transaction');
    }
  }
  if (session.stopRecording().steps.isNotEmpty) {
    throw StateError(
      'Playback, validation or failed Word runs changed the recording',
    );
  }
  final readOnly = OfficeMacroSession(
    original,
    format: OfficeMacroFormat.docx,
    policy: OfficeMacroPolicy(allowMutation: false),
  );
  try {
    await readOnly.run(macro);
    throw StateError('Word VBA bypassed the read-only policy');
  } on OfficeMacroException catch (error) {
    if (error.code != 'permission_denied') rethrow;
  }
  if (base64Encode(readOnly.bytes) != originalBytes || readOnly.revision != 0) {
    throw StateError('Denied Word VBA changed its document');
  }
  final mcp = OfficeMacroMcp(session);
  final compiled = await mcp.callTool('office_macro_compile', {
    'source': {
      'language': 'vba-word',
      'format': 'docx',
      'source': '''
Sub Main()
    ThisDocument.Paragraphs(2).Range.InsertBefore "MCP "
End Sub
''',
    },
  });
  if (compiled['isError'] != false || session.revision != 1) {
    throw StateError('Portable MCP Word compilation failed');
  }
  final content = compiled['structuredContent']! as Map<String, Object?>;
  final executed = await mcp.callTool('office_macro_run', {
    'macro': content['macro'],
  });
  if (executed['isError'] != false ||
      session.revision != 2 ||
      WordDeserializer()
              .readBytes(session.bytes)
              .paragraphs
              .elementAt(1)
              .text !=
          'MCP 2 Value') {
    throw StateError('Portable MCP Word playback failed');
  }
  print(
    jsonEncode({
      'language': 'vba-word',
      'steps': macro.steps.length,
      'paragraphs': paragraphs.length,
      'revision': session.revision,
      'unicodeAndVariantText': true,
      'fontAndParagraphFormatting': true,
      'immutableValidation': true,
      'lateFailurePreservedBytesAndRecording': true,
      'readOnlyPolicy': true,
      'mcpCompileAndRun': true,
    }),
  );
}
