import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

Uint8List _source({
  required int emptyFormattingRuns,
  bool missingPreviousFormatting = false,
}) {
  // Use the application's ordinary native package, including its default
  // settings part. Import honors that authored tracking-disabled setting;
  // a minimal package without settings instead retains record()'s true flag.
  final builder = DocxDocumentBuilder()..paragraph('Template');
  final package = OpcPackage.openBytes(builder.build());
  final runs = StringBuffer();
  for (var index = 0; index < emptyFormattingRuns; index++) {
    final previous = missingPreviousFormatting && index == 0
        ? ''
        : '<w:rPr><w:i/></w:rPr>';
    runs.write(
      '<w:r><w:rPr><w:b/>'
      '<w:rPrChange w:id="${index + 13}" w:author="Original reviewer" '
      'w:date="2026-11-19T10:00:00Z">$previous</w:rPrChange>'
      '</w:rPr><w:t xml:space="preserve"></w:t></w:r>',
    );
  }
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body>'
        '<w:p>$runs</w:p><w:p><w:r><w:t>Original heading</w:t></w:r></w:p>'
        '<w:sectPr/></w:body></w:document>',
      );
  // Keep incomplete native revision markup in the fixture so the macro
  // runtime reaches the same save guard as a real imported document.
  return package.save();
}

const _headingArguments = <String, Object?>{'paragraph': 1, 'level': 2};

OfficeMacro _headingPlan() => OfficeMacro(
  name: 'Heading with existing formatting history',
  format: OfficeMacroFormat.docx,
  steps: [OfficeMacroStep(tool: 'docx.heading', arguments: _headingArguments)],
);

Matcher _saveGuardFailure() => isA<OfficeMacroException>()
    .having((error) => error.code, 'code', 'document_error')
    .having((error) => error.stepIndex, 'stepIndex', isNull)
    .having((error) => error.tool, 'tool', isNull)
    .having(
      (error) => error.message,
      'message',
      contains('The previous formatting is missing.'),
    );

void main() {
  test(
    'missing previous formatting refuses macro save without publication or recording',
    () async {
      final source = _source(
        emptyFormattingRuns: 2,
        missingPreviousFormatting: true,
      );
      final admitted =
          OfficeOperationCatalog.open(source, OfficeMacroFormat.docx)
              as WmlDocument;
      expect(admitted.trackRevisions, isFalse);
      expect(admitted.revisions, hasLength(2));
      expect(
        admitted.revisions.map((revision) => revision.kind),
        everyElement(WmlRevisionKind.runFormat),
      );
      expect(
        () => OfficeOperationCatalog.assertEditable(admitted),
        returnsNormally,
      );

      final session = OfficeMacroSession(
        source,
        format: OfficeMacroFormat.docx,
      );
      session.startRecording('No failed save should be recorded');
      for (final operation in ['run', 'validate', 'callTool']) {
        final future = switch (operation) {
          'run' => session.run(_headingPlan()),
          'validate' => session.validate(_headingPlan()),
          _ => session.callTool('docx.heading', _headingArguments),
        };
        await expectLater(
          future,
          throwsA(_saveGuardFailure()),
          reason: operation,
        );
        expect(session.bytes, source, reason: operation);
        expect(session.revision, 0, reason: operation);
        expect(session.isRecording, isTrue, reason: operation);
        final unchanged = WordDeserializer().readBytes(session.bytes);
        expect(unchanged.revisions, hasLength(2), reason: operation);
        expect(unchanged.paragraphs.elementAt(1).text, 'Original heading');
        expect(
          unchanged.paragraphs.elementAt(1).properties.headingLevel,
          isNull,
        );
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );

  test(
    'two native empty formatting runs survive a macro save independently',
    () async {
      final source = _source(emptyFormattingRuns: 2);
      final session = OfficeMacroSession(
        source,
        format: OfficeMacroFormat.docx,
      );
      final preview = await session.validate(_headingPlan());
      expect(preview.validatedOnly, isTrue);
      expect(session.bytes, source);
      expect(session.revision, 0);

      await session.run(_headingPlan());
      expect(session.revision, 1);
      final saved = WordDeserializer().readBytes(session.bytes);
      final runs = saved.paragraphs.first.inlines.whereType<WmlRun>().toList();
      expect(saved.paragraphs.last.properties.headingLevel, 2);
      expect(saved.revisions, hasLength(2));
      expect(runs, hasLength(2));
      for (var index = 0; index < runs.length; index++) {
        expect(runs[index].text, isEmpty);
        expect(
          saved.revisions[index].emptyFormattingAnchor,
          same(runs[index].formattingAnchor),
        );
      }
      expect(
        runs.first.formattingAnchor,
        isNot(same(runs.last.formattingAnchor)),
      );
    },
  );

  test(
    'a single empty formatting run survives detached macro validation and a recorded save',
    () async {
      final source = _source(emptyFormattingRuns: 1);
      final session = OfficeMacroSession(
        source,
        format: OfficeMacroFormat.docx,
      );
      session.startRecording('Successful heading edit');

      final validated = await session.validate(_headingPlan());
      expect(validated.validatedOnly, isTrue);
      expect(validated.completedSteps, 1);
      expect(session.bytes, source);
      expect(session.revision, 0);

      final saved = await session.callTool('docx.heading', _headingArguments);
      expect(saved.validatedOnly, isFalse);
      expect(saved.completedSteps, 1);
      expect(saved.revision, 1);
      expect(session.revision, 1);
      final document = WordDeserializer().readBytes(session.bytes);
      expect(document.paragraphs.elementAt(1).text, 'Original heading');
      expect(document.paragraphs.elementAt(1).properties.headingLevel, 2);
      final revision = document.revisions.single;
      expect(revision.kind, WmlRevisionKind.runFormat);
      expect((revision.start, revision.end), (0, 0));
      expect(revision.author, 'Original reviewer');
      expect(revision.previousPropertiesXml, isNotNull);
      expect(revision.accepted, isNull);
      final emptyRun = document.paragraphs.first.inlines
          .whereType<WmlRun>()
          .single;
      expect(emptyRun.text, isEmpty);
      expect(emptyRun.properties.bold, isTrue);
      expect(emptyRun.properties.italic, isFalse);
      final recording = session.stopRecording();
      expect(recording.steps, hasLength(1));
      expect(recording.steps.single.tool, 'docx.heading');
      expect(recording.steps.single.arguments, _headingArguments);
    },
  );
}
