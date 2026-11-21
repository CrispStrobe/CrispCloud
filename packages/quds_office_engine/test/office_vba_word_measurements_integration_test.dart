import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_measurements_smoke.dart' as portable;

String _example() =>
    File('example/macros/word_measurements.bas').readAsStringSync();

OfficeMacro _plan(String body) =>
    portable.measurementPlan('Sub Main()\n$body\nEnd Sub');

void main() {
  test('the BAS example survives publication, reopen and replay', () async {
    final result = await portable.runWordMeasurementExample(_example());
    expect(result['operations'], 8);
    expect(result['revision'], 1);
    expect(result['additionalReopens'], 2);
    expect(result['replayStable'], isTrue);
  });

  test('late failure rolls back measured writes and recording', () async {
    final input = portable.wordMeasurementInput();
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    session.startRecording('Do not publish');
    final plan = _plan('''
ActiveDocument.Paragraphs(1).Format.LeftIndent = InchesToPoints(0.5)
ActiveDocument.Paragraphs(99).TabStops.Add CentimetersToPoints(2.54)
''');
    final failure = isA<OfficeMacroException>()
        .having((error) => error.code, 'code', 'operation_failed')
        .having((error) => error.stepIndex, 'step', 1);
    await expectLater(session.validate(plan), throwsA(failure));
    await expectLater(session.run(plan), throwsA(failure));
    expect(session.bytes, input);
    expect(session.revision, 0);
    expect(session.stopRecording().steps, isEmpty);
  });

  for (final (name, policy, code) in <(String, OfficeMacroPolicy, String)>[
    ('read-only', OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (
      'allowlist',
      OfficeMacroPolicy(allowedTools: {'docx.paragraphFormat'}),
      'permission_denied',
    ),
    ('step-limit', OfficeMacroPolicy(maxSteps: 1), 'limit_exceeded'),
  ]) {
    test('measurement plans retain the $name policy boundary', () async {
      final input = portable.wordMeasurementInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      final plan = portable.measurementPlan(_example());
      final failure = isA<OfficeMacroException>().having(
        (error) => error.code,
        'code',
        code,
      );
      await expectLater(session.validate(plan), throwsA(failure));
      await expectLater(session.run(plan), throwsA(failure));
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test('DOCM measurement writes retain opaque VBA project bytes', () async {
    const documentType =
        'application/vnd.ms-word.document.macroEnabled.main+xml';
    const projectType = 'application/vnd.ms-office.vbaProject';
    const relationship =
        'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
    final project = Uint8List.fromList([0, 1, 127, 128, 254, 255]);
    final package = OpcPackage.openBytes(portable.wordMeasurementInput());
    package.getPart('/word/document.xml')!.contentType = documentType;
    package.contentTypes.setOverride('/word/document.xml', documentType);
    package.createPart('/word/vbaProject.bin', projectType, project);
    package
        .relationshipsFor('/word/document.xml')
        .add(type: relationship, target: 'vbaProject.bin');
    final input = package.save();
    final guard = (await WordPackagePreservation.capture(
      input,
      'measurements.docm',
    ))!;
    final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
    await session.run(portable.measurementPlan(_example()));
    var saved = session.bytes;
    for (var cycle = 0; cycle < 3; cycle++) {
      await guard.validateSaved(saved);
      final reopened = OpcPackage.openBytes(saved);
      expect(reopened.getPart('/word/vbaProject.bin')!.readBytes(), project);
      expect(reopened.getPart('/word/document.xml')!.contentType, documentType);
      portable.wordMeasurementState(saved);
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  });
}
