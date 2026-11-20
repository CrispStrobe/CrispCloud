import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/macros/web_vba_word_tabstops_smoke.dart' as portable;

OfficeMacro _compile(String body) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    source: 'Sub Main()\n$body\nEnd Sub',
  ),
);

Matcher _failure(String code) =>
    isA<OfficeMacroException>().having((error) => error.code, 'code', code);

List<WmlTabStop> _tabs(Uint8List bytes, int paragraph) => WordDeserializer()
    .readBytes(bytes)
    .paragraphs
    .elementAt(paragraph)
    .properties
    .tabs;

void main() {
  test(
    'actual BAS example publishes once and survives two native reopens',
    () async {
      final source = File(
        'example/macros/word_tabstops.bas',
      ).readAsStringSync();
      final result = await portable.runWordTabStopExample(source);
      expect(result['operations'], 7);
      expect(result['revision'], 1);
      expect(result['additionalReopens'], 2);
    },
  );

  test(
    'same-position Add replaces the stop while retaining neighboring stops',
    () async {
      final input = portable.wordTabStopInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = _compile('''
With ActiveDocument.Paragraphs(2).Format.TabStops
  .Add Position:=90, Leader:=wdTabLeaderDots, Alignment:=wdAlignTabRight
  .Add 144, wdAlignTabDecimal, wdTabLeaderDashes
End With
''');
      await session.validate(plan);
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        final tabs = _tabs(saved, 1);
        expect(tabs.map((tab) => tab.position), [90, 144]);
        expect(tabs.map((tab) => tab.alignment), [
          WmlTabAlignment.right,
          WmlTabAlignment.decimal,
        ]);
        expect(tabs.map((tab) => tab.leader), [
          WmlTabLeader.dot,
          WmlTabLeader.hyphen,
        ]);
        expect(_tabs(saved, 0).single.position, 36);
        expect(_tabs(saved, 3).single.position, 54);
        saved = WordSerializer().writeBytes(
          WordDeserializer().readBytes(saved),
        );
      }
    },
  );

  test(
    'successive ClearAll and Add runs preserve an empty paragraph',
    () async {
      final session = OfficeMacroSession(
        portable.wordTabStopInput(),
        format: OfficeMacroFormat.docx,
      );
      for (var cycle = 1; cycle <= 3; cycle++) {
        await session.run(
          _compile('''
Dim stops As TabStops
Set stops = ActiveDocument.Paragraphs(3).Range.ParagraphFormat.TabStops
stops.ClearAll
stops.Add 0.05
'''),
        );
        expect(session.revision, cycle);
        expect(_tabs(session.bytes, 2).single.position, 0.05);
        expect(
          WordDeserializer()
              .readBytes(session.bytes)
              .paragraphs
              .elementAt(2)
              .text,
          isEmpty,
        );
      }
    },
  );

  test(
    'late missing paragraph rolls back Add, ClearAll and recording',
    () async {
      final input = portable.wordTabStopInput();
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      session.startRecording('Must not publish');
      final plan = _compile('''
ActiveDocument.Paragraphs(1).TabStops.ClearAll
ActiveDocument.Paragraphs(2).TabStops.Add 72
ActiveDocument.Paragraphs(99).TabStops.Add 144
''');
      final failure = isA<OfficeMacroException>()
          .having((error) => error.code, 'code', 'operation_failed')
          .having((error) => error.stepIndex, 'step', 2)
          .having((error) => error.tool, 'tool', 'docx.tabStop');
      await expectLater(session.validate(plan), throwsA(failure));
      await expectLater(session.run(plan), throwsA(failure));
      expect(session.bytes, input);
      expect(session.revision, 0);
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  for (final (label, policy, code) in <(String, OfficeMacroPolicy, String)>[
    ('read-only', OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (
      'add-only',
      OfficeMacroPolicy(allowedTools: {'docx.tabStop'}),
      'permission_denied',
    ),
    (
      'clear-only',
      OfficeMacroPolicy(allowedTools: {'docx.clearTabStops'}),
      'permission_denied',
    ),
    ('step-limit', OfficeMacroPolicy(maxSteps: 1), 'limit_exceeded'),
  ]) {
    test('source tab-stop plans retain $label policy restriction', () async {
      final input = portable.wordTabStopInput();
      final session = OfficeMacroSession(
        input,
        format: OfficeMacroFormat.docx,
        policy: policy,
      );
      final plan = _compile('''
ActiveDocument.Paragraphs(1).TabStops.ClearAll
ActiveDocument.Paragraphs(1).TabStops.Add 72
''');
      await expectLater(session.validate(plan), throwsA(_failure(code)));
      await expectLater(session.run(plan), throwsA(_failure(code)));
      expect(session.bytes, input);
      expect(session.revision, 0);
    });
  }

  test(
    'an explicit allowlist for both tab operations permits one transaction',
    () async {
      final session = OfficeMacroSession(
        portable.wordTabStopInput(),
        format: OfficeMacroFormat.docx,
        policy: OfficeMacroPolicy(
          allowedTools: {'docx.tabStop', 'docx.clearTabStops'},
        ),
      );
      await session.run(
        _compile('''
ActiveDocument.Paragraphs(1).TabStops.ClearAll
ActiveDocument.Paragraphs(1).TabStops.Add 72
'''),
      );
      expect(session.revision, 1);
      expect(_tabs(session.bytes, 0).single.position, 72);
    },
  );

  test(
    'explicit tab-stop source keeps embedded DOCM VBA bytes inert and intact',
    () async {
      const documentType =
          'application/vnd.ms-word.document.macroEnabled.main+xml';
      const projectType = 'application/vnd.ms-office.vbaProject';
      const projectRelationship =
          'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
      final projectBytes = Uint8List.fromList([0, 1, 127, 128, 254, 255]);
      final signatureBytes = Uint8List.fromList([9, 8, 7, 6]);
      final package = OpcPackage.openBytes(portable.wordTabStopInput());
      package.getPart('/word/document.xml')!.contentType = documentType;
      package.contentTypes.setOverride('/word/document.xml', documentType);
      package.createPart('/word/vbaProject.bin', projectType, projectBytes);
      package.createPart(
        '/word/vbaProjectSignature.bin',
        'application/octet-stream',
        signatureBytes,
      );
      final project = package
          .relationshipsFor('/word/document.xml')
          .add(type: projectRelationship, target: 'vbaProject.bin');
      final signature = package
          .relationshipsFor('/word/vbaProject.bin')
          .add(
            type: '${projectRelationship}Signature',
            target: 'vbaProjectSignature.bin',
          );
      final input = package.save();
      final guard = (await WordPackagePreservation.capture(
        input,
        'tabs.docm',
      ))!;
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = _compile('''
ActiveDocument.Paragraphs(1).TabStops.ClearAll
ActiveDocument.Paragraphs(1).TabStops.Add 72, wdAlignTabRight, wdTabLeaderDots
''');
      await session.validate(plan);
      expect(session.bytes, input);
      await session.run(plan);
      var saved = session.bytes;
      for (var cycle = 0; cycle < 3; cycle++) {
        await guard.validateSaved(saved);
        final reopened = OpcPackage.openBytes(saved);
        expect(
          reopened.getPart('/word/document.xml')!.contentType,
          documentType,
        );
        expect(
          reopened.getPart('/word/vbaProject.bin')!.contentType,
          projectType,
        );
        expect(
          reopened.getPart('/word/vbaProject.bin')!.readBytes(),
          projectBytes,
        );
        expect(
          reopened.getPart('/word/vbaProjectSignature.bin')!.readBytes(),
          signatureBytes,
        );
        final retainedProject = reopened
            .relationshipsFor('/word/document.xml')
            .items
            .singleWhere((item) => item.type == projectRelationship);
        expect(retainedProject.id, project.id);
        expect(retainedProject.target, project.target);
        final retainedSignature = reopened
            .relationshipsFor('/word/vbaProject.bin')
            .items
            .single;
        expect(retainedSignature.id, signature.id);
        expect(retainedSignature.target, signature.target);
        expect(retainedSignature.type, signature.type);
        expect(_tabs(saved, 0).single.alignment, WmlTabAlignment.right);
        saved = WordSerializer().writeBytes(
          WordDeserializer().readBytes(saved),
        );
      }
    },
  );
}
