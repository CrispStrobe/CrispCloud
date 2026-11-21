@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_arguments_smoke.dart' as portable;
import 'support/office_macro_cli.dart';

String _language(OfficeMacroFormat format) => switch (format) {
  OfficeMacroFormat.docx => 'vba-word',
  OfficeMacroFormat.pptx => 'vba-powerpoint',
  _ => 'vba-excel',
};

OfficeMacro _compile(OfficeMacroFormat format, String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: _language(format),
        format: format,
        source: source,
      ),
    );

Uint8List _input(OfficeMacroFormat format) => switch (format) {
  OfficeMacroFormat.docx => portable.wordHelperInput(),
  OfficeMacroFormat.pptx => portable.powerPointHelperInput(),
  _ => (XlsxWorkbookBuilder()..addSheet('Sheet1')).build(),
};

String _body(OfficeMacroFormat format) => switch (format) {
  OfficeMacroFormat.docx =>
    'ActiveDocument.Paragraphs(index).Range.InsertBefore text',
  OfficeMacroFormat.pptx =>
    'ActivePresentation.Slides(index).Shapes("Title").TextFrame.TextRange.Text = text',
  _ => 'Worksheets(index).Range("A1").Value2 = text',
};

String _source(OfficeMacroFormat format, {bool fail = false}) =>
    '''
Sub Main()
  Put text:="first"
  Put ${fail ? 'index:=99, ' : ''}text:="second"
End Sub
Sub Put(Optional ByVal index As Long = 1, Optional ByVal text As String = "default")
  ${_body(format)}
End Sub
''';

TypeMatcher<OfficeMacroException> _error(String code) =>
    isA<OfficeMacroException>().having((error) => error.code, 'code', code);

Future<ProcessResult> _run(List<String> arguments) =>
    runOfficeMacroCli(arguments);

void main() {
  registerOfficeMacroCliCleanup();
  test(
    'actual Word and PowerPoint BAS examples survive two native reopens',
    () async {
      final result = await portable.runOptionalHelperExamples(
        File('example/macros/word_optional_helpers.bas').readAsStringSync(),
        File(
          'example/macros/powerpoint_optional_helpers.bas',
        ).readAsStringSync(),
      );
      expect(result.keys, <String>['word', 'powerpoint']);
      expect((result['word']! as Map<String, Object?>)['operations'], 7);
      expect((result['powerpoint']! as Map<String, Object?>)['operations'], 5);
    },
  );

  for (final format in OfficeMacroFormat.values) {
    group('${format.name} optional helper transactions', () {
      test(
        'validate leaves input unchanged and a late run failure rolls back',
        () async {
          final input = _input(format);
          final original = Uint8List.fromList(input);
          final session = OfficeMacroSession(input, format: format);
          final plan = _compile(format, _source(format, fail: true));
          expect(plan.steps, hasLength(2));
          session.startRecording('Optional helper failure');
          final failure = _error(
            'operation_failed',
          ).having((error) => error.stepIndex, 'stepIndex', 1);
          await expectLater(session.validate(plan), throwsA(failure));
          expect(session.bytes, original);
          expect(session.revision, 0);
          await expectLater(
            session.run(OfficeMacro.parse(plan.encode())),
            throwsA(failure),
          );
          expect(session.bytes, original);
          expect(input, original);
          expect(session.revision, 0);
          expect(session.stopRecording().steps, isEmpty);
        },
      );

      test('helper arguments cannot bypass mutation or tool policy', () async {
        for (final policy in <OfficeMacroPolicy>[
          OfficeMacroPolicy(allowMutation: false),
          OfficeMacroPolicy(allowedTools: <String>{}),
        ]) {
          final session = OfficeMacroSession(
            _input(format),
            format: format,
            policy: policy,
          );
          final original = session.bytes;
          final plan = _compile(format, _source(format));
          await expectLater(
            session.run(plan),
            throwsA(_error('permission_denied')),
          );
          expect(session.bytes, original);
          expect(session.revision, 0);
        }
      });

      test(
        'MCP source compilation preserves named/optional helper behavior',
        () async {
          final session = OfficeMacroSession(_input(format), format: format);
          final original = session.bytes;
          final adapter = OfficeMacroMcp(session);
          final compiled = await adapter.callTool(
            'office_macro_compile',
            <String, Object?>{
              'source': <String, Object?>{
                'language': _language(format),
                'format': format.name,
                'source': _source(format),
              },
            },
          );
          expect(compiled['isError'], isFalse, reason: '$compiled');
          expect(session.bytes, original);
          expect(session.revision, 0);
          final structured =
              compiled['structuredContent']! as Map<String, Object?>;
          final plan = OfficeMacro.fromJson(
            structured['macro']! as Map<String, Object?>,
          );
          expect(plan.steps, hasLength(2));
          await session.run(plan);
          expect(session.revision, 1);
          expect(session.bytes, isNot(original));
        },
      );

      test(
        'MCP Missing failure cannot publish an earlier compiled write',
        () async {
          final session = OfficeMacroSession(_input(format), format: format);
          final original = session.bytes;
          final adapter = OfficeMacroMcp(session);
          final result = await adapter.callTool(
            'office_macro_compile',
            <String, Object?>{
              'source': <String, Object?>{
                'language': _language(format),
                'format': format.name,
                'source':
                    '''
Sub Main()
  Put text:="first"
  Missing
End Sub
Sub Put(Optional ByVal index As Long = 1, Optional ByVal text As String = "default")
  ${_body(format)}
End Sub
Sub Missing(Optional ByVal item)
  Put text:=CStr(item)
End Sub
''',
              },
            },
          );
          expect(result['isError'], isTrue);
          expect(jsonEncode(result), contains('vba_missing_argument'));
          expect(session.bytes, original);
          expect(session.revision, 0);
        },
      );

      test(
        'CLI runs the source adapter and preserves output on late failure',
        () async {
          final directory = Directory.current.createTempSync('arguments-cli-');
          try {
            final input = File('${directory.path}/input.${format.name}')
              ..writeAsBytesSync(_input(format));
            final source = File('${directory.path}/helpers.bas')
              ..writeAsStringSync(_source(format));
            final output = File('${directory.path}/output.${format.name}');
            final command = switch (format) {
              OfficeMacroFormat.docx => 'run-word-vba',
              OfficeMacroFormat.pptx => 'run-powerpoint-vba',
              _ => 'run-vba',
            };
            final success = await _run(<String>[
              command,
              input.path,
              source.path,
              output.path,
            ]);
            expect(
              success.exitCode,
              0,
              reason: '${success.stdout}\n${success.stderr}',
            );
            final published = output.readAsBytesSync();
            source.writeAsStringSync(_source(format, fail: true));
            final failed = await _run(<String>[
              command,
              input.path,
              source.path,
              output.path,
            ]);
            expect(failed.exitCode, isNot(0));
            expect(output.readAsBytesSync(), published);
          } finally {
            directory.deleteSync(recursive: true);
          }
        },
      );
    });
  }
}
