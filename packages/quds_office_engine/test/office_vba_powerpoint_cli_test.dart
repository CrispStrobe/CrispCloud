import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

Future<ProcessResult> _run(List<String> args) =>
    Process.run(Platform.resolvedExecutable, <String>[
      if (Platform.packageConfig case final String packages)
        '--packages=$packages',
      'tool/macros/office_macro.dart',
      ...args,
    ]);

Map<String, Object?> _json(Object? value) =>
    jsonDecode(value! as String) as Map<String, Object?>;

void main() {
  late Directory directory;
  File file(String name) => File('${directory.path}/$name');
  setUp(
    () => directory = Directory.systemTemp.createTempSync('quds-ppt-vba-cli-'),
  );
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'PowerPoint BAS custom entry compiles, validates, runs and matches native plan replay',
    () async {
      final input = file('input.pptx')
        ..writeAsBytesSync(
          SlideSerializer().writeBytes(
            PmlPresentation(
              slides: <PmlSlide>[
                PmlSlide(
                  id: 256,
                  shapes: <PmlShape>[
                    PmlShape(id: 2, name: 'Title', text: 'Original'),
                  ],
                ),
              ],
            ),
          ),
        );
      final before = input.readAsBytesSync();
      final source = file('report.bas')
        ..writeAsStringSync('''
Sub Main()
  ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text = "Wrong entry"
End Sub
Sub Build()
  With ActivePresentation.Slides(1).Shapes("Title").TextFrame.TextRange
    .Text = "Chosen 😀 entry"
    .Font.Bold = msoTrue
    .Font.Underline = msoFalse
  End With
End Sub
''');
      final planFile = file('plan.json');
      final compiled = await _run([
        'compile-powerpoint-vba',
        source.path,
        planFile.path,
        'Build',
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      expect(_json(compiled.stdout)['language'], 'vba-powerpoint');
      final plan = OfficeMacro.parse(planFile.readAsStringSync());
      expect(plan.name, 'report.Build');
      expect(plan.format, OfficeMacroFormat.pptx);
      expect(plan.steps, hasLength(3));
      final validated = await _run([
        'validate-powerpoint-vba',
        input.path,
        source.path,
        'Build',
      ]);
      expect(
        validated.exitCode,
        0,
        reason: '${validated.stdout}\n${validated.stderr}',
      );
      expect(_json(validated.stdout)['validatedOnly'], isTrue);
      expect(input.readAsBytesSync(), before);

      final output = file('output.pptx');
      final executed = await _run([
        'run-powerpoint-vba',
        input.path,
        source.path,
        output.path,
        'Build',
      ]);
      expect(
        executed.exitCode,
        0,
        reason: '${executed.stdout}\n${executed.stderr}',
      );
      expect(_json(executed.stdout)['language'], 'vba-powerpoint');
      final title = SlideDeserializer()
          .readBytes(output.readAsBytesSync())
          .slides
          .first
          .shapes
          .first;
      expect(title.text, 'Chosen 😀 entry');
      expect(title.resolvedRichText.first.runs.first.bold, isTrue);
      expect(title.resolvedRichText.first.runs.first.underline, isFalse);
      final replayed = file('native.pptx');
      final replay = await _run([
        'run',
        input.path,
        planFile.path,
        replayed.path,
      ]);
      expect(replay.exitCode, 0, reason: '${replay.stdout}\n${replay.stderr}');
      String xml(File source) => OpcPackage.openBytes(
        source.readAsBytesSync(),
      ).getPart('/ppt/slides/slide1.xml')!.readText();
      expect(xml(output), xml(replayed));
      expect(input.readAsBytesSync(), before);
    },
  );

  test(
    'late PowerPoint failure and extension mismatch preserve existing output',
    () async {
      final input = file('input.pptx')
        ..writeAsBytesSync(
          SlideSerializer().writeBytes(
            PmlPresentation(
              slides: <PmlSlide>[
                PmlSlide(
                  id: 256,
                  shapes: <PmlShape>[
                    PmlShape(id: 2, name: 'Title', text: 'Original'),
                  ],
                ),
              ],
            ),
          ),
        );
      final source = file('failure.bas')
        ..writeAsStringSync('''
Sub Main()
  ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text = "Do not publish"
  ActivePresentation.Slides(1).Shapes("Missing").TextFrame.TextRange.Font.Bold = True
End Sub
''');
      final output = file('existing.pptx')
        ..writeAsStringSync('earlier user output');
      final before = output.readAsBytesSync();
      final result = await _run([
        'run-powerpoint-vba',
        input.path,
        source.path,
        output.path,
      ]);
      expect(result.exitCode, 1);
      final error = _json(result.stderr)['error']! as Map<String, Object?>;
      expect(error['code'], 'operation_failed');
      expect(error['stepIndex'], 1);
      expect(output.readAsBytesSync(), before);

      final wrongType = file('existing.pptm')..writeAsBytesSync(before);
      final mismatch = await _run([
        'run-powerpoint-vba',
        input.path,
        source.path,
        wrongType.path,
      ]);
      expect(mismatch.exitCode, 1);
      expect(
        (_json(mismatch.stderr)['error']! as Map<String, Object?>)['code'],
        'input_output_error',
      );
      expect(wrongType.readAsBytesSync(), before);
      final invalid = file('invalid.bas')
        ..writeAsStringSync('''
Sub Main()
  ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text = "Valid prefix"
  Shell "unsupported"
End Sub
''');
      final plan = file('previous.json')..writeAsStringSync('existing plan');
      final rejected = await _run([
        'compile-powerpoint-vba',
        invalid.path,
        plan.path,
      ]);
      expect(rejected.exitCode, 1);
      expect(plan.readAsStringSync(), 'existing plan');
    },
  );
}
