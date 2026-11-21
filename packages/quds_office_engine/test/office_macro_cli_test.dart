@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import 'support/office_macro_cli.dart';

Future<ProcessResult> _run(List<String> args) => runOfficeMacroCli(args);

Map<String, Object?> _json(Object? value) {
  final Object? decoded = jsonDecode(value! as String);
  return decoded! as Map<String, Object?>;
}

void main() {
  registerOfficeMacroCliCleanup();
  late Directory temporary;
  setUp(() {
    temporary = Directory.current.createTempSync('macro-cli-test-');
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  test(
    'committed monthly example runs and recalculates its net formula',
    () async {
      final output = '${temporary.path}/summary.xlsx';
      final result = await _run(<String>[
        'run',
        'test/fixtures/fidelity/native.xlsx',
        'example/macros/monthly_totals.qudsmacro.json',
        output,
        'example/macros/monthly_totals.parameters.json',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stderr, isEmpty);
      expect(_json(result.stdout)['completedSteps'], 9);
      final book = SheetDeserializer().readBytes(
        File(output).readAsBytesSync(),
      );
      expect(book.sheets.first.cellA1('A1').value, 'November summary');
      expect(book.sheets.first.cellA1('A1').fontBold, isTrue);
      expect(book.sheets.first.cellA1('B4').formula, 'B2-B3');
      expect(book.sheets.first.cellA1('B4').value, 4700);
      expect(book.sheets.first.freezeRows, 1);
    },
  );

  test(
    'later invalid step preserves existing input and output bytes',
    () async {
      final input = File('${temporary.path}/input.xlsx');
      final original = File(
        'test/fixtures/fidelity/native.xlsx',
      ).readAsBytesSync();
      input.writeAsBytesSync(original);
      final output = File('${temporary.path}/output.xlsx')
        ..writeAsBytesSync(<int>[4, 3, 2, 1]);
      final macro = File('${temporary.path}/bad.json')
        ..writeAsStringSync(
          jsonEncode(<String, Object?>{
            'version': 1,
            'name': 'Reject later error',
            'format': 'xlsx',
            'steps': <Object?>[
              <String, Object?>{
                'tool': 'xlsx.cellValue',
                'arguments': <String, Object?>{
                  'cell': 'A1',
                  'value': 'Do not publish',
                },
              },
              <String, Object?>{
                'tool': 'xlsx.cellFormat',
                'arguments': <String, Object?>{
                  'cell': 'A1',
                  'bold': true,
                  'size': -1,
                },
              },
            ],
          }),
        );
      final result = await _run(<String>[
        'run',
        input.path,
        macro.path,
        output.path,
      ]);
      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      final error = _json(result.stderr)['error']! as Map<String, Object?>;
      expect(error['stepIndex'], 1);
      expect(error['tool'], 'xlsx.cellFormat');
      expect(input.readAsBytesSync(), original);
      expect(output.readAsBytesSync(), <int>[4, 3, 2, 1]);
      expect(temporary.listSync().whereType<Directory>(), isEmpty);
    },
  );

  test(
    'validate succeeds without changing the source or creating output',
    () async {
      final input = File('${temporary.path}/input.xlsx');
      final bytes = File(
        'test/fixtures/fidelity/native.xlsx',
      ).readAsBytesSync();
      input.writeAsBytesSync(bytes);
      final result = await _run(<String>[
        'validate',
        input.path,
        'example/macros/monthly_totals.qudsmacro.json',
        'example/macros/monthly_totals.parameters.json',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(_json(result.stdout)['validatedOnly'], isTrue);
      expect(_json(result.stdout)['revision'], 0);
      expect(input.readAsBytesSync(), bytes);
      expect(temporary.listSync(), hasLength(1));
    },
  );

  test(
    'Word and presentation examples use the same runnable macro format',
    () async {
      final word = File('${temporary.path}/source.docx')
        ..writeAsBytesSync(
          (DocxDocumentBuilder()..paragraph('Old title')).build(),
        );
      final wordParameters = File('${temporary.path}/word.json')
        ..writeAsStringSync('{"title":"New title"}');
      final wordOutput = File('${temporary.path}/result.docx');
      final wordRun = await _run(<String>[
        'run',
        word.path,
        'example/macros/word_heading.qudsmacro.json',
        wordOutput.path,
        wordParameters.path,
      ]);
      expect(wordRun.exitCode, 0, reason: '${wordRun.stderr}');
      final document = WordDeserializer().readBytes(
        wordOutput.readAsBytesSync(),
      );
      expect(document.paragraphs.first.text, 'New title');
      expect(document.paragraphs.first.properties.headingLevel, 1);

      final slideParameters = File('${temporary.path}/slide.json')
        ..writeAsStringSync('{"notes":"Opening remarks"}');
      final slideOutput = File('${temporary.path}/result.pptx');
      final slideRun = await _run(<String>[
        'run',
        'test/fixtures/fidelity/native.pptx',
        'example/macros/slide_notes.qudsmacro.json',
        slideOutput.path,
        slideParameters.path,
      ]);
      expect(slideRun.exitCode, 0, reason: '${slideRun.stderr}');
      expect(
        SlideDeserializer()
            .readBytes(slideOutput.readAsBytesSync())
            .slides
            .first
            .notes,
        'Opening remarks',
      );
    },
  );

  test(
    'extension mismatch and unsupported VBA compilation do not create files',
    () async {
      final wrong = File('${temporary.path}/wrong.xlsm');
      final result = await _run(<String>[
        'run',
        'test/fixtures/fidelity/native.xlsx',
        'example/macros/monthly_totals.qudsmacro.json',
        wrong.path,
      ]);
      expect(result.exitCode, 1);
      expect(wrong.existsSync(), isFalse);

      final source = File('${temporary.path}/source.json')
        ..writeAsStringSync(
          jsonEncode(<String, Object?>{
            'language': 'vba',
            'format': 'xlsx',
            'source': 'Sub Main()\nEnd Sub',
          }),
        );
      final compiled = File('${temporary.path}/compiled.json');
      final compile = await _run(<String>[
        'compile',
        source.path,
        compiled.path,
      ]);
      expect(compile.exitCode, 1);
      expect(
        (_json(compile.stderr)['error']! as Map<String, Object?>)['code'],
        'unsupported_language',
      );
      expect(compiled.existsSync(), isFalse);
    },
  );
}
