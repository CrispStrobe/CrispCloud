import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

Map<String, Object?> _failure(ProcessResult result) {
  expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
  return _json(result.stderr)['error']! as Map<String, Object?>;
}

Uint8List _document([String text = 'Original']) =>
    (DocxDocumentBuilder()..paragraph(text)).build();

void main() {
  late Directory directory;
  File file(String name) => File('${directory.path}/$name');

  setUp(() {
    directory = Directory.systemTemp.createTempSync('quds-word-vba-cli-');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'Word BAS custom entry compiles, validates and matches saved-plan replay',
    () async {
      final input = file('input.docx')..writeAsBytesSync(_document());
      final before = input.readAsBytesSync();
      final source = file('entry.bas')
        ..writeAsStringSync('''
Option Explicit
Sub Main()
    ThisDocument.Paragraphs(1).Range.InsertBefore "Wrong entry "
End Sub
Sub Build()
    With ThisDocument.Paragraphs(1).Range
        .InsertBefore "Custom 😀: "
        .Font.Bold = True
    End With
End Sub
''');
      final plan = file('plan.json');
      final compiled = await _run([
        'compile-word-vba',
        source.path,
        plan.path,
        'Build',
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      expect(_json(compiled.stdout)['language'], 'vba-word');
      final macro = OfficeMacro.parse(plan.readAsStringSync());
      expect(macro.format, OfficeMacroFormat.docx);
      expect(macro.name, 'entry.Build');
      expect(macro.steps, hasLength(2));

      final validation = await _run([
        'validate-word-vba',
        input.path,
        source.path,
        'Build',
      ]);
      expect(
        validation.exitCode,
        0,
        reason: '${validation.stdout}\n${validation.stderr}',
      );
      expect(_json(validation.stdout)['language'], 'vba-word');
      expect(input.readAsBytesSync(), before);

      final output = file('bas-output.docx');
      final executed = await _run([
        'run-word-vba',
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
      expect(_json(executed.stdout)['language'], 'vba-word');
      final native = file('native-output.docx');
      final replay = await _run(['run', input.path, plan.path, native.path]);
      expect(replay.exitCode, 0, reason: '${replay.stdout}\n${replay.stderr}');
      final document = WordDeserializer().readBytes(output.readAsBytesSync());
      expect(document.paragraphs.single.text, 'Custom 😀: Original');
      expect(
        document.paragraphs.single.inlines.whereType<WmlRun>().map(
          (run) => run.properties.bold,
        ),
        everyElement(isTrue),
      );
      final basXml = OpcPackage.openBytes(
        output.readAsBytesSync(),
      ).getPart('/word/document.xml')!.readText();
      final nativeXml = OpcPackage.openBytes(
        native.readAsBytesSync(),
      ).getPart('/word/document.xml')!.readText();
      expect(basXml, nativeXml);
      expect(input.readAsBytesSync(), before);
    },
  );

  test(
    'unsupported Word replacement cannot overwrite an existing compiled plan',
    () async {
      final source = file('unsupported.bas')
        ..writeAsStringSync('''
Sub Main()
    ThisDocument.Paragraphs(1).Range.InsertBefore "Prefix "
    ThisDocument.Paragraphs(1).Range.Text = "Do not replace a paragraph mark"
End Sub
''');
      final output = file('existing-plan.json')
        ..writeAsStringSync('previous user output\n');
      final before = output.readAsBytesSync();
      final error = _failure(
        await _run(['compile-word-vba', source.path, output.path]),
      );
      expect(error['code'], 'vba_unsupported');
      expect(output.readAsBytesSync(), before);
    },
  );

  test(
    'late missing paragraph preserves input and prior output in actual CLI',
    () async {
      final input = file('input.docx')..writeAsBytesSync(_document());
      final output = file('saved.docx')
        ..writeAsBytesSync(_document('Saved before'));
      final inputBefore = input.readAsBytesSync();
      final outputBefore = output.readAsBytesSync();
      final source = file('late.bas')
        ..writeAsStringSync('''
Sub Main()
    ThisDocument.Paragraphs(1).Range.InsertBefore "Do not publish "
    ThisDocument.Paragraphs(2).Range.InsertBefore "Missing"
End Sub
''');
      for (final args in [
        ['validate-word-vba', input.path, source.path],
        ['run-word-vba', input.path, source.path, output.path],
      ]) {
        final error = _failure(await _run(args));
        expect(error['code'], 'operation_failed');
        expect(error['stepIndex'], 1);
        expect(error['tool'], 'docx.replaceText');
        expect(input.readAsBytesSync(), inputBefore);
        expect(output.readAsBytesSync(), outputBefore);
      }
    },
  );

  test(
    'Word CLI preserves opaque DOCM project and macro-enabled document kind',
    () async {
      const mainType = 'application/vnd.ms-word.document.macroEnabled.main+xml';
      const vbaType = 'application/vnd.ms-office.vbaProject';
      const relationType =
          'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
      final package = OpcPackage.openBytes(_document());
      package.getPart('/word/document.xml')!.contentType = mainType;
      package.contentTypes.setOverride('/word/document.xml', mainType);
      final opaque = Uint8List.fromList([0, 255, 13, 10, 127, 1, 2, 3]);
      package.createPart('/word/vbaProject.bin', vbaType, opaque);
      final relation = package
          .relationshipsFor('/word/document.xml')
          .add(type: relationType, target: 'vbaProject.bin');
      final input = file('input.docm')..writeAsBytesSync(package.save());
      final output = file('output.docm');
      final source = file('docm.bas')
        ..writeAsStringSync('''
Sub Main()
    ThisDocument.Paragraphs(1).Range.InsertBefore "DOCM "
End Sub
''');
      final result = await _run([
        'run-word-vba',
        input.path,
        source.path,
        output.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final saved = OpcPackage.openBytes(output.readAsBytesSync());
      expect(saved.getPart('/word/document.xml')!.contentType, mainType);
      expect(saved.getPart('/word/vbaProject.bin')!.readBytes(), opaque);
      expect(saved.getPart('/word/vbaProject.bin')!.contentType, vbaType);
      final retained = saved
          .relationshipsFor('/word/document.xml')
          .firstByType(relationType)!;
      expect(retained.id, relation.id);
      expect(retained.target, relation.target);
      expect(
        WordDeserializer().read(saved).paragraphs.single.text,
        'DOCM Original',
      );
    },
  );

  test(
    'Word CLI refuses incompatible host and output extension before publication',
    () async {
      final book = XlsxWorkbookBuilder()
        ..addSheet('Data').addRow(['unchanged']);
      final input = file('input.xlsx')..writeAsBytesSync(book.build());
      final output = file('output.xlsx')..writeAsBytesSync([1, 2, 3]);
      final source = file('word.bas')
        ..writeAsStringSync('''
Sub Main()
    ThisDocument.Paragraphs(1).Range.InsertBefore "Wrong host"
End Sub
''');
      expect(
        _failure(
          await _run(['run-word-vba', input.path, source.path, output.path]),
        )['code'],
        'format_mismatch',
      );
      expect(output.readAsBytesSync(), [1, 2, 3]);
      final word = file('input.docx')..writeAsBytesSync(_document());
      expect(
        _failure(
          await _run(['run-word-vba', word.path, source.path, output.path]),
        )['code'],
        'input_output_error',
      );
      expect(output.readAsBytesSync(), [1, 2, 3]);
    },
  );
}
